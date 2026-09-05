// 条件导出：Web 用受限实现，其他平台用 io 实现
// （移动端虽有 dart:io，但 io 实现内部会按平台降级为受限模式）。
// 调用方只 import 这一个文件即可。
export 'term_backend_interface.dart';
export 'term_backend_io.dart' if (dart.library.html) 'term_backend_web.dart';
