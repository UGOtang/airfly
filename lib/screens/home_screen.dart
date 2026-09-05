import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';
import 'clipboard_screen.dart';
import 'devices_screen.dart';
import 'files_screen.dart';
import 'settings_screen.dart';

/// 主页面：剪切板 / 文件 / 设备 / 设置 + 顶部连接状态条。
class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ClipboardScreen(controller: widget.controller),
      FilesScreen(controller: widget.controller),
      DevicesScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _StatusBar(controller: widget.controller),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: pages),
              ),
            ],
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.content_paste_rounded,
                  label: '剪切板',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.folder_rounded,
                  label: '文件',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.devices_rounded,
                  label: '设备',
                  index: 2,
                ),
                _buildNavItem(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  index: 3,
                ),
              ],
            ),
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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

/// 顶部连接状态条：点按可重连。
class _StatusBar extends StatelessWidget {
  final AppController controller;

  const _StatusBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final svc = controller.service;
        final Color dot;
        final String text;
        switch (svc.state) {
          case ConnState.connected:
            dot = const Color(0xFF4CAF50);
            text = '已连接 · ${controller.spaceId}';
            break;
          case ConnState.connecting:
            dot = AppTheme.accentOrange;
            text = '连接中…';
            break;
          case ConnState.disconnected:
            dot = const Color(0xFFF44336);
            final err = svc.lastErrorMessage ??
                (svc.lastErrorCode != null
                    ? '(${svc.lastErrorCode})'
                    : '');
            text = controller.serverUrl.isEmpty || controller.spaceId.isEmpty
                ? '未配置服务端，去「设置」填写'
                : '未连接 $err · 点按重连';
            break;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (svc.state != ConnState.connecting) {
                  controller.connect();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('正在连接…'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textGrey,
                        ),
                      ),
                    ),
                    Text(
                      controller.deviceName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
