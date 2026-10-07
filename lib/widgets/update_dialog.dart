import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'Загрузка обновления...';
      _errorMessage = null;
    });

    try {
      final result = await UpdateService.downloadAndInstall(
        update: widget.updateInfo,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText =
                  '${(progress * 100).toInt()}% (${_formatBytes(downloaded)} / ${_formatBytes(total)})';
            });
          }
        },
      );

      if (!mounted) return;

      if (result == 'pendingPermission') {
        setState(() {
          _statusText = 'Требуется разрешение на установку APK';
        });
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Ошибка установки: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E222A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.system_update_rounded, color: primary, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Обновление NeManga',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Текущая: v${UpdateService.currentVersion}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Icon(Icons.arrow_forward, size: 16, color: primary),
                Text(
                  'Новая: v${widget.updateInfo.version}',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (widget.updateInfo.fileSize > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Размер: ${_formatBytes(widget.updateInfo.fileSize)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Что нового:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: primary,
                backgroundColor: Colors.white12,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _statusText,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _startUpdate,
            child: const Text('Обновить'),
          ),
        ],
      ],
    );
  }
}
