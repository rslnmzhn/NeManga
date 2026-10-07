import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/compressor_service.dart';

class CompressDialog extends StatefulWidget {
  final BookMetadata book;
  final VoidCallback onCompressed;

  const CompressDialog({
    super.key,
    required this.book,
    required this.onCompressed,
  });

  static Future<void> show(
    BuildContext context, {
    required BookMetadata book,
    required VoidCallback onCompressed,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => CompressDialog(book: book, onCompressed: onCompressed),
    );
  }

  @override
  State<CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<CompressDialog> {
  bool _isCompressing = false;
  CompressionResult? _result;
  String? _error;

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

  Future<void> _startCompression() async {
    setState(() {
      _isCompressing = true;
      _error = null;
    });

    try {
      final res = await CompressorService.compressArchive(
        sourcePath: widget.book.filePath,
        maxWidth: 1440,
        quality: 80,
        replaceOriginal: true,
      );

      setState(() {
        _isCompressing = false;
        _result = res;
      });
      widget.onCompressed();
    } catch (e) {
      setState(() {
        _isCompressing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AlertDialog(
      backgroundColor: const Color(0xFF1B1E26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.speed_rounded, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Сжать архив манги',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_result == null && !_isCompressing) ...[
            Text(
              widget.book.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Текущий размер архива:', style: TextStyle(color: Colors.grey)),
                      Text(
                        _formatBytes(widget.book.fileSize),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (widget.book.isOptimized) ...[
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Статус:', style: TextStyle(color: Colors.grey)),
                        Text('Уже сжат (WebP)', style: TextStyle(color: Colors.greenAccent)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Нативный компрессор конвертирует сканы в оптимизированный WebP (до 1440p) с аппаратным кодированием Android. Это освободит до 70–85% памяти архива и кэша.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
          ],
          if (_isCompressing) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Аппаратное сжатие страниц...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          ],
          if (_result != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.greenAccent, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Архив успешно сжат!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.greenAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Было:', style: TextStyle(color: Colors.grey)),
                      Text(_formatBytes(_result!.originalSize)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Стало:', style: TextStyle(color: Colors.grey)),
                      Text(
                        _formatBytes(_result!.compressedSize),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Освобождено:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${_result!.savedBytesFormatted} (-${_result!.savedPercent.toStringAsFixed(0)}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              'Ошибка: $_error',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (_result == null && !_isCompressing) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _startCompression,
            child: const Text('Сжать'),
          ),
        ],
        if (_result != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Отлично'),
          ),
      ],
    );
  }
}
