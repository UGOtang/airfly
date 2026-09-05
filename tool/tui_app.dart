// AirFly TUI：状态 + 渲染 + 键鼠分发 + 动作（纯 Dart，无 Flutter 依赖）。
// 渲染是纯函数 render(w,h) → FrameResult，可 headless 单测对齐与越界。
// 网络/磁盘动作是 async 方法，测试只调纯逻辑部分。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'relay_client.dart';
import 'tui_term.dart';

// ---------------------------------------------------------------- 主题

class TuiTheme {
  final int border;
  final int borderFocus;
  final int title;
  final int titleFocus;
  final int text;
  final int dim;
  final int accent;
  final int good;
  final int warn;
  final int bad;
  final int barFill;
  final int barTrack;

  const TuiTheme({
    this.border = 240,
    this.borderFocus = 51,
    this.title = 245,
    this.titleFocus = 51,
    this.text = 252,
    this.dim = 245,
    this.accent = 51,
    this.good = 42,
    this.warn = 220,
    this.bad = 203,
    this.barFill = 42,
    this.barTrack = 236,
  });
}

// ---------------------------------------------------------------- 状态

enum TuiPanel { devices, files, clips }

class InputReq {
  final String title;
  final List<int> runes;
  int cursor;
  final int maxRunes;
  final void Function(String) submit;
  InputReq({
    required this.title,
    String initial = '',
    this.maxRunes = 20000,
    required this.submit,
  })  : runes = initial.runes.toList(),
        cursor = initial.runes.length;
}

class ConfirmReq {
  final String text;
  final void Function(bool) submit;
  ConfirmReq({required this.text, required this.submit});
}

class ClickRegion {
  final String id;
  final int x, y, w, h;
  const ClickRegion(this.id, this.x, this.y, this.w, this.h);
  bool hit(int px, int py) =>
      px >= x && px < x + w && py >= y && py < y + h;
}

class FrameResult {
  final String text;
  final List<ClickRegion> clicks;
  const FrameResult(this.text, this.clicks);
}

class TuiState {
  TuiPanel focus = TuiPanel.files;
  int devSel = 0, fileSel = 0, clipSel = 0;
  int devScroll = 0, fileScroll = 0, clipScroll = 0;
  bool helpOpen = false;
  InputReq? input;
  ConfirmReq? confirm;
  String logMsg = '就绪';
  bool logErr = false;
  final Map<String, double> upProgress = {};
  final Map<String, double> dlProgress = {};
  final Map<String, bool> cancelFlags = {};

  void log(String msg, {bool err = false}) {
    logMsg = msg;
    logErr = err;
  }
}

// ---------------------------------------------------------------- App

class TuiApp {
  final RelayClient client;
  final TuiState state = TuiState();
  final InputParser parser = InputParser();
  final TuiTheme theme = const TuiTheme();

  /// 返回 true 表示请求退出主循环。
  bool wantQuit = false;

  TuiApp(this.client) {
    client.onEvent = () {};
  }

  // ---------------- 纯逻辑（可测）

  void moveSel(int delta) {
    final s = state;
    switch (s.focus) {
      case TuiPanel.devices:
        s.devSel = (s.devSel + delta)
            .clamp(0, max(0, client.devices.length - 1));
        break;
      case TuiPanel.files:
        s.fileSel =
            (s.fileSel + delta).clamp(0, max(0, client.files.length - 1));
        break;
      case TuiPanel.clips:
        s.clipSel = (s.clipSel + delta)
            .clamp(0, max(0, client.clipHistory.length - 1));
        break;
    }
  }

  void gotoEdge(bool toStart) {
    final s = state;
    int last(int len) => toStart ? 0 : max(0, len - 1);
    switch (s.focus) {
      case TuiPanel.devices:
        s.devSel = last(client.devices.length);
        break;
      case TuiPanel.files:
        s.fileSel = last(client.files.length);
        break;
      case TuiPanel.clips:
        s.clipSel = last(client.clipHistory.length);
        break;
    }
  }

  void cycleFocus(int dir) {
    final order = TuiPanel.values;
    final i = order.indexOf(state.focus);
    state.focus = order[(i + dir + order.length) % order.length];
  }

