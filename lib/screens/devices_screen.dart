import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/device_info.dart';
import '../theme/app_theme.dart';

/// 设备发现页面
class DevicesScreen extends StatefulWidget {
  final AppController controller;

  const DevicesScreen({super.key, required this.controller});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
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
                final devices = widget.controller.devices;
                if (devices.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildDeviceList(devices);
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
              gradient: AppTheme.cardGradient,
              radius: 16,
            ),
            child: const Icon(
              Icons.air_rounded,
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
                  'AirFly',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '发现附近的设备',
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
              widget.controller.refreshDevices();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在刷新设备列表...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
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
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.radar_rounded,
              size: 56,
              color: AppTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '正在寻找附近的设备...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '请确保其他设备也打开了 AirFly\n并连接到同一个 Wi-Fi 网络',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textGrey,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // 使用静态脉冲动画替代持续旋转的进度指示器，降低功耗
          const _PulseRadar(),
        ],
      ),
    );
  }

  /// 设备列表
  Widget _buildDeviceList(List<DeviceInfo> devices) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return _buildDeviceCard(device);
      },
    );
  }

  /// 设备卡片
  Widget _buildDeviceCard(DeviceInfo device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: CardDecoration.soft(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showSendOptions(device),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildDeviceAvatar(device),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: device.isOnline
                                  ? const Color(0xFF4CAF50)
                                  : AppTheme.textLight,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            device.isOnline ? '在线' : '离线',
                            style: TextStyle(
                              fontSize: 12,
                              color: device.isOnline
                                  ? const Color(0xFF4CAF50)
                                  : AppTheme.textLight,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            device.typeLabel,
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
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 设备头像
  Widget _buildDeviceAvatar(DeviceInfo device) {
    final iconMap = {
      'smartphone': Icons.smartphone_rounded,
      'tablet': Icons.tablet_rounded,
      'desktop': Icons.desktop_windows_rounded,
      'laptop': Icons.laptop_rounded,
      'devices': Icons.devices_rounded,
    };

    final icon = iconMap[device.iconName] ?? Icons.devices_rounded;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }

  /// 显示发送选项
  void _showSendOptions(DeviceInfo device) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _SendOptionsSheet(
        device: device,
        onSendFile: () => _pickAndSendFile(device),
      ),
    );
  }

  /// 选择并发送文件
  Future<void> _pickAndSendFile(DeviceInfo device) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      final fileSize = await File(path).length();

      await widget.controller.sendFileToDevice(
        target: device,
        filePath: path,
        fileName: file.name,
        fileSize: fileSize,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在向 ${device.name} 发送 ${file.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// 脉冲雷达动画 - 低功耗的静态脉冲效果
class _PulseRadar extends StatefulWidget {
  const _PulseRadar();

  @override
  State<_PulseRadar> createState() => _PulseRadarState();
}

class _PulseRadarState extends State<_PulseRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primaryBlue.withValues(
                alpha: 0.6 * (1 - _controller.value),
              ),
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.radar_rounded,
              size: 24,
              color: AppTheme.primaryBlue.withValues(
                alpha: 0.4 + 0.6 * _controller.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 发送选项底部弹窗
class _SendOptionsSheet extends StatelessWidget {
  final DeviceInfo device;
  final VoidCallback onSendFile;

  const _SendOptionsSheet({
    required this.device,
    required this.onSendFile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.send_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '发送到 ${device.name}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${device.typeLabel} · ${device.ip}',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textGrey,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onSendFile();
              },
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('选择文件发送'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textGrey,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}