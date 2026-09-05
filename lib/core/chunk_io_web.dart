// Web 平台的分块读写实现。
// 上传：file_picker 在 Web 上直接给 bytes，用内存读取。
// 下载：内存累积后通过 Blob 触发浏览器下载。

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'chunk_io_interface.dart';

Future<ChunkReader> openUploadReader({String? path, Uint8List? bytes}) {
  if (bytes != null) {
    return Future.value(MemoryChunkReader(bytes));
  }
  return Future.error(StateError('Web 端无法读取该文件，请重新选择'));
}

Future<(DownloadSink, String)> openDownloadSink(String fileName) async {
  final sink = WebDownloadSink(fileName);
  return (sink, fileName);
}

String _mimeFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'md':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'mp4':
      return 'video/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

class WebDownloadSink implements DownloadSink {
  final String fileName;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  bool _done = false;

  WebDownloadSink(this.fileName);

  @override
  Future<void> write(Uint8List bytes) async {
    if (_done) throw StateError('sink finished');
    _buf.add(bytes);
  }

  @override
  Future<String> finish() async {
    _done = true;
    final data = _buf.toBytes();
    final jsBytes = data.toJS;
    final blob = web.Blob(
      [jsBytes].toJS,
      web.BlobPropertyBag(type: _mimeFor(fileName)),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName;
      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
    } finally {
      web.URL.revokeObjectURL(url);
    }
    return fileName;
  }

  @override
  Future<void> abort() async {
    _done = true;
    _buf.clear();
  }
}