  void _clampSelections() {
    final s = state;
    s.devSel = s.devSel.clamp(0, max(0, client.devices.length - 1));
    s.fileSel = s.fileSel.clamp(0, max(0, client.files.length - 1));
    s.clipSel = s.clipSel.clamp(0, max(0, client.clipHistory.length - 1));
    s.devScroll = max(0, s.devScroll);
    s.fileScroll = max(0, s.fileScroll);
    s.clipScroll = max(0, s.clipScroll);
  }

  // ---------------- 按键分发（同步部分；动作 async 另起）

  /// 返回 true 表示消费了该键（调用方决定是否重绘——这里总是重绘）。
  void handleKey(TuiKey k) {
    final s = state;
    if (s.helpOpen) {
      s.helpOpen = false;
      return;
    }
    final input = s.input;
    if (input != null) {
      _handleInputKey(input, k);
      return;
    }
    final confirm = s.confirm;
    if (confirm != null) {
      if (k.kind == TuiKeyKind.esc ||
          (k.kind == TuiKeyKind.printable &&
              (k.text == 'n' || k.text == 'N'))) {
        s.confirm = null;
        confirm.submit(false);
      } else if (k.kind == TuiKeyKind.enter ||
          (k.kind == TuiKeyKind.printable &&
              (k.text == 'y' || k.text == 'Y'))) {
        s.confirm = null;
        confirm.submit(true);
      }
      return;
    }
    switch (k.kind) {
      case TuiKeyKind.ctrlC:
        wantQuit = true;
        break;
      case TuiKeyKind.up:
        moveSel(-1);
        break;
      case TuiKeyKind.down:
        moveSel(1);
        break;
      case TuiKeyKind.pgup:
        moveSel(-10);
        break;
      case TuiKeyKind.pgdn:
        moveSel(10);
        break;
      case TuiKeyKind.home:
        gotoEdge(true);
        break;
      case TuiKeyKind.end:
        gotoEdge(false);
        break;
      case TuiKeyKind.tab:
        cycleFocus(1);
        break;
      case TuiKeyKind.backtab:
        cycleFocus(-1);
        break;
      case TuiKeyKind.enter:
        _activate();
        break;
      case TuiKeyKind.printable:
        _handlePrintable(k.text);
        break;
      default:
        break;
    }
  }

  void _handlePrintable(String t) {
    switch (t) {
      case 'q':
      case 'Q':
        wantQuit = true;
        break;
      case 'j':
        moveSel(1);
        break;
      case 'k':
        moveSel(-1);
        break;
      case 'p':
      case 'P':
        _askPushClip();
        break;
      case 'u':
      case 'U':
        _askUpload();
        break;
      case 'd':
      case 'D':
        _activate();
        break;
      case 'x':
      case 'X':
        _askDelete();
        break;
      case 'c':
      case 'C':
        _cancelActive();
        break;
      case 'v':
      case 'V':
        _copyClip();
        break;
      case 'r':
      case 'R':
        _refresh();
        break;
      case '?':
        state.helpOpen = true;
        break;
      default:
        break;
    }
  }

  void _handleInputKey(InputReq input, TuiKey k) {
    final s = state;
    switch (k.kind) {
      case TuiKeyKind.esc:
      case TuiKeyKind.ctrlC:
        s.input = null;
        s.log('已取消');
        break;
      case TuiKeyKind.enter:
        final text = String.fromCharCodes(input.runes).replaceAll('\n', ' ');
        s.input = null;
        input.submit(text);
        break;
      case TuiKeyKind.backspace:
        if (input.cursor > 0) {
          input.cursor--;
          input.runes.removeAt(input.cursor);
        }
        break;
      case TuiKeyKind.left:
        if (input.cursor > 0) input.cursor--;
        break;
      case TuiKeyKind.right:
        if (input.cursor < input.runes.length) input.cursor++;
        break;
      case TuiKeyKind.home:
        input.cursor = 0;
        break;
      case TuiKeyKind.end:
        input.cursor = input.runes.length;
        break;
      case TuiKeyKind.printable:
        if (input.runes.length < input.maxRunes) {
          input.runes.insertAll(input.cursor, k.text.runes);
          input.cursor += k.text.runes.length;
        }
        break;
      default:
        break;
    }
  }

