import 'package:flutter/material.dart';

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
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _buildComposer(c),
                  const SizedBox(height: 12),
                  _buildAutoSyncCard(c),
                  const SizedBox(height: 12),
                  _buildHistoryHeader(c),
                  ...c.service.clipHistory.map(_buildHistoryCard),
                  if (c.service.clipHistory.isEmpty) _buildEmptyHint(),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共享剪切板',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '同空间设备实时同步文本',
                  style: TextStyle(fontSize: 13, color: AppTheme.textGrey),
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
      decoration: CardDecoration.soft(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _input,
            maxLines: 4,
            minLines: 2,
            maxLength: 20000,
            decoration: const InputDecoration(
              hintText: '输入要同步的文本…',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
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
                icon: const Icon(Icons.paste_rounded, size: 18),
                label: const Text('粘贴'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textGrey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (!connected || _sending)
                      ? null
                      : () => _push(c),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(connected ? '同步到云端' : '未连接'),
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
      decoration: CardDecoration.soft(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // SwitchListTile 的水波纹需要 Material 祖先在装饰层之内
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '自动推送本地剪切板',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '复制即同步（每2秒检测）',
                style: TextStyle(fontSize: 12),
              ),
              value: c.autoPushClip,
              onChanged: (v) => c.setAutoSync(push: v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '自动写入本地剪切板',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '收到远端文本即复制到本机',
                style: TextStyle(fontSize: 12),
              ),
              value: c.autoPullClip,
              onChanged: (v) => c.setAutoSync(pull: v),
            ),
          ],
        ),
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
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const Spacer(),
          if (c.service.clipLatest != null)
            TextButton.icon(
              onPressed: () => _copyItem(c, c.service.clipLatest!),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制最新'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: CardDecoration.soft(),
      child: const Column(
        children: [
          Icon(Icons.history_rounded, size: 40, color: AppTheme.textLight),
          SizedBox(height: 12),
          Text(
            '暂无同步记录\n在上方输入文本并同步，或在其他设备同步',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textGrey,
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
      decoration: CardDecoration.soft(),
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
                        ? AppTheme.deepBlue
                        : const Color(0xFFE65100),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(item.updatedAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight,
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
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
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
    return '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
