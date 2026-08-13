/// 传输状态
enum TransferStatus {
  pending, // 等待中
  transferring, // 传输中
  completed, // 已完成
  failed, // 失败
  cancelled, // 已取消
}

/// 传输方向
enum TransferDirection {
  send, // 发送
  receive, // 接收
}

/// 文件传输项
class TransferItem {
  final String id;
  final String fileName;
  final int fileSize;
  final String? filePath;
  final TransferDirection direction;
  final String peerName;
  final String peerIp;
  final DateTime startTime;
  DateTime? endTime;
  TransferStatus status;
  int transferredBytes;
  String? error;

  TransferItem({
    required this.id,
    required this.fileName,
    required this.fileSize,
    this.filePath,
    required this.direction,
    required this.peerName,
    required this.peerIp,
    required this.startTime,
    this.endTime,
    this.status = TransferStatus.pending,
    this.transferredBytes = 0,
    this.error,
  });

  /// 传输进度 (0.0 - 1.0)
  double get progress {
    if (fileSize <= 0) return 0;
    return (transferredBytes / fileSize).clamp(0.0, 1.0);
  }

  /// 传输速度 (bytes/s)
  double get speed {
    final elapsed = DateTime.now().difference(startTime).inSeconds;
    if (elapsed <= 0) return 0;
    return transferredBytes / elapsed;
  }

  /// 格式化文件大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 格式化速度
  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// 获取状态显示文本
  String get statusLabel {
    switch (status) {
      case TransferStatus.pending:
        return '等待中';
      case TransferStatus.transferring:
        return '传输中';
      case TransferStatus.completed:
        return '已完成';
      case TransferStatus.failed:
        return '失败';
      case TransferStatus.cancelled:
        return '已取消';
    }
  }

  /// 获取文件图标
  String get fileIcon {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
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
        return 'music';
      case 'pdf':
        return 'picture_as_pdf';
      case 'doc':
      case 'docx':
        return 'description';
      case 'xls':
      case 'xlsx':
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
      default:
        return 'insert_drive_file';
    }
  }
}