  // ---------------- 鼠标分发

  void handleMouse(TuiMouse m, List<ClickRegion> regions) {
    final s = state;
    if (s.helpOpen) {
      // 帮助是模态的：任意点击先关帮助
      if (!m.release) s.helpOpen = false;
      return;
    }
    if (s.input != null || s.confirm != null) return;
    if (m.button == 64 || m.button == 65) {
      // 滚轮：只滚当前焦点面板
      moveSel(m.button == 64 ? -3 : 3);
      return;
    }
    if (m.button != 0 || m.release) return;
    for (final r in regions) {
      if (!r.hit(m.x, m.y)) continue;
      _activateRegion(r.id);
      return;
    }
  }

  void _activateRegion(String id) {
    final s = state;
    if (id == 'quit') {
      wantQuit = true;
      return;
    }
    if (id == 'refresh') {
      _refresh();
      return;
    }
    if (id == 'upload') {
      s.focus = TuiPanel.files;
      _askUpload();
      return;
    }
    if (id == 'push') {
      _askPushClip();
      return;
    }
    if (id == 'help') {
      s.helpOpen = true;
      return;
    }
    final parts = id.split(':');
    if (parts.length != 2) return;
    if (parts[0] == 'panel') {
      // 点标题栏/边框 = 只聚焦不动作
      switch (parts[1]) {
        case 'dev':
          s.focus = TuiPanel.devices;
          break;
        case 'file':
          s.focus = TuiPanel.files;
          break;
        case 'clip':
          s.focus = TuiPanel.clips;
          break;
      }
      return;
    }
    final idx = int.tryParse(parts[1]) ?? -1;
    if (idx < 0) return;
    switch (parts[0]) {
      case 'dev':
        s.focus = TuiPanel.devices;
        s.devSel = idx;
        break;
      case 'file':
        s.focus = TuiPanel.files;
        s.fileSel = idx;
        _activate(); // 点文件行 = 直接下载（若已完成）
        break;
      case 'clip':
        s.focus = TuiPanel.clips;
        s.clipSel = idx;
        break;
    }
  }

  // ---------------- 动作入口（同步改状态 + 起 async 任务）

  void _activate() {
    final s = state;
    if (s.focus == TuiPanel.files) {
      if (s.fileSel < client.files.length) {
        startDownload(client.files[s.fileSel]);
      }
    } else if (s.focus == TuiPanel.clips) {
      _copyClip();
    }
  }

  void _askPushClip() {
    final s = state;
    s.input = InputReq(
      title: '推送剪切板（单行，Enter 发送，Esc 取消）',
      submit: (text) => _doPushClip(text),
    );
  }

  void _askUpload() {
    final s = state;
    s.input = InputReq(
      title: '上传文件：输入本地路径（Enter 开始，Esc 取消）',
      submit: (path) {
        if (path.trim().isEmpty) {
          s.log('路径为空，已取消');
          return;
        }
        startUpload(path.trim());
      },
    );
  }

  void _askDelete() {
    final s = state;
    if (s.focus != TuiPanel.files || s.fileSel >= client.files.length) return;
    final f = client.files[s.fileSel];
    s.confirm = ConfirmReq(
      text: '删除云端文件「${ellipsis(f.name, 30)}」？ [y/n]',
      submit: (yes) {
        if (!yes) {
          s.log('已取消删除');
          return;
        }
        _doDelete(f.id, f.name);
      },
    );
  }

  void _cancelActive() {
    final s = state;
    var n = 0;
    for (final k in [...s.cancelFlags.keys]) {
      s.cancelFlags[k] = true;
      n++;
    }
    s.log(n == 0 ? '没有进行中的传输' : '已请求取消 $n 个传输');
  }

  void _copyClip() {
    final s = state;
    if (s.clipSel >= client.clipHistory.length) return;
    final text = client.clipHistory[s.clipSel].text;
    _doCopy(text);
  }

  void _refresh() {
    try {
      client.refresh();
      state.log('已请求刷新');
    } catch (e) {
      state.log('刷新失败：$e', err: true);
    }
  }

