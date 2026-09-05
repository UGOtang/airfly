// 分块读写抽象（纯 Dart，可单测）。
// 具体实现按平台拆分：chunk_io_io.dart / chunk_io_web.dart，
// 由 chunk_io.dart 按条件导出，避免在 Web 编译时引入 dart:io。

import 'dart:typed_data';

/// 分块读取（上传用）。
abstract class ChunkReader {
  int get size;
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}

/// 分块写入（下载用，顺序追加）。
abstract class DownloadSink {
  /// 写入一块数据（调用方保证 offset 连续）。
  Future<void> write(Uint8List bytes);

  /// 完成，返回保存位置描述（io: 文件路径；web: 文件名）。
  Future<String> finish();

  /// 中止并清理半成品。
  Future<void> abort();
}

/// 纯内存读取器（Web 上传 / 小文件通用）。
class MemoryChunkReader implements ChunkReader {
  final Uint8List _bytes;
  bool _closed = false;

  MemoryChunkReader(this._bytes);

  @override
  int get size => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw StateError('reader closed');
    if (offset < 0 || offset > _bytes.length) {
      throw RangeError('offset $offset out of range ${_bytes.length}');
    }
    final end = (offset + length).clamp(0, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, end);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
