// RelayClient 端到端检查：自起服务端（临时端口+临时目录），
// 用纯 Dart 客户端跑 presence/剪切板/上传/下载/续传/纠错/删除全流程。
// 用法：dart tool/check_relay.dart   退出码 0 = 全过。
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'relay_client.dart';

const String host = '127.0.0.1';
const int port = 18082;

int _failures = 0;

void check(bool cond, String name, [String extra = '']) {
  if (cond) {
    print('  ok   $name');
  } else {
    _failures++;
    print('  FAIL $name${extra.isEmpty ? '' : ' -- $extra'}');
  }
}

Future<void> waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
  String what = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('timeout waiting $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

bool listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<Process> startServer(Directory dataDir) async {
  final proc = await Process.start(
    Platform.resolvedExecutable,
    ['server/bin/server.dart'],
    workingDirectory: '.',
    environment: {
      'PORT': '$port',
      'HOST': host,
      'DATA_DIR': dataDir.path,
    },
  );
  unawaited(proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((l) => print('[srv] $l')));
  unawaited(proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((l) => print('[srv:err] $l')));
  return proc;
}

Future<bool> waitHealthy() async {
  final cli = HttpClient();
  try {
    for (var i = 0; i < 50; i++) {
      try {
        final req = await cli.get(host, port, '/healthz');
        final resp = await req.close().timeout(const Duration(seconds: 2));
        final ok = resp.statusCode == 200;
        await resp.drain();
        if (ok) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  } finally {
    cli.close();
  }
}

Future<void> stopServer(Process p) async {
  try {
    p.kill();
  } catch (_) {}
  try {
    await p.exitCode.timeout(const Duration(seconds: 5));
  } catch (_) {
    try {
      p.kill();
    } catch (_) {}
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

String newFileId([String prefix = 'rc']) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return '$prefix${List.generate(14, (_) => chars[r.nextInt(chars.length)]).join()}';
}

Future<void> main() async {
  final dataDir = await Directory.systemTemp.createTemp('airfly_rc_');
  print('data dir: ${dataDir.path}');

  Process srv = await startServer(dataDir);
  if (!await waitHealthy()) {
    check(false, 'server healthy');
    await stopServer(srv);
    print('FAILURES: $_failures');
    exit(1);
  }
  check(true, 'server healthy');

  const space = 'rc-space1';
  const key = 'pw123';
  final url = 'ws://$host:$port/ws';

  RelayClient mk(String dev, String name) => RelayClient(
        serverUrl: url,
        spaceId: space,
        spaceKey: key,
        deviceId: dev,
        deviceName: name,
        platform: 'test',
      );

  final a = mk('devA', 'A');
  final b = mk('devB', 'B');
  try {
    await a.connect();
    await b.connect();
    await waitFor(() => a.connected && b.connected, what: 'connected');
    check(true, 'AB 连接成功');
    await waitFor(() => a.devices.length == 2 && b.devices.length == 2,
        what: 'presence(2)');
    check(true, '双方看到 2 台在线');

    // 错误密码
    final bad = RelayClient(
      serverUrl: url,
      spaceId: space,
      spaceKey: 'wrong',
      deviceId: 'devC',
      deviceName: 'C',
    );
    await bad.connect();
    await Future<void>.delayed(const Duration(seconds: 1));
    check(bad.lastErrorCode == 'bad_space_key', '错误密码被拒绝');
    await bad.dispose();

    // 剪切板
    const clipText = 'relay client 你好 456';
    await a.pushClip(clipText);
    await waitFor(
        () => b.clipHistory.isNotEmpty && b.clipHistory.first.text == clipText,
        what: 'clip broadcast');
    check(true, 'B 收到剪切板广播');

    // 上传 300KB
    final rnd = Random(7);
    final payload = List<int>.generate(300 * 1024, (_) => rnd.nextInt(256));
    final fid1 = newFileId();
    var meta = await a.announceFile(
        fileId: fid1, fileName: 'demo.bin', fileSize: payload.length);
    check(meta.uploadedBytes == 0, '新文件从 0 开始');
    var off = 0;
    var done = false;
    while (off < payload.length) {
      final end = (off + RelayClient.kChunkSize).clamp(0, payload.length);
      final chunk = payload.sublist(off, end);
      final (up, complete, mismatch) = await a.uploadChunk(
        fileId: fid1,
        offset: off,
        bytes: chunk,
        isLast: end == payload.length,
      );
      check(!mismatch, '无错位');
      off = up;
      done = complete;
    }
    check(done && off == payload.length, '上传完成');
    await waitFor(
        () => b.files.any((f) => f.id == fid1 && f.complete),
        what: 'B 看到完整文件');
    check(true, 'B 看到完整文件');

    // 下载校验
    final got = <int>[];
    var doff = 0;
    while (true) {
      final (at, bytes, isLast) =
          await b.downloadChunk(fileId: fid1, offset: doff);
      check(at == doff, '下载偏移连续 @$doff');
      got.addAll(bytes);
      doff += bytes.length;
      if (isLast) break;
      if (doff > payload.length + 1024) throw StateError('download loop');
    }
    check(listEq(got, payload), '下载字节一致 (${got.length}B)');

    // 断点续传
    final payload2 = List<int>.generate(200 * 1024, (_) => rnd.nextInt(256));
    final fid2 = newFileId('rs');
    await a.announceFile(
        fileId: fid2, fileName: 'resume.bin', fileSize: payload2.length);
    final (up1, _, _) = await a.uploadChunk(
      fileId: fid2,
      offset: 0,
      bytes: payload2.sublist(0, RelayClient.kChunkSize),
      isLast: false,
    );
    check(up1 == RelayClient.kChunkSize, '第一块落盘');
    await a.close(); // 模拟掉线
    final a2 = mk('devA', 'A');
    await a2.connect();
    await waitFor(() => a2.connected, what: 'reconnected');
    meta = await a2.announceFile(
        fileId: fid2, fileName: 'resume.bin', fileSize: payload2.length);
    check(meta.uploadedBytes == RelayClient.kChunkSize, '续传偏移对');
    final (up2, complete2, _) = await a2.uploadChunk(
      fileId: fid2,
      offset: meta.uploadedBytes,
      bytes: payload2.sublist(meta.uploadedBytes),
      isLast: true,
    );
    check(complete2 && up2 == payload2.length, '续传完成');

    // 错位纠正
    final fid3 = newFileId('mm');
    await a2.announceFile(fileId: fid3, fileName: 'mm.bin', fileSize: 50000);
    final (upBad, _, mismatch) = await a2.uploadChunk(
      fileId: fid3,
      offset: 999,
      bytes: List.filled(100, 7),
      isLast: false,
    );
    check(mismatch && upBad == 0, '错位被拒绝并纠正');

    // 删除
    await b.deleteFile(fid1);
    await waitFor(() => !b.files.any((f) => f.id == fid1),
        what: '删除同步');
    check(true, '删除后列表同步');

    await a2.dispose();
    await b.dispose();
  } catch (e, st) {
    _failures++;
    print('  FAIL exception: $e\n$st');
  }

  await stopServer(srv);
  try {
    await dataDir.delete(recursive: true);
  } catch (_) {}

  print(_failures == 0 ? 'ALL PASS' : 'FAILURES: $_failures');
  exit(_failures == 0 ? 0 : 1);
}
