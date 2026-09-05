// AirFly 云中转客户端：单 WebSocket 连接管理。
//
// 对旧局域网版的针对性修复：
//  - WebSocket 自带消息帧，彻底消除 TCP 粘包/半包导致 JSON 解析失败
//  - stop-and-wait + offset 校验 + mismatch 自纠正，支持断点续传
//  - hello 看门狗 + 服务端静默看门狗 + 指数退避重连，不再有僵尸连接
//  - 所有请求统一 msgId 配对 + 超时，杜绝无限挂起
//  - 本文件不引用 dart:io，全平台（含 Web）可编译
//
// 状态持有：连接状态 / 在线设备 / 剪切板 / 文件列表，本身就是
// ChangeNotifier，UI 直接监听即可。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/protocol.dart';
import '../models/clipboard_item.dart';
import '../models/cloud_file.dart';
import '../models/device_info.dart';

enum ConnState { disconnected, connecting, connected }

/// 服务端返回的业务错误（带 code，可转中文）。
class ServerError implements Exception {
  final String code;
  ServerError(this.code);

  @override
  String toString() => friendlyError(code);
}

/// 可重试的传输中断（掉线等），调用方可重新发起以续传。
class RetryableError implements Exception {
  final String message;
  RetryableError(this.message);
  @override
  String toString() => message;
}

/// 用户取消。
class CancelledError implements Exception {
  @override
  String toString() => '已取消';
}

class CloudService extends ChangeNotifier {
  final _uuid = const Uuid();

  // ---------------- 配置（由控制器写入持久化设置后 apply）
  String serverUrl = '';
  String spaceId = '';
  String spaceKey = '';
  String apiKey = '';
  String deviceId = '';
  String deviceName = '我的设备';
  String platform = 'unknown';

  // ---------------- 状态
  ConnState state = ConnState.disconnected;

  /// 最近一次错误码（UI 转中文展示），成功连接后清零。
  String? lastErrorCode;
  String? lastErrorMessage;

  int maxFileBytes = 2 * 1024 * 1024 * 1024;
  int maxClipChars = 100000;

  List<DeviceInfo> devices = const [];
  ClipboardItem? clipLatest;
  List<ClipboardItem> clipHistory = const [];
  List<CloudFile> files = const [];

  /// welcome 之后服务端确认的 deviceId（控制器负责持久化）。
  String? confirmedDeviceId;

  // ---------------- 连接内部
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _helloTimer;
  bool _manualClose = false;
  bool _disposed = false;
  int _attempt = 0;
  DateTime _lastRecv = DateTime.now();

  Timer? _notifyTimer;
  bool _notifyPending = false;

  final Map<String, Completer<Map<String, dynamic>>> _waiters = {};
  final Map<String, Completer<Map<String, dynamic>>> _dlWaiters = {};

  bool get isConnected => state == ConnState.connected;

