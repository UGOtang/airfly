// TUI 终端原语：纯 Dart（dart:core + dart:convert），无 IO，可单测。
// 覆盖：半角/全角列宽、ANSI 剥离与样式、键盘/鼠标(SGR)输入解析、
// 进度条/省略/大小时间格式化。

import 'dart:convert';

// ---------------------------------------------------------------- 列宽

/// 是否为零宽字符（组合符/变体选择符等）。
bool _isZeroWidth(int cp) {
  return (cp >= 0x0300 && cp <= 0x036F) ||
      (cp >= 0x1AB0 && cp <= 0x1AFF) ||
      (cp >= 0x1DC0 && cp <= 0x1DFF) ||
      (cp >= 0x20D0 && cp <= 0x20FF) ||
      (cp >= 0xFE00 && cp <= 0xFE0F) ||
      cp == 0x00AD ||
      cp == 0x200B ||
      cp == 0x200C ||
      cp == 0x200D ||
      cp == 0x2060 ||
      cp == 0xFEFF;
}

/// 是否为全角（占 2 列）。
bool _isWide(int cp) {
  if (cp < 0x1100) return false;
  return (cp >= 0x1100 && cp <= 0x115F) || // Hangul Jamo
      (cp >= 0x2E80 && cp <= 0x303E) || // CJK 部首/标点
      (cp >= 0x3041 && cp <= 0x33FF) || // 平假名/片假名/注音/兼容
      (cp >= 0x3400 && cp <= 0x4DBF) || // Ext A
      (cp >= 0x4E00 && cp <= 0x9FFF) || // CJK 统一
      (cp >= 0xA000 && cp <= 0xA4CF) || // 彝文等
      (cp >= 0xAC00 && cp <= 0xD7A3) || // Hangul 音节
      (cp >= 0xF900 && cp <= 0xFAFF) || // 兼容表意
      (cp >= 0xFE30 && cp <= 0xFE4F) || // CJK 兼容形
      (cp >= 0xFF00 && cp <= 0xFF60) || // 全角 ASCII/标点
      (cp >= 0xFFE0 && cp <= 0xFFE6) || // 全角符号
      (cp >= 0x1F300 && cp <= 0x1FAFF) || // Emoji 主区
      (cp >= 0x1F1E6 && cp <= 0x1F1FF) || // 区域指示符
      (cp >= 0x20000 && cp <= 0x3FFFD); // Ext B~F
}

int cellWidthOf(int cp) {
  if (cp < 0x20 || (cp >= 0x7F && cp < 0xA0)) return 0;
  if (_isZeroWidth(cp)) return 0;
  return _isWide(cp) ? 2 : 1;
}

/// 字符串显示列宽。
int cellWidth(String s) {
  var w = 0;
  for (final cp in s.runes) {
    w += cellWidthOf(cp);
  }
  return w;
}

/// 按列宽截断（保证不把宽字符拦腰截断），超长加 …。
String ellipsis(String s, int maxWidth) {
  if (maxWidth <= 0) return '';
  if (cellWidth(s) <= maxWidth) return s;
  if (maxWidth == 1) return '…';
  final buf = StringBuffer();
  var w = 0;
  for (final cp in s.runes) {
    final cw = cellWidthOf(cp);
    if (w + cw > maxWidth - 1) break;
    buf.writeCharCode(cp);
    w += cw;
  }
  buf.write('…');
  // 补齐（宽字符边界导致不足时后面由调用方 pad）
  return buf.toString();
}

/// 按列宽左对齐填充。
String padCells(String s, int width) {
  final w = cellWidth(s);
  if (w >= width) return s;
  return s + ' ' * (width - w);
}

// ---------------------------------------------------------------- ANSI

final RegExp _ansiCsi = RegExp('\x1B\\[[0-9;?]*[a-zA-Z]');
final RegExp _ansiOsc = RegExp('\x1B\\][^\x07\x1B]*(?:\x07|\x1B\\\\)');

String stripAnsi(String s) =>
    s.replaceAll(_ansiOsc, '').replaceAll(_ansiCsi, '');

class Ansi {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const reverse = '\x1B[7m';
  static String fg(int n) => '\x1B[38;5;${n}m';
  static String bg(int n) => '\x1B[48;5;${n}m';
}

