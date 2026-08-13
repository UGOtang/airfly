/// 局域网设备信息模型
class DeviceInfo {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String deviceType;
  final String os;
  final String version;
  final DateTime lastSeen;
  final bool isOnline;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.deviceType,
    required this.os,
    required this.version,
    required this.lastSeen,
    this.isOnline = true,
  });

  DeviceInfo copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? deviceType,
    String? os,
    String? version,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      deviceType: deviceType ?? this.deviceType,
      os: os ?? this.os,
      version: version ?? this.version,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'deviceType': deviceType,
      'os': os,
      'version': version,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
      'isOnline': isOnline,
    };
  }

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未知设备',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      deviceType: json['deviceType'] as String? ?? 'unknown',
      os: json['os'] as String? ?? 'unknown',
      version: json['version'] as String? ?? '1.0.0',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        json['lastSeen'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isOnline: json['isOnline'] as bool? ?? true,
    );
  }

  /// 获取设备类型图标
  String get iconName {
    switch (deviceType) {
      case 'phone':
        return 'smartphone';
      case 'tablet':
        return 'tablet';
      case 'desktop':
        return 'desktop';
      case 'laptop':
        return 'laptop';
      default:
        return 'devices';
    }
  }

  /// 获取设备类型显示名称
  String get typeLabel {
    switch (deviceType) {
      case 'phone':
        return '手机';
      case 'tablet':
        return '平板';
      case 'desktop':
        return '电脑';
      case 'laptop':
        return '笔记本';
      default:
        return '设备';
    }
  }
}