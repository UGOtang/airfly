import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/transfer_item.dart';
import '../theme/app_theme.dart';

/// 传输记录页面
class TransfersScreen extends StatefulWidget {
  final AppController controller;

  const TransfersScreen({super.key, required this.controller});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final transfers = widget.controller.transfers;
                if (transfers.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildTransferList(transfers);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: CardDecoration.gradient(
              gradient: AppTheme.accentGradient,
              radius: 16,
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
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
                  '传输记录',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '查看文件传输状态',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textGrey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              widget.controller.clearTransfers();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已清除传输记录'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: '清除记录',
          ),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 56,
              color: AppTheme.accentOrange,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '暂无传输记录',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '发送或接收文件后\n这里会显示传输记录',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textGrey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 传输列表
  Widget _buildTransferList(List<TransferItem> transfers) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        return _buildTransferCard(transfer);
      },
    );
  }

  /// 传输卡片
  Widget _buildTransferCard(TransferItem transfer) {
    final isSend = transfer.direction == TransferDirection.send;
    final statusColor = _getStatusColor(transfer.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: CardDecoration.soft(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _buildFileIcon(transfer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transfer.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isSend
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 14,
                            color: isSend
                                ? AppTheme.primaryBlue
                                : AppTheme.accentOrange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isSend ? '发送给' : '来自'} ${transfer.peerName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    transfer.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            if (transfer.status == TransferStatus.transferring ||
                transfer.status == TransferStatus.pending) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: transfer.progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE1F5FE),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSend ? AppTheme.primaryBlue : AppTheme.accentOrange,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(transfer.progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                  Text(
                    '${TransferItem.formatSize(transfer.transferredBytes)} / ${TransferItem.formatSize(transfer.fileSize)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    TransferItem.formatSize(transfer.fileSize),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                  if (transfer.endTime != null)
                    Text(
                      _formatTime(transfer.endTime!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textLight,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 文件图标
  Widget _buildFileIcon(TransferItem transfer) {
    final iconMap = {
      'image': Icons.image_rounded,
      'video': Icons.videocam_rounded,
      'music': Icons.music_note_rounded,
      'picture_as_pdf': Icons.picture_as_pdf_rounded,
      'description': Icons.description_rounded,
      'table_chart': Icons.table_chart_rounded,
      'slideshow': Icons.slideshow_rounded,
      'folder_zip': Icons.folder_zip_rounded,
      'article': Icons.article_rounded,
      'insert_drive_file': Icons.insert_drive_file_rounded,
    };

    final icon = iconMap[transfer.fileIcon] ?? Icons.insert_drive_file_rounded;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
    );
  }

  /// 获取状态颜色
  Color _getStatusColor(TransferStatus status) {
    switch (status) {
      case TransferStatus.pending:
        return AppTheme.textGrey;
      case TransferStatus.transferring:
        return AppTheme.primaryBlue;
      case TransferStatus.completed:
        return const Color(0xFF4CAF50);
      case TransferStatus.failed:
        return const Color(0xFFF44336);
      case TransferStatus.cancelled:
        return AppTheme.textLight;
    }
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${time.month}月${time.day}日';
  }
}