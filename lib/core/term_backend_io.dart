// dart:io 平台的终端后端（Windows / macOS / Linux 桌面端）。
// 注意：本文件只能被条件导出引用，Web 编译时不可见。

import 'dart:convert';
import 'dart:io';

import 'term_backend_interface.dart';

TermBackend createBackend() {
  // 移动端有 dart:io 但不允许随意起 shell，统一走受限模式。
  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    return const RestrictedBackend();
  }
  return IoBackend();
}

class IoBackend implements TermBackend {
  Process? _current;

  @override
  bool get supportsShell => true;

  @override
  String get shellName => Platform.isWindows ? 'cmd' : 'sh';

  @override
  String get promptChar => Platform.isWindows ? '>' : r'$';

  @override
  String get homeDir {
    if (Platform.isWindows) {
      final up = Platform.environment['USERPROFILE'];
      if (up != null && up.isNotEmpty) return up;
      final drive = Platform.environment['HOMEDRIVE'] ?? 'C:';
      final path = Platform.environment['HOMEPATH'] ?? '\\';
      return '$drive$path';
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    return '.';
  }

  @override
  Future<String> initialCwd() async {
    final h = homeDir;
    try {
      if (await Directory(h).exists()) return h;
    } catch (_) {}
    return '.';
  }

  @override
  Future<bool> isDirectory(String path) async {
    try {
      return await Directory(path).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TermResult> run(
    String command,
    String cwd,
    void Function(String text, bool isErr) onChunk,
  ) async {
    final isWin = Platform.isWindows;
    // Windows 先 chcp 65001，保证输出是 UTF-8（否则中文 GBK 解码乱码）。
    // utf8.decoder 是流式解码，能正确处理多字节字符被拆到两个 chunk 的情况。
    final proc = await Process.start(
      isWin ? 'cmd.exe' : 'sh',
      isWin ? ['/c', 'chcp 65001 >nul & $command'] : ['-c', command],
      workingDirectory: cwd,
      runInShell: false,
    );
    _current = proc;
    try {
      final pending = <Future<void>>[
        proc.stdout
            .transform(utf8.decoder)
            .listen(
              (s) => onChunk(s, false),
              // 个别非法字节导致解码中断时给一行提示，不掐断整个会话
              onError: (_) => onChunk('\n（部分输出无法解码，已跳过）\n', true),
            )
            .asFuture<void>(),
        proc.stderr
            .transform(utf8.decoder)
            .listen(
              (s) => onChunk(s, true),
              onError: (_) => onChunk('\n（部分输出无法解码，已跳过）\n', true),
            )
            .asFuture<void>(),
      ];
      final code = await proc.exitCode;
      // exitCode 可能比流先结束，等两路流排空再返回，保证输出不丢尾
      for (final f in pending) {
        try {
          await f;
        } catch (_) {}
      }
      return TermResult(code);
    } finally {
      if (identical(_current, proc)) _current = null;
    }
  }

  @override
  void abort() {
    try {
      _current?.kill();
    } catch (_) {}
  }
}