  // ---------------- async 任务（UI 线程外跑，靠回调改状态）

  Future<void> _doPushClip(String text) async {
    final s = state;
    if (text.trim().isEmpty) {
      s.log('内容为空，未发送');
      return;
    }
    try {
      await client.pushClip(text);
      s.log('剪切板已同步');
    } catch (e) {
      s.log('同步失败：$e', err: true);
    }
  }

  Future<void> _doDelete(String fileId, String name) async {
    final s = state;
    try {
      await client.deleteFile(fileId);
      s.log('已删除 $name');
    } catch (e) {
      s.log('删除失败：$e', err: true);
    }
  }

  Future<void> _doCopy(String text) async {
    final s = state;
    try {
      final ok = await copyToSystemClipboard(text);
      s.log(ok ? '已复制到系统剪切板' : '系统剪切板不可用（缺 xclip/clip 工具）',
          err: !ok);
    } catch (e) {
      s.log('复制失败：$e', err: true);
    }
  }

  Future<void> startUpload(String path) async {
    final s = state;
    File file;
    int size;
    try {
      file = File(path);
      if (!await file.exists()) {
        s.log('文件不存在：$path', err: true);
        return;
      }
      size = await file.length();
    } catch (e) {
      s.log('读取文件失败：$e', err: true);
      return;
    }
    if (size <= 0) {
      s.log('空文件，跳过', err: true);
      return;
    }
    if (size > client.maxFileBytes) {
      s.log('超出服务端单文件上限', err: true);
      return;
    }
    final name = _basename(path);
    final fileId = _newFileId();
    final token = 'up:$fileId';
    s.cancelFlags[token] = false;
    try {
      final meta = await client.announceFile(
          fileId: fileId, fileName: name, fileSize: size);
      var offset = meta.uploadedBytes.clamp(0, size);
      s.upProgress[fileId] = size == 0 ? 1 : offset / size;
      final raf = await file.open(mode: FileMode.read);
      try {
        while (offset < size) {
          if (s.cancelFlags[token] == true) {
            s.log('上传已取消：$name');
            return;
          }
          if (!client.connected) throw RetryableError('连接断开，已中断（重传可续）');
          final len = min(RelayClient.kChunkSize, size - offset);
          await raf.setPosition(offset);
          final bytes = await raf.read(len);
          if (bytes.isEmpty) throw RetryableError('读取本地文件失败');
          final isLast = offset + bytes.length >= size;
          final (up, complete, mismatch) = await client.uploadChunk(
            fileId: fileId,
            offset: offset,
            bytes: bytes,
            isLast: isLast,
          );
          if (up < 0) throw StateError('意外的服务端响应');
          // 无论是否 mismatch，一律以服务端回的偏移为准继续
          offset = up.clamp(0, size);
          s.upProgress[fileId] = offset / size;
          if (complete) break;
        }
      } finally {
        try {
          await raf.close();
        } catch (_) {}
      }
      s.log('上传完成：$name');
      try {
        await client.refresh();
      } catch (_) {}
    } on RetryableError catch (e) {
      s.log('上传中断：${e.message}', err: true);
    } catch (e) {
      s.log('上传失败：$e', err: true);
    } finally {
      s.upProgress.remove(fileId);
      s.cancelFlags.remove(token);
    }
  }

