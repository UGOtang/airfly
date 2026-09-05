import 'package:airfly/core/term_backend.dart';
import 'package:airfly/core/term_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 可控假后端：按预设脚本回放输出，断言会话逻辑不碰真 shell。
class FakeBackend implements TermBackend {
  @override
  bool supportsShell = true;
  @override
  String shellName = 'fake';
  @override
  String promptChar = r'$';
  @override
  String homeDir = '/home/u';

  String cwd = '/home/u';
  // 用 p.* 构造期望目录，保证 Windows/posix 主机下断言一致
  late final Set<String> dirs = {
    p.normalize('/home/u'),
    p.normalize('/home/u/sub'),
    p.normalize('/'),
  };
  final Map<String, TermScript> scripts = {};
  int runs = 0;

  @override
  Future<String> initialCwd() async => cwd;

  @override
  Future<bool> isDirectory(String path) async => dirs.contains(path);

  @override
  Future<TermResult> run(
    String command,
    String cwd,
    void Function(String text, bool isErr) onChunk,
  ) async {
    runs++;
    final s = scripts[command];
    if (s == null) return const TermResult(0);
    for (final chunk in s.chunks) {
      onChunk(chunk.text, chunk.isErr);
    }
    if (s.hang) {
      // 模拟长命令：等一小拍（测试里靠 abort 标记验证）
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return TermResult(s.exitCode);
  }

  @override
  void abort() {}
}

class TermChunk {
  final String text;
  final bool isErr;
  const TermChunk(this.text, [this.isErr = false]);
}

class TermScript {
  final List<TermChunk> chunks;
  final int exitCode;
  final bool hang;
  const TermScript(this.chunks, {this.exitCode = 0, this.hang = false});
}

Future<TermSession> _open(FakeBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final s = TermSession(backend: backend);
  await s.init();
  return s;
}

void main() {
  group('TermSession', () {
    test('初始化横幅与工作目录', () async {
      final s = await _open(FakeBackend());
      expect(s.cwd, '/home/u');
      expect(s.lines.length, 2);
      expect(s.lines.first.kind, TermLineKind.system);
      s.dispose();
    });

    test('普通命令回显 + 输出 + 退出码非零提示', () async {
      final b = FakeBackend()
        ..scripts['ok'] = const TermScript([
          TermChunk('hello\n'),
        ])
        ..scripts['bad'] = const TermScript(
          [TermChunk('nope\n', true)],
          exitCode: 3,
        );
      final s = await _open(b);
      await s.submit('ok');
      expect(
        s.lines.any((e) =>
            e.kind == TermLineKind.input && e.text.endsWith(r'$ ok')),
        isTrue,
      );
      expect(s.lines.last.text, 'hello');
      await s.submit('bad');
      expect(s.lines.last.text, '[exit 3]');
      expect(
        s.lines.where((e) => e.kind == TermLineKind.error).length,
        1,
      );
      s.dispose();
    });

    test('跨 chunk 半行正确拼接', () async {
      final b = FakeBackend()
        ..scripts['p'] = const TermScript([
          TermChunk('hel'),
          TermChunk('lo wor'),
          TermChunk('ld\nbye\n'),
        ]);
      final s = await _open(b);
      await s.submit('p');
      final texts = s.lines.map((e) => e.text).toList();
      expect(texts.contains('hello world'), isTrue);
      expect(texts.contains('bye'), isTrue);
      expect(texts.any((t) => t == 'hel' || t == 'lo wor'), isFalse);
      s.dispose();
    });

    test('ANSI 转义被剥掉', () async {
      expect(
        TermSession.stripAnsi('\x1B[32mgreen\x1B[0m plain'),
        'green plain',
      );
      final b = FakeBackend()
        ..scripts['c'] = const TermScript([
          TermChunk('\x1B[1;31merr\x1B[0m\n'),
        ]);
      final s = await _open(b);
      await s.submit('c');
      expect(s.lines.last.text, 'err');
      s.dispose();
    });

    test('空输入与运行中重复提交', () async {
      final b = FakeBackend()
        ..scripts['long'] = const TermScript(
          [TermChunk('x\n')],
          hang: true,
        );
      final s = await _open(b);
      final before = s.lines.length;
      await s.submit('   ');
      expect(s.lines.length, before); // 空输入无任何输出
      // 模拟运行中
      final f = s.submit('long');
      await s.submit('other'); // 应被拒绝而不是排队
      expect(
        s.lines.last.text,
        contains('已有命令在运行'),
      );
      await f;
      s.dispose();
    });

    test('后端抛异常不卡死会话', () async {
      final b = _ThrowingBackend();
      final s = await _open(b);
      await s.submit('boom');
      expect(s.running, isFalse);
      expect(s.lines.last.kind, TermLineKind.error);
      // 会话仍可用
      await s.submit('echo hi');
      expect(s.lines.last.text, 'hi');
      s.dispose();
    });

    test('cd 切换/回主目录/不存在', () async {
      final s = await _open(FakeBackend());
      await s.submit('cd sub');
      expect(s.cwd, p.normalize('/home/u/sub'));
      await s.submit('cd /');
      expect(s.cwd, p.normalize('/'));
      await s.submit('cd nowhere');
      expect(s.cwd, p.normalize('/')); // 失败保持原目录
      expect(s.lines.last.text, contains('目录不存在'));
      await s.submit('cd');
      expect(s.cwd, '/home/u');
      s.dispose();
    });

    test('受限模式行为', () async {
      SharedPreferences.setMockInitialValues({});
      final s = TermSession(backend: const RestrictedBackend());
      await s.init();
      expect(s.supportsShell, isFalse);
      final runs0 = s.lines.length;
      await s.submit('ls');
      // 不会调用后端，而是友好提示
      expect(s.lines.length, greaterThan(runs0));
      expect(s.lines.last.text, contains('受限模式'));
      await s.submit('echo hi');
      expect(s.lines.last.text, 'hi');
      await s.submit('cd /tmp');
      expect(s.lines.last.text, contains('受限模式'));
      s.dispose();
    });

    test('clear 与历史去重/上下翻', () async {
      final s = await _open(FakeBackend());
      await s.submit('echo a');
      await s.submit('echo b');
      await s.submit('echo a'); // 重复提到末尾
      expect(s.history, ['echo b', 'echo a']);
      expect(s.recallOlder('draft'), 'echo a');
      expect(s.recallOlder('draft'), 'echo b');
      expect(s.recallOlder('draft'), 'echo b'); // 顶不动
      expect(s.recallNewer(), 'echo a');
      expect(s.recallNewer(), 'draft'); // 回到草稿
      expect(s.recallNewer(), isNull);
      s.clear();
      expect(s.lines, isEmpty);
      s.dispose();
    });

    test('输出超长截断保内存', () async {
      final b = FakeBackend()
        ..scripts['spam'] = TermScript(
          List.generate(2500, (i) => TermChunk('line $i\n')),
        );
      final s = await _open(b);
      await s.submit('spam');
      expect(s.lines.length, TermSession.maxLines);
      // 最新的行保留
      expect(s.lines.last.text, 'line 2499');
      s.dispose();
    });

    test('历史持久化 roundtrip', () async {
      SharedPreferences.setMockInitialValues({});
      final b = FakeBackend();
      final s = TermSession(backend: b);
      await s.init();
      await s.submit('echo persisted');
      // 等一拍让异步落盘完成
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(TermSession.historyKey),
          contains('echo persisted'));
      s.dispose();
    });
  });
}

class _ThrowingBackend extends FakeBackend {
  @override
  Future<TermResult> run(
    String command,
    String cwd,
    void Function(String text, bool isErr) onChunk,
  ) {
    throw StateError('shell 炸了');
  }
}
