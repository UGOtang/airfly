// 本地终端会话：行缓冲 / 内置命令 / 历史 / 截断 / 持久化。
// 纯 Dart + ChangeNotifier，不直接碰平台 API（平台差异由 TermBackend 屏蔽），
// 因此可以用 FakeBackend 完整单测。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'term_backend.dart';

/// 输出行种类（UI 按种类配色）。
enum TermLineKind { input, output, error, system }

class TermLine {
  final String text;
  final TermLineKind kind;
  const TermLine(this.text, this.kind);
}

class TermSession extends ChangeNotifier {
  static const int maxLines = 2000;
  static const int maxHistory = 100;
  static const String historyKey = 'af_term_history';

  final TermBackend backend;

  TermSession({TermBackend? backend}) : backend = backend ?? createBackend();

  final List<TermLine> _lines = [];
  List<TermLine> get lines => List.unmodifiable(_lines);

  bool _running = false;
  bool get running => _running;

  String _cwd = '.';
  String get cwd => _cwd;

  String get shellName => backend.shellName;
  String get promptChar => backend.promptChar;
  bool get supportsShell => backend.supportsShell;

  final List<String> _history = [];
  List<String> get history => List.unmodifiable(_history);

  /// 历史浏览指针：-1 表示不在浏览（显示草稿）。
  int _histIndex = -1;
  String _draft = '';

  /// 跨 chunk 的行碎片（多字节/半行拼接用）。
  String _fragment = '';

  bool _inited = false;
  bool _disposed = false;

  Timer? _notifyTimer;
  bool _notifyPending = false;

  // ANSI 转义（颜色/光标控制）：行模式终端不解释，只剥掉，避免显示乱码。
  static final RegExp _ansiCsi = RegExp('\x1B\\[[0-9;?]*[a-zA-Z]');
  static final RegExp _ansiOsc = RegExp('\x1B\\][^\x07\x1B]*(?:\x07|\x1B\\\\)');
  static final RegExp _winDrive = RegExp(r'^[A-Za-z]:$');

  static String stripAnsi(String s) {
    return s.replaceAll(_ansiOsc, '').replaceAll(_ansiCsi, '');
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await _loadHistory();
    try {
      // 注意：widget 测试是 FakeAsync，真 IO 必须用 tester.runAsync() 包住
      // init 调用，详见 test/theme_test.dart；平时 exists() 瞬时返回。
      _cwd = await backend.initialCwd();
    } catch (_) {
      _cwd = '.';
    }
    if (supportsShell) {
      _add(TermLine('AirFly 本地终端 · $shellName · $_cwd', TermLineKind.system));
      _add(TermLine(
          '命令在本机 shell 下执行，输出实时显示。输入 help 查看内置命令。',
          TermLineKind.system));
    } else {
      _add(const TermLine('AirFly 终端（受限模式）', TermLineKind.system));
      _add(const TermLine(
          '当前平台不支持本地 shell，可用内置命令：help / echo / clear。完整终端请用桌面端。',
          TermLineKind.system));
    }
    _notify();
  }

  // ---------------------------------------------------------------- 执行

  /// 提交一行输入。同一时间只跑一个命令，重复提交会提示而不排队
  /// （排队容易造成“输出对不上哪条命令”的困惑，是 bug 温床）。
  Future<void> submit(String raw) async {
    if (_disposed) return;
    final cmd = raw.trim();
    if (cmd.isEmpty) return;
    if (_running) {
      _add(const TermLine('已有命令在运行，先停止它再执行新命令。',
          TermLineKind.system));
      _notify();
      return;
    }
    _pushHistory(cmd);
    _histIndex = -1;
    _draft = '';
    _add(TermLine('$_cwd $promptChar $cmd', TermLineKind.input));

    final first = _firstWord(cmd);
    switch (first.toLowerCase()) {
      case 'clear':
      case 'cls':
        _lines.clear();
        _notify();
        return;
      case 'help':
        _printHelp();
        _notify();
        return;
      case 'echo':
        _add(TermLine(_afterFirst(cmd), TermLineKind.output));
        _notify();
        return;
      case 'cd':
        await _changeDir(_afterFirst(cmd));
        _notify();
        return;
    }

    if (!supportsShell) {
      _add(const TermLine(
          '受限模式不支持执行外部命令，可用：help / echo / clear。',
          TermLineKind.system));
      _notify();
      return;
    }

    _running = true;
    var aborted = false;
    _notify();
    try {
      final res = await backend.run(cmd, _cwd, (chunk, isErr) {
        _appendChunk(chunk, isErr ? TermLineKind.error : TermLineKind.output);
      });
      if (_abortedFlag) {
        aborted = true;
      } else if (res.exitCode != 0) {
        _add(TermLine('[exit ${res.exitCode}]', TermLineKind.system));
      }
    } catch (e) {
      _flushFragment(TermLineKind.output);
      _add(TermLine('执行失败：$e', TermLineKind.error));
    } finally {
      _abortedFlag = false;
      _running = false;
      _flushFragment(TermLineKind.output);
      if (aborted) {
        _add(const TermLine('（已停止）', TermLineKind.system));
      }
      _notify();
    }
  }

