// 共享剪切板条目。

class ClipboardItem {
  final String id;
  final String text;
  final String deviceId;
  final String deviceName;
  final DateTime updatedAt;

  const ClipboardItem({
    required this.id,
    required this.text,
    required this.deviceId,
    required this.deviceName,
    required this.updatedAt,
  });

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '未知设备',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  String get preview =>
      text.length <= 120 ? text : '${text.substring(0, 120)}…';
}
