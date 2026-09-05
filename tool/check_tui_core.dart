// tui_term 原语自测：dart tool/check_tui_core.dart，退出码 0 = 全过。
// ignore_for_file: avoid_print

import 'dart:convert';

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

List<int> bytes(String s) => utf8.encode(s);

void main() {
  // ---- 列宽
  check(cellWidth('abc') == 3, 'ascii 宽 1');
  check(cellWidth('中文') == 4, 'CJK 宽 2');
  check(cellWidth('a中b') == 4, '混排');
  check(cellWidth('😀') == 2, 'emoji 宽 2');
  check(cellWidth('e\u0301') == 1, '组合符零宽');
  check(cellWidth('\x1B') == 0, '控制字符零宽');
  check(ellipsis('hello world', 5) == 'hell…', '省略英文');
  check(ellipsis('中文测试', 5) == '中文…', '省略不拦腰');
  check(ellipsis('ab', 5) == 'ab', '短串不动');
  check(padCells('ab', 5) == 'ab   ', 'pad ascii');
  check(cellWidth(padCells('中文', 6)) == 6, 'pad CJK 对齐');

  // ---- ANSI/展示
  check(stripAnsi('\x1B[32mgreen\x1B[0m') == 'green', '剥 SGR');
  check(stripAnsi('\x1B]0;title\x07x') == 'x', '剥 OSC');
  check(progressBar(0.5, 10) == '█████░░░░░', '进度条半');
  check(progressBar(0, 4) == '░░░░', '进度条空');
  check(progressBar(1, 3) == '███', '进度条满');
  check(formatSize(1536) == '1.5K', '大小格式化');

  // ---- 解析：整体序列
  var p = InputParser();
  p.feed([0x1B, 0x5B, 0x41]);
  var ks = p.takeKeys();
  check(ks.length == 1 && ks[0].kind == TuiKeyKind.up, '上键');
  check(!p.hasPendingEsc, '无挂起');

  // ---- 解析：拆包到达
  p = InputParser();
  p.feed([0x1B]);
  check(p.hasPendingEsc && p.takeKeys().isEmpty, '孤 ESC 挂起不等');
  p.feed([0x5B, 0x42]);
  ks = p.takeKeys();
  check(ks.length == 1 && ks[0].kind == TuiKeyKind.down, '拆包下键拼回');
  check(!p.hasPendingEsc, '拼回后清除挂起');

  // ---- 解析：孤 ESC 超时
  p = InputParser();
  p.feed([0x1B]);
  p.flush();
  ks = p.takeKeys();
  check(ks.length == 1 && ks[0].kind == TuiKeyKind.esc, '孤 ESC 超时判 esc');

  // ---- 解析：功能键
  p = InputParser();
  p.feed([0x1B, 0x5B, 0x35, 0x7E, 0x1B, 0x5B, 0x36, 0x7E]);
  ks = p.takeKeys();
  check(ks.length == 2 &&
      ks[0].kind == TuiKeyKind.pgup &&
      ks[1].kind == TuiKeyKind.pgdn, 'PgUp/PgDn');
  p.feed([0x1B, 0x5B, 0x33, 0x7E, 0x1B, 0x4F, 0x50]);
  ks = p.takeKeys();
  check(ks.length == 2 &&
      ks[0].kind == TuiKeyKind.delete &&
      ks[1].kind == TuiKeyKind.f1, 'Delete/SS3-F1');

  // ---- 解析：控制键
  p = InputParser();
  p.feed([0x0D, 0x7F, 0x09, 0x03]);
  ks = p.takeKeys();
  check(
      ks.length == 4 &&
          ks[0].kind == TuiKeyKind.enter &&
          ks[1].kind == TuiKeyKind.backspace &&
          ks[2].kind == TuiKeyKind.tab &&
          ks[3].kind == TuiKeyKind.ctrlC,
      '回车/退格/Tab/CtrlC');

  // ---- 解析：UTF-8 被拆开也不吐半个字
  p = InputParser();
  final zh = bytes('中'); // [0xE4,0xB8,0xAD]
  p.feed(zh.sublist(0, 2));
  check(p.takeKeys().isEmpty, '半个汉字不出键');
  p.feed(zh.sublist(2));
  ks = p.takeKeys();
  check(ks.length == 1 &&
      ks[0].kind == TuiKeyKind.printable &&
      ks[0].text == '中', '汉字拼回');

  // ---- 解析：鼠标 SGR
  p = InputParser();
  p.feed(bytes('\x1B[<0;10;20M'));
  var ms = p.takeMice();
  check(ms.length == 1 &&
      ms[0].button == 0 &&
      ms[0].x == 10 &&
      ms[0].y == 20 &&
      !ms[0].release, '左键按下');
  p.feed(bytes('\x1B[<0;10;20m'));
  ms = p.takeMice();
  check(ms.length == 1 && ms[0].release, '左键松开');
  p.feed(bytes('\x1B[<64;5;5M'));
  ms = p.takeMice();
  check(ms.length == 1 && ms[0].button == 64, '滚轮上');

  // ---- 解析：垃圾不卡死
  p = InputParser();
  p.feed([0x01, 0x02, 0x1B, 0x5B, 0x39, 0x39, 0x39, 0x58]);
  ks = p.takeKeys();
  check(ks.length == 1 && ks[0].kind == TuiKeyKind.unknown,
      '未知序列吞掉不卡死');
  check(!p.hasPendingEsc, '垃圾后无挂起');

  print(_failures == 0 ? 'ALL PASS' : 'FAILURES: $_failures');
  if (_failures != 0) throw StateError('fail');
}
