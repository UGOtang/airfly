import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/device_info.dart';
import '../theme/app_theme.dart';

/// 同空间在线设备（云中转 presence，不再依赖局域网广播）。
class DevicesScreen extends StatelessWidget {
  final AppController controller;

  const DevicesScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final devices = controller.service.devices;
              if (!controller.service.isConnected) {
                return _buildOfflineHint(context);
              }
              if (devices.isEmpty) {
                return _buildEmptyState(context);
              }
              return RefreshIndicator(
                onRefresh: () => controller.refreshFiles(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: devices.length,
                  itemBuilder: (context, i) =>
                      _buildDeviceCard(context, devices[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
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
              Icons.devices_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '在线设备',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.of(context).text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    controller.spaceId.isEmpty
                        ? '未加入空间'
                        : '空间 ${controller.spaceId} · ${controller.service.devices.length} 台在线',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.of(context).sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              controller.refreshFiles();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在刷新…'),
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

  Widget _buildOfflineHint(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                Icons.cloud_off_rounded,
                size: 56,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '尚未连接到云端',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppPalette.of(context).text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '去「设置」填写服务端地址和空间码\n同一空间码的设备会自动在这里相见',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppPalette.of(context).sub,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => controller.connect(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('立即连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
            Text(
              '空间里只有你',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppPalette.of(context).text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在其他设备安装 AirFly\n填入相同的服务端地址和空间码即可加入',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppPalette.of(context).sub,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, DeviceInfo device) {
    final isMine = device.id == controller.deviceId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: CardDecoration.softOf(
        context,
        borderColor: isMine
            ? AppTheme.primaryBlue.withValues(alpha: 0.4)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildAvatar(device),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.of(context).text,
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '本机',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.of(context).strong,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '在线',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        device.platformLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPalette.of(context).sub,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(DeviceInfo device) {
    const map = {
      'smartphone': Icons.smartphone_rounded,
      'tablet': Icons.tablet_rounded,
      'desktop': Icons.desktop_windows_rounded,
      'laptop': Icons.laptop_rounded,
      'devices': Icons.devices_rounded,
    };
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        map[device.iconName] ?? Icons.devices_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}
