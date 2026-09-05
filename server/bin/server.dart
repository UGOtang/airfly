// AirFly 云中转服务端
//
// 纯 Dart 实现、零第三方依赖，可直接跑在 x86 云服务器上：
//   dart run bin/server.dart
// 或编译为单文件可执行程序：
//   dart compile exe bin/server.dart -o airfly-server
//
// 配置全部走环境变量：
//   PORT              监听端口            (默认 8080)
//   HOST              监听地址            (默认 0.0.0.0)
//   DATA_DIR          数据目录            (默认 ./data)
//   MAX_FILE_MB       单文件上限(MB)      (默认 2048)
//   SPACE_QUOTA_MB    单空间配额(MB)      (默认 5120)
//   FILE_TTL_HOURS    文件保留小时数      (默认 168 = 7天)
//   API_KEY           全局密钥(可选)      (默认空 = 不校验)
//   MAX_CLIP_CHARS    剪切板单条上限(字符) (默认 100000)
//
// 协议: 单端口 WebSocket，每一帧 = 一个 JSON 对象，详见 ../PROTOCOL.md
// 设计要点(针对旧局域网版 bug 的修复):
//  - WebSocket 自带消息帧，不再有 TCP 粘包/半包问题
//  - 上传采用 stop-and-wait + offset 校验，支持断点续传，拒绝错位写入
//  - 同一文件的并发写用 Future 链串行化，避免交叉覆盖
//  - 文件名做清洗，防止路径穿越
//  - 心跳 + 僵尸连接清理，避免云上连接泄漏
//  - 元数据先写 tmp 再 rename，原子落盘，重启可恢复

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ---------------------------------------------------------------- 配置

class ServerConfig {
  final String host;
  final int port;
  final String dataDir;
  final int maxFileBytes;
  final int spaceQuotaBytes;
  final Duration fileTtl;
  final String apiKey;
  final int maxClipChars;

  const ServerConfig({
    required this.host,
    required this.port,
    required this.dataDir,
    required this.maxFileBytes,
    required this.spaceQuotaBytes,
    required this.fileTtl,
    required this.apiKey,
    required this.maxClipChars,
  });

  static int _envInt(String key, int fallback) {
    final raw = Platform.environment[key];
    if (raw == null || raw.isEmpty) return fallback;
    return int.tryParse(raw.trim()) ?? fallback;
  }

  static ServerConfig fromEnv() {
    return ServerConfig(
      host: Platform.environment['HOST']?.trim().isEmpty == true
          ? '0.0.0.0'
          : (Platform.environment['HOST'] ?? '0.0.0.0'),
      port: _envInt('PORT', 8080),
      dataDir: Platform.environment['DATA_DIR'] ?? 'data',
      maxFileBytes: _envInt('MAX_FILE_MB', 2048) * 1024 * 1024,
      spaceQuotaBytes: _envInt('SPACE_QUOTA_MB', 5120) * 1024 * 1024,
      fileTtl: Duration(hours: _envInt('FILE_TTL_HOURS', 168)),
      apiKey: Platform.environment['API_KEY'] ?? '',
      maxClipChars: _envInt('MAX_CLIP_CHARS', 100000),
    );
  }
}

// ---------------------------------------------------------------- 工具

void log(String msg) {
  final ts = DateTime.now().toIso8601String();
  // ignore: avoid_print
  print('[$ts] $msg');
}

String newId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${t}_$rand';
}

final RegExp _spaceIdExp = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_]{2,31}$');
final RegExp _fileIdExp = RegExp(r'^[A-Za-z0-9\-_]{8,64}$');
final RegExp _deviceIdExp = RegExp(r'^[A-Za-z0-9\-_:]{4,128}$');

bool validSpaceId(String s) => _spaceIdExp.hasMatch(s);
bool validFileId(String s) => _fileIdExp.hasMatch(s);
bool validDeviceId(String s) => _deviceIdExp.hasMatch(s);

/// 清洗文件名：去路径、去控制字符、限长，绝不允许穿越目录。
String sanitizeFileName(String raw) {
  var name = raw.replaceAll('\\', '/');
  if (name.contains('/')) {
    name = name.split('/').last;
  }
  // 去掉控制字符与首尾空白/点
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  name = name.replaceAll(RegExp(r'^\.+'), '');
  if (name.isEmpty) name = 'unnamed';
  if (name.length > 180) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 16) {
      name = '${name.substring(0, 180 - (name.length - dot))}${name.substring(dot)}';
    } else {
      name = name.substring(0, 180);
    }
  }
  if (name == '.' || name == '..') name = 'unnamed';
  return name;
}

String truncate(String s, int max) =>
    s.length <= max ? s : s.substring(0, max);

