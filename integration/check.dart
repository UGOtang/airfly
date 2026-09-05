// AirFly 云中转端到端检查：真起服务端（临时端口 + 临时数据目录），
// 用裸 WebSocket 跑完  presence / 剪切板 / 上传 / 下载 / 续传 /
// 错位纠正 / 删除 / 隔离性 / 错误密码 / 重启恢复 全流程。
//
// 用法：dart integration/check.dart
// 仅依赖 dart SDK（dart:io / dart:convert），退出码 0 = 全过。
// ignore_for_file: avoid_print, library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const String host = '127.0.0.1';
const int port = 18081;

int _failures = 0;

void check(bool cond, String name, [String extra = '']) {
  if (cond) {
      print('  ok   $name');
  } else {
    _failures++;
      print('  FAIL $name${extra.isEmpty ? '' : ' -- $extra'}');
  }
}

bool listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ------------------------------------------------------------ 测试客户端

class _Wait {
  final bool Function(Map<String, dynamic>) pred;
  final Completer<Map<String, dynamic>> c = Completer();
  _Wait(this.pred);
}

class TClient {
  final WebSocket ws;
  final List<Map<String, dynamic>> buf = [];
  final List<_Wait> waiters = [];
  late final StreamSubscription _sub;

  TClient(this.ws) {
    _sub = ws.listen((data) {
      Map<String, dynamic>? msg;
      try {
        if (data is String) {
          final d = jsonDecode(data);
          if (d is Map<String, dynamic>) msg = d;
        }
      } catch (_) {}
      if (msg == null) return;
      final m = msg;
      if (m['type'] == 'ping') {
        try {
          ws.add(jsonEncode({'type': 'pong', 'ts': m['ts']}));
        } catch (_) {}
        return;
      }
      for (final w in List<_Wait>.from(waiters)) {
        if (!w.c.isCompleted && w.pred(m)) {
          waiters.remove(w);
          w.c.complete(m);
          return;
        }
      }
      buf.add(m);
    });
  }

  static Future<TClient> connect() async {
    final ws = await WebSocket.connect('ws://$host:$port/ws');
    return TClient(ws);
  }

  void send(Map<String, dynamic> m) => ws.add(jsonEncode(m));

  Future<Map<String, dynamic>> nextWhere(
    bool Function(Map<String, dynamic>) pred, {
    Duration timeout = const Duration(seconds: 8),
    String what = 'message',
  }) async {
    for (var i = 0; i < buf.length; i++) {
      if (pred(buf[i])) return buf.removeAt(i);
    }
    final w = _Wait(pred);
    waiters.add(w);
    try {
      return await w.c.future.timeout(timeout);
    } on TimeoutException {
      waiters.remove(w);
      throw TimeoutException('timeout waiting $what');
    }
  }

  Future<void> hello({
    required String space,
    String key = '',
    required String deviceId,
    String name = 'dev',
  }) async {
    send({
      'type': 'hello',
      'protocol': 1,
      'spaceId': space,
      'spaceKey': key,
      'apiKey': '',
      'device': {'id': deviceId, 'name': name, 'platform': 'test'},
    });
  }

  Future<void> close() async {
    await _sub.cancel();
    try {
      await ws.close();
    } catch (_) {}
  }
}

// ------------------------------------------------------------ 服务端进程