  Future<void> startDownload(RelayFile f) async {
    final s = state;
    if (!f.complete) {
      s.log('文件还在上传中，稍后再试', err: true);
      return;
    }
    if (!client.connected) {
      s.log('未连接', err: true);
      return;
    }
    final token = 'dl:${f.id}';
    if (s.cancelFlags.containsKey(token)) {
      s.log('该文件正在下载中');
      return;
    }
    s.cancelFlags[token] = false;
    try {
      final dir = Directory('airfly-downloads');
      await dir.create(recursive: true);
      final target = await _uniqueFile(dir.path, f.name);
      final raf = await target.open(mode: FileMode.write);
      var offset = 0;
      try {
        while (true) {
          if (s.cancelFlags[token] == true) {
            s.log('下载已取消：${f.name}');
            try {
              await raf.close();
            } catch (_) {}
            try {
              await target.delete();
            } catch (_) {}
            return;
          }
          final (at, bytes, isLast) =
              await client.downloadChunk(fileId: f.id, offset: offset);
          if (at != offset) throw RetryableError('偏移不一致，请重试');
          if (bytes.isNotEmpty) await raf.writeFrom(bytes);
          offset += bytes.length;
          if (offset > f.size) throw RetryableError('大小不一致，请重试');
          s.dlProgress[f.id] = f.size == 0 ? 1 : offset / f.size;
          if (isLast) break;
        }
      } finally {
        try {
          await raf.close();
        } catch (_) {}
      }
      s.log('已保存：${target.path}');
    } on RetryableError catch (e) {
      s.log('下载中断：${e.message}', err: true);
    } catch (e) {
      s.log('下载失败：$e', err: true);
    } finally {
      s.dlProgress.remove(f.id);
      s.cancelFlags.remove(token);
    }
  }

  // ---------------- 渲染（纯函数，headless 可测）

  FrameResult render(int w, int h) {
    _clampSelections();
    if (w < 50 || h < 12) {
      return FrameResult(
          '\x1B[2J\x1B[H窗口太小（至少 50x12，当前 ${w}x$h），请放大终端。\n', const []);
    }
    final clicks = <ClickRegion>[];
    final b = StringBuffer();
    b.write('\x1B[2J\x1B[H'); // 清屏回家（重绘整帧，简单无闪烁）
    b.writeln(_header(w));
    // 布局：上半 设备|文件，下半 剪切板，底栏 3 行
    final bottomH = (h * 0.34).round().clamp(6, h - 8);
    final footerH = 3;
    final topH = h - 1 - bottomH - footerH;
    final leftW = (w * 0.32).round().clamp(20, w - 30);
    final rightW = w - leftW;
    var y = 1; // 0 行是 header
    final devBox = _panelBox(
      title: '设备',
      focused: state.focus == TuiPanel.devices,
      w: leftW,
      h: topH,
      rows: _deviceRows(leftW - 4),
      sel: state.devSel,
      scroll: state.devScroll,
      idPrefix: 'dev',
      clicks: clicks,
      ox: 0,
      oy: y,
    );
    final fileBox = _panelBox(
      title: '文件',
      focused: state.focus == TuiPanel.files,
      w: rightW,
      h: topH,
      rows: _fileRows(rightW - 4),
      sel: state.fileSel,
      scroll: state.fileScroll,
      idPrefix: 'file',
      clicks: clicks,
      ox: leftW,
      oy: y,
    );
    for (var i = 0; i < topH; i++) {
      b.write(devBox[i]);
      b.write(fileBox[i]);
      b.writeln();
      y++;
    }
    final clipBox = _panelBox(
      title: '剪切板',
      focused: state.focus == TuiPanel.clips,
      w: w,
      h: bottomH,
      rows: _clipRows(w - 4),
      sel: state.clipSel,
      scroll: state.clipScroll,
      idPrefix: 'clip',
      clicks: clicks,
      ox: 0,
      oy: y,
    );
    for (final line in clipBox) {
      b.writeln(line);
      y++;
    }
    b.write(_footer(w, footerH, clicks, y));
    var text = b.toString();
    if (state.helpOpen) text += _helpOverlay(w, h);
    if (state.input != null) {
      // 输入条画在底栏上（覆盖 hints 行）
    }
    if (state.confirm != null) text += _confirmOverlay(w, h);
    return FrameResult(text, clicks);
  }

  String _header(int w) {
    final c = client;
    final ok = c.connected;
    final dot =
        ok ? '${Ansi.fg(theme.good)}●${Ansi.reset}' : '${Ansi.fg(theme.bad)}◌${Ansi.reset}';
    final left =
        ' ${Ansi.bold}AirFly TUI${Ansi.reset} ${Ansi.fg(theme.dim)}${ellipsis(c.spaceId, 20)} $dot${ok ? '已连接' : '未连接'}${Ansi.reset}';
    final right =
        '${Ansi.fg(theme.dim)}${c.devices.length}设备 ${c.files.length}文件 ${_clock()}${Ansi.reset} ';
    final lw = cellWidth(stripAnsi(left));
    final rw = cellWidth(stripAnsi(right));
    final mid = max(0, w - lw - rw);
    return left + ' ' * mid + right;
  }

