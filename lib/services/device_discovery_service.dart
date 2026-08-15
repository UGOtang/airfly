import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device_info.dart';

/// 设备发现服务
/// 使用UDP广播进行局域网设备发现
/// 采用自适应广播间隔以降低功耗
class DeviceDiscoveryService {
  static const int discoveryPort = 53317;

  // 自适应广播间隔（秒）
  static const int activeInterval = 3; // 活跃时快速发现
  static const int idleInterval = 15; // 空闲时降低功耗
  static const int deviceTimeout = 30; // 设备超时时间（秒）
  static const int cleanupInterval = 15; // 清理间隔（秒）

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;
  bool _isPaused = false;

  final Map<String, DeviceInfo> _devices = {};
  final List<DeviceInfo> _deviceList = [];

  /// 本机设备信息
  DeviceInfo? _localDevice;

  /// 设备列表变化回调
  ValueChanged<List<DeviceInfo>>? onDevicesChanged;

  /// 本机设备信息
  DeviceInfo? get localDevice => _localDevice;

  /// 获取设备列表
  List<DeviceInfo> get devices => List.unmodifiable(_deviceList);

  /// 启动发现服务
  Future<void> start({
    required String deviceName,
    required String deviceType,
    required String os,
    required String version,
  }) async {
    if (_isRunning) return;

    // Web 平台不支持 UDP socket 和网络接口访问
    if (kIsWeb) {
      debugPrint('Web平台不支持UDP设备发现，请使用桌面或移动版本');
      return;
    }

    try {
      // 获取本机IP
      final localIp = await _getLocalIp();
      if (localIp == null) {
        debugPrint('无法获取本机IP地址');
        return;
      }

      // 创建本机设备信息
      _localDevice = DeviceInfo(
        id: _generateDeviceId(),
        name: deviceName,
        ip: localIp,
        port: discoveryPort,
        deviceType: deviceType,
        os: os,
        version: version,
        lastSeen: DateTime.now(),
      );

      // 创建UDP socket
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.broadcastEnabled = true;
      _isRunning = true;

      // 监听广播消息
      _socket!.listen(_handleDatagram);

      // 启动自适应定时广播
      _startBroadcastTimer();

      // 启动设备清理
      _cleanupTimer = Timer.periodic(
        Duration(seconds: cleanupInterval),
        (_) => _cleanupOfflineDevices(),
      );

      // 立即广播一次
      _broadcastPresence();

      debugPrint('设备发现服务已启动: $localIp:$discoveryPort');
    } catch (e) {
      debugPrint('启动设备发现服务失败: $e');
      _isRunning = false;
    }
  }

  /// 启动自适应广播定时器
  void _startBroadcastTimer() {
    _broadcastTimer?.cancel();
    final interval = _devices.isEmpty ? idleInterval : activeInterval;
    _broadcastTimer = Timer.periodic(
      Duration(seconds: interval),
      (_) => _broadcastPresence(),
    );
  }

  /// 暂停发现（应用进入后台时调用）
  void pause() {
    if (!_isRunning || _isPaused) return;
    _isPaused = true;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    debugPrint('设备发现服务已暂停');
  }

  /// 恢复发现（应用回到前台时调用）
  void resume() {
    if (!_isRunning || !_isPaused) return;
    _isPaused = false;
    _startBroadcastTimer();
    _broadcastPresence();
    debugPrint('设备发现服务已恢复');
  }

  /// 停止发现服务
  void stop() {
    _isRunning = false;
    _isPaused = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    _deviceList.clear();
    debugPrint('设备发现服务已停止');
  }

  /// 获取本机IP地址
  Future<String?> _getLocalIp() async {
    // Web 平台不支持网络接口访问
    if (kIsWeb) return null;

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // 跳过虚拟网卡和回环地址
          if (addr.address.startsWith('127.') ||
              addr.address.startsWith('169.254') ||
              addr.address.startsWith('0.')) {
            continue;
          }
          return addr.address;
        }
      }
    } catch (e) {
      debugPrint('获取本机IP失败: $e');
    }
    return null;
  }

  /// 生成设备ID
  String _generateDeviceId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch}';
  }

  /// 广播本机存在（带随机抖动避免多设备同步广播）
  void _broadcastPresence() {
    if (_socket == null || _localDevice == null || _isPaused) return;

    try {
      final message = jsonEncode({
        'type': 'presence',
        'device': _localDevice!.toJson(),
      });

      final data = utf8.encode(message);
      _socket!.send(
        data,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (e) {
      debugPrint('广播失败: $e');
    }
  }

  /// 处理接收到的数据报
  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;

      if (json['type'] != 'presence') return;

      final deviceJson = json['device'] as Map<String, dynamic>;
      final device = DeviceInfo.fromJson(deviceJson);

      // 忽略本机
      if (device.id == _localDevice?.id) return;

      // 更新设备信息
      final updated = device.copyWith(
        ip: datagram.address.address,
        lastSeen: DateTime.now(),
        isOnline: true,
      );

      final existing = _devices[updated.id];
      if (existing == null) {
        _devices[updated.id] = updated;
        _deviceList.add(updated);
        debugPrint('发现新设备: ${updated.name} (${updated.ip})');
        // 有新设备时切换到活跃广播模式
        _startBroadcastTimer();
      } else {
        final index = _deviceList.indexOf(existing);
        if (index >= 0) {
          _deviceList[index] = updated;
        }
        _devices[updated.id] = updated;
      }

      onDevicesChanged?.call(_deviceList);
    } catch (e) {
      debugPrint('解析设备消息失败: $e');
    }
  }

  /// 清理离线设备
  void _cleanupOfflineDevices() {
    final now = DateTime.now();
    final offlineDevices = <DeviceInfo>[];

    for (final device in _deviceList) {
      final diff = now.difference(device.lastSeen).inSeconds;
      if (diff > deviceTimeout) {
        offlineDevices.add(device);
      }
    }

    if (offlineDevices.isNotEmpty) {
      for (final device in offlineDevices) {
        _devices.remove(device.id);
        _deviceList.remove(device);
        debugPrint('设备离线: ${device.name}');
      }
      // 设备减少时切回空闲广播模式
      if (_devices.isEmpty) {
        _startBroadcastTimer();
      }
      onDevicesChanged?.call(_deviceList);
    }
  }

  /// 检查服务是否运行中
  bool get isRunning => _isRunning;

  /// 手动刷新设备列表
  void refresh() {
    _broadcastPresence();
  }

  void dispose() {
    stop();
  }
}