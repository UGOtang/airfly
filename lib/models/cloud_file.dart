// 云空间内的共享文件（服务端落盘存储，支持离线上传/稍后下载）。

class CloudFile {
  final String id;
  final String name;
  final int size;
  final int uploadedBytes;
  final bool complete;
  final String ownerDeviceId;
  final String ownerDeviceName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const CloudFile({
    required this.id,
    required this.name,
    required this.size,
    required this.uploadedBytes,
    required this.complete,
    required this.ownerDeviceId,
    required this.ownerDeviceName,
    required this.createdAt,
    required this.expiresAt,
  });

  factory CloudFile.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    return CloudFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'unnamed',
      size: asInt(json['size']),
      uploadedBytes: asInt(json['uploadedBytes']),
      complete: json['complete'] == true,
      ownerDeviceId: json['ownerDeviceId'] as String? ?? '',
      ownerDeviceName: json['ownerDeviceName'] as String? ?? '未知设备',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        asInt(json['createdAt']),
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        asInt(json['expiresAt']),
      ),
    );
  }

  double get progress {
    if (size <= 0) return 0;
    return (uploadedBytes / size).clamp(0.0, 1.0);
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get fileIcon {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'heic':
        return 'image';
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
        return 'video';
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return 'music';
      case 'pdf':
        return 'picture_as_pdf';
      case 'doc':
      case 'docx':
        return 'description';
      case 'xls':
      case 'xlsx':
      case 'csv':
        return 'table_chart';
      case 'ppt':
      case 'pptx':
        return 'slideshow';
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return 'folder_zip';
      case 'txt':
      case 'md':
        return 'article';
      case 'apk':
        return 'android';
      case 'exe':
      case 'msi':
        return 'desktop_windows';
      default:
        return 'insert_drive_file';
    }
  }
}

/// 本地上传/下载任务状态（仅客户端维护，不上传服务端）。
enum TransferState { queued, active, paused, done, failed, cancelled }

class TransferTask {
  final String key; // upload:fileId 或 download:fileId
  final String fileId;
  final String fileName;
  int total;
  final bool isUpload;
  int done;
  TransferState state;
  String? error;
  String? savedPath;

  TransferTask({
    required this.key,
    required this.fileId,
    required this.fileName,
    required this.total,
    required this.isUpload,
    this.done = 0,
    this.state = TransferState.queued,
    this.error,
    this.savedPath,
  });

  double get progress {
    if (total <= 0) return 0;
    return (done / total).clamp(0.0, 1.0);
  }

  /// 是否可一键打开：已完成的下载且本地路径有效。
  /// 上传任务不开放（源文件可能已被用户移走，且语义是“发送”）。
  bool get canOpen =>
      !isUpload &&
      state == TransferState.done &&
      (savedPath?.isNotEmpty ?? false);
}
