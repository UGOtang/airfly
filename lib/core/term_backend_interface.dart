// 终端后端接口（纯 Dart，可单测）。
// 桌面端用真 shell（term_backend_io.dart），Web/移动端用受限实现。

/// 单次命令执行结果。
class TermResult {
  final int exitCode;
  const TermResult(this.exitCode);
}

/// 终端后端：屏蔽平台差异。
abstract class TermBackend {
  /// 是否支持真 shell。false = 受限模式（仅内置命令）。
  bool get supportsShell;

  /// shell 名称展示（如 cmd / sh / 受限模式）。
  String get shellName;

  /// 提示符尾字符（Windows '>'，Unix '$'）。
  String get promptChar;

  /// 用户主目录（cd 无参时用）。
  String get homeDir;

  /// 会话初始工作目录。
  Future<String> initialCwd();

  /// 路径是否为已存在目录（cd 校验用）。
  Future<bool> isDirectory(String path);

  /// 执行命令，实时通过 onChunk 回调输出文本分块。
  /// [isErr] 为 true 表示来自 stderr。
  /// 正常结束返回退出码；被 abort() 后同样经 exitCode 返回。
  Future<TermResult> run(
    String command,
    String cwd,
    void Function(String text, bool isErr) onChunk,
  );

  /// 终止当前正在执行的命令（无命令运行时无操作）。
  void abort();
}

/// 受限后端：Web / Android / iOS，没有本地 shell。
/// 只跑会话层的内置命令（help/echo/clear/cd 提示），绝不抛到 UI。
class RestrictedBackend implements TermBackend {
  const RestrictedBackend();

  @override
  bool get supportsShell => false;

  @override
  String get shellName => '受限模式';

  @override
  String get promptChar => r'$';

  @override
  String get homeDir => '/';

  @override
  Future<String> initialCwd() async => '/';

  @override
  Future<bool> isDirectory(String path) async => false;

  @override
  Future<TermResult> run(
    String command,
    String cwd,
    void Function(String text, bool isErr) onChunk,
  ) {
    throw UnsupportedError('当前平台不支持本地 shell');
  }

  @override
  void abort() {}
}