  void applyConfig({
    required String serverUrl,
    required String spaceId,
    required String spaceKey,
    required String apiKey,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    this.serverUrl = serverUrl;
    this.spaceId = spaceId;
    this.spaceKey = spaceKey;
    this.apiKey = apiKey;
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    this.platform = platform;
  }

  void _throttledNotify() {
    if (_disposed) return;
    _notifyPending = true;
    _notifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      if (_notifyPending && !_disposed) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  void _setState(ConnState s) {
    state = s;
    _throttledNotify();
  }

  void _setError(String code, [String? message]) {
    lastErrorCode = code;
    lastErrorMessage = message;
    _throttledNotify();
  }

  // ---------------- 连接

  /// 用户主动连接（重置退避计数）。
  Future<void> connect() {
    _manualClose = false;
    _attempt = 0;
    _reconnectTimer?.cancel();
    return _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _manualClose) return;
    if (state == ConnState.connecting || state == ConnState.connected) return;

    final normalized = normalizeServerUrl(serverUrl);
    if (normalized == null) {
      _setError('bad_url', '服务端地址格式不对');
      _setState(ConnState.disconnected);
      return;
    }
    if (!isValidSpaceId(spaceId)) {
      _setError('bad_space_id');
      _setState(ConnState.disconnected);
      return;
    }
    if (deviceId.isEmpty) {
      _setError('bad_config', '设备 ID 缺失，请重装或清除数据');
      _setState(ConnState.disconnected);
      return;
    }

    _setState(ConnState.connecting);
    _cleanupChannel();

    try {
      final uri = Uri.parse(normalized);
      _channel = WebSocketChannel.connect(uri);
      _lastRecv = DateTime.now();
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _handleDisconnect('socket error'),
        onDone: () => _handleDisconnect('socket done'),
        cancelOnError: false,
      );
      _startWatchdog();

      _rawSend({
        'type': 'hello',
        'protocol': kProtocolVersion,
        'spaceId': spaceId.trim(),
        'spaceKey': spaceKey,
        'apiKey': apiKey,
        'device': {
          'id': deviceId,
          'name': deviceName,
          'platform': platform,
        },
      });
      // hello 看门狗：15s 内没收到 welcome 则掐线走重连
      _helloTimer?.cancel();
      _helloTimer = Timer(kHelloTimeout, () {
        if (!_disposed &&
            !_manualClose &&
            state == ConnState.connecting) {
          _failWaiters('hello 超时');
          try {
            _channel?.sink.close();
          } catch (_) {}
          _handleDisconnect('hello timeout');
        }
      });
    } catch (e) {
      debugPrint('connect failed: $e');
      _handleDisconnect('connect exception');
    }
  }

