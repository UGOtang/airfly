import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device_info.dart';
import '../models/transfer_item.dart';

/// 文件传输服务
/// 使用TCP进行文件传输
class FileTransferService {
  static const int transferPort = 53318;

  ServerSocket? _serverSocket;
  bool _isRunning = false;

  /// 传输项列表
  final List<TransferItem> _transfers = [];

  /// 传输列表变化回调
  ValueChanged<List<TransferItem>>? onTransfersChanged;

  /// 收到文件请求回调
  void Function(TransferItem item, DeviceInfo sender)? onFileRequest;

  /// 获取传输列表
  List<TransferItem> get transfers => List.unmodifiable(_transfers);

  /// 启动传输服务
  Future<void> start() async {
    if (_isRunning) return;

    // Web 平台不支持 TCP ServerSocket
    if (kIsWeb) {
      debugPrint('Web平台不支持TCP文件接收，请使用桌面或移动版本');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        transferPort,
        shared: true,
      );

      _serverSocket!.listen(_handleConnection);
      _isRunning = true;
      debugPrint('文件传输服务已启动: 端口 $transferPort');
    } catch (e) {
      debugPrint('启动文件传输服务失败: $e');
      _isRunning = false;
    }
  }

  /// 停止传输服务
  void stop() {
    _isRunning = false;
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('文件传输服务已停止');
  }

  /// 处理新连接
  void _handleConnection(Socket socket) {
    debugPrint('收到连接: ${socket.remoteAddress.address}');
    socket.listen(
      (data) => _handleData(socket, data),
      onError: (error) {
        debugPrint('连接错误: $error');
        socket.close();
      },
      onDone: () {
        socket.close();
      },
    );
  }

  /// 处理接收到的数据
  void _handleData(Socket socket, List<int> data) {
    try {
      final message = utf8.decode(data);
      final json = jsonDecode(message) as Map<String, dynamic>;

      switch (json['type']) {
        case 'file_request':
          _handleFileRequest(socket, json);
          break;
        case 'file_accept':
          _handleFileAccept(socket, json);
          break;
        case 'file_reject':
          _handleFileReject(socket, json);
          break;
        case 'file_data':
          _handleFileData(socket, json);
          break;
        case 'file_complete':
          _handleFileComplete(socket, json);
          break;
        case 'file_error':
          _handleFileError(socket, json);
          break;
        default:
          debugPrint('未知消息类型: ${json['type']}');
      }
    } catch (e) {
      debugPrint('解析传输消息失败: $e');
    }
  }

  /// 处理文件请求
  void _handleFileRequest(Socket socket, Map<String, dynamic> json) {
    final senderJson = json['sender'] as Map<String, dynamic>;
    final sender = DeviceInfo.fromJson(senderJson);
    final fileName = json['fileName'] as String? ?? '未知文件';
    final fileSize = json['fileSize'] as int? ?? 0;

    final item = TransferItem(
      id: json['transferId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: fileName,
      fileSize: fileSize,
      direction: TransferDirection.receive,
      peerName: sender.name,
      peerIp: socket.remoteAddress.address,
      startTime: DateTime.now(),
      status: TransferStatus.pending,
    );

    _transfers.add(item);
    onTransfersChanged?.call(_transfers);
    onFileRequest?.call(item, sender);
  }

  /// 处理文件接受
  void _handleFileAccept(Socket socket, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String?;
    final item = _findTransfer(transferId);
    if (item != null) {
      item.status = TransferStatus.transferring;
      onTransfersChanged?.call(_transfers);
    }
  }

  /// 处理文件拒绝
  void _handleFileReject(Socket socket, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String?;
    final item = _findTransfer(transferId);
    if (item != null) {
      item.status = TransferStatus.cancelled;
      item.endTime = DateTime.now();
      onTransfersChanged?.call(_transfers);
    }
  }

  /// 处理文件数据
  void _handleFileData(Socket socket, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String?;
    final item = _findTransfer(transferId);
    if (item != null) {
      item.transferredBytes = json['bytes'] as int? ?? item.transferredBytes;
      onTransfersChanged?.call(_transfers);
    }
  }

  /// 处理文件完成
  void _handleFileComplete(Socket socket, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String?;
    final item = _findTransfer(transferId);
    if (item != null) {
      item.status = TransferStatus.completed;
      item.endTime = DateTime.now();
      item.transferredBytes = item.fileSize;
      onTransfersChanged?.call(_transfers);
    }
  }

  /// 处理文件错误
  void _handleFileError(Socket socket, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String?;
    final item = _findTransfer(transferId);
    if (item != null) {
      item.status = TransferStatus.failed;
      item.error = json['error'] as String?;
      item.endTime = DateTime.now();
      onTransfersChanged?.call(_transfers);
    }
  }

  /// 查找传输项
  TransferItem? _findTransfer(String? id) {
    if (id == null) return null;
    for (final item in _transfers) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 发送文件
  Future<void> sendFile({
    required DeviceInfo target,
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    // Web 平台不支持 TCP Socket
    if (kIsWeb) {
      debugPrint('Web平台不支持TCP文件发送，请使用桌面或移动版本');
      return;
    }

    final transferId = DateTime.now().millisecondsSinceEpoch.toString();

    final item = TransferItem(
      id: transferId,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      direction: TransferDirection.send,
      peerName: target.name,
      peerIp: target.ip,
      startTime: DateTime.now(),
      status: TransferStatus.pending,
    );

    _transfers.add(item);
    onTransfersChanged?.call(_transfers);

    Socket? socket;
    try {
      socket = await Socket.connect(target.ip, transferPort, timeout: const Duration(seconds: 10));
      debugPrint('已连接到 ${target.name} (${target.ip})');

      // 发送文件请求
      final request = jsonEncode({
        'type': 'file_request',
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'sender': {
          'id': 'local',
          'name': '本机',
          'ip': '0.0.0.0',
          'port': transferPort,
          'deviceType': 'phone',
          'os': 'android',
          'version': '1.0.0',
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'isOnline': true,
        },
      });
      socket.add(utf8.encode(request));

      // 等待接受响应
      final completer = Completer<bool>();
      socket.listen(
        (data) {
          try {
            final response = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
            if (response['type'] == 'file_accept') {
              completer.complete(true);
            } else if (response['type'] == 'file_reject') {
              completer.complete(false);
            }
          } catch (_) {}
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      final accepted = await completer.future.timeout(const Duration(seconds: 30));
      if (!accepted) {
        item.status = TransferStatus.cancelled;
        item.endTime = DateTime.now();
        onTransfersChanged?.call(_transfers);
        socket.close();
        return;
      }

      // 开始传输
      item.status = TransferStatus.transferring;
      onTransfersChanged?.call(_transfers);

      final file = File(filePath);
      final fileStream = file.openRead();
      var sentBytes = 0;

      await for (final chunk in fileStream) {
        // 发送数据块
        final header = jsonEncode({
          'type': 'file_data',
          'transferId': transferId,
          'bytes': sentBytes + chunk.length,
        });
        socket.add(utf8.encode(header));
        socket.add(chunk);

        sentBytes += chunk.length;
        item.transferredBytes = sentBytes;
        onTransfersChanged?.call(_transfers);

        // 控制发送速度
        await Future.delayed(const Duration(milliseconds: 1));
      }

      // 发送完成消息
      final completeMsg = jsonEncode({
        'type': 'file_complete',
        'transferId': transferId,
      });
      socket.add(utf8.encode(completeMsg));

      item.status = TransferStatus.completed;
      item.endTime = DateTime.now();
      item.transferredBytes = fileSize;
      onTransfersChanged?.call(_transfers);

      socket.close();
      debugPrint('文件发送完成: $fileName');
    } catch (e) {
      debugPrint('文件发送失败: $e');
      item.status = TransferStatus.failed;
      item.error = e.toString();
      item.endTime = DateTime.now();
      onTransfersChanged?.call(_transfers);
      socket?.close();
    }
  }

  /// 接受文件
  void acceptFile(TransferItem item) {
    item.status = TransferStatus.transferring;
    onTransfersChanged?.call(_transfers);
  }

  /// 拒绝文件
  void rejectFile(TransferItem item) {
    item.status = TransferStatus.cancelled;
    item.endTime = DateTime.now();
    onTransfersChanged?.call(_transfers);
  }

  /// 清除传输记录
  void clearTransfers() {
    _transfers.clear();
    onTransfersChanged?.call(_transfers);
  }

  void dispose() {
    stop();
  }
}