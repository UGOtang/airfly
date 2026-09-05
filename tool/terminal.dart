// AirFly 独立二进制终端：零第三方依赖，仅用 Dart SDK。
// 编译：dart compile exe tool/terminal.dart -o airfly-term(.exe)
// 在 Linux 云服务器上用同样命令可产出 Linux 版。
//
// 两种模式（自动选择，也可用参数强制）：
// - 真 shell 模式（默认，有 TTY 时）：把控制台直接交给系统 shell
//   （Windows 默认 PowerShell，Unix 用 $SHELL），补全、交互程序、
//   Ctrl+C、颜色全是原生行为；本程序只负责启动和退出码透传。
// - 行模式（管道/重定向时自动降级，或 --line）：逐行读入，cd/echo/
//   clear 内置，其余交给 shell 单条执行，适合脚本。

import 'dart:ffi' as ffi;
import 'dart:io';

// ---------------------------------------------------------------- 诊断 transcript
//
// 只记生命周期事件与退出码（不记命令与输出内容），路径固定
// %TEMP%/airfly-term-last.log，每次启动覆盖写，不堆积。
// 作用：若进程静默消失，看它走到了哪一步即可定性（spawn 前/等待中/exit 后）。
String _tlogPath() {
  final tmp = Platform.environment['TEMP'] ??
      Platform.environment['TMP'] ??
      (Platform.isWindows ? 'C:\\Windows\\Temp' : '/tmp');
  return '$tmp${Platform.pathSeparator}airfly-term-last.log';
}

