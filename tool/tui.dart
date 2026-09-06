// AirFly TUI 入口：btop 风格的云空间可视化客户端（纯 Dart，编译成二进制跑）。
// 用法见 --help。配置经参数或环境变量（AIRFLY_SERVER/SPACE/KEY/NAME/API）。

import 'dart:async';
import 'dart:io';

import 'relay_client.dart';
import 'tui_app.dart';

class _UsageError implements Exception {
  final String message;
  _UsageError(this.message);
}

class TuiConfig {
  String server = '';
  String space = '';
  String key = '';
  String name = '';
  String api = '';
  bool noMouse = false;
}

void _usage() {
  stdout.writeln('AirFly TUI —— 云空间可视化客户端');
  stdout.writeln('');
  stdout.writeln('用法： airfly-tui --server <ws(s)://host:port/ws> --space <空间码> [选项]');
  stdout.writeln('  --server URL   服务端地址，也可用环境变量 AIRFLY_SERVER');
  stdout.writeln('  --space 码     空间码，也可用 AIRFLY_SPACE');
  stdout.writeln('  --key 密码     空间密码，也可用 AIRFLY_KEY');
  stdout.writeln('  --name 名称     本机显示名，默认取主机名，也可用 AIRFLY_NAME');
  stdout.writeln('  --api 密钥     服务端 API_KEY，也可用 AIRFLY_API');
  stdout.writeln('  --no-mouse     禁用鼠标（只用键盘）');
  stdout.writeln('  --help         显示本帮助');
  stdout.writeln('注：--key/--api 经命令行传入可能被本机其他用户看到，敏感环境请用环境变量。');
  stdout.writeln('');
  stdout.writeln('键盘：Tab切换面板 ↑↓/jk选择 Enter动作 p推送 u上传 d下载 x删除');
  stdout.writeln('      c取消传输 v复制 r刷新 ?帮助 q退出（鼠标点选/滚轮同样可用）');
}

TuiConfig _parseArgs(List<String> args) {
  final cfg = TuiConfig();
  String? take(String flag) {
    final i = args.indexOf(flag);
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    return null;
  }

  final env = Platform.environment;
  cfg.server = take('--server') ?? env['AIRFLY_SERVER'] ?? '';
  cfg.space = take('--space') ?? env['AIRFLY_SPACE'] ?? '';
  cfg.key = take('--key') ?? env['AIRFLY_KEY'] ?? '';
  cfg.name = take('--name') ?? env['AIRFLY_NAME'] ?? '';
  cfg.api = take('--api') ?? env['AIRFLY_API'] ?? '';
  cfg.noMouse = args.contains('--no-mouse');
  if (cfg.server.trim().isEmpty) throw _UsageError('缺少 --server（或环境变量 AIRFLY_SERVER）');
  if (cfg.space.trim().isEmpty) throw _UsageError('缺少 --space（或环境变量 AIRFLY_SPACE）');
  if (cfg.name.trim().isEmpty) {
    String host = 'tui';
    try {
      host = Platform.localHostname;
    } catch (_) {}
    cfg.name = host.isEmpty ? 'tui' : host;
  }
  return cfg;
}

/// 稳定的设备 ID（存在家里，避免每次启动设备列表闪一下旧自己）。
Future<String> _loadOrCreateDeviceId() async {
  String? home;
  try {
    home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
  } catch (_) {
    home = null;
  }
  if (home != null && home.isNotEmpty) {
    final f = File(
        '$home${Platform.pathSeparator}.airfly-tui-id');
    try {
      if (await f.exists()) {
        final id = (await f.readAsString()).trim();
        if (id.length >= 8) return id;
      }
    } catch (_) {}
    final id = 'tui_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${(DateTime.now().microsecondsSinceEpoch % 1296).toRadixString(36)}';
    try {
      await f.writeAsString(id);
    } catch (_) {}
    return id;
  }
  return 'tui_${DateTime.now().millisecondsSinceEpoch}';
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }
  late final TuiConfig cfg;
  try {
    cfg = _parseArgs(args);
  } on _UsageError catch (e) {
    stderr.writeln('参数错误：${e.message}\n');
    _usage();
    exitCode = 2;
    return;
  }
  exitCode = await runTui(cfg);
}

// ---------------------------------------------------------------- 主循环

