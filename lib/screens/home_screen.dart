import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/transfer_item.dart';
import '../theme/app_theme.dart';
import 'devices_screen.dart';
import 'settings_screen.dart';
import 'transfers_screen.dart';

/// 主页面 - 包含设备发现、传输记录、设置三个标签页
class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  /// 监听控制器变化，处理文件请求对话框
  void _handleControllerChange() {
    final pending = widget.controller.pendingRequest;
    if (pending != null && !widget.controller.isDialogShowing) {
      widget.controller.markDialogShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showFileRequestDialog(pending);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DevicesScreen(controller: widget.controller),
      TransfersScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.bgGradient,
        ),
        child: IndexedStack(
          index: _currentIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.radar_rounded,
                  label: '发现',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.swap_horiz_rounded,
                  label: '传输',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示文件接收请求对话框
  void _showFileRequestDialog(TransferItem item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.mark_email_unread_rounded,
              color: AppTheme.primaryBlue,
            ),
            SizedBox(width: 8),
            Text('收到文件请求'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.peerName} 想要发送文件给你',
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_rounded,
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          TransferItem.formatSize(item.fileSize),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.controller.rejectFileRequest();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textGrey,
            ),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () {
              widget.controller.acceptFileRequest();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已接受文件请求'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('接受'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.deepBlue : AppTheme.textGrey,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.deepBlue : AppTheme.textGrey,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}