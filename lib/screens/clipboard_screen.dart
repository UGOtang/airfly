import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../controllers/app_controller.dart';
import '../models/clipboard_item.dart';
import '../theme/app_theme.dart';

/// 共享剪切板页：可只当剪切板用，不传文件也能同步文本。
class ClipboardScreen extends StatefulWidget {
  final AppController controller;

  const ClipboardScreen({super.key, required this.controller});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  /// 分页：每次多显示 20 条。直接按当前列表长度 take，
  /// 远端新增/替换时自动跟随，无需手动重置（也不会把用户顶回顶部）。
  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final history = c.service.clipHistory;
              final visible = history.take(_visibleCount).toList();
              final rest = history.length - visible.length;
              return ListView(
                key: const Key('clipboard_list'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _buildComposer(c),
                  const SizedBox(height: 12),
                  _buildAutoSyncCard(c),
                  const SizedBox(height: 12),
                  _buildHistoryHeader(c),
                  ...visible.map(_buildHistoryCard),
                  if (rest > 0) _buildLoadMore(rest),
                  if (history.isEmpty) _buildEmptyHint(),
                ],
              );
            },
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
              gradient: AppTheme.cardGradient,
              radius: 16,
            ),
            child: const Icon(
              Icons.content_paste_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共享剪切板',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.of(context).text,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '同空间设备实时同步文本',
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.of(context).sub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(AppController c) {
    final connected = c.service.isConnected;
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField.multiline(
            control: FTextFieldControl.managed(controller: _input),
            hint: '输入要同步的文本…',
            minLines: 2,
            maxLines: 4,
            maxLength: 20000,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FButton(
                variant: .outline,
                onPress: () async {
                  final t = await c.readLocalClipboard();
                  if (t == null || t.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('本地剪切板是空的')),
                    );
                    return;
                  }
                  _input.text = t;
                },
                child: const Text('粘贴'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  onPress: (!connected || _sending)
                      ? null
                      : () => _push(c),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(connected ? '同步到云端' : '未连接'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _push(AppController c) async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先输入点内容吧')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await c.pushClipboard(text);
      _input.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已同步，同空间设备可见'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步失败：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildAutoSyncCard(AppController c) {
    return Container(
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          FTile(
            title: const Text('自动推送本地剪切板'),
            subtitle: const Text('复制即同步（每2秒检测）'),
            suffix: FSwitch(
              value: c.autoPushClip,
              onChange: (v) => c.setAutoSync(push: v),
            ),
          ),
          const FDivider(),
          FTile(
            title: const Text('自动写入本地剪切板'),
            subtitle: const Text('收到远端文本即复制到本机'),
            suffix: FSwitch(
              value: c.autoPullClip,
              onChange: (v) => c.setAutoSync(pull: v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader(AppController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Text(
            '同步记录（${c.service.clipHistory.length}）',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.of(context).text,
            ),
          ),
          const Spacer(),
          if (c.service.clipLatest != null)
            FButton(
              variant: .ghost,
              onPress: () => _copyItem(c, c.service.clipLatest!),
              child: const Text('复制最新'),
            ),
        ],
      ),
    );
  }

  /// 分页加载更多按钮（显示剩余条数）。
  Widget _buildLoadMore(int rest) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: FButton(
          variant: .outline,
          onPress: () => setState(() => _visibleCount += _pageSize),
          child: Text('显示更多（剩余 $rest 条）'),
        ),
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: CardDecoration.softOf(context),
      child: Column(
        children: [
          Icon(Icons.history_rounded,
              size: 40, color: AppPalette.of(context).faint),
          const SizedBox(height: 12),
          Text(
            '暂无同步记录\n在上方输入文本并同步，或在其他设备同步',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppPalette.of(context).sub,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(ClipboardItem item) {
    final isMine = item.deviceId == widget.controller.deviceId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (isMine
                          ? AppTheme.primaryBlue
                          : AppTheme.accentOrange)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isMine ? '我' : item.deviceName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isMine
                        ? AppPalette.of(context).strong
                        : const Color(0xFFE65100),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // 绝对时间 + 相对时间双记：绝对用于查证，相对一眼可读
                  '${_formatAbsolute(item.updatedAt)} · ${_formatTime(item.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).faint,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '复制',
                onPressed: () =>
                    _copyItem(widget.controller, item),
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            item.text.length > 500
                ? '${item.text.substring(0, 500)}…（共 ${item.text.length} 字）'
                : item.text,
            style: TextStyle(
              fontSize: 14,
              color: AppPalette.of(context).text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyItem(AppController c, ClipboardItem item) async {
    await c.copyToLocal(item.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到本地剪切板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return _formatAbsolute(t);
  }

  /// 绝对时间：同年省略年，今天省略日期，精确到分钟（跨年补年）。
  String _formatAbsolute(DateTime t) {
    final now = DateTime.now();
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final sameDay = t.year == now.year &&
        t.month == now.month &&
        t.day == now.day;
    if (sameDay) return hm;
    final md = '${t.month}月${t.day}日';
    if (t.year == now.year) return '$md $hm';
    return '${t.year}年$md $hm';
  }
}