Future<int> runTui(TuiConfig cfg) async {
  bool stdinTty = false;
  bool stdoutTty = false;
  try {
    stdinTty = stdin.hasTerminal;
  } catch (_) {}
  try {
    stdoutTty = stdout.hasTerminal;
  } catch (_) {}
  if (!stdinTty || !stdoutTty) {
    stderr.writeln('AirFly TUI 需要真实终端（检测到管道/重定向），请直接在终端里运行。');
    stderr.writeln('只看帮助：airfly-tui --help；脚本调用请用 relay 协议或 Flutter 客户端。');
    return 2;
  }

  // Windows 旧控制台默认 GBK，盒线/中文必乱码：切 UTF-8（TUI 接管期间）。
  // 必须在进 alt buffer 之前做，输出那行字会被清屏吃掉，看不见。
  if (Platform.isWindows) {
    try {
      await Process.run('cmd.exe', ['/c', 'chcp 65001 >nul'],
          runInShell: false);
    } catch (_) {}
  }

  final mouse = !cfg.noMouse;
  if (!_setupTerminal(mouse)) {
    stderr.writeln('终端初始化失败（raw 模式不可用），换个终端再试。');
    return 2;
  }

  final deviceId = await _loadOrCreateDeviceId();
  final client = RelayClient(
    serverUrl: cfg.server.trim(),
    spaceId: cfg.space.trim(),
    spaceKey: cfg.key,
    apiKey: cfg.api,
    deviceId: deviceId,
    deviceName: cfg.name.trim().isEmpty ? 'tui' : cfg.name.trim(),
    platform: 'tui',
  );
  final app = TuiApp(client);
  var dirty = true;
  DateTime lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  List<ClickRegion> regions = const [];
  Timer? escTimer;
  Timer? tick;
  StreamSubscription<List<int>>? sub;
  final sigSubs = <StreamSubscription<ProcessSignal>>[];
  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      sigSubs.add(sig.watch().listen((_) => app.wantQuit = true));
    } catch (_) {}
  }

  void paint() {
    final now = DateTime.now();
    if (!dirty) return;
    if (now.difference(lastPaint).inMilliseconds < 80) return;
    dirty = false;
    lastPaint = now;
    var w = 80;
    var h = 24;
    try {
      w = stdout.terminalColumns;
      h = stdout.terminalLines;
    } catch (_) {}
    final frame = app.render(w, h);
    regions = frame.clicks;
    try {
      stdout.write(frame.text);
    } catch (_) {
      app.wantQuit = true;
    }
  }

  void onBytes(List<int> data) {
    app.parser.feed(data);
    for (final m in app.parser.takeMice()) {
      app.handleMouse(m, regions);
    }
    for (final k in app.parser.takeKeys()) {
      app.handleKey(k);
    }
    if (app.parser.hasPendingEsc) {
      escTimer?.cancel();
      escTimer = Timer(const Duration(milliseconds: 50), () {
        app.parser.flush();
        for (final k in app.parser.takeKeys()) {
          app.handleKey(k);
        }
        dirty = true;
      });
    }
    dirty = true;
  }

  try {
    client.onEvent = () => dirty = true;
    unawaited(client.connect());
    sub = stdin.listen(
      onBytes,
      onError: (_) => app.wantQuit = true,
      onDone: () => app.wantQuit = true,
      cancelOnError: false,
    );
    tick = Timer.periodic(const Duration(seconds: 1), (_) => dirty = true);
    paint();
    while (!app.wantQuit) {
      paint();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return 0;
  } finally {
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      escTimer?.cancel();
    } catch (_) {}
    try {
      tick?.cancel();
    } catch (_) {}
    for (final s in sigSubs) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    try {
      await client.dispose();
    } catch (_) {}
    _restoreTerminal(mouse);
    try {
      stdout.writeln('已退出 AirFly TUI。');
    } catch (_) {}
  }
}

bool _setupTerminal(bool mouse) {
  try {
    stdin.echoMode = false;
    stdin.lineMode = false;
  } catch (_) {
    return false;
  }
  try {
    stdout.write('\x1B[?1049h'); // alt buffer
    stdout.write('\x1B[?25l'); // 藏光标
    if (mouse) stdout.write('\x1B[?1000h\x1B[?1006h'); // 鼠标+SGR
    return true;
  } catch (_) {
    _restoreTerminal(mouse);
    return false;
  }
}

void _restoreTerminal(bool mouse) {
  try {
    if (mouse) stdout.write('\x1B[?1006l\x1B[?1000l');
  } catch (_) {}
  try {
    stdout.write('\x1B[?25h');
  } catch (_) {}
  try {
    stdout.write('\x1B[?1049l');
  } catch (_) {}
  try {
    stdin.echoMode = true;
  } catch (_) {}
  try {
    stdin.lineMode = true;
  } catch (_) {}
}
