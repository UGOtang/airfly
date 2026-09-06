import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../controllers/app_controller.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';
import 'clipboard_screen.dart';
import 'devices_screen.dart';
import 'files_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

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
      TerminalScreen(controller: widget.controller),
      DevicesScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    final dark =
        Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 自定义顶栏没有 AppBar，必须手动让状态栏图标随主题反色，
      // 否则深色下黑图标黑底看不见。
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: AppPalette.of(context).page),
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
      bottomNavigationBar: FBottomNavigationBar(
        index: _currentIndex,
        onChange: (i) => setState(() => _currentIndex = i),
        children: const [
          FBottomNavigationBarItem(
            icon: Icon(Icons.content_paste_rounded),
            label: Text('剪切板'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: Text('文件'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.terminal_rounded),
            label: Text('终端'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.devices_rounded),
            label: Text('设备'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: Text('设置'),
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
                  color: AppPalette.of(context).chip,
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
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPalette.of(context).sub,
                        ),
                      ),
                    ),
                    Text(
                      controller.deviceName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).sub,
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
