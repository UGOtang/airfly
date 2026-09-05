// dart:io 平台的分块读写实现（桌面/移动端）。
// 注意：本文件只能在非 Web 平台被条件导出引用。

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'chunk_io_interface.dart';

/// 打开上传读取器：优先用文件路径流式读（大文件不爆内存），
/// 无路径时退化为内存读取。
Future<ChunkReader> openUploadReader({String? path, Uint8List? bytes}) {
  if (path != null && path.isNotEmpty) {
    return IoChunkReader.open(path);
  }
  if (bytes != null) {
    return Future.value(MemoryChunkReader(bytes));
  }
  return Future.error(StateError('no file path or bytes'));
}

class IoChunkReader implements ChunkReader {
  final RandomAccessFile _raf;
  final int _size;

  IoChunkReader._(this._raf, this._size);

  static Future<IoChunkReader> open(String path) async {
    final f = File(path);
    if (!await f.exists()) {
      throw StateError('文件不存在：$path');
    }
    final raf = await f.open(mode: FileMode.read);
    try {
      final size = await raf.length();
      return IoChunkReader._(raf, size);
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  @override
  int get size => _size;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || offset > _size) {
      throw RangeError('offset $offset out of range $_size');
    }
    final want = length.clamp(0, _size - offset);
    if (want == 0) return Uint8List(0);
    await _raf.setPosition(offset);
    return await _raf.read(want);
  }

  @override
  Future<void> close() async {
    try {
      await _raf.close();
    } catch (_) {}
  }
}

/// 打开下载写入器：落盘到下载目录（取不到则用文档目录），文件名自动去重。
/// 返回 (sink, 显示路径)。
Future<(DownloadSink, String)> openDownloadSink(String fileName) async {
  final dir = await _downloadDir();
  final safe = _safeName(fileName);
  var target = File(p.join(dir.path, safe));
  var n = 1;
  while (await target.exists()) {
    final stem = p.basenameWithoutExtension(safe);
    final ext = p.extension(safe);
    target = File(p.join(dir.path, '$stem($n)$ext'));
    n++;
    if (n > 999) break;
  }
  final raf = await target.open(mode: FileMode.write);
  return (IoDownloadSink(raf, target), target.path);
}

Future<Directory> _downloadDir() async {
  try {
    final dl = await getDownloadsDirectory();
    if (dl != null) {
      await Directory(dl.path).create(recursive: true);
      return Directory(dl.path);
    }
  } catch (_) {}
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'AirFly'));
  await dir.create(recursive: true);
  return dir;
}

String _safeName(String raw) {
  var name = raw.replaceAll('\\', '/');
  if (name.contains('/')) name = name.split('/').last;
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  name = name.replaceAll(RegExp(r'^\.+'), '');
  if (name.isEmpty) name = 'unnamed';
  if (name.length > 180) name = name.substring(0, 180);
  return name;
}

class IoDownloadSink implements DownloadSink {
  final RandomAccessFile _raf;
  final File _file;
  bool _done = false;

  IoDownloadSink(this._raf, this._file);

  @override
  Future<void> write(Uint8List bytes) async {
    if (_done) throw StateError('sink finished');
    if (bytes.isEmpty) return;
    await _raf.writeFrom(bytes);
  }

  @override
  Future<String> finish() async {
    _done = true;
    try {
      await _raf.close();
    } catch (_) {}
    return _file.path;
  }

  @override
  Future<void> abort() async {
    _done = true;
    try {
      await _raf.close();
    } catch (_) {}
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }
}