  bool _abortedFlag = false;

  /// 停止当前命令（对应 UI 的停止按钮 / Ctrl+C）。
  void abort() {
    if (!_running) return;
    _abortedFlag = true;
    try {
      backend.abort();
    } catch (_) {}
  }

  void clear() {
    _lines.clear();
    _notify();
  }

  /// 全量文本（UI“复制输出”用）。
  String copyAll() => _lines.map((e) => e.text).join('\n');

  // ---------------------------------------------------------------- 内置命令

  void _printHelp() {
    const help = [
      '内置命令：',
      '  help        显示本帮助',
      '  echo 文本    原样输出一行',
      '  cd [目录]    切换工作目录（无参数回主目录）',
      '  clear/cls   清屏',
      '',
      '其他输入都交给本机 shell 执行；Tab 上方按钮可停止运行中的命令，',
      '上下方向键翻历史命令，输出保留最近 2000 行。',
    ];
    for (final h in help) {
      _add(TermLine(h, TermLineKind.system));
    }
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

  Future<void> _changeDir(String arg) async {
    if (!supportsShell) {
      _add(const TermLine('受限模式不支持切换目录。', TermLineKind.system));
      return;
    }
    var target = _unquote(arg);
    if (target.isEmpty) {
      _cwd = backend.homeDir;
      return;
    }
    if (target.startsWith('~')) {
      target = backend.homeDir + target.substring(1);
    }
    // Windows: cd /d D:\xxx
    if (target.startsWith('/d ') || target.startsWith('/D ')) {
      target = target.substring(3).trim();
    }
    String resolved;
    try {
      if (p.isAbsolute(target)) {
        resolved = p.normalize(target);
      } else if (_winDrive.hasMatch(target)) {
        resolved = '${target[0]}:${p.separator}';
      } else {
        resolved = p.normalize(p.join(_cwd, target));
      }
    } catch (_) {
      _add(TermLine('路径无效：$arg', TermLineKind.error));
      return;
    }
    bool ok = false;
    try {
      ok = await backend.isDirectory(resolved);
    } catch (_) {
      ok = false;
    }
    if (ok) {
      _cwd = resolved;
    } else {
      _add(TermLine('目录不存在：$arg', TermLineKind.error));
    }
  }

  // ---------------------------------------------------------------- 行缓冲

  void _appendChunk(String chunk, TermLineKind kind) {
    if (_disposed) return;
    // stdout/stderr 共用行碎片：极端穿插下可能并行，不影响正确性
    _addChunkWithFragment(chunk, kind);
    _throttledNotify();
  }

  void _addChunkWithFragment(String chunk, TermLineKind kind) {
    final text = _fragment + chunk;
    _fragment = '';
    final parts = stripAnsi(text).split('\n');
    for (var i = 0; i < parts.length; i++) {
      final line = parts[i].replaceAll('\r', '');
      if (i == parts.length - 1) {
        // 最后一个分段可能是半行，留到下个 chunk 再拼
        _fragment = line;
      } else {
        _add(TermLine(line, kind));
      }
    }
  }

  void _flushFragment(TermLineKind kind) {
    if (_fragment.isNotEmpty) {
      _add(TermLine(_fragment, kind));
      _fragment = '';
    }
  }

  void _add(TermLine line) {
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  // ---------------------------------------------------------------- 历史

  void _pushHistory(String cmd) {
    _history.remove(cmd); // 去重：重复命令提到末尾
    _history.add(cmd);
    if (_history.length > maxHistory) {
      _history.removeRange(0, _history.length - maxHistory);
    }
    unawaited(_saveHistory());
  }

  /// 上翻历史，返回应填入输入框的文本（无历史返回 null）。
  String? recallOlder(String draft) {
    if (_history.isEmpty) return null;
    if (_histIndex == -1) {
      _draft = draft;
      _histIndex = _history.length - 1;
    } else if (_histIndex > 0) {
      _histIndex--;
    }
    return _history[_histIndex];
  }

  /// 下翻历史，返回应填入输入框的文本（回到草稿）。
  String? recallNewer() {
    if (_histIndex == -1) return null;
    if (_histIndex < _history.length - 1) {
      _histIndex++;
      return _history[_histIndex];
    }
    _histIndex = -1;
    return _draft;
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(historyKey) ?? const [];
      _history
        ..clear()
        ..addAll(saved.where((e) => e.trim().isNotEmpty).take(maxHistory));
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(historyKey, List.of(_history));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 通知/释放

  void _notify() {
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

  void _throttledNotify() => _notify();

  @override
  void dispose() {
    _disposed = true;
    try {
      backend.abort();
    } catch (_) {}
    _notifyTimer?.cancel();
    super.dispose();
  }
}