Future<Process> startServer(Directory dataDir) async {
  final proc = await Process.start(
    Platform.resolvedExecutable,
    ['bin/server.dart'],
    workingDirectory: 'server',
    environment: {
      'PORT': '$port',
      'HOST': host,
      'DATA_DIR': dataDir.path,
      'FILE_TTL_HOURS': '168',
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
        if (resp.statusCode == 200) {
          await resp.drain();
          return true;
        }
        await resp.drain();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  } finally {
    cli.close();
  }
}

Future<void> stopServer(Process p) async {
  try {
    // Windows 下只支持默认 kill（TerminateProcess），不传信号
    p.kill();
  } catch (_) {}
  try {
    await p.exitCode.timeout(const Duration(seconds: 5));
  } catch (_) {
    try {
      p.kill();
    } catch (_) {}
  }
  // 让 stdout/stderr 转发有机会收尾，避免悬挂
  await Future.delayed(const Duration(milliseconds: 200));
}

// ------------------------------------------------------------ 主流程

Future<void> main() async {
  final dataDir =
      await Directory.systemTemp.createTemp('airfly_e2e_');
  print('data dir: ${dataDir.path}');

  Process srv = await startServer(dataDir);
  if (!await waitHealthy()) {
    check(false, 'server healthy（启动失败，见上方 [srv] 日志）');
    await stopServer(srv);
    try {
      await dataDir.delete(recursive: true);
    } catch (_) {}
      print('FAILURES: $_failures');
    exit(1);
  }
  check(true, 'server healthy');

  const space = 'e2e-space1';
  const key = 'pw123';

  try {
    // ---- 1. A 加入
    final a = await TClient.connect();
    await a.hello(space: space, key: key, deviceId: 'devA', name: 'A');
    final wa = await a.nextWhere((m) => m['type'] == 'welcome');
    check(wa['deviceId'] == 'devA', 'A welcome 回显 deviceId');
    final pa1 = await a.nextWhere((m) => m['type'] == 'presence');
    check((pa1['devices'] as List).length == 1, 'A 看到自己在线');

    // ---- 2. B 加入同空间
    final b = await TClient.connect();
    await b.hello(space: space, key: key, deviceId: 'devB', name: 'B');
    await b.nextWhere((m) => m['type'] == 'welcome');
    final pa2 = await a.nextWhere(
      (m) => m['type'] == 'presence' && (m['devices'] as List).length == 2,
      what: 'presence(2) on A',
    );
    check((pa2['devices'] as List).length == 2, 'A 看到 B 上线');
    final pb = await b.nextWhere(
      (m) => m['type'] == 'presence' && (m['devices'] as List).length == 2,
      what: 'presence(2) on B',
    );
    check((pb['devices'] as List).length == 2, 'B 看到 A 与自己');

    // ---- 3. 密码错误被拒
    final c = await TClient.connect();
    await c.hello(
        space: space, key: 'wrong', deviceId: 'devC', name: 'C');
    final cerr = await c.nextWhere((m) => m['type'] == 'error');
    check(cerr['code'] == 'bad_space_key', '错误密码被拒绝');
    await c.close();

    // ---- 4. 不同空间隔离
    final d = await TClient.connect();
    await d.hello(
        space: 'other-space', key: '', deviceId: 'devD', name: 'D');
    await d.nextWhere((m) => m['type'] == 'welcome');
    final pd = await d.nextWhere((m) => m['type'] == 'presence');
    check((pd['devices'] as List).length == 1, '不同空间互相隔离');

    // ---- 5. 剪切板推送 + 广播
    const clipText = 'hello from A 你好 123';
    a.send({'type': 'clipboard_push', 'msgId': 'm1', 'text': clipText});
    final cuB = await b.nextWhere(
      (m) => m['type'] == 'clipboard_update',
      what: 'clipboard_update on B',
    );
    check((cuB['item'] as Map)['text'] == clipText, 'B 收到剪切板广播');
    // D 不应收到（等 1.2s 确认无消息）
    var dGotClip = false;
    try {
      await d.nextWhere(
        (m) => m['type'] == 'clipboard_update',
        timeout: const Duration(milliseconds: 1200),
      );
      dGotClip = true;
    } on TimeoutException {
      dGotClip = false;
    }
    check(!dGotClip, '剪切板不串空间');

    // ---- 6. 上传 300KB 文件（3 块 stop-and-wait）
    final rnd = Random(42);
    final payload =
        List<int>.generate(300 * 1024, (_) => rnd.nextInt(256));
    const fid1 = 'e2eFile00123456';
    a.send({
      'type': 'file_announce',
      'msgId': 'm2',
      'fileId': fid1,
      'name': 'demo.bin',
      'size': payload.length,
    });
    final ann = await a.nextWhere((m) => m['type'] == 'file_announced');
    check((ann['file'] as Map)['uploadedBytes'] == 0, '新文件从 0 开始');

    var off = 0;
    var lastAckComplete = false;
    var n = 0;
    while (off < payload.length) {
      final end = (off + 128 * 1024).clamp(0, payload.length);
      final chunk = payload.sublist(off, end);
      final isLast = end == payload.length;
      a.send({
        'type': 'file_chunk',
        'msgId': 'm2c$n',
        'fileId': fid1,
        'offset': off,
        'dataBase64': base64.encode(chunk),
        'isLast': isLast,
      });
      final ack = await a.nextWhere(
        (m) =>
            m['type'] == 'file_chunk_ack' &&
            m['refMsgId'] == 'm2c$n',
        what: 'chunk ack $n',
      );
      off = (ack['uploadedBytes'] as num).toInt();
      lastAckComplete = ack['complete'] == true;
      n++;
    }
    check(lastAckComplete && off == payload.length, '上传完成');
    final flB = await b.nextWhere(
      (m) =>
          m['type'] == 'file_list' &&
          (m['files'] as List).any((f) =>
              f is Map &&
              f['id'] == fid1 &&
              f['complete'] == true),
      what: 'file_list complete on B',
    );
    check(true, 'B 看到完整文件: ${(flB['files'] as List).length} 个');

    // ---- 7. B 下载并校验字节一致
    final expect = payload;
    final got = <int>[];
    var doff = 0;
    while (true) {
      b.send({
        'type': 'file_download_request',
        'msgId': 'dl$n',
        'fileId': fid1,
        'offset': doff,
      });
      final ch = await b.nextWhere(
        (m) =>
            m['type'] == 'file_download_chunk' &&
            (m['offset'] as num).toInt() == doff,
        what: 'download chunk @$doff',
      );
      final bytes =
          base64.decode((ch['dataBase64'] as String?) ?? '');
      got.addAll(bytes);
      doff += bytes.length;
      if (ch['isLast'] == true) break;
      n++;
      if (n > 20) throw StateError('download loop');
    }
    check(listEq(got, expect), '下载字节与上传一致 (${got.length}B)');

    // ---- 8. 断点续传：传一半断线，重连后继续
    const fid2 = 'e2eFileResume01';
    final payload2 =
        List<int>.generate(200 * 1024, (_) => rnd.nextInt(256));
    a.send({
      'type': 'file_announce',
      'msgId': 'm3',
      'fileId': fid2,
      'name': 'resume.bin',
      'size': payload2.length,
    });
    await a.nextWhere((m) => m['type'] == 'file_announced');
    a.send({
      'type': 'file_chunk',
      'msgId': 'm3c0',
      'fileId': fid2,
      'offset': 0,
      'dataBase64': base64.encode(payload2.sublist(0, 128 * 1024)),
      'isLast': false,
    });
    final ack1 = await a.nextWhere(
        (m) => m['type'] == 'file_chunk_ack' && m['refMsgId'] == 'm3c0');
    check((ack1['uploadedBytes'] as num).toInt() == 128 * 1024,
        '第一块落盘 128KB');
    await a.close(); // 模拟掉线

    final a2 = await TClient.connect();
    await a2.hello(
        space: space, key: key, deviceId: 'devA', name: 'A');
    await a2.nextWhere((m) => m['type'] == 'welcome');
    a2.send({
      'type': 'file_announce',
      'msgId': 'm4',
      'fileId': fid2,
      'name': 'resume.bin',
      'size': payload2.length,
    });
    final ann2 = await a2.nextWhere((m) => m['type'] == 'file_announced');
    check(
      ann2['resumed'] == true &&
          (ann2['file'] as Map)['uploadedBytes'] == 128 * 1024,
      '重连后续传（resumed + 偏移对）',
    );
    a2.send({
      'type': 'file_chunk',
      'msgId': 'm4c1',
      'fileId': fid2,
      'offset': 128 * 1024,
      'dataBase64': base64.encode(payload2.sublist(128 * 1024)),
      'isLast': true,
    });
    final ack2 = await a2.nextWhere(
        (m) => m['type'] == 'file_chunk_ack' && m['refMsgId'] == 'm4c1');
    check(
      ack2['complete'] == true &&
          (ack2['uploadedBytes'] as num).toInt() == payload2.length,
      '续传完成',
    );

    // ---- 9. 错位块被纠正
    const fid3 = 'e2eFileMismatch1';
    a2.send({
      'type': 'file_announce',
      'msgId': 'm5',
      'fileId': fid3,
      'name': 'mm.bin',
      'size': 50000,
    });
    await a2.nextWhere((m) => m['type'] == 'file_announced');
    a2.send({
      'type': 'file_chunk',
      'msgId': 'm5cBad',
      'fileId': fid3,
      'offset': 999,
      'dataBase64': base64.encode(List.filled(100, 7)),
      'isLast': false,
    });
    final mmAck = await a2.nextWhere(
        (m) => m['type'] == 'file_chunk_ack' && m['refMsgId'] == 'm5cBad');
    check(
      mmAck['mismatch'] == true &&
          (mmAck['uploadedBytes'] as num).toInt() == 0,
      '错位写入被拒绝并纠正偏移',
    );
    final payload3 = List<int>.generate(50000, (_) => rnd.nextInt(256));
    a2.send({
      'type': 'file_chunk',
      'msgId': 'm5c0',
      'fileId': fid3,
      'offset': 0,
      'dataBase64': base64.encode(payload3),
      'isLast': true,
    });
    final mmAck2 = await a2.nextWhere(
        (m) => m['type'] == 'file_chunk_ack' && m['refMsgId'] == 'm5c0');
    check(mmAck2['complete'] == true, '纠正后上传成功');

    // ---- 10. B 删除文件
    b.send({'type': 'file_delete', 'msgId': 'm6', 'fileId': fid1});
    final del = await b.nextWhere((m) =>
        m['type'] == 'file_deleted' && m['fileId'] == fid1);
    check(del['refMsgId'] == 'm6', '删除回执配对 msgId');
    final flAfter = await a2.nextWhere(
      (m) =>
          m['type'] == 'file_list' &&
          (m['files'] as List).every((f) => f is Map && f['id'] != fid1),
      what: 'file_list without deleted',
    );
    check(
        (flAfter['files'] as List).every((f) => f['id'] != fid1),
        '删除后列表同步');

    await d.close();
    await b.close();
    await a2.close();
  } catch (e, st) {
    _failures++;
      print('  FAIL exception: $e\n$st');
  }

  // ---- 11. 重启恢复：KEEP 文件重启后仍在且可下载
  await stopServer(srv);
  print('--- restart server, verify persistence ---');
  srv = await startServer(dataDir);
  if (!await waitHealthy()) {
    check(false, 'server restarted');
  } else {
    try {
      final e = await TClient.connect();
      await e.hello(
          space: 'e2e-space1', key: 'pw123', deviceId: 'devE', name: 'E');
      await e.nextWhere((m) => m['type'] == 'welcome');
      final fl = await e.nextWhere((m) => m['type'] == 'file_list');
      final files = fl['files'] as List;
      final hasResume = files.any(
          (f) => f is Map && f['id'] == 'e2eFileResume01' && f['complete'] == true);
      final hasMm = files.any((f) =>
          f is Map && f['id'] == 'e2eFileMismatch1' && f['complete'] == true);
      check(hasResume && hasMm, '重启后文件元数据恢复');
      final hist = await e.nextWhere(
          (m) => m['type'] == 'clipboard_history');
      final items = hist['items'] as List;
      check(
        items.isNotEmpty &&
            (items.first as Map)['text'] == 'hello from A 你好 123',
        '重启后剪切板历史恢复',
      );
      await e.close();
    } catch (err) {
      check(false, 'restart checks', '$err');
    }
  }

  await stopServer(srv);
  try {
    await dataDir.delete(recursive: true);
  } catch (_) {}

  print(_failures == 0 ? 'ALL PASS' : 'FAILURES: $_failures');
  exit(_failures == 0 ? 0 : 1);
}
