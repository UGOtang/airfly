// 应用状态控制器：设置持久化 + 剪切板自动同步 + 文件上传下载任务。
// 传输走 CloudService（单 WebSocket 云中转），本类只做任务编排与 UI 状态。
// 不引用 dart:io，全平台可编译；平台差异由 core/chunk_io.dart 屏蔽。

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/chunk_io.dart';
import '../core/term_session.dart';
import '../models/cloud_file.dart';
import '../services/cloud_service.dart';

class AppController extends ChangeNotifier {
  final CloudService service = CloudService();

  /// 本地终端会话（UI 直接监听它）。
  late final TermSession terminal = TermSession();
  final _uuid = const Uuid();

  // ---------------- 设置（持久化）
  String serverUrl = '';
  String spaceId = '';
  String spaceKey = '';
  String apiKey = '';
  String deviceName = '我的设备';
  String deviceId = '';
  bool autoPushClip = false;
  bool autoPullClip = false;

  /// 外观模式，默认跟随系统。
  /// 用独立 ValueNotifier 持有：main 只监听它，避免传输进度每 100ms
  /// 的通知把整个 MaterialApp 重建一遍。
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);

  bool isInitialized = false;
  bool _appPaused = false;

  // ---------------- 任务
  final Map<String, TransferTask> _tasks = {};
  final Map<String, _UploadSource> _uploadSources = {};

  List<TransferTask> get tasks {
    final list = _tasks.values.toList();
    list.sort((a, b) {
      int rank(TransferState s) {
        switch (s) {
          case TransferState.active:
            return 0;
          case TransferState.queued:
          case TransferState.paused:
            return 1;
          case TransferState.failed:
            return 2;
          case TransferState.cancelled:
            return 3;
          case TransferState.done:
            return 4;
        }
      }

      final r = rank(a.state).compareTo(rank(b.state));
      if (r != 0) return r;
      return b.key.compareTo(a.key);
    });
    return list;
  }

  // ---------------- 剪切板同步内部
  Timer? _clipPollTimer;
  String? _lastLocalClip;
  String? _lastPushed;
  String? _lastSeenRemoteId;

  Timer? _notifyTimer;
  bool _notifyPending = false;

  void _throttledNotify() {
    _notifyPending = true;
    _notifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      if (_notifyPending) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------- 初始化

  Future<void> initialize() async {
    if (isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      serverUrl = prefs.getString('af_server_url') ?? '';
      spaceId = prefs.getString('af_space_id') ?? '';
      spaceKey = prefs.getString('af_space_key') ?? '';
      apiKey = prefs.getString('af_api_key') ?? '';
      deviceName =
          (prefs.getString('af_device_name') ?? '').trim().isEmpty
              ? '我的设备'
              : prefs.getString('af_device_name')!.trim();
      deviceId = prefs.getString('af_device_id') ?? '';
      if (deviceId.isEmpty) {
        deviceId = _uuid.v4();
        await prefs.setString('af_device_id', deviceId);
      }
      autoPushClip = prefs.getBool('af_auto_push') ?? false;
      autoPullClip = prefs.getBool('af_auto_pull') ?? false;
      themeMode.value = _parseThemeMode(prefs.getString('af_theme_mode'));

      _applyToService();
      service.addListener(_onServiceChanged);
      service.confirmedDeviceId; // 占位：welcome 回来后在回调里持久化
      _onServiceChanged(); // 初始化 UI 快照

      _clipPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollClipboard(),
      );

      await terminal.init();

      // 配好地址和空间码则自动连接
      if (serverUrl.trim().isNotEmpty && spaceId.trim().isNotEmpty) {
        unawaited(service.connect().catchError((_) {}));
      }
      isInitialized = true;
      _throttledNotify();
    } catch (e) {
      debugPrint('initialize failed: $e');
      isInitialized = true;
      _throttledNotify();
    }
  }

  void _applyToService() {
    service.applyConfig(
      serverUrl: serverUrl.trim(),
      spaceId: spaceId.trim(),
      spaceKey: spaceKey,
      apiKey: apiKey,
      deviceId: deviceId,
      deviceName: deviceName.trim().isEmpty ? '我的设备' : deviceName.trim(),
      platform: currentPlatform(),
    );
  }

  void _onServiceChanged() {
    // 服务端确认 deviceId（首次为空时分配）：持久化，保证重连稳定，
    // 避免旧版每次随机 ID 导致设备列表闪烁。
    final confirmed = service.confirmedDeviceId;
    if (confirmed != null &&
        confirmed.isNotEmpty &&
        confirmed != deviceId) {
      deviceId = confirmed;
      unawaited(SharedPreferences.getInstance().then(
        (p) => p.setString('af_device_id', deviceId),
      ));
      _applyToService();
    }
    // 自动拉取远端剪切板到本地
    final latest = service.clipLatest;
    if (autoPullClip &&
        latest != null &&
        latest.id != _lastSeenRemoteId &&
        latest.deviceId != deviceId) {
      _lastSeenRemoteId = latest.id;
      if (latest.text != _lastLocalClip) {
        _lastLocalClip = latest.text;
        unawaited(Clipboard.setData(ClipboardData(text: latest.text))
            .catchError((_) {}));
      }
    } else if (latest != null) {
      _lastSeenRemoteId ??= latest.id;
    }
    _throttledNotify();
  }

  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeKey(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 切换外观并持久化，即时生效。
  Future<void> setThemeMode(ThemeMode m) async {
    if (themeMode.value == m) return;
    themeMode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('af_theme_mode', _themeModeKey(m));
  }

  static String currentPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }

  // ---------------------------------------------------------------- 应用前后台

  void onAppPaused() {
    _appPaused = true;
  }

  void onAppResumed() {
    final was = _appPaused;
    _appPaused = false;
    if (was && service.isConnected) {
      // 回到前台刷新一次，防止后台期间的状态过期
      unawaited(service.refreshAll().catchError((_) {}));
    }
  }

  // ---------------------------------------------------------------- 设置

  Future<void> saveSettings({
    required String serverUrl,
    required String spaceId,
    required String spaceKey,
    required String apiKey,
    required String deviceName,
  }) async {
    this.serverUrl = serverUrl.trim();
    this.spaceId = spaceId.trim();
    this.spaceKey = spaceKey;
    this.apiKey = apiKey;
    final name = deviceName.trim();
    this.deviceName = name.isEmpty ? '我的设备' : name;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('af_server_url', this.serverUrl);
    await prefs.setString('af_space_id', this.spaceId);
    await prefs.setString('af_space_key', this.spaceKey);
    await prefs.setString('af_api_key', this.apiKey);
    await prefs.setString('af_device_name', this.deviceName);

    _applyToService();
    _throttledNotify();
    // 保存即重连，保证新配置立刻生效
    unawaited(service.reconnectNow().catchError((_) {}));
  }

  Future<void> setAutoSync({bool? push, bool? pull}) async {
    if (push != null) autoPushClip = push;
    if (pull != null) autoPullClip = pull;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('af_auto_push', autoPushClip);
    await prefs.setBool('af_auto_pull', autoPullClip);
    _throttledNotify();
  }

  Future<void> connect() => service.reconnectNow();
  Future<void> disconnect() => service.disconnect();

  /// 重置设备标识并重连：当提示“设备已在别处在线”（多因换机克隆
  /// 把旧设备 ID 一起搬过来，导致两端互踢）时用这个一键自救。
  /// 重置后本机是全新身份，老记录 90 秒内自动过期，不影响他人。
  Future<void> resetDeviceId() async {
    deviceId = _uuid.v4();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('af_device_id', deviceId);
    _applyToService();
    _throttledNotify();
    unawaited(service.reconnectNow().catchError((_) {}));
  }

  // ---------------------------------------------------------------- 剪切板

  /// 本地轮询：自动推送开启时，把本地新内容同步到云端。
  Future<void> _pollClipboard() async {
    if (!isInitialized || _appPaused || !autoPushClip) return;
    if (!service.isConnected) return;
    ClipboardData? data;
    try {
      data = await Clipboard.getData('text/plain');
    } catch (_) {
      return;
    }
    final text = data?.text ?? '';
    if (text.isEmpty || text == _lastLocalClip) return;
    _lastLocalClip = text;
    // 远端刚广播回来的内容不再推回去（防循环）
    if (text == service.clipLatest?.text) return;
    if (text == _lastPushed) return;
    if (text.length > service.maxClipChars) return; // 超限静默跳过
    try {
      await service.pushClipboard(text);
      _lastPushed = text;
    } catch (_) {
      // 自动推送失败不打扰用户，下次轮询内容不变则不再试
      _lastPushed = text;
    }
  }

  /// 手动推送（抛友好错误信息，由页面 snackbar 展示）。
  Future<void> pushClipboard(String text) async {
    try {
      await service.pushClipboard(text);
      _lastPushed = text.trim();
      _lastLocalClip = text.trim();
    } on ServerError catch (e) {
      throw e.toString();
    } on TimeoutException {
      throw '请求超时，请检查网络后重试';
    } on RetryableError catch (e) {
      throw e.message;
    }
  }

  Future<String?> readLocalClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  Future<void> copyToLocal(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _lastLocalClip = text;
  }

  // ---------------------------------------------------------------- 文件上传

  static const int kWebSoftLimit = 100 * 1024 * 1024;

  /// 无本地路径时的内存读取上限（移动端 SAF 等场景），超了请用桌面端。
  static const int kMemoryReadLimit = 200 * 1024 * 1024;

  Future<void> pickAndUpload() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles();
    } catch (e) {
      throw '选择文件失败：$e';
    }
    if (files.isEmpty) return;
    if (!service.isConnected) throw '未连接到服务端，请先连接';
    for (final f in files) {
      int size;
      try {
        size = f.lengthSync() ?? await f.length();
      } catch (_) {
        _addFailedUpload(f.name, '无法读取该文件大小');
        continue;
      }
      if (size <= 0) {
        _addFailedUpload(f.name, '空文件，跳过');
        continue;
      }
      if (size > service.maxFileBytes) {
        _addFailedUpload(f.name, '超出服务端单文件上限');
        continue;
      }
      if (kIsWeb && size > kWebSoftLimit) {
        _addFailedUpload(f.name, 'Web 端建议传 100MB 以内文件');
        continue;
      }
      var path = f.path;
      Uint8List? bytes;
      if (path == null || path.isEmpty) {
        // 无本地路径（如 Web / SAF）：一次性读入内存
        if (!kIsWeb && size > kMemoryReadLimit) {
          _addFailedUpload(f.name, '文件较大且无法直接读取，请用桌面端发送');
          continue;
        }
        try {
          bytes = await f.readAsBytes();
        } catch (e) {
          _addFailedUpload(f.name, '读取文件失败：$e');
          continue;
        }
        if (bytes.length != size) size = bytes.length;
        if (size <= 0) {
          _addFailedUpload(f.name, '空文件，跳过');
          continue;
        }
        path = null;
      }
      unawaited(_startUpload(
        name: f.name,
        size: size,
        path: path,
        bytes: bytes,
      ));
    }
    _throttledNotify();
  }

  void _addFailedUpload(String name, String reason) {
    final id = _uuid.v4().replaceAll('-', '');
    final task = TransferTask(
      key: 'up:$id',
      fileId: id,
      fileName: name,
      total: 0,
      isUpload: true,
      state: TransferState.failed,
      error: reason,
    );
    _tasks[task.key] = task;
    _throttledNotify();
  }

  Future<void> _startUpload({
    required String name,
    required int size,
    required String? path,
    required Uint8List? bytes,
    String? reuseFileId,
  }) async {
    final fileId = reuseFileId ?? _uuid.v4().replaceAll('-', '');
    final key = 'up:$fileId';
    var task = _tasks[key];
    if (task == null) {
      task = TransferTask(
        key: key,
        fileId: fileId,
        fileName: name,
        total: size,
        isUpload: true,
        state: TransferState.active,
      );
      _tasks[key] = task;
    } else {
      task.state = TransferState.active;
      task.error = null;
    }
    _uploadSources[fileId] =
        _UploadSource(name: name, size: size, path: path, bytes: bytes);
    _throttledNotify();

    ChunkReader? reader;
    try {
      reader = await openUploadReader(path: path, bytes: bytes);
      if (reader.size != size && !(reuseFileId != null)) {
        // 文件在选择后被修改：以实际大小为准并提示
        task.total = reader.size;
      }
      final total = reader.size;
      final meta = await service.announceFile(
        fileId: fileId,
        fileName: name,
        fileSize: total,
      );
      task.done = meta.uploadedBytes.clamp(0, total);
      _throttledNotify();
      final r = reader;
      await service.uploadChunks(
        fileId: fileId,
        fileSize: total,
        startOffset: task.done,
        readChunk: (off, len) => r.read(off, len),
        onProgress: (sent, _) {
          task!.done = sent;
          _throttledNotify();
        },
        isCancelled: () => task!.state == TransferState.cancelled,
      );
      task.state = TransferState.done;
      task.done = total;
      _uploadSources.remove(fileId);
      await service.refreshAll().catchError((_) {});
    } on CancelledError {
      task.state = TransferState.cancelled;
    } on ServerError catch (e) {
      task.state = TransferState.failed;
      task.error = e.toString();
    } on RetryableError catch (e) {
      // 保留已传进度，可重试续传
      task.state = TransferState.paused;
      task.error = '${e.message}（可重试续传）';
    } on TimeoutException {
      task.state = TransferState.paused;
      task.error = '网络超时，已保留进度，可重试续传';
    } catch (e) {
      task.state = TransferState.failed;
      task.error = '$e';
    } finally {
      try {
        await reader?.close();
      } catch (_) {}
      // Web 内存源及时释放
      if (task.state == TransferState.done ||
          task.state == TransferState.cancelled ||
          task.state == TransferState.failed) {
        final src = _uploadSources[fileId];
        if (src != null && (kIsWeb || task.state != TransferState.paused)) {
          _uploadSources.remove(fileId);
        }
      }
      _throttledNotify();
    }
  }

  Future<void> retryUpload(String key) async {
    final task = _tasks[key];
    if (task == null || !task.isUpload) return;
    if (task.state != TransferState.paused &&
        task.state != TransferState.failed &&
        task.state != TransferState.cancelled) {
      return;
    }
    if (!service.isConnected) throw '未连接到服务端，请先连接';
    final src = _uploadSources[task.fileId];
    if (src == null) {
      task.state = TransferState.failed;
      task.error = '本地文件引用已丢失，请重新选择';
      _throttledNotify();
      return;
    }
    await _startUpload(
      name: src.name,
      size: src.size,
      path: src.path,
      bytes: src.bytes,
      reuseFileId: task.fileId,
    );
  }

  void cancelTask(String key) {
    final task = _tasks[key];
    if (task == null) return;
    if (task.state == TransferState.active ||
        task.state == TransferState.queued ||
        task.state == TransferState.paused) {
      task.state = TransferState.cancelled;
      task.error = null;
      _throttledNotify();
    }
  }

  void dismissTask(String key) {
    final task = _tasks[key];
    if (task == null) return;
    if (task.state == TransferState.active ||
        task.state == TransferState.queued) {
      return; // 进行中的不允许直接移除，先取消
    }
    _tasks.remove(key);
    _throttledNotify();
  }

  void clearFinishedTasks() {
    _tasks.removeWhere((_, t) =>
        t.state == TransferState.done ||
        t.state == TransferState.failed ||
        t.state == TransferState.cancelled);
    _throttledNotify();
  }

  // ---------------------------------------------------------------- 文件下载

  Future<void> startDownload(CloudFile file) async {
    if (!file.complete) throw '文件还在上传中，稍后再试';
    if (!service.isConnected) throw '未连接到服务端，请先连接';
    final key = 'dl:${file.id}';
    final existing = _tasks[key];
    if (existing != null && existing.state == TransferState.active) return;

    final task = TransferTask(
      key: key,
      fileId: file.id,
      fileName: file.name,
      total: file.size,
      isUpload: false,
      state: TransferState.active,
    );
    _tasks[key] = task;
    _throttledNotify();

    DownloadSink? sink;
    try {
      final opened = await openDownloadSink(file.name);
      sink = opened.$1;
      final s = sink;
      await service.downloadTo(
        fileId: file.id,
        fileSize: file.size,
        write: (off, data, isLast) => s.write(data),
        onProgress: (rec, _) {
          task.done = rec;
          _throttledNotify();
        },
        isCancelled: () => task.state == TransferState.cancelled,
      );
      final saved = await s.finish();
      sink = null;
      task.state = TransferState.done;
      task.done = file.size;
      task.savedPath = saved;
    } on CancelledError {
      task.state = TransferState.cancelled;
      try {
        await sink?.abort();
      } catch (_) {}
      sink = null;
    } on ServerError catch (e) {
      task.state = TransferState.failed;
      task.error = e.toString();
      try {
        await sink?.abort();
      } catch (_) {}
      sink = null;
    } on RetryableError catch (e) {
      task.state = TransferState.failed;
      task.error = '${e.message}，可重试';
      try {
        await sink?.abort();
      } catch (_) {}
      sink = null;
    } on TimeoutException {
      task.state = TransferState.failed;
      task.error = '下载超时，可重试';
      try {
        await sink?.abort();
      } catch (_) {}
      sink = null;
    } catch (e) {
      task.state = TransferState.failed;
      task.error = '$e';
      try {
        await sink?.abort();
      } catch (_) {}
      sink = null;
    } finally {
      _throttledNotify();
    }
  }

  Future<void> retryDownload(String key) async {
    final task = _tasks[key];
    if (task == null || task.isUpload) return;
    if (task.state == TransferState.active) return;
    final match = service.files.where((f) => f.id == task.fileId).toList();
    if (match.isEmpty) {
      task.state = TransferState.failed;
      task.error = '云端已没有该文件';
      _throttledNotify();
      return;
    }
    _tasks.remove(key);
    await startDownload(match.first);
  }

  /// 一键打开已下载完成的文件：APK 调起安装，其余走系统默认应用。
  /// 抛友好中文错误，由页面 snackbar 展示。
  Future<void> openDownload(String key) async {
    final task = _tasks[key];
    if (task == null) throw '任务不存在';
    if (kIsWeb) throw 'Web 端文件已通过浏览器下载，请在浏览器下载记录中打开';
    if (!task.canOpen) throw '该任务暂无可打开的本地文件';
    final path = task.savedPath!;
    try {
      final result = await OpenFilex.open(path);
      switch (result.type) {
        case ResultType.done:
          return;
        case ResultType.fileNotFound:
          throw '文件不存在或已被删除';
        case ResultType.noAppToOpen:
          throw '没有可打开此文件的应用';
        case ResultType.permissionDenied:
          throw '系统拒绝了打开请求（安装 APK 请先允许“安装未知应用”）';
        case ResultType.error:
          throw result.message.isEmpty ? '打开失败' : result.message;
      }
    } catch (e) {
      if (e is String) rethrow;
      throw '打开失败：$e';
    }
  }

  Future<void> deleteCloudFile(String fileId) async {
    try {
      await service.deleteFile(fileId);
    } on ServerError catch (e) {
      throw e.toString();
    } on TimeoutException {
      throw '请求超时，请重试';
    } on RetryableError catch (e) {
      throw e.message;
    }
  }

  Future<void> refreshFiles() async {
    try {
      await service.refreshAll();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 释放

  @override
  void dispose() {
    _clipPollTimer?.cancel();
    _notifyTimer?.cancel();
    service.removeListener(_onServiceChanged);
    service.dispose();
    terminal.dispose();
    themeMode.dispose();
    super.dispose();
  }
}

class _UploadSource {
  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;

  _UploadSource({
    required this.name,
    required this.size,
    required this.path,
    required this.bytes,
  });
}
