import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
    final p = AppPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 自定义顶栏没有 AppBar，必须手动让状态栏图标随主题反色，
      // 否则深色下黑图标黑底看不见。
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        // 内容延伸到底栏之下，毛玻璃才有东西可模糊
        extendBody: true,
        body: Container(
          decoration: BoxDecoration(gradient: p.page),
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
        bottomNavigationBar: GlassTabBar.bottom(
          tabs: const [
            GlassTab(icon: Icon(Icons.content_paste_rounded), label: '剪切板'),
            GlassTab(icon: Icon(Icons.folder_rounded), label: '文件'),
            GlassTab(icon: Icon(Icons.terminal_rounded), label: '终端'),
            GlassTab(icon: Icon(Icons.devices_rounded), label: '设备'),
            GlassTab(icon: Icon(Icons.settings_rounded), label: '设置'),
          ],
          selectedIndex: _currentIndex,
          onTabSelected: (i) {
            try {
              HapticFeedback.selectionClick();
            } catch (_) {}
            setState(() => _currentIndex = i);
          },
          // 选中指示：淡品牌色玻璃 tint（亮 14%/暗 22%），柔和不刺眼；
          // 选中态靠品牌色图标/文字表达，边缘清晰度交给 sharp 高光
          indicatorColor: (dark
                  ? AppTheme.primaryBlue
                  : AppTheme.deepBlue)
              .withValues(alpha: dark ? 0.22 : 0.14),
          selectedIconColor:
              dark ? AppTheme.primaryBlue : AppTheme.deepBlue,
          selectedLabelColor:
              dark ? AppTheme.primaryBlue : AppTheme.deepBlue,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          // 不要外发光晕：边缘清晰度只靠指示条自身的高光
          glowOpacity: 0.0,
          // 指示条自身用紧致镜面高光，边缘线条锋利（默认 medium 偏 diffuse）
          indicatorSettings: const LiquidGlassSettings(
            specularSharpness: GlassSpecularSharpness.sharp,
          ),
          // 指示 pill 稍大一圈，更醒目（只影响绘制，不影响点击区）
          indicatorExpansion:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).chip,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppPalette.of(context).isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.06),
                        width: 1,
                      ),
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
        ),
      ),
    );
      },
    );
  }
}