  /// 用户主动断开（不再自动重连）。
  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _helloTimer?.cancel();
    _failWaiters('连接已断开');
    _cleanupChannel();
    _setState(ConnState.disconnected);
  }

  Future<void> reconnectNow() {
    _manualClose = false;
    _attempt = 0;
    _reconnectTimer?.cancel();
    _failWaiters('正在重连');
    _cleanupChannel();
    return _doConnect();
  }

  void _cleanupChannel() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _handleDisconnect(String reason) {
    debugPrint('disconnected: $reason');
    _helloTimer?.cancel();
    _failWaiters('连接已断开');
    _cleanupChannel();
    if (_disposed || _manualClose) {
      _setState(ConnState.disconnected);
      return;
    }
    _setState(ConnState.disconnected);
    final delay = reconnectDelay(_attempt++);
    final jitter = Random().nextInt(500);
    debugPrint('reconnect in ${delay.inSeconds}s (attempt $_attempt)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay + Duration(milliseconds: jitter), () {
      if (!_disposed && !_manualClose) _doConnect();
    });
  }

  void _startWatchdog() {
    if (_watchdogTimer != null && _watchdogTimer!.isActive) return;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed || _manualClose) return;
      if (state == ConnState.connected &&
          DateTime.now().difference(_lastRecv) > kSilenceTimeout) {
        debugPrint('silence timeout, reconnecting');
        _handleDisconnect('silence timeout');
      }
    });
  }

  void _failWaiters(String message) {
    if (_waiters.isEmpty && _dlWaiters.isEmpty) return;
    final err = RetryableError(message);
    for (final c in _waiters.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _waiters.clear();
    for (final c in _dlWaiters.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _dlWaiters.clear();
  }

  // ---------------- 收发

  void _rawSend(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) throw RetryableError('连接已断开');
    ch.sink.add(jsonEncode(msg));
  }

  void _ensureConnected() {
    if (state != ConnState.connected || _channel == null) {
      throw RetryableError('连接已断开，可重连后重试');
    }
  }

  /// 发送带 msgId 的请求，等待服务端回执（refMsgId 配对）。
  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> msg, {
    Duration timeout = kRequestTimeout,
  }) {
    _ensureConnected();
    final msgId = _uuid.v4();
    msg['msgId'] = msgId;
    final c = Completer<Map<String, dynamic>>();
    _waiters[msgId] = c;
    try {
      _rawSend(msg);
    } catch (e) {
      _waiters.remove(msgId);
      rethrow;
    }
    return c.future.timeout(timeout, onTimeout: () {
      _waiters.remove(msgId);
      throw TimeoutException('等待服务端响应超时');
    });
  }

  void _onData(dynamic data) {
    _lastRecv = DateTime.now();
    Map<String, dynamic> msg;
    try {
      if (data is! String) return;
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }
    final type = msg['type'] as String?;
    switch (type) {
      case 'welcome':
        _onWelcome(msg);
        break;
      case 'ping':
        try {
          _rawSend({'type': 'pong', 'ts': msg['ts']});
        } catch (_) {}
        break;
      case 'pong':
        break;
      case 'presence':
        _onPresence(msg);
        break;
      case 'clipboard_update':
        _onClipUpdate(msg);
        break;
      case 'clipboard_history':
        _onClipHistory(msg);
        break;
      case 'file_list':
        _onFileList(msg);
        break;
      case 'file_announced':
        _completeWaiter(msg);
        _onFileListMaybe(msg);
        break;
      case 'file_chunk_ack':
        _completeWaiter(msg);
        break;
      case 'file_progress':
        _onFileProgress(msg);
        break;
      case 'file_download_chunk':
        _onDownloadChunk(msg);
        break;
      case 'file_deleted':
        _onFileDeleted(msg);
        break;
      case 'error':
        _onErrorMsg(msg);
        break;
      default:
        debugPrint('unknown msg type: $type');
    }
  }

  void _completeWaiter(Map<String, dynamic> msg) {
    final ref = msg['refMsgId'] as String?;
    if (ref != null) {
      final c = _waiters.remove(ref);
      if (c != null && !c.isCompleted) c.complete(msg);
    }
  }

  void _failWaiter(Map<String, dynamic> errMsg) {
    final ref = errMsg['refMsgId'] as String?;
    final code = errMsg['code'] as String? ?? 'internal';
    if (ref != null) {
      final c = _waiters.remove(ref);
      if (c != null && !c.isCompleted) {
        c.completeError(ServerError(code));
        return;
      }
    }
    // 下载等待按 fileId 配对
    final fid = errMsg['fileId'] as String?;
    if (fid != null) {
      final c = _dlWaiters.remove(fid);
      if (c != null && !c.isCompleted) {
        c.completeError(ServerError(code));
        return;
      }
    }
    // 无人认领的错误：展示给 UI
    _setError(code);
  }

  void _onWelcome(Map<String, dynamic> msg) {
    _helloTimer?.cancel();
    _attempt = 0;
    lastErrorCode = null;
    lastErrorMessage = null;
    final v = msg['maxFileBytes'];
    if (v is num) maxFileBytes = v.toInt();
    final cc = msg['maxClipChars'];
    if (cc is num) maxClipChars = cc.toInt();
    final did = msg['deviceId'] as String?;
    if (did != null && did.isNotEmpty) confirmedDeviceId = did;
    _setState(ConnState.connected);
  }

  void _onPresence(Map<String, dynamic> msg) {
    final list = msg['devices'];
    if (list is! List) return;
    final out = <DeviceInfo>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(DeviceInfo.fromJson(e));
        } catch (_) {}
      }
    }
    devices = List.unmodifiable(out);
    _throttledNotify();
  }

  void _onClipUpdate(Map<String, dynamic> msg) {
    final raw = msg['item'];
    if (raw is! Map<String, dynamic>) return;
    ClipboardItem item;
    try {
      item = ClipboardItem.fromJson(raw);
    } catch (_) {
      return;
    }
    if (item.text.isEmpty) return;
    clipLatest = item;
    final hist = clipHistory.toList();
    hist.removeWhere((e) => e.id == item.id);
    hist.insert(0, item);
    if (hist.length > 100) hist.removeRange(100, hist.length);
    clipHistory = List.unmodifiable(hist);
    _completeWaiter(msg); // push 的确认（带 refMsgId 广播回来）
    _throttledNotify();
  }

  void _onClipHistory(Map<String, dynamic> msg) {
    final list = msg['items'];
    if (list is! List) return;
    final out = <ClipboardItem>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          final item = ClipboardItem.fromJson(e);
          if (item.text.isNotEmpty) out.add(item);
        } catch (_) {}
      }
    }
    clipHistory = List.unmodifiable(out);
    clipLatest ??= out.isNotEmpty ? out.first : null;
    _throttledNotify();
  }

  void _onFileList(Map<String, dynamic> msg) {
    final list = msg['files'];
    if (list is! List) return;
    files = List.unmodifiable(_parseFiles(list));
    _throttledNotify();
  }

  void _onFileListMaybe(Map<String, dynamic> msg) {
    final f = msg['file'];
    if (f is Map<String, dynamic>) {
      try {
        final cf = CloudFile.fromJson(f);
        final cur = files.toList();
        final i = cur.indexWhere((e) => e.id == cf.id);
        if (i >= 0) {
          cur[i] = cf;
        } else {
          cur.insert(0, cf);
        }
        files = List.unmodifiable(cur);
        _throttledNotify();
      } catch (_) {}
    }
  }

  List<CloudFile> _parseFiles(List list) {
    final out = <CloudFile>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(CloudFile.fromJson(e));
        } catch (_) {}
      }
    }
    return out;
  }

  void _onFileProgress(Map<String, dynamic> msg) {
    final fid = msg['fileId'] as String?;
    final up = (msg['uploadedBytes'] as num?)?.toInt();
    if (fid == null || up == null) return;
    final cur = files.toList();
    final i = cur.indexWhere((e) => e.id == fid);
    if (i < 0) return;
    final old = cur[i];
    cur[i] = CloudFile(
      id: old.id,
      name: old.name,
      size: old.size,
      uploadedBytes: up.clamp(0, old.size),
      complete: msg['complete'] == true,
      ownerDeviceId: old.ownerDeviceId,
      ownerDeviceName: old.ownerDeviceName,
      createdAt: old.createdAt,
      expiresAt: old.expiresAt,
    );
    files = List.unmodifiable(cur);
    _throttledNotify();
  }

  void _onDownloadChunk(Map<String, dynamic> msg) {
    final fid = msg['fileId'] as String?;
    if (fid == null) return;
    final c = _dlWaiters.remove(fid);
    if (c != null && !c.isCompleted) c.complete(msg);
  }

  void _onFileDeleted(Map<String, dynamic> msg) {
    final fid = msg['fileId'] as String?;
    if (fid == null) return;
    // 直接回复（带 refMsgId）先完成等待者
    _completeWaiter(msg);
    final cur = files.toList()..removeWhere((e) => e.id == fid);
    files = List.unmodifiable(cur);
    _throttledNotify();
  }

  void _onErrorMsg(Map<String, dynamic> msg) {
    _failWaiter(msg);
  }

  // ---------------- 业务 API

  Future<void> pushClipboard(String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ArgumentError('内容为空');
    if (t.length > maxClipChars) {
      throw ServerError('clip_too_large');
    }
    final resp = await _request({'type': 'clipboard_push', 'text': t});
    // 服务端广播 clipboard_update 回来即算成功；若被去重也会带 deduped 回来
    if (resp['type'] != 'clipboard_update') {
      throw StateError('意外的服务端响应');
    }
  }

  Future<void> refreshAll() async {
    _ensureConnected();
    _rawSend({'type': 'clipboard_history_request'});
    _rawSend({'type': 'file_list_request'});
  }

  /// 公布文件并返回服务端视角的元信息（含已上传字节，用于续传）。
  Future<CloudFile> announceFile({
    required String fileId,
    required String fileName,
    required int fileSize,
  }) async {
    if (!kFileIdExp.hasMatch(fileId)) {
      throw ArgumentError('文件 ID 非法');
    }
    if (fileSize <= 0 || fileSize > maxFileBytes) {
      throw ServerError('bad_file_size');
    }
    final resp = await _request({
      'type': 'file_announce',
      'fileId': fileId,
      'name': fileName,
      'size': fileSize,
    });
    final f = resp['file'];
    if (f is! Map<String, dynamic>) throw StateError('意外的服务端响应');
    return CloudFile.fromJson(f);
  }

  /// 分块上传（stop-and-wait）。readChunk(offset, length) 按需读块。
  Future<void> uploadChunks({
    required String fileId,
    required int fileSize,
    required Future<Uint8List> Function(int offset, int length) readChunk,
    required int startOffset,
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var offset = startOffset.clamp(0, fileSize);
    onProgress?.call(offset, fileSize);
    while (offset < fileSize) {
      if (isCancelled?.call() == true) throw CancelledError();
      _ensureConnected();
      final len = min(kChunkSize, fileSize - offset);
      Uint8List bytes;
      try {
        bytes = await readChunk(offset, len);
      } catch (e) {
        throw RetryableError('读取本地文件失败：$e');
      }
      if (bytes.isEmpty) {
        throw RetryableError('读取本地文件失败（空块）');
      }
      if (offset + bytes.length > fileSize) {
        throw StateError('本地文件大小发生变化，请重新选择');
      }
      final isLast = offset + bytes.length == fileSize;
      final ack = await _request(
        {
          'type': 'file_chunk',
          'fileId': fileId,
          'offset': offset,
          'dataBase64': base64.encode(bytes),
          'isLast': isLast,
        },
        timeout: kChunkTimeout,
      );
      if (ack['type'] != 'file_chunk_ack') {
        throw StateError('意外的服务端响应');
      }
      final serverBytes = (ack['uploadedBytes'] as num?)?.toInt() ?? -1;
      if (serverBytes < 0) throw StateError('意外的服务端响应');
      if (ack['mismatch'] == true) {
        // 服务端纠正：seek 到正确位置重发（不算错误）
        offset = serverBytes.clamp(0, fileSize);
        onProgress?.call(offset, fileSize);
        continue;
      }
      offset = serverBytes.clamp(0, fileSize);
      onProgress?.call(offset, fileSize);
      if (ack['complete'] == true) break;
    }
  }

  /// 分块下载（stop-and-wait）。write(offset, bytes, isLast) 顺序写入。
  Future<void> downloadTo({
    required String fileId,
    required int fileSize,
    required Future<void> Function(int offset, Uint8List bytes, bool isLast)
        write,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var offset = 0;
    onProgress?.call(0, fileSize);
    // 死循环保护：连续空块 / 无进展超过 N 次则报错
    var emptyStreak = 0;
    while (true) {
      if (isCancelled?.call() == true) throw CancelledError();
      _ensureConnected();
      final c = Completer<Map<String, dynamic>>();
      _dlWaiters[fileId] = c;
      try {
        _rawSend({
          'type': 'file_download_request',
          'msgId': _uuid.v4(),
          'fileId': fileId,
          'offset': offset,
        });
      } catch (e) {
        _dlWaiters.remove(fileId);
        rethrow;
      }
      Map<String, dynamic> resp;
      try {
        resp = await c.future.timeout(kChunkTimeout, onTimeout: () {
          _dlWaiters.remove(fileId);
          throw TimeoutException('下载超时');
        });
      } finally {
        _dlWaiters.remove(fileId);
      }
      if (resp['type'] != 'file_download_chunk') {
        throw StateError('意外的服务端响应');
      }
      final at = (resp['offset'] as num?)?.toInt() ?? -1;
      if (at != offset) {
        throw RetryableError('服务端偏移不一致，请重试');
      }
      final b64 = resp['dataBase64'] as String? ?? '';
      Uint8List bytes;
      try {
        bytes = b64.isEmpty ? Uint8List(0) : base64.decode(b64);
      } catch (_) {
        throw RetryableError('数据块损坏，已中断，请重试');
      }
      final isLast = resp['isLast'] == true;
      if (bytes.isEmpty && !isLast) {
        if (++emptyStreak > 5) throw RetryableError('下载停滞，请重试');
        continue;
      }
      emptyStreak = 0;
      await write(offset, bytes, isLast);
      offset += bytes.length;
      if (offset > fileSize) throw RetryableError('文件大小不一致，请重试');
      onProgress?.call(offset, fileSize);
      if (isLast) break;
    }
  }

  Future<void> deleteFile(String fileId) async {
    final resp = await _request({'type': 'file_delete', 'fileId': fileId});
    if (resp['type'] != 'file_deleted') {
      throw StateError('意外的服务端响应');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _manualClose = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _helloTimer?.cancel();
    _notifyTimer?.cancel();
    _failWaiters('已释放');
    _cleanupChannel();
    super.dispose();
  }
}
