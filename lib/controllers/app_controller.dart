import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_info.dart';
import '../models/transfer_item.dart';
import '../services/device_discovery_service.dart';
import '../services/file_transfer_service.dart';

/// 应用状态控制器
class AppController extends ChangeNotifier {
  final DeviceDiscoveryService _discoveryService = DeviceDiscoveryService();
  final FileTransferService _transferService = FileTransferService();

  List<DeviceInfo> _devices = [];
  List<TransferItem> _transfers = [];

  String _deviceName = '我的设备';
  String _deviceType = 'phone';
  String _os = 'unknown';
  final String _version = '1.0.0';

  bool _isInitialized = false;
  bool _isDiscovering = false;

  /// 待处理的文件请求
  TransferItem? _pendingRequest;
  bool _isDialogShowing = false;

  /// 获取设备列表
  List<DeviceInfo> get devices => _devices;

  /// 获取传输列表
  List<TransferItem> get transfers => _transfers;

  /// 本机设备信息
  DeviceInfo? get localDevice => _discoveryService.localDevice;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否正在发现设备
  bool get isDiscovering => _isDiscovering;

  /// 待处理的文件请求
  TransferItem? get pendingRequest => _pendingRequest;

  /// 初始化应用
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 加载设置
      final prefs = await SharedPreferences.getInstance();
      _deviceName = prefs.getString('device_name') ?? _deviceName;

      // 获取设备信息
      _detectDeviceInfo();

      // 设置回调
      _discoveryService.onDevicesChanged = (devices) {
        _devices = devices;
        notifyListeners();
      };

      _transferService.onTransfersChanged = (transfers) {
        _transfers = transfers;
        notifyListeners();
      };

      _transferService.onFileRequest = (item, sender) {
        _pendingRequest = item;
        notifyListeners();
      };

      // 启动服务（Web平台不支持时自动跳过）
      await _transferService.start();
      await _startDiscovery();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('初始化失败: $e');
    }
  }

  /// 检测设备信息
  void _detectDeviceInfo() {
    if (kIsWeb) {
      // Web 平台无法使用 dart:io 的 Platform
      _os = 'web';
      _deviceType = 'desktop';
      return;
    }

    try {
      if (Platform.isAndroid) {
        _os = 'android';
        _deviceType = 'phone';
      } else if (Platform.isIOS) {
        _os = 'ios';
        _deviceType = 'phone';
      } else if (Platform.isWindows) {
        _os = 'windows';
        _deviceType = 'desktop';
      } else if (Platform.isMacOS) {
        _os = 'macos';
        _deviceType = 'laptop';
      } else if (Platform.isLinux) {
        _os = 'linux';
        _deviceType = 'desktop';
      }
    } catch (e) {
      debugPrint('检测设备信息失败: $e');
    }
  }

  /// 启动设备发现
  Future<void> _startDiscovery() async {
    _isDiscovering = true;
    notifyListeners();

    await _discoveryService.start(
      deviceName: _deviceName,
      deviceType: _deviceType,
      os: _os,
      version: _version,
    );

    _isDiscovering = false;
    notifyListeners();
  }

  /// 刷新设备列表
  void refreshDevices() {
    _discoveryService.refresh();
  }

  /// 设置设备名称
  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);

    // 重启发现服务以更新名称
    _discoveryService.stop();
    await _startDiscovery();
    notifyListeners();
  }

  /// 选择文件并发送
  Future<void> sendFileToDevice({
    required DeviceInfo target,
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    await _transferService.sendFile(
      target: target,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  /// 接受文件请求
  void acceptFileRequest() {
    final item = _pendingRequest;
    if (item == null) return;

    _transferService.acceptFile(item);
    _pendingRequest = null;
    _isDialogShowing = false;
    notifyListeners();
  }

  /// 拒绝文件请求
  void rejectFileRequest() {
    final item = _pendingRequest;
    if (item == null) return;

    _transferService.rejectFile(item);
    _pendingRequest = null;
    _isDialogShowing = false;
    notifyListeners();
  }

  /// 检查对话框是否正在显示
  bool get isDialogShowing => _isDialogShowing;

  /// 标记对话框已显示
  void markDialogShown() {
    _isDialogShowing = true;
  }

  /// 清除传输记录
  void clearTransfers() {
    _transferService.clearTransfers();
  }

  /// 获取下载目录
  Future<Directory?> getDownloadDirectory() async {
    // Web 平台不支持文件系统目录访问
    if (kIsWeb) return null;

    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      debugPrint('获取下载目录失败: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    _transferService.dispose();
    super.dispose();
  }
}