void _tlog(String s) {
  try {
    File(_tlogPath()).writeAsStringSync(
      '${DateTime.now().toIso8601String()} $s\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  // 新启动先清掉上次的 transcript（同步写，崩溃也安全）
  try {
    File(_tlogPath()).writeAsStringSync('', mode: FileMode.write);
  } catch (_) {}
  int code = 0;
  try {
    code = await _run(args);
  } catch (e, st) {
    _tlog('FATAL $e');
    _tlog('$st');
    stderr.writeln('致命错误：$e');
    code = 1;
  }
  exit(code);
}

Future<int> _run(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _help();
    return 0;
  }

  final forceLine = args.contains('--line');
  final forceReal = args.contains('--real');
  // 测试钩子：强制认为有 TTY（无头环境下验证真 shell 分支用）
  final forceTty = Platform.environment.containsKey('AIRFLY_FORCE_TTY');
  bool hasTty = false;
  try {
    hasTty = stdin.hasTerminal;
  } catch (_) {
    hasTty = false;
  }
  bool stdoutTty = false;
  try {
    stdoutTty = stdout.hasTerminal;
  } catch (_) {
    stdoutTty = false;
  }
  _tlog('start platform=${Platform.operatingSystem} '
      'stdinTty=$hasTty stdoutTty=$stdoutTty forceTty=$forceTty args=$args');
  final isTty = forceTty || hasTty;
  final realMode = forceReal || (!forceLine && isTty);
  _tlog('mode=${realMode ? 'real' : 'line'}');

  if (args.contains('--new-window')) {
    return _newWindow(args);
  }
  if (realMode) {
    return _realShell(args, isTty);
  } else {
    return _lineMode();
  }
}

void _help() {
  stdout.writeln('AirFly Terminal (standalone)');
  stdout.writeln('用法： airfly-term [选项]');
  stdout.writeln('  （无参数）  有 TTY 进真 shell，无 TTY 自动用行模式');
  stdout.writeln('  --real      强制真 shell 模式');
  stdout.writeln('  --line      强制行模式（管道/脚本用）');
  stdout.writeln('  --cmd       真 shell 用 cmd.exe（仅 Windows）');
  stdout.writeln('  --ps        真 shell 用 powershell.exe（仅 Windows）');
  stdout.writeln('  --pwsh      真 shell 用 pwsh（找不到则回退）');
  stdout.writeln('  --new-window  新开控制台窗口跑真 shell（继承输入失败时的兜底）');
  stdout.writeln('  --help      显示本帮助');
  stdout.writeln('行模式内置命令：help / echo / cd / clear / exit');
  stdout.writeln('注：本程序自身输出为 UTF-8，旧版 cmd 若显示乱码请先执行 chcp 65001。');
}

// ---------------------------------------------------------------- 真 shell

/// 候选 shell 列表（按优先顺序，逐个尝试）。
List<String> _shellCandidates(List<String> args) {
  final isWin = Platform.isWindows;
  if (args.contains('--cmd') && isWin) return ['cmd.exe'];
  if ((args.contains('--ps') || args.contains('--powershell')) && isWin) {
    return ['powershell.exe', 'cmd.exe'];
  }
  if (args.contains('--pwsh')) {
    return isWin
        ? ['pwsh.exe', 'powershell.exe', 'cmd.exe']
        : ['pwsh', 'bash', 'sh'];
  }
  if (isWin) return ['powershell.exe', 'cmd.exe'];
  final sh = Platform.environment['SHELL'];
  if (sh != null && sh.trim().isNotEmpty) return [sh.trim(), 'bash', 'sh'];
  return ['bash', 'sh'];
}

Future<int> _realShell(List<String> args, bool isTty) async {
  // 接住 Ctrl+C：控制台事件会同时发给父子进程，父进程必须无视，
  // 让真 shell 自己处理（取消当前行、不退出），否则用户一按
  // Ctrl+C 父子同归于尽，看起来就像“闪退且什么都不显示”。
  // 注意：Dart 层的 sigint.watch 在 Windows 下拦不住默认终止行为，
  // 必须调 SetConsoleCtrlHandler(NULL, TRUE) 才真正有效。
  try {
    ProcessSignal.sigint.watch().listen((_) {});
  } catch (_) {}
  var guard = 'watch-only';
  if (Platform.isWindows) {
    guard = _ignoreConsoleCtrl() ? 'ignored' : 'ignore-failed';
  }
  _tlog('ctrlc-guard=$guard');
  // 窗口标题区分：父子 shell 提示符长得一样是误会之源，标题写清楚。
  await _setConsoleTitle('AirFly Terminal');

  final sw = Stopwatch()..start();
  for (final shell in _shellCandidates(args)) {
    try {
      stdout.writeln('AirFly Terminal → $shell（真 shell 模式，退出即返回）');
      await stdout.flush();
      _tlog('spawn $shell');
      final proc = await Process.start(
        shell,
        const [],
        mode: ProcessStartMode.inheritStdio,
        runInShell: false,
      );
      _tlog('spawned pid=${proc.pid}, waiting exitCode…');
      final code = await proc.exitCode;
      _tlog('exitCode=$code elapsed=${sw.elapsedMilliseconds}ms');
      stdout.writeln('[shell exit $code]');
      await stdout.flush();
      // TTY 下 shell 瞬间退出 ≈ 输入继承坏了（正常交互不可能 1.5 秒就走），
      // 直接告诉用户逃生通道，而不是静默回到提示符让人猜。
      // 注意只在有 TTY 时提示：管道脚本本来就是秒退，不能误报。
      if (isTty && sw.elapsedMilliseconds < 1500) {
        stdout.writeln('（提示：shell 瞬间退出了，可能是当前终端输入继承失败，');
        stdout.writeln(' 试试新窗口模式：airfly-term --new-window）');
        await stdout.flush();
      }
      return code;
    } on ProcessException catch (e) {
      _tlog('spawn $shell failed: ${e.message}');
      stderr.writeln('启动 $shell 失败（${e.message}），尝试下一个…');
      continue;
    } catch (e) {
      _tlog('spawn $shell error: $e');
      stderr.writeln('启动 $shell 失败：$e');
      continue;
    }
  }
  _tlog('no shell available, fallback to line mode');
  stderr.writeln('没有可用的 shell，已回退到行模式（--line 可直接进）。');
  await stderr.flush();
  return _lineMode();
}

// ---------------------------------------------------------------- 新窗口兜底

/// 在全新控制台窗口里跑真 shell：不继承任何句柄，专治各类终端
/// 输入继承失败（ConPTY 复制句柄等坑）。代价：退出码透传丢失，
/// 且多一个窗口——所以只是兜底，不做默认。
Future<int> _newWindow(List<String> args) async {
  if (!Platform.isWindows) {
    stderr.writeln('--new-window 目前仅支持 Windows。');
    await stderr.flush();
    return 2;
  }
  final shell = _shellCandidates(args).first;
  try {
    // start 的第一个引号参数是窗口标题，必须占位，否则 shell 名被当标题吞掉
    final proc = await Process.start(
      'cmd.exe',
      ['/c', 'start', '', shell],
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    await proc.exitCode; // start 秒回，这里只是回收进程
  } catch (e) {
    stderr.writeln('打开新窗口失败：$e');
    await stderr.flush();
    return 1;
  }
  stdout.writeln('已在新窗口打开 $shell（新窗口模式不透传退出码）。');
  await stdout.flush();
  return 0;
}

// ---------------------------------------------------------------- 行模式

Future<int> _lineMode() async {
  final isWin = Platform.isWindows;
  var cwd = _home() ?? '.';
  try {
    if (!await Directory(cwd).exists()) cwd = '.';
  } catch (_) {
    cwd = '.';
  }
  var lastCode = 0;

  stdout.writeln('AirFly Terminal（行模式）· ${isWin ? 'cmd' : 'sh'}');
  stdout.writeln('输入 help 查看内置命令，exit 退出。');
  stdout.writeln('');
  await stdout.flush();

  final history = <String>[];

  while (true) {
    stdout.write('$cwd${isWin ? '>' : r'$'} ');
    String? line;
    try {
      line = stdin.readLineSync();
    } catch (_) {
      break;
    }
    if (line == null) break; // EOF (Ctrl+Z / Ctrl+D)
    final cmd = line.trim();
    if (cmd.isEmpty) continue;
    history.add(cmd);

    final first = _firstWord(cmd).toLowerCase();
    if (first == 'exit' || first == 'quit') break;
    if (first == 'clear' || first == 'cls') {
      stdout.write('\x1B[2J\x1B[H');
      continue;
    }
    if (first == 'help') {
      _lineHelp();
      continue;
    }
    if (first == 'echo') {
      stdout.writeln(_afterFirst(cmd));
      lastCode = 0;
      continue;
    }
    if (first == 'cd') {
      cwd = await _changeDir(cwd, _afterFirst(cmd));
      lastCode = 0;
      continue;
    }

    try {
      // 注意：这里故意不加 chcp 65001 前缀。stdio 直通时子进程直接写
      // 控制台，用控制台自带编码永远是对的；加了反而在 GBK 控制台乱码。
      // （Flutter App 内那版要自己解码字节，所以才需要 chcp，不要混淆。）
      final proc = await Process.start(
        isWin ? 'cmd.exe' : 'sh',
        isWin ? ['/c', cmd] : ['-c', cmd],
        workingDirectory: cwd,
        mode: ProcessStartMode.inheritStdio,
        runInShell: false,
      );
      lastCode = await proc.exitCode;
      if (lastCode != 0) stdout.writeln('[exit $lastCode]');
    } catch (e) {
      stderr.writeln('执行失败：$e');
      lastCode = 1;
    }
  }
  await stdout.flush();
  return lastCode;
}

void _lineHelp() {
  stdout.writeln('内置命令：');
  stdout.writeln('  help        显示本帮助');
  stdout.writeln('  echo 文本    输出一行');
  stdout.writeln('  cd [目录]    切换目录（无参数回主目录，Windows 支持 cd /d D:\\x）');
  stdout.writeln('  clear/cls   清屏');
  stdout.writeln('  exit/quit   退出');
  stdout.writeln('其他输入交给系统 shell 执行（stdio 直通，交互程序可用）。');
}

// ---------------------------------------------------------------- 平台小件

/// Windows：让本进程忽略控制台 Ctrl+C（返回 true 表示成功）。
/// 只用 dart:ffi 调 kernel32.SetConsoleCtrlHandler(NULL, TRUE)，
/// 不分配内存、不引入外部包；非 Windows 永不调用。
bool _ignoreConsoleCtrl() {
  try {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final setHandler = kernel32.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Void>, int)>('SetConsoleCtrlHandler');
    return setHandler(ffi.nullptr, 1) != 0;
  } catch (_) {
    return false;
  }
}

/// Windows：设置控制台窗口标题（尽力而为，失败忽略）。
Future<void> _setConsoleTitle(String title) async {
  if (!Platform.isWindows) return;
  try {
    final r = await Process.run(
      'cmd.exe',
      ['/c', 'title $title'],
      runInShell: false,
    );
    _tlog('title-set exit=${r.exitCode}');
  } catch (e) {
    _tlog('title-set failed: $e');
  }
}

String? _home() {
  if (Platform.isWindows) {
    final up = Platform.environment['USERPROFILE'];
    if (up != null && up.isNotEmpty) return up;
    final drive = Platform.environment['HOMEDRIVE'] ?? 'C:';
    final path = Platform.environment['HOMEPATH'] ?? '\\';
    return '$drive$path';
  }
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return home;
  return null;
}

String _firstWord(String cmd) {
  final i = cmd.indexOf(RegExp(r'\s'));
  return i < 0 ? cmd : cmd.substring(0, i);
}

String _afterFirst(String cmd) {
  final i = cmd.indexOf(RegExp(r'\s'));
  return i < 0 ? '' : cmd.substring(i).trim();
}

String _unquote(String s) {
  final t = s.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'")))) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

bool _isAbsolute(String target) {
  if (target.startsWith('/') || target.startsWith('\\')) return true;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target)) return true;
  return false;
}

String _join(String a, String b) {
  final sep = Platform.pathSeparator;
  final left = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
  return '$left$sep$b';
}

Future<String> _changeDir(String cwd, String arg) async {
  var target = _unquote(arg);
  if (target.isEmpty) return _home() ?? cwd;
  final home = _home();
  if (target.startsWith('~') && home != null) {
    target = home + target.substring(1);
  }
  if (target.startsWith('/d ') || target.startsWith('/D ')) {
    target = target.substring(3).trim();
  }
  String resolved;
  if (_isAbsolute(target)) {
    resolved = target;
  } else if (RegExp(r'^[A-Za-z]:$').hasMatch(target)) {
    resolved = '${target[0]}:${Platform.pathSeparator}';
  } else {
    resolved = _join(cwd, target);
  }
  try {
    if (await Directory(resolved).exists()) return resolved;
  } catch (_) {}
  stderr.writeln('目录不存在：$arg');
  return cwd;
}