  String _clock() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(n.hour)}:${p(n.minute)}:${p(n.second)}';
  }

  List<String> _deviceRows(int innerW) {
    final out = <String>[];
    for (final d in client.devices) {
      final mine = d.id == client.deviceId;
      out.add(
          '${mine ? Ansi.fg(theme.accent) : Ansi.fg(theme.good)}●${Ansi.reset} '
          '${ellipsis(d.name, innerW - 12)}${mine ? ' (本机)' : ''}');
    }
    if (out.isEmpty) out.add('${Ansi.fg(theme.dim)}（暂无在线设备）${Ansi.reset}');
    return out;
  }

  List<String> _fileRows(int innerW) {
    final out = <String>[];
    for (final f in client.files) {
      final up = state.upProgress[f.id];
      final dl = state.dlProgress[f.id];
      final String bar;
      final String tag;
      if (up != null) {
        bar = _bar(up, 10);
        tag = '↑${(up * 100).round()}%';
      } else if (dl != null) {
        bar = _bar(dl, 10);
        tag = '↓${(dl * 100).round()}%';
      } else if (!f.complete) {
        bar = _bar(f.progress, 10);
        tag = '…${(f.progress * 100).round()}%';
      } else {
        bar = '';
        tag = formatSize(f.size);
      }
      final nameW = max(4, innerW - cellWidth(tag) - (bar.isEmpty ? 1 : 13));
      out.add('${ellipsis(f.name, nameW)}${bar.isEmpty ? ' ' : ' $bar '}$tag');
    }
    if (out.isEmpty) out.add('${Ansi.fg(theme.dim)}（云端暂无文件，按 u 上传）${Ansi.reset}');
    return out;
  }

  String _bar(double p, int w) =>
      '${Ansi.fg(theme.barFill)}${progressBar(p, w)}${Ansi.reset}';

  List<String> _clipRows(int innerW) {
    final out = <String>[];
    for (final c in client.clipHistory) {
      final preview = c.text.replaceAll('\n', ' ');
      out.add(
          '${Ansi.fg(theme.dim)}${ellipsis(c.deviceName, 10)} ${ago(c.updatedAt)}${Ansi.reset} '
          '${ellipsis(preview, max(4, innerW - 16))}');
    }
    if (out.isEmpty) out.add('${Ansi.fg(theme.dim)}（暂无同步记录，按 p 推送）${Ansi.reset}');
    return out;
  }

  /// 通用面板盒：返回 h 行、每行宽 w（含点击区注册）。
  List<String> _panelBox({
    required String title,
    required bool focused,
    required int w,
    required int h,
    required List<String> rows,
    required int sel,
    required int scroll,
    required String idPrefix,
    required List<ClickRegion> clicks,
    required int ox,
    required int oy,
  }) {
    final out = <String>[];
    final bc = focused ? theme.borderFocus : theme.border;
    final tc = focused ? theme.titleFocus : theme.title;
    final top =
        '${Ansi.fg(bc)}┌─${Ansi.reset}${Ansi.bold}${Ansi.fg(tc)} $title ${Ansi.reset}${Ansi.fg(bc)}${'─' * max(0, w - cellWidth(title) - 5)}┐${Ansi.reset}';
    out.add(top);
    clicks.add(ClickRegion('panel:$idPrefix', ox, oy, w, 1));
    final innerH = max(1, h - 2);
    var start = scroll;
    final maxStart = max(0, rows.length - innerH);
    if (start > maxStart) start = maxStart;
    // 选中行始终可见
    if (sel < start) start = sel;
    if (sel >= start + innerH) start = sel - innerH + 1;
    // 写回（渲染即对齐，简单可靠）
    _writeBackScroll(idPrefix, start);
    for (var i = 0; i < innerH; i++) {
      final ri = start + i;
      final isSel = ri == sel && ri < rows.length;
      final raw = ri < rows.length ? rows[ri] : '';
      final line = _fitLine(raw, w - 4);
      final body = isSel ? '${Ansi.reverse}$line${Ansi.reset}' : line;
      out.add('${Ansi.fg(bc)}│${Ansi.reset} $body ${Ansi.fg(bc)}│${Ansi.reset}');
      if (ri < rows.length) {
        clicks.add(ClickRegion('$idPrefix:$ri', ox, oy + 1 + i, w, 1));
      }
    }
    out.add(
        '${Ansi.fg(bc)}└${'─' * max(0, w - 2)}┘${Ansi.reset}');
    return out;
  }

  void _writeBackScroll(String prefix, int start) {
    switch (prefix) {
      case 'dev':
        state.devScroll = start;
        break;
      case 'file':
        state.fileScroll = start;
        break;
      case 'clip':
        state.clipScroll = start;
        break;
    }
  }

  /// 把一行内容处理成正好 width 列：颜色码不占列，空格补在尾部 reset 之前。
  /// 只保证不超宽（测试断言 ≤w），截断时可能丢失行中颜色（罕见，可接受）。
  String _fitLine(String raw, int width) {
    final plain = stripAnsi(raw);
    final pw = cellWidth(plain);
    if (pw >= width) {
      final cut = ellipsis(plain, width);
      final m = RegExp(r'^((?:\x1B\[[0-9;]*m)+)').firstMatch(raw);
      if (m != null) return '${m.group(1)}$cut${Ansi.reset}';
      return cut;
    }
    final pad = ' ' * (width - pw);
    if (raw.endsWith(Ansi.reset)) {
      return '${raw.substring(0, raw.length - Ansi.reset.length)}$pad${Ansi.reset}';
    }
    return '$raw$pad';
  }

  String _footer(int w, int h, List<ClickRegion> clicks, int y) {
    final b = StringBuffer();
    final logColor = state.logErr ? theme.bad : theme.dim;
    final logLine = padCells(ellipsis(state.logMsg, w), w);
    b.writeln('${Ansi.fg(logColor)}$logLine${Ansi.reset}');
    y++;
    if (state.input != null) {
      b.write(_fitLine(_inputBar(w), w));
    } else {
      const hints =
          'Tab切换 q退出 ↑↓/jk选择 Enter动作 p推送 u上传 d下载 x删除 c取消传输 v复制 r刷新 ?帮助';
      const btnDefs = [
        ('upload', '上传'),
        ('push', '推送'),
        ('refresh', '刷新'),
        ('quit', '退出'),
      ];
      final btnText = btnDefs.map((e) => '[${e.$2}]').join(' ');
      final hintsW = max(0, w - cellWidth(btnText) - 1);
      final left = padCells(ellipsis(hints, hintsW), hintsW);
      b.write('$left ${Ansi.fg(theme.accent)}$btnText${Ansi.reset}');
      var bx = hintsW + 1;
      for (final def in btnDefs) {
        // '[xx]' 占 6 列（中文 2 列×2 + 括号），+1 空格步进
        clicks.add(ClickRegion(def.$1, bx, y, 6, 1));
        bx += 7;
      }
    }
    return b.toString();
  }

  String _inputBar(int w) {
    final input = state.input!;
    final label = '${input.title}：';
    final labelW = cellWidth(label);
    final fieldW = max(4, w - labelW - 1);
    // 光标前后按列宽切出可见窗口
    final before = String.fromCharCodes(
        input.runes.sublist(0, input.cursor.clamp(0, input.runes.length)));
    final after = String.fromCharCodes(
        input.runes.sublist(input.cursor.clamp(0, input.runes.length)));
    var visible = before + after;
    if (cellWidth(visible) > fieldW) {
      // 保留光标可见：从光标处往左截
      final all = input.runes;
      var start = input.cursor;
      var ww = 0;
      while (start > 0) {
        final cw = cellWidthOf(all[start - 1]);
        if (ww + cw > fieldW - 2) break;
        ww += cw;
        start--;
      }
      visible =
          '…${String.fromCharCodes(all.sublist(start, input.cursor))}$after';
      if (cellWidth(visible) > fieldW) {
        visible = ellipsis(visible, fieldW);
      }
      return '$label$visible';
    }
    // 光标块：反白光标处字符（末尾则反白空格）
    final cursorChar =
        input.cursor < input.runes.length
            ? String.fromCharCodes([input.runes[input.cursor]])
            : ' ';
    final cursorW = cellWidth(cursorChar);
    final tail = input.cursor < input.runes.length
        ? String.fromCharCodes(
            input.runes.sublist(input.cursor + 1))
        : '';
    final shown =
        '$before${Ansi.reverse}$cursorChar${Ansi.reset}$tail';
    final pad = max(0, fieldW - cellWidth(before) - cursorW - cellWidth(tail));
    return '$label$shown${' ' * pad}';
  }

  String _helpOverlay(int w, int h) {
    final rows = [
      'AirFly TUI 帮助',
      '',
      'Tab / Shift-Tab      切换面板（鼠标点面板也行）',
      '↑↓ jk PgUp/PgDn      移动选择（滚轮也行）',
      'Enter                文件下载 / 剪切板复制',
      'p                    推送剪切板（输入条）',
      'u                    上传文件（输入本地路径）',
      'd                    下载选中文件到 airfly-downloads/',
      'x                    删除选中云端文件（需确认）',
      'c                    取消进行中的传输',
      'v                    复制选中剪切板到系统剪切板',
      'r                    刷新列表',
      'q / Ctrl+C           退出（鼠标点右下 [退出] 也行）',
      '',
      '任意键关闭本帮助',
    ];
    return _centerBox(w, h, rows, width: min(58, w - 4));
  }

  String _confirmOverlay(int w, int h) {
    final c = state.confirm!;
    return _centerBox(w, h, [c.text, '', '[y] 确认   [n] 取消'],
        width: min(52, w - 4));
  }

  String _centerBox(int sw, int sh, List<String> rows,
      {required int width}) {
    final bw = width;
    final b = StringBuffer();
    final bh = rows.length + 2;
    final bx = max(0, (sw - bw) ~/ 2);
    final by = max(0, (sh - bh) ~/ 2);
    // 把游标搬到盒子位置逐行画（覆盖在帧末尾）
    for (var i = 0; i < rows.length + 2; i++) {
      final isEdge = i == 0 || i == rows.length + 1;
      final content = isEdge ? '' : rows[i - 1];
      final line = isEdge ? '─' * (bw - 2) : ' ${padCells(ellipsis(content, bw - 4), bw - 4)} ';
      b.write('\x1B[${by + i + 1};${bx + 1}H');
      b.write(
          '${Ansi.bg(236)}${Ansi.fg(theme.accent)}${isEdge ? (i == 0 ? '┌$line┐' : '└$line┘') : '│$line│'}${Ansi.reset}');
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------- 小件（可测）

String _basename(String path) {
  var name = path.replaceAll('\\', '/');
  if (name.contains('/')) name = name.split('/').last;
  return name.isEmpty ? 'unnamed' : name;
}

String _newFileId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random();
  return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}

Future<File> _uniqueFile(String dir, String name) async {
  var target = File('$dir${Platform.pathSeparator}$name');
  var n = 1;
  while (await target.exists()) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    target = File('$dir${Platform.pathSeparator}$stem($n)$ext');
    n++;
    if (n > 9999) break;
  }
  return target;
}

/// 复制文本到系统剪切板（尽力而为，返回是否成功）。
Future<bool> copyToSystemClipboard(String text) async {
  try {
    Process proc;
    if (Platform.isWindows) {
      proc = await Process.start('clip', [], runInShell: false);
    } else if (Platform.isMacOS) {
      proc = await Process.start('pbcopy', [], runInShell: false);
    } else if (Platform.isLinux) {
      try {
        proc = await Process.start(
            'xclip', ['-selection', 'clipboard'], runInShell: false);
      } catch (_) {
        proc = await Process.start('xsel', ['--clipboard', '--input'],
            runInShell: false);
      }
    } else {
      return false;
    }
    try {
      proc.stdin.encoding = systemEncoding;
    } catch (_) {}
    proc.stdin.write(text);
    await proc.stdin.close();
    final code = await proc.exitCode.timeout(const Duration(seconds: 5));
    return code == 0;
  } catch (_) {
    return false;
  }
}
