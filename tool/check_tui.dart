// TUI headless 检查：伪造数据跑 render/分发/输入条/确认框，断言
// 对齐不变式（每行列宽 ≤w）、区域越界、键鼠行为。
// 用法：dart tool/check_tui.dart   退出码 0 = 全过。
// ignore_for_file: avoid_print

import 'relay_client.dart';
import 'tui_app.dart';
import 'tui_term.dart';

int _failures = 0;

void check(bool cond, String name, [String extra = '']) {
  if (cond) {
    print('  ok   $name');
  } else {
    _failures++;
    print('  FAIL $name${extra.isEmpty ? '' : ' -- $extra'}');
  }
}

RelayClient _dummy() => RelayClient(
      serverUrl: 'ws://127.0.0.1:1/ws',
      spaceId: 'test-space',
      deviceId: 'devT',
      deviceName: 'TUI-TEST',
    );

void _fabricate(RelayClient c) {
  c.devices = [
    RelayDevice(
        id: 'devT',
        name: '本机测试终端',
        platform: 'tui',
        connectedAt: DateTime.now()),
    RelayDevice(
        id: 'devM',
        name: 'Pixel手机',
        platform: 'android',
        connectedAt: DateTime.now()),
  ];
  c.files = [
    RelayFile(
      id: 'f1',
      name: '中文文件名测试报告.pdf',
      size: 1234567,
      uploadedBytes: 1234567,
      complete: true,
      ownerDeviceId: 'devM',
      ownerDeviceName: 'Pixel手机',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      expiresAt: DateTime.now().add(const Duration(days: 6)),
    ),
    RelayFile(
      id: 'f2',
      name: 'half.bin',
      size: 1000000,
      uploadedBytes: 250000,
      complete: false,
      ownerDeviceId: 'devT',
      ownerDeviceName: 'TUI-TEST',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    ),
  ];
  c.clipHistory = [
    RelayClip(
      id: 'c1',
      text: 'hello 剪切板第一条比较长的内容用来测试省略号逻辑是否正常工作',
      deviceId: 'devM',
      deviceName: 'Pixel手机',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    RelayClip(
      id: 'c2',
      text: 'short',
      deviceId: 'devT',
      deviceName: 'TUI-TEST',
      updatedAt: DateTime.now(),
    ),
  ];
}

List<String> _visualLines(String frame) {
  // 按 \n 切行并剥码（overlay 的游标定位符也剥掉，不影响宽度断言）
  return frame.split('\n').map((l) {
    var s = stripAnsi(l);
    s = s.replaceAll(RegExp('\x1B\\[[0-9;]+[Hf]'), '');
    s = s.replaceAll('\r', '');
    return s;
  }).toList();
}

void main() {
  // ---- 渲染不变式：多尺寸
  for (final size in [
    [100, 30],
    [80, 24],
    [60, 15],
    [120, 40],
  ]) {
    final w = size[0], h = size[1];
    final app = TuiApp(_dummy());
    _fabricate(app.client);
    final f = app.render(w, h);
    final lines = _visualLines(f.text);
    final overflow =
        lines.where((l) => cellWidth(l) > w).toList();
    check(overflow.isEmpty, '行宽≤$w（${w}x$h）',
        overflow.take(2).join('|'));
    final joined = lines.join('\n');
    check(joined.contains('AirFly TUI'), '标题 $w x $h');
    check(joined.contains('Pixel手机'), '设备行 $w x $h');
    check(joined.contains('中文文件名'), '文件行 $w x $h');
    check(joined.contains('剪切板第一条'), '剪切板行 $w x $h');
    final badRegion = f.clicks.where(
        (r) => r.x < 0 || r.y < 0 || r.x + r.w > w || r.y + r.h > h);
    check(badRegion.isEmpty, '点击区越界 $w x $h');
  }

  // ---- 小窗口提示
  {
    final app = TuiApp(_dummy());
    final f = app.render(40, 10);
    check(_visualLines(f.text).join().contains('窗口太小'), '小窗口提示');
  }

  // ---- 焦点/选择纯逻辑
  {
    final app = TuiApp(_dummy());
    _fabricate(app.client);
    check(app.state.focus == TuiPanel.files, '默认焦点文件');
    app.handleKey(const TuiKey(TuiKeyKind.tab));
    check(app.state.focus == TuiPanel.clips, 'Tab 循环');
    app.handleKey(const TuiKey(TuiKeyKind.tab));
    check(app.state.focus == TuiPanel.devices, 'Tab 循环2');
    app.state.focus = TuiPanel.files;
    app.handleKey(const TuiKey(TuiKeyKind.down));
    app.handleKey(const TuiKey(TuiKeyKind.down));
    app.handleKey(const TuiKey(TuiKeyKind.down));
    check(app.state.fileSel == 1, '选择钳制在末尾');
    app.handleKey(const TuiKey(TuiKeyKind.up));
    check(app.state.fileSel == 0, '上移');
    app.handleKey(const TuiKey(TuiKeyKind.printable, 'j'));
    check(app.state.fileSel == 1, 'j 下移');
    app.handleKey(const TuiKey(TuiKeyKind.printable, 'k'));
    check(app.state.fileSel == 0, 'k 上移');
  }

  // ---- 鼠标：点行选中（离线下载只记日志不抛错）
  {
    final app = TuiApp(_dummy());
    _fabricate(app.client);
    final f = app.render(100, 30);
    final row = f.clicks.firstWhere((r) => r.id == 'file:1');
    app.handleMouse(
        TuiMouse(0, row.x + 1, row.y, false), f.clicks);
    check(app.state.focus == TuiPanel.files && app.state.fileSel == 1,
        '点文件行选中');
    check(app.state.logMsg.contains('未连接') ||
        app.state.logMsg.contains('上传中'), '离线下载优雅拒绝');
    // 滚轮
    final before = app.state.fileSel;
    app.handleMouse(const TuiMouse(65, 50, 10, false), f.clicks);
    check(app.state.fileSel >= before, '滚轮下滚');
  }

  // ---- 输入条编辑
  {
    final app = TuiApp(_dummy());
    String? got;
    app.state.input = InputReq(title: 't', submit: (s) => got = s);
    for (final ch in 'ab中文'.runes) {
      app.handleKey(TuiKey(TuiKeyKind.printable, String.fromCharCode(ch)));
    }
    app.handleKey(const TuiKey(TuiKeyKind.left));
    app.handleKey(const TuiKey(TuiKeyKind.backspace));
    app.handleKey(const TuiKey(TuiKeyKind.enter));
    check(got == 'ab文', '输入条编辑+提交(ab中文左移删中): $got');
    check(app.state.input == null, '提交后关闭输入条');
    // Esc 取消
    var called = false;
    app.state.input =
        InputReq(title: 't', submit: (_) => called = true);
    app.handleKey(const TuiKey(TuiKeyKind.esc));
    check(!called && app.state.input == null, 'Esc 取消不提交');
  }

  // ---- 确认框/help
  {
    final app = TuiApp(_dummy());
    bool? answer;
    app.state.confirm =
        ConfirmReq(text: '删?', submit: (v) => answer = v);
    app.handleKey(const TuiKey(TuiKeyKind.printable, 'n'));
    check(answer == false && app.state.confirm == null, '确认框否');
    app.state.confirm =
        ConfirmReq(text: '删?', submit: (v) => answer = v);
    app.handleKey(const TuiKey(TuiKeyKind.enter));
    check(answer == true, '确认框回车是');
    app.handleKey(const TuiKey(TuiKeyKind.printable, '?'));
    check(app.state.helpOpen, '帮助打开');
    final f = app.render(100, 30);
    check(_visualLines(f.text).join().contains('帮助'), '帮助覆盖层');
    app.handleKey(const TuiKey(TuiKeyKind.esc));
    check(!app.state.helpOpen, '帮助关闭');
  }

  // ---- q 退出（帮助开着时先关帮助）
  {
    final app = TuiApp(_dummy());
    app.state.helpOpen = true;
    app.handleKey(const TuiKey(TuiKeyKind.printable, 'q'));
    check(!app.state.helpOpen && !app.wantQuit, 'q 先关帮助');
    app.handleKey(const TuiKey(TuiKeyKind.printable, 'q'));
    check(app.wantQuit, 'q 退出');
  }

  print(_failures == 0 ? 'ALL PASS' : 'FAILURES: $_failures');
  if (_failures != 0) throw StateError('fail');
}
