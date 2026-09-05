// 云空间内的在线设备（服务端 presence 广播）。

class DeviceInfo {
  final String id;
  final String name;
  final String platform;
  final DateTime connectedAt;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.connectedAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未知设备',
      platform: json['platform'] as String? ?? 'unknown',
      connectedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['connectedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'connectedAt': connectedAt.millisecondsSinceEpoch,
      };

  /// 平台 → 显示名。
  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'android':
        return '安卓';
      case 'ios':
        return 'iPhone';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      case 'web':
        return '网页';
      default:
        return platform;
    }
  }

  /// 兼容旧 UI 的设备类型（由平台推导）。
  String get deviceType {
    switch (platform.toLowerCase()) {
      case 'android':
      case 'ios':
        return 'phone';
      case 'macos':
        return 'laptop';
      case 'web':
        return 'desktop';
      default:
        return 'desktop';
    }
  }

  String get typeLabel {
    switch (deviceType) {
      case 'phone':
        return '手机';
      case 'tablet':
        return '平板';
      case 'laptop':
        return '笔记本';
      case 'desktop':
        return '电脑';
      default:
        return '设备';
    }
  }

  String get iconName {
    switch (deviceType) {
      case 'phone':
        return 'smartphone';
      case 'tablet':
        return 'tablet';
      case 'laptop':
        return 'laptop';
      case 'desktop':
        return 'desktop';
      default:
        return 'devices';
    }
  }
}