// ---------------------------------------------------------------- 杂项展示

String progressBar(double p, int width) {
  final v = p.clamp(0.0, 1.0);
  if (width <= 0) return '';
  final fill = (v * width).round().clamp(0, width);
  return '${'█' * fill}${'░' * (width - fill)}';
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}G';
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 10) return '刚刚';
  if (d.inMinutes < 1) return '${d.inSeconds}秒前';
  if (d.inHours < 1) return '${d.inMinutes}分前';
  if (d.inDays < 1) return '${d.inHours}小时前';
  if (d.inDays < 30) return '${d.inDays}天前';
  return '${t.month}/${t.day}';
}

// ---------------------------------------------------------------- 输入解析

enum TuiKeyKind {
  printable,
  enter,
  backspace,
  tab,
  backtab,
  esc,
  up,
  down,
  left,
  right,
  home,
  end,
  pgup,
  pgdn,
  insert,
  delete,
  ctrlC,
  f1,
  f5, // 刷新惯例键，按需扩展
  unknown,
}

class TuiKey {
  final TuiKeyKind kind;
  final String text; // printable 时为字符
  const TuiKey(this.kind, [this.text = '']);
}

/// 鼠标事件（SGR 1006 坐标，1-based）。
class TuiMouse {
  /// 0=左 1=中 2=右 64=滚轮上 65=滚轮下
  final int button;
  final int x;
  final int y;
  final bool release;
  const TuiMouse(this.button, this.x, this.y, this.release);
}

/// 键盘/鼠标字节流解析器。
/// ESC 序列可能被拆到多次 read：收到的 ESC 先挂起，等 TUI 主循环
/// 50ms 无后续字节再 flush() 为 esc 键（见 hasPendingEsc）。
class InputParser {
  final List<TuiKey> keys = [];
  final List<TuiMouse> mice = [];
  final List<int> _pending = [];
  bool hasPendingEsc = false;

  // ignore: avoid_print
  void _debug(String s) {} // 保留钩子，平时静默

  List<TuiKey> takeKeys() {
    final out = List<TuiKey>.of(keys);
    keys.clear();
    return out;
  }

  List<TuiMouse> takeMice() {
    final out = List<TuiMouse>.of(mice);
    mice.clear();
    return out;
  }

  void feed(List<int> bytes) {
    _pending.addAll(bytes);
    _parse();
  }

  /// 超时后调用：挂起的孤 ESC 判定为 esc 键。
  void flush() {
    if (hasPendingEsc) {
      hasPendingEsc = false;
      _pending.clear();
      keys.add(const TuiKey(TuiKeyKind.esc));
    }
  }

  void _parse() {
    while (_pending.isNotEmpty) {
      final b = _pending[0];
      if (b == 0x1B) {
        if (_pending.length == 1) {
          // 等一等：可能是 Alt/方向键/鼠标的前缀
          hasPendingEsc = true;
          return;
        }
        hasPendingEsc = false;
        if (_pending[1] == 0x5B) {
          // CSI …
          if (!_parseCsi()) return; // 不完整，等更多字节
        } else if (_pending[1] == 0x4F) {
          // SS3 (F1-F4 老式)：ESC O P/Q/R/S
          if (_pending.length < 3) {
            hasPendingEsc = true;
            return;
          }
          _pending.removeRange(0, 3);
          keys.add(const TuiKey(TuiKeyKind.f1));
        } else {
          // ESC + 其他：按 esc 处理，保留后续字节
          _pending.removeAt(0);
          keys.add(const TuiKey(TuiKeyKind.esc));
        }
        continue;
      }
      if (b == 0x03) {
        _pending.removeAt(0);
        keys.add(const TuiKey(TuiKeyKind.ctrlC));
        continue;
      }
      if (b == 0x0D || b == 0x0A) {
        _pending.removeAt(0);
        keys.add(const TuiKey(TuiKeyKind.enter));
        continue;
      }
      if (b == 0x7F || b == 0x08) {
        _pending.removeAt(0);
        keys.add(const TuiKey(TuiKeyKind.backspace));
        continue;
      }
      if (b == 0x09) {
        _pending.removeAt(0);
        keys.add(const TuiKey(TuiKeyKind.tab));
        continue;
      }
      if (b < 0x20) {
        // 其他控制字符丢弃（Ctrl 组合暂不支持）
        _pending.removeAt(0);
        _debug('drop ctrl $b');
        continue;
      }
      // 可打印（含 UTF-8 多字节：按 UTF-8 前导字节算长度整体取出，
      // 用 utf8 解码——绝不能用 fromCharCodes，那是 UTF-16，会乱码）
      final len = _utf8Len(b);
      if (_pending.length < len) return; // 等齐
      final slice = _pending.sublist(0, len);
      String text;
      try {
        text = utf8.decode(slice);
      } catch (_) {
        // 非法序列：丢首字节防卡死
        _pending.removeAt(0);
        continue;
      }
      _pending.removeRange(0, len);
      keys.add(TuiKey(TuiKeyKind.printable, text));
    }
    hasPendingEsc = false;
  }

