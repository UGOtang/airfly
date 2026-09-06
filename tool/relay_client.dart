// AirFly 云中转纯 Dart 客户端（零第三方依赖，仅 dart SDK）。
// 给 TUI / 脚本 / 测试用：dart run 或随 TUI 一起 dart compile exe。
// 与 Flutter 端 CloudService 同协议（见 PROTOCOL.md），行为对齐：
// stop-and-wait + offset 校验 + msgId 配对 + 超时 + 指数退避重连。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ---------------------------------------------------------------- 模型

class RelayDevice {
  final String id;
  final String name;
  final String platform;
  final DateTime connectedAt;

  const RelayDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.connectedAt,
  });

  factory RelayDevice.fromJson(Map<String, dynamic> j) => RelayDevice(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? '未知设备'}',
        platform: '${j['platform'] ?? 'unknown'}',
        connectedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['connectedAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

class RelayClip {
  final String id;
  final String text;
  final String deviceId;
  final String deviceName;
  final DateTime updatedAt;

  const RelayClip({
    required this.id,
    required this.text,
    required this.deviceId,
    required this.deviceName,
    required this.updatedAt,
  });

  factory RelayClip.fromJson(Map<String, dynamic> j) => RelayClip(
        id: '${j['id'] ?? ''}',
        text: '${j['text'] ?? ''}',
        deviceId: '${j['deviceId'] ?? ''}',
        deviceName: '${j['deviceName'] ?? '未知设备'}',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['updatedAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

class RelayFile {
  final String id;
  final String name;
  final int size;
  final int uploadedBytes;
  final bool complete;
  final String ownerDeviceId;
  final String ownerDeviceName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const RelayFile({
    required this.id,
    required this.name,
    required this.size,
    required this.uploadedBytes,
    required this.complete,
    required this.ownerDeviceId,
    required this.ownerDeviceName,
    required this.createdAt,
    required this.expiresAt,
  });

  factory RelayFile.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    return RelayFile(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? 'unnamed'}',
      size: asInt(j['size']),
      uploadedBytes: asInt(j['uploadedBytes']),
      complete: j['complete'] == true,
      ownerDeviceId: '${j['ownerDeviceId'] ?? ''}',
      ownerDeviceName: '${j['ownerDeviceName'] ?? '未知设备'}',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(asInt(j['createdAt'])),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(asInt(j['expiresAt'])),
    );
  }

  double get progress {
    if (size <= 0) return 0;
    return (uploadedBytes / size).clamp(0.0, 1.0);
  }
}

class ServerError implements Exception {
  final String code;
  ServerError(this.code);
  @override
  String toString() => '服务端错误($code)';
}

class RetryableError implements Exception {
  final String message;
  RetryableError(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- 客户端

class RelayClient {
  String serverUrl;
  String spaceId;
  String spaceKey;
  String apiKey;
  String deviceId;
  String deviceName;
  String platform;

  bool connected = false;
  String? lastErrorCode;
  String? lastErrorMessage;
  int maxFileBytes = 2 * 1024 * 1024 * 1024;
  int maxClipChars = 100000;

  List<RelayDevice> devices = const [];
  RelayClip? clipLatest;
  List<RelayClip> clipHistory = const [];
  List<RelayFile> files = const [];

  /// 任何状态变化都回调（TUI 重绘 / 日志）。
  void Function()? onEvent;

  /// 已安排的重连次数（测试/状态展示用；duplicate 拒收后应保持 0）。
  int get reconnectAttempts => _attempt;

  WebSocket? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _helloTimer;
  Timer? _watchdogTimer;
  bool _manualClose = false;
  bool _disposed = false;
  int _attempt = 0;
  DateTime _lastRecv = DateTime.now();
  int _msgSeq = 0;

  /// duplicate_device 拒收后为 true：停自动重连（与 Flutter 端同逻辑）。
  bool _duplicateRejected = false;
  DateTime? _lastDisconnectAt;

  final Map<String, Completer<Map<String, dynamic>>> _waiters = {};
  final Map<String, Completer<Map<String, dynamic>>> _dlWaiters = {};

  static const int kChunkSize = 128 * 1024;
  static const Duration kChunkTimeout = Duration(seconds: 30);
  static const Duration kRequestTimeout = Duration(seconds: 20);
  static const Duration kHelloTimeout = Duration(seconds: 15);
  static const Duration kSilenceTimeout = Duration(seconds: 45);

  RelayClient({
    required this.serverUrl,
    required this.spaceId,
    this.spaceKey = '',
    this.apiKey = '',
    required this.deviceId,
    this.deviceName = 'tui',
    this.platform = 'console',
  });

  String _nextMsgId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_msgSeq++}_${Random().nextInt(1 << 32)}';

  void _emit() {
    try {
      onEvent?.call();
    } catch (_) {}
  }

  // ---------------- 连接

  Future<void> connect() {
    _manualClose = false;
    _duplicateRejected = false;
    _attempt = 0;
    _reconnectTimer?.cancel();
    return _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _manualClose) return;
    Uri uri;
    try {
      uri = Uri.parse(serverUrl);
      if (uri.scheme != 'ws' && uri.scheme != 'wss') throw FormatException();
      if (uri.host.isEmpty) throw FormatException();
    } catch (_) {
      lastErrorCode = 'bad_url';
      lastErrorMessage = '服务端地址格式不对';
      connected = false;
      _emit();
      return;
    }
    _cleanupChannel();
    try {
      _ws = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 15));
      _lastRecv = DateTime.now();
      _sub = _ws!.listen(
        _onData,
        onError: (_) => _handleDisconnect('socket error'),
        onDone: () => _handleDisconnect('socket done'),
        cancelOnError: false,
      );
      _startWatchdog();
      _send({
        'type': 'hello',
        'protocol': 1,
        'spaceId': spaceId.trim(),
        'spaceKey': spaceKey,
        'apiKey': apiKey,
        'device': {'id': deviceId, 'name': deviceName, 'platform': platform},
      });
      _helloTimer?.cancel();
      _helloTimer = Timer(kHelloTimeout, () {
        _failWaiters('hello 超时');
        try {
          _ws?.close();
        } catch (_) {}
        _handleDisconnect('hello timeout');
      });
    } catch (e) {
      _handleDisconnect('connect failed: $e');
    }
  }

  Future<void> reconnectNow() {
    _manualClose = false;
    _duplicateRejected = false;
    _attempt = 0;
    _reconnectTimer?.cancel();
    _failWaiters('正在重连');
    _cleanupChannel();
    return _doConnect();
  }

  Future<void> close() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _helloTimer?.cancel();
    _failWaiters('连接已断开');
    _cleanupChannel();
    connected = false;
    _emit();
  }

  void _cleanupChannel() {
    _sub?.cancel();
    _sub = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  void _handleDisconnect(String reason) {
    _helloTimer?.cancel();
    _failWaiters('连接已断开');
    _cleanupChannel();
    connected = false;
    _emit();
    _lastDisconnectAt = DateTime.now();
    if (_disposed || _manualClose || _duplicateRejected) return;
    final delay = _backoff(_attempt++);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      delay + Duration(milliseconds: Random().nextInt(500)),
      () {
        if (!_disposed && !_manualClose) _doConnect();
      },
    );
  }

  static Duration _backoff(int attempt) {
    var secs = 1 << attempt.clamp(0, 5);
    if (secs > 30) secs = 30;
    return Duration(seconds: secs);
  }

  void _startWatchdog() {
    if (_watchdogTimer != null && _watchdogTimer!.isActive) return;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed || _manualClose || !connected) return;
      if (DateTime.now().difference(_lastRecv) > kSilenceTimeout) {
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

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) throw RetryableError('连接已断开');
    ws.add(jsonEncode(msg));
  }

  void _ensureConnected() {
    if (!connected || _ws == null) throw RetryableError('未连接');
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> msg, {
    Duration timeout = kRequestTimeout,
  }) {
    _ensureConnected();
    final msgId = _nextMsgId();
    msg['msgId'] = msgId;
    final c = Completer<Map<String, dynamic>>();
    _waiters[msgId] = c;
    try {
      _send(msg);
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
    Map<String, dynamic>? msg;
    try {
      if (data is String) {
        final d = jsonDecode(data);
        if (d is Map<String, dynamic>) msg = d;
      }
    } catch (_) {}
    if (msg == null) return;
    switch (msg['type'] as String?) {
      case 'welcome':
        _onWelcome(msg);
        break;
      case 'ping':
        try {
          _send({'type': 'pong', 'ts': msg['ts']});
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
        _mergeFile(msg['file']);
        break;
      case 'file_chunk_ack':
        _completeWaiter(msg);
        break;
      case 'file_progress':
        _onFileProgress(msg);
        break;
      case 'file_download_chunk':
        final fid = msg['fileId'] as String?;
        if (fid != null) {
          final c = _dlWaiters.remove(fid);
          if (c != null && !c.isCompleted) c.complete(msg);
        }
        break;
      case 'file_deleted':
        _completeWaiter(msg);
        final fid = msg['fileId'] as String?;
        if (fid != null) {
          files = List.unmodifiable(
              files.where((e) => e.id != fid).toList());
          _emit();
        }
        break;
      case 'error':
        _onErrorMsg(msg);
        break;
      default:
        break;
    }
  }

  void _completeWaiter(Map<String, dynamic> msg) {
    final ref = msg['refMsgId'] as String?;
    if (ref == null) return;
    final c = _waiters.remove(ref);
    if (c != null && !c.isCompleted) c.complete(msg);
  }

  void _onErrorMsg(Map<String, dynamic> msg) {
    final ref = msg['refMsgId'] as String?;
    final code = msg['code'] as String? ?? 'internal';
    if (ref != null) {
      final c = _waiters.remove(ref);
      if (c != null && !c.isCompleted) {
        c.completeError(ServerError(code));
        return;
      }
    }
    final fid = msg['fileId'] as String?;
    if (fid != null) {
      final c = _dlWaiters.remove(fid);
      if (c != null && !c.isCompleted) {
        c.completeError(ServerError(code));
        return;
      }
    }
    lastErrorCode = code;
    if (code == 'duplicate_device') {
      _duplicateRejected = true;
    }
    _emit();
  }

  void _onWelcome(Map<String, dynamic> msg) {
    _helloTimer?.cancel();
    final sinceDisc = _lastDisconnectAt == null
        ? null
        : DateTime.now().difference(_lastDisconnectAt!);
    if (sinceDisc == null || sinceDisc > const Duration(seconds: 10)) {
      _attempt = 0;
    }
    _duplicateRejected = false;
    lastErrorCode = null;
    lastErrorMessage = null;
    final v = msg['maxFileBytes'];
    if (v is num) maxFileBytes = v.toInt();
    final cc = msg['maxClipChars'];
    if (cc is num) maxClipChars = cc.toInt();
    connected = true;
    _emit();
  }

  void _onPresence(Map<String, dynamic> msg) {
    final list = msg['devices'];
    if (list is! List) return;
    final out = <RelayDevice>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(RelayDevice.fromJson(e));
        } catch (_) {}
      }
    }
    devices = List.unmodifiable(out);
    _emit();
  }

  void _onClipUpdate(Map<String, dynamic> msg) {
    final raw = msg['item'];
    if (raw is! Map<String, dynamic>) return;
    RelayClip item;
    try {
      item = RelayClip.fromJson(raw);
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
    _completeWaiter(msg);
    _emit();
  }

  void _onClipHistory(Map<String, dynamic> msg) {
    final list = msg['items'];
    if (list is! List) return;
    final out = <RelayClip>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          final item = RelayClip.fromJson(e);
          if (item.text.isNotEmpty) out.add(item);
        } catch (_) {}
      }
    }
    clipHistory = List.unmodifiable(out);
    clipLatest ??= out.isNotEmpty ? out.first : null;
    _emit();
  }

  List<RelayFile> _parseFiles(List list) {
    final out = <RelayFile>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(RelayFile.fromJson(e));
        } catch (_) {}
      }
    }
    return out;
  }

  void _onFileList(Map<String, dynamic> msg) {
    final list = msg['files'];
    if (list is! List) return;
    files = List.unmodifiable(_parseFiles(list));
    _emit();
  }

  void _mergeFile(dynamic raw) {
    if (raw is! Map<String, dynamic>) return;
    try {
      final cf = RelayFile.fromJson(raw);
      final cur = files.toList();
      final i = cur.indexWhere((e) => e.id == cf.id);
      if (i >= 0) {
        cur[i] = cf;
      } else {
        cur.insert(0, cf);
      }
      files = List.unmodifiable(cur);
      _emit();
    } catch (_) {}
  }

  void _onFileProgress(Map<String, dynamic> msg) {
    final fid = msg['fileId'] as String?;
    final up = (msg['uploadedBytes'] as num?)?.toInt();
    if (fid == null || up == null) return;
    final cur = files.toList();
    final i = cur.indexWhere((e) => e.id == fid);
    if (i < 0) return;
    final old = cur[i];
    cur[i] = RelayFile(
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
    _emit();
  }

  // ---------------- 业务 API

  Future<void> pushClip(String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ArgumentError('内容为空');
    if (t.length > maxClipChars) throw ServerError('clip_too_large');
    final resp = await _request({'type': 'clipboard_push', 'text': t});
    if (resp['type'] != 'clipboard_update') throw StateError('意外的响应');
  }

  Future<void> refresh() async {
    _ensureConnected();
    _send({'type': 'clipboard_history_request'});
    _send({'type': 'file_list_request'});
  }

  Future<RelayFile> announceFile({
    required String fileId,
    required String fileName,
    required int fileSize,
  }) async {
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
    if (f is! Map<String, dynamic>) throw StateError('意外的响应');
    return RelayFile.fromJson(f);
  }

  /// 上传一块，返回 (uploadedBytes, complete, mismatch)。
  Future<(int, bool, bool)> uploadChunk({
    required String fileId,
    required int offset,
    required List<int> bytes,
    required bool isLast,
  }) async {
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
    if (ack['type'] != 'file_chunk_ack') throw StateError('意外的响应');
    return (
      (ack['uploadedBytes'] as num?)?.toInt() ?? -1,
      ack['complete'] == true,
      ack['mismatch'] == true,
    );
  }

  /// 取一块下载数据，返回 (offset, bytes, isLast)。
  Future<(int, List<int>, bool)> downloadChunk({
    required String fileId,
    required int offset,
  }) async {
    _ensureConnected();
    final c = Completer<Map<String, dynamic>>();
    _dlWaiters[fileId] = c;
    try {
      _send({
        'type': 'file_download_request',
        'msgId': _nextMsgId(),
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
      throw StateError('意外的响应');
    }
    final at = (resp['offset'] as num?)?.toInt() ?? -1;
    final b64 = resp['dataBase64'] as String? ?? '';
    List<int> bytes;
    try {
      bytes = b64.isEmpty ? const [] : base64.decode(b64);
    } catch (_) {
      throw RetryableError('数据块损坏，请重试');
    }
    return (at, bytes, resp['isLast'] == true);
  }

  Future<void> deleteFile(String fileId) async {
    final resp = await _request({'type': 'file_delete', 'fileId': fileId});
    if (resp['type'] != 'file_deleted') throw StateError('意外的响应');
  }

  Future<void> dispose() async {
    _disposed = true;
    _manualClose = true;
    _reconnectTimer?.cancel();
    _helloTimer?.cancel();
    _watchdogTimer?.cancel();
    _failWaiters('已释放');
    _cleanupChannel();
  }
}
