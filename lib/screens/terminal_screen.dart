import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../core/term_session.dart';
import '../theme/app_theme.dart';

/// 可视化本地终端页：桌面端跑真 shell，移动/Web 为受限模式。
/// 输出区固定深色控制台风格（两套主题下都一样，最像终端也最护眼）。
class TerminalScreen extends StatefulWidget {
  final AppController controller;

  const TerminalScreen({super.key, required this.controller});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final FocusNode _focus;

  /// 是否跟随最新输出（用户上翻查看历史时暂停跟随）。
  bool _follow = true;

  TermSession get _s => widget.controller.terminal;

  static const _monoFallback = [
    'JetBrains Mono',
    'Consolas',
    'Menlo',
    'DejaVu Sans Mono',
    'monospace',
  ];

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _handleKey);
    _scroll.addListener(_onScroll);
    _s.addListener(_onSession);
    // 首帧后滚到底（会话横幅在 UI 订阅前就已写入）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    _scroll.removeListener(_onScroll);
    _focus.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final t = _s.recallOlder(_input.text);
      if (t != null) _setInput(t);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final t = _s.recallNewer();
      if (t != null) _setInput(t);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setInput(String t) {
    _input.text = t;
    _input.selection = TextSelection.collapsed(offset: t.length);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final follow =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 120;
    if (follow != _follow && mounted) {
      setState(() => _follow = follow);
    }
  }

  void _onSession() {
    if (!_follow || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _jumpToBottom() {
    if (!mounted || !_follow || !_scroll.hasClients) return;
    try {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final cmd = _input.text;
    if (cmd.trim().isEmpty || _s.running) return;
    _input.clear();
    if (!_follow) setState(() => _follow = true);
    await _s.submit(cmd);
  }

  Future<void> _copyAll() async {
    final text = _s.copyAll();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('终端输出已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: AnimatedBuilder(
            animation: _s,
            builder: (context, _) => _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: CardDecoration.gradient(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF26A69A), Color(0xFF00897B)],
              ),
              radius: 16,
            ),
            child: const Icon(
              Icons.terminal_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedBuilder(
              animation: _s,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本地终端',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.of(context).text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    _s.running ? '● 运行中 · ${_s.shellName}' : _s.shellName,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制输出',
          ),
          IconButton(
            onPressed: () => _s.clear(),
            icon: const Icon(Icons.clear_all_rounded),
            tooltip: '清屏',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    // 控制台固定深色：浅色主题下是深 slate 卡，深色下更黑
                    color: p.isDark
                        ? const Color(0xFF0A0F18)
                        : const Color(0xFF10151F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.border, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _s.lines.length,
                        itemBuilder: (context, i) =>
                            _buildLine(_s.lines[i]),
                      ),
                    ),
                  ),
                ),
                if (!_follow)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      onPressed: () {
                        setState(() => _follow = true);
                        _jumpToBottom();
                      },
                      tooltip: '回到最新',
                      child: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildInputBar(),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '保留最近 ${TermSession.maxLines} 行 · 上下键翻历史 · 右上按钮可停止运行中的命令',
              style: TextStyle(fontSize: 11, color: p.faint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(TermLine line) {
    final Color color;
    final FontWeight weight;
    switch (line.kind) {
      case TermLineKind.input:
        color = const Color(0xFF7FD0F7);
        weight = FontWeight.w600;
        break;
      case TermLineKind.output:
        color = const Color(0xFFD7E3F0);
        weight = FontWeight.w400;
        break;
      case TermLineKind.error:
        color = const Color(0xFFFF9E9E);
        weight = FontWeight.w400;
        break;
      case TermLineKind.system:
        color = const Color(0xFF6B7C93);
        weight = FontWeight.w400;
        break;
    }
    return Text(
      line.text.isEmpty ? ' ' : line.text,
      style: TextStyle(
        fontFamilyFallback: _monoFallback,
        fontSize: 13,
        height: 1.45,
        color: color,
        fontWeight: weight,
      ),
    );
  }

  Widget _buildInputBar() {
    final p = AppPalette.of(context);
    final running = _s.running;
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Flexible(
            child: Tooltip(
              message: _s.cwd,
              child: Text(
                '${_s.cwd} ${_s.promptChar}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamilyFallback: _monoFallback,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.strong,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _input,
              focusNode: _focus,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                fontFamilyFallback: _monoFallback,
                fontSize: 13,
                color: p.text,
              ),
              decoration: InputDecoration.collapsed(
                hintText: running ? '运行中…' : '输入命令…',
                hintStyle: TextStyle(color: p.faint, fontSize: 13),
              ),
            ),
          ),
          if (running)
            IconButton(
              onPressed: () => _s.abort(),
              icon: const Icon(Icons.stop_circle_rounded),
              color: const Color(0xFFF44336),
              tooltip: '停止命令 (Ctrl+C)',
            )
          else
            IconButton(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded),
              tooltip: '执行',
            ),
        ],
      ),
    );
  }
}