  int _utf8Len(int b) {
    if (b < 0x80) return 1;
    if (b >= 0xC2 && b <= 0xDF) return 2;
    if (b >= 0xE0 && b <= 0xEF) return 3;
    if (b >= 0xF0 && b <= 0xF4) return 4;
    return 1; // 非法前导：单字节消费，避免死循环
  }

  /// 解析 _pending 开头的 CSI，完整返回 true，不完整返回 false（等）。
  bool _parseCsi() {
    // 找终结字节 @-~，同时收集参数
    var i = 2;
    while (i < _pending.length) {
      final b = _pending[i];
      if (b >= 0x40 && b <= 0x7E) break;
      i++;
      if (i - 2 > 16) {
        // 参数过长：损坏序列，整体丢弃防卡死
        _pending.removeRange(0, i);
        keys.add(const TuiKey(TuiKeyKind.unknown));
        return true;
      }
    }
    if (i >= _pending.length) return false;
    final params = String.fromCharCodes(_pending.sublist(2, i));
    final fin = _pending[i];
    final total = i + 1;

    // 鼠标 SGR：ESC [ < Cb ; Cx ; Cy M/m（我们只开 1006，不处理 X10）
    if (params.startsWith('<')) {
      final parts = params.substring(1).split(';');
      if (parts.length == 3) {
        final cb = int.tryParse(parts[0]) ?? -1;
        final cx = int.tryParse(parts[1]) ?? 1;
        final cy = int.tryParse(parts[2]) ?? 1;
        if (cb >= 0) {
          _pending.removeRange(0, total);
          mice.add(TuiMouse(cb & 0x43, cx, cy, fin == 0x6D));
          return true;
        }
      }
      _pending.removeRange(0, total);
      return true;
    }

    TuiKeyKind kind;
    switch (fin) {
      case 0x41:
        kind = TuiKeyKind.up;
        break;
      case 0x42:
        kind = TuiKeyKind.down;
        break;
      case 0x43:
        kind = TuiKeyKind.right;
        break;
      case 0x44:
        kind = TuiKeyKind.left;
        break;
      case 0x48:
        kind = TuiKeyKind.home;
        break;
      case 0x46:
        kind = TuiKeyKind.end;
        break;
      case 0x5A:
        kind = TuiKeyKind.backtab;
        break;
      case 0x7E: // ~
        switch (params) {
          case '1':
          case '7':
            kind = TuiKeyKind.home;
            break;
          case '2':
            kind = TuiKeyKind.insert;
            break;
          case '3':
            kind = TuiKeyKind.delete;
            break;
          case '4':
          case '8':
            kind = TuiKeyKind.end;
            break;
          case '5':
            kind = TuiKeyKind.pgup;
            break;
          case '6':
            kind = TuiKeyKind.pgdn;
            break;
          case '11':
          case '12':
          case '13':
          case '14':
          case '15':
            kind = TuiKeyKind.f1;
            break;
          case '18':
          case '19':
          case '20':
          case '21':
            kind = TuiKeyKind.f5;
            break;
          default:
            kind = TuiKeyKind.unknown;
        }
        break;
      default:
        kind = TuiKeyKind.unknown;
    }
    _pending.removeRange(0, total);
    keys.add(TuiKey(kind));
    return true;
  }
}