String asString(dynamic v, [String fallback = '']) {
  if (v is String) return v;
  if (v == null) return fallback;
  return v.toString();
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

// ---------------------------------------------------------------- 数据模型

class DevicePresence {
  final String id;
  String name;
  String platform;
  DateTime connectedAt;
  DateTime lastSeen;

  DevicePresence({
    required this.id,
    required this.name,
    required this.platform,
    required this.connectedAt,
  }) : lastSeen = DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'connectedAt': connectedAt.millisecondsSinceEpoch,
      };
}

class ClipItem {
  final String id;
  final String text;
  final String deviceId;
  final String deviceName;
  final DateTime updatedAt;

  ClipItem({
    required this.id,
    required this.text,
    required this.deviceId,
    required this.deviceName,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  static ClipItem? fromJson(Map<String, dynamic> j) {
    try {
      final text = j['text'];
      if (text is! String) return null;
      return ClipItem(
        id: asString(j['id'], newId()),
        text: text,
        deviceId: asString(j['deviceId'], '?'),
        deviceName: asString(j['deviceName'], '?'),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          asInt(j['updatedAt'], DateTime.now().millisecondsSinceEpoch),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class FileEntry {
  final String id;
  final String name;
  final int size;
  final String ownerDeviceId;
  String ownerDeviceName;
  final DateTime createdAt;
  DateTime expiresAt;
  int uploadedBytes;
  bool complete;

  FileEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.ownerDeviceId,
    required this.ownerDeviceName,
    required this.createdAt,
    required this.expiresAt,
    this.uploadedBytes = 0,
    this.complete = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'uploadedBytes': uploadedBytes,
        'complete': complete,
        'ownerDeviceId': ownerDeviceId,
        'ownerDeviceName': ownerDeviceName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  static FileEntry? fromJson(Map<String, dynamic> j) {
    try {
      return FileEntry(
        id: asString(j['id']),
        name: asString(j['name'], 'unnamed'),
        size: asInt(j['size']),
        ownerDeviceId: asString(j['ownerDeviceId'], '?'),
        ownerDeviceName: asString(j['ownerDeviceName'], '?'),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          asInt(j['createdAt'], DateTime.now().millisecondsSinceEpoch),
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          asInt(j['expiresAt'],
              DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch),
        ),
        uploadedBytes: asInt(j['uploadedBytes']),
        complete: j['complete'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------- 空间

class Space {
  final String id;
  String key; // 空间密码，空 = 无密码
  // 单文件服务端，无对外 package API，_Conn 仅库内使用。
  // ignore: library_private_types_in_public_api
  final Map<String, _Conn> conns = {}; // connKey -> conn
  final Map<String, DevicePresence> devices = {}; // deviceId -> presence
  ClipItem? clipLatest;
  final List<ClipItem> clipHistory = [];
  final Map<String, FileEntry> files = {};

  // 元数据落盘防抖
  Timer? _saveTimer;
  bool _saveScheduled = false;

  // 每个文件的写串行链
  final Map<String, Future<void>> _writeChains = {};

  // file_progress 广播节流
  final Map<String, DateTime> _lastProgressBroadcast = {};

  Space({required this.id, this.key = ''});

  int get usedBytes {
    var total = 0;
    for (final f in files.values) {
      total += f.uploadedBytes;
    }
    return total;
  }

  List<Map<String, dynamic>> presenceJson() =>
      devices.values.map((d) => d.toJson()).toList();

  List<Map<String, dynamic>> filesJson() {
    final list = files.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.map((f) => f.toJson()).toList();
  }

  void scheduleSave(void Function(Space) persist) {
    if (_saveScheduled) return;
    _saveScheduled = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveScheduled = false;
      try {
        persist(this);
      } catch (e) {
        log('space $id persist failed: $e');
      }
    });
  }

  void saveNow(void Function(Space) persist) {
    _saveTimer?.cancel();
    _saveScheduled = false;
    try {
      persist(this);
    } catch (e) {
      log('space $id persist failed: $e');
    }
  }

  Future<void> chainWrite(String fileId, Future<void> Function() fn) {
    final prev = _writeChains[fileId] ?? Future.value();
    final next = prev.then((_) => fn()).catchError((Object e) {
      log('space $id file $fileId write error: $e');
    });
    _writeChains[fileId] = next;
    // 清理已完成的链，防止 map 无限增长
    next.whenComplete(() {
      if (_writeChains[fileId] == next) {
        _writeChains.remove(fileId);
      }
    });
    return next;
  }

  bool shouldBroadcastProgress(String fileId) {
    final now = DateTime.now();
    final last = _lastProgressBroadcast[fileId];
    if (last == null || now.difference(last).inMilliseconds >= 500) {
      _lastProgressBroadcast[fileId] = now;
      return true;
    }
    return false;
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}

class _Conn {
  final WebSocket socket;
  final String connKey;
  String? deviceId;
  String spaceId = '';
  DateTime lastSeen = DateTime.now();
  int msgCount = 0;
  DateTime windowStart = DateTime.now();
  bool helloOk = false;

  _Conn({required this.socket, required this.connKey});
}

// ---------------------------------------------------------------- 服务端

class RelayServer {
  final ServerConfig cfg;
  HttpServer? _http;
  final Map<String, Space> _spaces = {};
  final Map<String, _Conn> _conns = {}; // connKey -> conn
  Timer? _heartbeatTimer;
  Timer? _sweepTimer;
  bool _closing = false;

  RelayServer(this.cfg);

  Directory get _spacesDir => Directory('${cfg.dataDir}/spaces');
  Directory _spaceFilesDir(String spaceId) =>
      Directory('${cfg.dataDir}/files/$spaceId');

  String _binPath(String spaceId, String fileId) =>
      '${cfg.dataDir}/files/$spaceId/$fileId.bin';

  Future<void> start() async {
    await Directory(cfg.dataDir).create(recursive: true);
    await _spacesDir.create(recursive: true);
    await _loadAllSpaces();

    _http = await HttpServer.bind(cfg.host, cfg.port);
    log('AirFly relay listening on ${cfg.host}:${cfg.port} '
        '(data=${cfg.dataDir}, ttl=${cfg.fileTtl.inHours}h, '
        'maxFile=${cfg.maxFileBytes ~/ 1024 ~/ 1024}MB)');

    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 25), (_) => _sendHeartbeats());
    _sweepTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _sweep());
    // 文件过期清理每小时一次
    Timer.periodic(const Duration(hours: 1), (_) => _expireFiles());

    await for (final req in _http!) {
      if (_closing) {
        try {
          req.response.statusCode = HttpStatus.serviceUnavailable;
          await req.response.close();
        } catch (_) {}
        continue;
      }
      unawaited(_route(req));
    }
  }

  Future<void> _route(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        final socket = await WebSocketTransformer.upgrade(req);
        _attachSocket(socket);
        return;
      }
      // 普通 HTTP：健康检查与说明页
      req.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..contentType = ContentType.json;
      if (path == '/healthz') {
        req.response.statusCode = HttpStatus.ok;
        req.response.write(jsonEncode({
          'ok': true,
          'time': DateTime.now().millisecondsSinceEpoch,
          'spaces': _spaces.length,
          'conns': _conns.length,
        }));
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.write(jsonEncode({
          'name': 'airfly-relay',
          'protocol': 1,
          'ws': '/ws',
          'health': '/healthz',
        }));
      }
      await req.response.close();
    } catch (e) {
      log('route error: $e');
      try {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
      } catch (_) {}
    }
  }

  // ---------------- 连接管理

  void _attachSocket(WebSocket socket) {
    final connKey = newId();
    final conn = _Conn(socket: socket, connKey: connKey);
    _conns[connKey] = conn;
    log('conn + $connKey (total ${_conns.length})');

    // hello 超时：15 秒内必须完成 hello，否则断开（防半开连接堆积）
    Timer(const Duration(seconds: 15), () {
      if (!conn.helloOk) {
        try {
          _send(conn, {'type': 'error', 'code': 'hello_timeout'});
        } catch (_) {}
        _closeConn(conn, 'hello timeout');
      }
    });

    socket.listen(
      (data) => unawaited(_onMessage(conn, data)),
      onError: (_) => _closeConn(conn, 'socket error'),
      onDone: () => _closeConn(conn, 'socket done'),
      cancelOnError: false,
    );
  }

  void _closeConn(_Conn conn, String reason) {
    final existed = _conns.remove(conn.connKey) != null;
    Space? space;
    if (conn.spaceId.isNotEmpty) {
      space = _spaces[conn.spaceId];
      if (space != null) {
        space.conns.remove(conn.connKey);
        // 同一 deviceId 是否还有别的连接？没有才移除 presence
        final stillThere =
            space.conns.values.any((c) => c.deviceId == conn.deviceId);
        if (!stillThere && conn.deviceId != null) {
          space.devices.remove(conn.deviceId);
        }
      }
    }
    try {
      conn.socket.close(WebSocketStatus.goingAway, reason);
    } catch (_) {}
    if (existed) {
      log('conn - ${conn.connKey} ($reason)');
      if (space != null) _broadcastPresence(space);
    }
  }

  void _send(_Conn conn, Map<String, dynamic> msg) {
    try {
      conn.socket.add(jsonEncode(msg));
    } catch (e) {
      log('send failed ${conn.connKey}: $e');
    }
  }

  void _broadcast(Space space, Map<String, dynamic> msg, {_Conn? except}) {
    final text = jsonEncode(msg);
    for (final c in space.conns.values) {
      if (except != null && c.connKey == except.connKey) continue;
      try {
        c.socket.add(text);
      } catch (_) {}
    }
  }

  void _broadcastPresence(Space space) {
    _broadcast(space, {
      'type': 'presence',
      'spaceId': space.id,
      'devices': space.presenceJson(),
      'serverTime': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _broadcastFileList(Space space) {
    _broadcast(space, {
      'type': 'file_list',
      'spaceId': space.id,
      'files': space.filesJson(),
    });
  }

  // ---------------- 消息入口

  Future<void> _onMessage(_Conn conn, dynamic data) async {
    conn.lastSeen = DateTime.now();
    // 简易限流：10 秒窗口最多 300 条
    final now = DateTime.now();
    if (now.difference(conn.windowStart).inSeconds >= 10) {
      conn.windowStart = now;
      conn.msgCount = 0;
    }
    conn.msgCount++;
    if (conn.msgCount > 300) {
      _send(conn, {'type': 'error', 'code': 'rate_limited'});
      _closeConn(conn, 'rate limited');
      return;
    }

    Map<String, dynamic> msg;
    try {
      if (data is! String) {
        _send(conn, {'type': 'error', 'code': 'binary_not_supported'});
        return;
      }
      if (data.length > 300 * 1024) {
        // 单帧上限 300KB（128KB 文件块 base64 后约 175KB，留余量）
        _send(conn, {'type': 'error', 'code': 'frame_too_large'});
        return;
      }
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        _send(conn, {'type': 'error', 'code': 'bad_json'});
        return;
      }
      msg = decoded;
    } catch (_) {
      _send(conn, {'type': 'error', 'code': 'bad_json'});
      return;
    }

    final type = asString(msg['type']);
    try {
      switch (type) {
        case 'hello':
          await _handleHello(conn, msg);
          break;
        case 'ping':
          conn.lastSeen = DateTime.now();
          _send(conn, {'type': 'pong', 'ts': msg['ts']});
          break;
        case 'pong':
          conn.lastSeen = DateTime.now();
          break;
        case 'clipboard_push':
          await _handleClipPush(conn, msg);
          break;
        case 'clipboard_history_request':
          _requireHello(conn);
          _send(conn, {
            'type': 'clipboard_history',
            'items': _spaces[conn.spaceId]!
                .clipHistory
                .map((e) => e.toJson())
                .toList(),
          });
          break;
        case 'file_list_request':
          _requireHello(conn);
          _send(conn, {
            'type': 'file_list',
            'spaceId': conn.spaceId,
            'files': _spaces[conn.spaceId]!.filesJson(),
          });
          break;
        case 'file_announce':
          await _handleFileAnnounce(conn, msg);
          break;
        case 'file_chunk':
          await _handleFileChunk(conn, msg);
          break;
        case 'file_download_request':
          await _handleDownload(conn, msg);
          break;
        case 'file_delete':
          await _handleDelete(conn, msg);
          break;
        default:
          _send(conn, {
            'type': 'error',
            'code': 'unknown_type',
            'refMsgId': msg['msgId'],
          });
      }
    } catch (e) {
      if (e is _NeedHello) {
        _send(conn, {'type': 'error', 'code': 'need_hello'});
      } else {
        log('handle $type error: $e');
        _send(conn, {'type': 'error', 'code': 'internal'});
      }
    }
  }

  void _requireHello(_Conn conn) {
    if (!conn.helloOk || conn.spaceId.isEmpty || !_spaces.containsKey(conn.spaceId)) {
      throw _NeedHello();
    }
  }

  // ---------------- hello / 加入空间

  Future<void> _handleHello(_Conn conn, Map<String, dynamic> msg) async {
    if (asInt(msg['protocol'], 0) != 1) {
      _send(conn, {'type': 'error', 'code': 'bad_protocol'});
      _closeConn(conn, 'bad protocol');
      return;
    }
    final spaceId = asString(msg['spaceId']).trim();
    if (!validSpaceId(spaceId)) {
      _send(conn, {'type': 'error', 'code': 'bad_space_id'});
      return;
    }
    if (cfg.apiKey.isNotEmpty && asString(msg['apiKey']) != cfg.apiKey) {
      _send(conn, {'type': 'error', 'code': 'bad_api_key'});
      // 延迟断开，避免暴力枚举时快速重试
      Timer(const Duration(milliseconds: 500), () => _closeConn(conn, 'bad api key'));
      return;
    }
    final devRaw = msg['device'];
    if (devRaw is! Map<String, dynamic>) {
      _send(conn, {'type': 'error', 'code': 'bad_device'});
      return;
    }
    var deviceId = asString(devRaw['id']).trim();
    if (!validDeviceId(deviceId)) {
      // 允许首次为空：服务端分配一个，客户端持久化后复用
      deviceId = 'd_${newId().replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '').substring(0, 20)}';
    }
    var rawName = asString(devRaw['name'], '未知设备').trim();
    if (rawName.isEmpty) rawName = '未知设备';
    final deviceName = truncate(rawName, 40);
    final platform =
        truncate(asString(devRaw['platform'], 'unknown'), 24);
    final spaceKey = asString(msg['spaceKey']);

    var space = _spaces[spaceId];
    if (space == null) {
      space = Space(id: spaceId, key: spaceKey);
      _spaces[spaceId] = space;
      space.saveNow(_persistSpace);
      log('space + $spaceId (by $deviceName)');
    } else {
      if (space.key.isNotEmpty && space.key != spaceKey) {
        _send(conn, {'type': 'error', 'code': 'bad_space_key'});
        return;
      }
      // 空间无密码但有人带密码创建？以首次创建为准，不覆盖。
    }

    // 同 deviceId 顶掉旧连接（切换网络/重连时常见），避免幽灵设备
    final stale = space.conns.values
        .where((c) => c.deviceId == deviceId)
        .toList();
    for (final s in stale) {
      try {
        s.socket.close(WebSocketStatus.policyViolation, 'replaced');
      } catch (_) {}
      _conns.remove(s.connKey);
      space.conns.remove(s.connKey);
    }

    conn.spaceId = spaceId;
    conn.deviceId = deviceId;
    conn.helloOk = true;
    conn.lastSeen = DateTime.now();
    space.conns[conn.connKey] = conn;
    space.devices[deviceId] = DevicePresence(
      id: deviceId,
      name: deviceName,
      platform: platform,
      connectedAt: DateTime.now(),
    );

    _send(conn, {
      'type': 'welcome',
      'spaceId': spaceId,
      'deviceId': deviceId,
      'serverTime': DateTime.now().millisecondsSinceEpoch,
      'maxFileBytes': cfg.maxFileBytes,
      'maxClipChars': cfg.maxClipChars,
    });
    // 给新连接补全状态
    if (space.clipLatest != null) {
      _send(conn, {
        'type': 'clipboard_update',
        'item': space.clipLatest!.toJson(),
      });
    }
    _send(conn, {
      'type': 'clipboard_history',
      'items': space.clipHistory.map((e) => e.toJson()).toList(),
    });
    _send(conn, {
      'type': 'file_list',
      'spaceId': spaceId,
      'files': space.filesJson(),
    });
    _broadcastPresence(space);
    log('hello $deviceName ($deviceId) -> $spaceId');
  }

  // ---------------- 剪切板

  Future<void> _handleClipPush(_Conn conn, Map<String, dynamic> msg) async {
    _requireHello(conn);
    final space = _spaces[conn.spaceId]!;
    final text = msg['text'];
    if (text is! String || text.isEmpty) {
      _send(conn, {
        'type': 'error',
        'code': 'empty_clip',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    if (text.length > cfg.maxClipChars) {
      _send(conn, {
        'type': 'error',
        'code': 'clip_too_large',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    final dev = space.devices[conn.deviceId] ?? DevicePresence(
      id: conn.deviceId ?? '?',
      name: '未知设备',
      platform: 'unknown',
      connectedAt: DateTime.now(),
    );
    final item = ClipItem(
      id: newId(),
      text: text,
      deviceId: dev.id,
      deviceName: dev.name,
      updatedAt: DateTime.now(),
    );
    // 去重：与最新一条完全相同则忽略（防止自动同步循环刷屏）
    if (space.clipLatest != null &&
        space.clipLatest!.text == item.text &&
        space.clipLatest!.deviceId == item.deviceId) {
      _send(conn, {
        'type': 'clipboard_update',
        'item': space.clipLatest!.toJson(),
        'deduped': true,
        'refMsgId': msg['msgId'],
      });
      return;
    }
    space.clipLatest = item;
    space.clipHistory.insert(0, item);
    if (space.clipHistory.length > 100) {
      space.clipHistory.removeRange(100, space.clipHistory.length);
    }
    space.scheduleSave(_persistSpace);
    _broadcast(space, {
      'type': 'clipboard_update',
      'item': item.toJson(),
      'refMsgId': msg['msgId'],
    });
  }

  // ---------------- 文件上传

  Future<void> _handleFileAnnounce(_Conn conn, Map<String, dynamic> msg) async {
    _requireHello(conn);
    final space = _spaces[conn.spaceId]!;
    final fileId = asString(msg['fileId']).trim();
    final name = sanitizeFileName(asString(msg['name'], 'unnamed'));
    final size = asInt(msg['size'], -1);

    if (!validFileId(fileId)) {
      _send(conn, {
        'type': 'error',
        'code': 'bad_file_id',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    if (size <= 0 || size > cfg.maxFileBytes) {
      _send(conn, {
        'type': 'error',
        'code': 'bad_file_size',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    final existing = space.files[fileId];
    if (existing != null) {
      // 断点续传：把实际已落盘长度对齐（防止元数据与磁盘不一致）
      final actual = await _diskSize(space.id, fileId);
      existing.uploadedBytes = actual.clamp(0, existing.size);
      if (existing.complete && existing.uploadedBytes == existing.size) {
        _send(conn, {
          'type': 'file_announced',
          'file': existing.toJson(),
          'refMsgId': msg['msgId'],
        });
        return;
      }
      // 同名冲突但 id 相同视为续传；不同发送者续传别人的文件也允许
      // （共享空间语义），但 size/name 必须一致，否则报错。
      if (existing.size != size) {
        _send(conn, {
          'type': 'error',
          'code': 'file_conflict',
          'refMsgId': msg['msgId'],
        });
        return;
      }
      _send(conn, {
        'type': 'file_announced',
        'file': existing.toJson(),
        'resumed': true,
        'refMsgId': msg['msgId'],
      });
      return;
    }
    // 配额检查
    if (space.usedBytes + size > cfg.spaceQuotaBytes) {
      _send(conn, {
        'type': 'error',
        'code': 'quota_exceeded',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    final dev = space.devices[conn.deviceId];
    final entry = FileEntry(
      id: fileId,
      name: name,
      size: size,
      ownerDeviceId: conn.deviceId ?? '?',
      ownerDeviceName: dev?.name ?? '未知设备',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(cfg.fileTtl),
    );
    space.files[fileId] = entry;
    await _spaceFilesDir(space.id).create(recursive: true);
    final bin = File(_binPath(space.id, fileId));
    if (!await bin.exists()) {
      await bin.create(recursive: true);
    } else {
      // 残留空文件：截断后重传
      await bin.writeAsBytes(const [], mode: FileMode.write);
    }
    space.saveNow(_persistSpace);
    _send(conn, {
      'type': 'file_announced',
      'file': entry.toJson(),
      'refMsgId': msg['msgId'],
    });
    _broadcastFileList(space);
    log('announce ${entry.name} (${entry.size}B) in ${space.id}');
  }

  Future<void> _handleFileChunk(_Conn conn, Map<String, dynamic> msg) async {
    _requireHello(conn);
    final space = _spaces[conn.spaceId]!;
    final fileId = asString(msg['fileId']).trim();
    final offset = asInt(msg['offset'], -1);
    final dataB64 = msg['dataBase64'];
    final isLast = msg['isLast'] == true;

    final entry = space.files[fileId];
    if (entry == null) {
      _send(conn, {
        'type': 'error',
        'code': 'no_such_file',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    if (entry.complete) {
      _send(conn, {
        'type': 'file_chunk_ack',
        'fileId': fileId,
        'uploadedBytes': entry.uploadedBytes,
        'complete': true,
        'refMsgId': msg['msgId'],
      });
      return;
    }
    if (dataB64 is! String || dataB64.isEmpty) {
      _send(conn, {
        'type': 'error',
        'code': 'empty_chunk',
        'refMsgId': msg['msgId'],
      });
      return;
    }
    // 串行化同一文件的写，避免流水线发送导致交叉覆盖
    await space.chainWrite(fileId, () async {
      // 在链内重新核对 offset（之前排队的写可能已推进）
      if (offset != entry.uploadedBytes) {
        final actual = await _diskSize(space.id, fileId);
        entry.uploadedBytes = actual.clamp(0, entry.size);
        _send(conn, {
          'type': 'file_chunk_ack',
          'fileId': fileId,
          'uploadedBytes': entry.uploadedBytes,
          'mismatch': true,
          'refMsgId': msg['msgId'],
        });
        return;
      }
      List<int> bytes;
      try {
        bytes = base64.decode(dataB64);
      } catch (_) {
        _send(conn, {
          'type': 'error',
          'code': 'bad_base64',
          'refMsgId': msg['msgId'],
        });
        return;
      }
      if (bytes.isEmpty || bytes.length > 200 * 1024) {
        _send(conn, {
          'type': 'error',
          'code': 'bad_chunk_size',
          'refMsgId': msg['msgId'],
        });
        return;
      }
      if (offset + bytes.length > entry.size) {
        _send(conn, {
          'type': 'error',
          'code': 'chunk_overflow',
          'refMsgId': msg['msgId'],
        });
        return;
      }
      try {
        final f = File(_binPath(space.id, fileId));
        final raf = await f.open(mode: FileMode.append);
        try {
          await raf.writeFrom(bytes);
        } finally {
          await raf.close();
        }
      } catch (e) {
        log('write ${space.id}/$fileId failed: $e');
        _send(conn, {
          'type': 'error',
          'code': 'disk_error',
          'refMsgId': msg['msgId'],
        });
        return;
      }
      entry.uploadedBytes = offset + bytes.length;
      final done = isLast || entry.uploadedBytes == entry.size;
      if (done) {
        if (entry.uploadedBytes != entry.size) {
          // 客户端提前说 isLast 但长度对不上：视为协议错误，回滚 ack
          _send(conn, {
            'type': 'error',
            'code': 'size_mismatch',
            'refMsgId': msg['msgId'],
          });
          return;
        }
        entry.complete = true;
        entry.expiresAt = DateTime.now().add(cfg.fileTtl);
        space.saveNow(_persistSpace);
        _send(conn, {
          'type': 'file_chunk_ack',
          'fileId': fileId,
          'uploadedBytes': entry.uploadedBytes,
          'complete': true,
          'refMsgId': msg['msgId'],
        });
        _broadcastFileList(space);
        log('complete ${entry.name} in ${space.id}');
      } else {
        space.scheduleSave(_persistSpace);
        _send(conn, {
          'type': 'file_chunk_ack',
          'fileId': fileId,
          'uploadedBytes': entry.uploadedBytes,
          'complete': false,
          'refMsgId': msg['msgId'],
        });
        if (space.shouldBroadcastProgress(fileId)) {
          _broadcast(space, {
            'type': 'file_progress',
            'fileId': fileId,
            'uploadedBytes': entry.uploadedBytes,
            'size': entry.size,
            'complete': false,
          });
        }
      }
    });
  }

  // ---------------- 文件下载

  Future<void> _handleDownload(_Conn conn, Map<String, dynamic> msg) async {
    _requireHello(conn);
    final space = _spaces[conn.spaceId]!;
    final fileId = asString(msg['fileId']).trim();
    var offset = asInt(msg['offset'], 0);
    final entry = space.files[fileId];
    if (entry == null) {
      _send(conn, {'type': 'error', 'code': 'no_such_file'});
      return;
    }
    if (!entry.complete) {
      _send(conn, {
        'type': 'error',
        'code': 'file_incomplete',
        'fileId': fileId,
        'uploadedBytes': entry.uploadedBytes,
      });
      return;
    }
    if (offset < 0 || offset > entry.size) {
      _send(conn, {'type': 'error', 'code': 'bad_offset'});
      return;
    }
    if (offset == entry.size) {
      _send(conn, {
        'type': 'file_download_chunk',
        'fileId': fileId,
        'offset': offset,
        'dataBase64': '',
        'isLast': true,
        'size': entry.size,
      });
      return;
    }
    const chunkSize = 128 * 1024;
    final length = (entry.size - offset).clamp(0, chunkSize);
    try {
      final f = File(_binPath(space.id, fileId));
      final raf = await f.open(mode: FileMode.read);
      List<int> bytes;
      try {
        await raf.setPosition(offset);
        bytes = await raf.read(length);
      } finally {
        await raf.close();
      }
      final isLast = offset + bytes.length >= entry.size;
      _send(conn, {
        'type': 'file_download_chunk',
        'fileId': fileId,
        'offset': offset,
        'dataBase64': base64.encode(bytes),
        'isLast': isLast,
        'size': entry.size,
        'name': entry.name,
      });
    } catch (e) {
      log('download ${space.id}/$fileId@$offset failed: $e');
      _send(conn, {'type': 'error', 'code': 'disk_error'});
    }
  }

  // ---------------- 删除

  Future<void> _handleDelete(_Conn conn, Map<String, dynamic> msg) async {
    _requireHello(conn);
    final space = _spaces[conn.spaceId]!;
    final fileId = asString(msg['fileId']).trim();
    final entry = space.files.remove(fileId);
    if (entry == null) {
      _send(conn, {'type': 'error', 'code': 'no_such_file'});
      return;
    }
    // 等待该文件排队的写完成后再删，避免删完又有追加写入复活文件
    await space.chainWrite(fileId, () async {});
    try {
      final f = File(_binPath(space.id, fileId));
      if (await f.exists()) await f.delete();
    } catch (e) {
      log('delete file failed: $e');
    }
    space.saveNow(_persistSpace);
    _send(conn, {
      'type': 'file_deleted',
      'fileId': fileId,
      'refMsgId': msg['msgId'],
    });
    _broadcast(space, {'type': 'file_deleted', 'fileId': fileId});
    _broadcastFileList(space);
    log('delete ${entry.name} in ${space.id}');
  }

  // ---------------- 心跳 / 清理

  void _sendHeartbeats() {
    final now = DateTime.now();
    for (final conn in _conns.values.toList()) {
      try {
        conn.socket.add(jsonEncode({'type': 'ping', 'ts': now.millisecondsSinceEpoch}));
      } catch (_) {}
    }
  }

  void _sweep() {
    final now = DateTime.now();
    for (final conn in _conns.values.toList()) {
      final idle = now.difference(conn.lastSeen).inSeconds;
      if (conn.helloOk && idle > 90) {
        _closeConn(conn, 'stale ($idle s)');
      }
    }
  }

  Future<void> _expireFiles() async {
    final now = DateTime.now();
    for (final space in _spaces.values) {
      final expired = space.files.values
          .where((f) => f.expiresAt.isBefore(now))
          .toList();
      for (final f in expired) {
        space.files.remove(f.id);
        try {
          final file = File(_binPath(space.id, f.id));
          if (await file.exists()) await file.delete();
        } catch (_) {}
        log('expired ${f.name} in ${space.id}');
      }
      if (expired.isNotEmpty) {
        space.saveNow(_persistSpace);
        _broadcastFileList(space);
      }
      // 未完成的上传超过 48h 无进展也清理（防止僵尸占配额）
      final zombie = space.files.values
          .where((f) =>
              !f.complete && now.difference(f.createdAt).inHours > 48)
          .toList();
      for (final f in zombie) {
        space.files.remove(f.id);
        try {
          final file = File(_binPath(space.id, f.id));
          if (await file.exists()) await file.delete();
        } catch (_) {}
        log('zombie upload cleaned ${f.name} in ${space.id}');
      }
      if (zombie.isNotEmpty) {
        space.saveNow(_persistSpace);
        _broadcastFileList(space);
      }
    }
  }

  // ---------------- 持久化

  Future<void> _loadAllSpaces() async {
    try {
      if (!await _spacesDir.exists()) return;
      await for (final ent in _spacesDir.list()) {
        if (ent is! File || !ent.path.endsWith('.json')) continue;
        try {
          final raw = await ent.readAsString();
          final j = jsonDecode(raw) as Map<String, dynamic>;
          final id = asString(j['id']);
          if (!validSpaceId(id)) continue;
          final space = Space(id: id, key: asString(j['key']));
          final clip = j['clipLatest'];
          if (clip is Map<String, dynamic>) {
            space.clipLatest = ClipItem.fromJson(clip);
          }
          final hist = j['clipHistory'];
          if (hist is List) {
            for (final h in hist) {
              if (h is Map<String, dynamic>) {
                final item = ClipItem.fromJson(h);
                if (item != null) space.clipHistory.add(item);
              }
              if (space.clipHistory.length >= 100) break;
            }
          }
          final files = j['files'];
          if (files is List) {
            for (final f in files) {
              if (f is Map<String, dynamic>) {
                final e = FileEntry.fromJson(f);
                if (e == null || !validFileId(e.id)) continue;
                // 用磁盘实际长度校准 uploadedBytes
                final actual = await _diskSize(id, e.id);
                e.uploadedBytes = actual.clamp(0, e.size);
                if (e.uploadedBytes != e.size) e.complete = false;
                if (e.complete && e.expiresAt.isBefore(DateTime.now())) {
                  // 已过期：跳过并删除文件
                  try {
                    final bin = File(_binPath(id, e.id));
                    if (await bin.exists()) await bin.delete();
                  } catch (_) {}
                  continue;
                }
                space.files[e.id] = e;
              }
            }
          }
          _spaces[id] = space;
          log('loaded space $id '
              '(${space.files.length} files, ${space.clipHistory.length} clips)');
        } catch (e) {
          log('load space file failed ${ent.path}: $e');
        }
      }
    } catch (e) {
      log('load spaces failed: $e');
    }
  }

  void _persistSpace(Space space) {
    try {
      final tmp =
          File('${cfg.dataDir}/spaces/${space.id}.json.tmp');
      final dst =
          File('${cfg.dataDir}/spaces/${space.id}.json');
      final data = jsonEncode({
        'id': space.id,
        'key': space.key,
        'clipLatest': space.clipLatest?.toJson(),
        'clipHistory': space.clipHistory.map((e) => e.toJson()).toList(),
        'files': space.files.values.map((e) => e.toJson()).toList(),
      });
      tmp.writeAsStringSync(data);
      tmp.renameSync(dst.path);
    } catch (e) {
      log('persist ${space.id} failed: $e');
    }
  }

  Future<int> _diskSize(String spaceId, String fileId) async {
    try {
      final f = File(_binPath(spaceId, fileId));
      if (!await f.exists()) return 0;
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> stop() async {
    _closing = true;
    _heartbeatTimer?.cancel();
    _sweepTimer?.cancel();
    for (final s in _spaces.values) {
      try {
        s.saveNow(_persistSpace);
      } catch (_) {}
      s.dispose();
    }
    for (final c in _conns.values.toList()) {
      try {
        await c.socket.close(WebSocketStatus.goingAway, 'shutdown');
      } catch (_) {}
    }
    try {
      await _http?.close(force: true);
    } catch (_) {}
    log('relay stopped');
  }
}

class _NeedHello implements Exception {}

// ---------------------------------------------------------------- main

/// 注册退出信号。注意：
/// - Windows 不支持 SIGTERM，直接跳过；
/// - 不支持的信号在部分平台是异步报错，必须同时挂 onError，
///   否则会变成 Zone 未处理异常导致进程退出。
void _watchSignal(ProcessSignal sig, RelayServer server) {
  if (Platform.isWindows && sig == ProcessSignal.sigterm) {
    log('SIGTERM not supported on Windows, skipped');
    return;
  }
  try {
    sig.watch().listen(
      (_) async {
        log('$sig, shutting down…');
        await server.stop();
        exit(0);
      },
      onError: (_) =>
          log('signal $sig listen failed, skipped'),
      cancelOnError: true,
    );
  } catch (_) {
    log('signal $sig not supported on this platform, skipped');
  }
}

Future<void> main() async {
  final cfg = ServerConfig.fromEnv();
  final server = RelayServer(cfg);

  _watchSignal(ProcessSignal.sigint, server);
  _watchSignal(ProcessSignal.sigterm, server);

  try {
    await server.start();
  } catch (e) {
    log('FATAL: $e');
    exit(1);
  }
}
