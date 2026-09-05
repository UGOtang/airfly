// 条件导出：Web 用 web 实现，其他平台用 io 实现。
// 调用方只 import 这一个文件即可。
export 'chunk_io_interface.dart';
export 'chunk_io_io.dart' if (dart.library.html) 'chunk_io_web.dart';
