import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/cloud_file.dart';
import '../theme/app_theme.dart';

/// 文件页：上传到云空间 / 从云空间下载 / 删除。
/// 文件落盘在服务端，离线上传、稍后下载都没问题。
class FilesScreen extends StatefulWidget {
  final AppController controller;

  const FilesScreen({super.key, required this.controller});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final activeTasks = c.tasks
                  .where(
                    (t) =>
                        t.state == TransferState.active ||
                        t.state == TransferState.queued ||
                        t.state == TransferState.paused,
                  )
                  .toList();
              final finishedTasks = c.tasks
                  .where(
                    (t) =>
                        t.state == TransferState.done ||
                        t.state == TransferState.failed ||
                        t.state == TransferState.cancelled,
                  )
                  .toList();
              return RefreshIndicator(
                onRefresh: () => c.refreshFiles(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (activeTasks.isNotEmpty) ...[
                      _sectionTitle('传输任务（${activeTasks.length}）'),
                      ...activeTasks.map((t) => _buildTaskCard(t)),
                      const SizedBox(height: 8),
                    ],
                    _sectionTitle('云端文件（${c.service.files.length}）'),
                    if (c.service.files.isEmpty) _buildEmptyFiles(),
                    ...c.service.files.map((f) => _buildFileCard(f)),
                    if (finishedTasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _sectionTitle('已完成 / 失败（${finishedTasks.length}）',
                          action: TextButton(
                            onPressed: () =>
                                widget.controller.clearFinishedTasks(),
                            child: const Text('清空'),
                          )),
                      ...finishedTasks.map((t) => _buildTaskCard(t)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, {Widget? action}) {
    final children = <Widget>[
      Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppPalette.of(context).text,
        ),
      ),
      const Spacer(),
    ];
    final a = action;
    if (a != null) children.add(a);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(children: children),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: CardDecoration.gradient(
              gradient: AppTheme.accentGradient,
              radius: 16,
            ),
            child: const Icon(
              Icons.folder_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '云端文件',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.of(context).text,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '同空间设备共享，支持断点续传',
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.of(context).sub),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _picking ? null : _pickAndUpload,
            icon: _picking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded, size: 18),
            label: const Text('上传'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _picking = true);
    try {
      await widget.controller.pickAndUpload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _buildEmptyFiles() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: CardDecoration.softOf(context),
      child: Column(
        children: [
          Icon(
            Icons.cloud_upload_rounded,
            size: 40,
            color: AppPalette.of(context).faint,
          ),
          const SizedBox(height: 12),
          Text(
            '云端还没有文件\n点右上「上传」，同空间设备都能下载',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppPalette.of(context).sub,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 任务卡片

  Widget _buildTaskCard(TransferTask t) {
    final color = t.isUpload
        ? AppTheme.primaryBlue
        : AppTheme.accentOrange;
    String status;
    Color statusColor;
    switch (t.state) {
      case TransferState.active:
      case TransferState.queued:
        status = t.isUpload ? '上传中' : '下载中';
        statusColor = color;
        break;
      case TransferState.paused:
        status = '已中断';
        statusColor = AppTheme.accentOrange;
        break;
      case TransferState.done:
        status = '已完成';
        statusColor = const Color(0xFF4CAF50);
        break;
      case TransferState.failed:
        status = '失败';
        statusColor = const Color(0xFFF44336);
        break;
      case TransferState.cancelled:
        status = '已取消';
        statusColor = AppPalette.of(context).faint;
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                t.isUpload
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: t.total > 0 ? t.progress : null,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.error ??
                      (t.state == TransferState.done && t.savedPath != null
                          ? '已保存：${t.savedPath}'
                          : '${CloudFile.formatSize(t.done)} / ${CloudFile.formatSize(t.total)}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).sub,
                  ),
                ),
              ),
              if (t.state == TransferState.active ||
                  t.state == TransferState.paused ||
                  t.state == TransferState.queued)
                TextButton(
                  onPressed: () =>
                      widget.controller.cancelTask(t.key),
                  child: const Text('取消'),
                ),
              if (t.state == TransferState.paused ||
                  t.state == TransferState.failed ||
                  t.state == TransferState.cancelled)
                TextButton(
                  onPressed: () => _retryTask(t),
                  child: const Text('重试'),
                ),
              if (t.state == TransferState.done ||
                  t.state == TransferState.failed ||
                  t.state == TransferState.cancelled)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '移除记录',
                  onPressed: () =>
                      widget.controller.dismissTask(t.key),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppPalette.of(context).faint,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _retryTask(TransferTask t) async {
    try {
      if (t.isUpload) {
        await widget.controller.retryUpload(t.key);
      } else {
        await widget.controller.retryDownload(t.key);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------- 云端文件卡片

  Widget _buildFileCard(CloudFile f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: CardDecoration.softOf(context),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _fileIcon(f.fileIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${CloudFile.formatSize(f.size)} · 来自 ${f.ownerDeviceName} · ${_expireLabel(f)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).sub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!f.complete) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: f.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '上传中 ${(f.progress * 100).toStringAsFixed(0)}%（${CloudFile.formatSize(f.uploadedBytes)} / ${CloudFile.formatSize(f.size)}）',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).sub,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _download(f),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('下载'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.of(context).strong,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '删除云端文件',
                  onPressed: () => _confirmDelete(f),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppPalette.of(context).faint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _expireLabel(CloudFile f) {
    final left = f.expiresAt.difference(DateTime.now());
    if (left.isNegative) return '已过期';
    if (left.inHours < 1) return '${left.inMinutes} 分钟后过期';
    if (left.inDays < 1) return '${left.inHours} 小时后过期';
    return '${left.inDays} 天后过期';
  }

  Widget _fileIcon(String name) {
    const map = {
      'image': Icons.image_rounded,
      'video': Icons.videocam_rounded,
      'music': Icons.music_note_rounded,
      'picture_as_pdf': Icons.picture_as_pdf_rounded,
      'description': Icons.description_rounded,
      'table_chart': Icons.table_chart_rounded,
      'slideshow': Icons.slideshow_rounded,
      'folder_zip': Icons.folder_zip_rounded,
      'article': Icons.article_rounded,
      'android': Icons.android_rounded,
      'desktop_windows': Icons.desktop_windows_rounded,
      'insert_drive_file': Icons.insert_drive_file_rounded,
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        map[name] ?? Icons.insert_drive_file_rounded,
        color: AppTheme.primaryBlue,
        size: 22,
      ),
    );
  }

  Future<void> _download(CloudFile f) async {
    if (kIsWeb && f.size > AppController.kWebSoftLimit) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件较大'),
          content: Text(
            '该文件 ${CloudFile.formatSize(f.size)}，Web 端下载可能因内存不足失败，建议用桌面 / 移动端下载。仍要继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.controller.startDownload(f);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始下载 ${f.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDelete(CloudFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除云端文件？'),
        content: Text('「${f.name}」将对空间内所有设备不可见，该操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.deleteCloudFile(f.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
      );
    }
  }
}
