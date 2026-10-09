import 'dart:io';
import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/compressor_service.dart';

/// Пресеты степени сжатия манги
enum CompressionPreset {
  balance, // Баланс (80%, 1440px)
  strong, // Сильное (55%, 1200px)
  extreme, // Максимальное (35%, 960px)
  custom, // Пользовательская настройка
}

extension CompressionPresetExt on CompressionPreset {
  String get title {
    switch (this) {
      case CompressionPreset.balance:
        return '⚡ Баланс (80%)';
      case CompressionPreset.strong:
        return '🚀 Сильное (55%)';
      case CompressionPreset.extreme:
        return '📦 Максимум (35%)';
      case CompressionPreset.custom:
        return '⚙️ Своё';
    }
  }

  String get description {
    switch (this) {
      case CompressionPreset.balance:
        return 'Высокая чёткость (1440px, качество 80%). До 75–80% экономии.';
      case CompressionPreset.strong:
        return 'Оптимально для экранов смартфонов (1200px, 55%). До 85–90% экономии.';
      case CompressionPreset.extreme:
        return 'Максимальное сжатие (960px, 35%). До 95% экономии памяти.';
      case CompressionPreset.custom:
        return 'Ручная настройка качества и максимального разрешения.';
    }
  }

  int get defaultQuality {
    switch (this) {
      case CompressionPreset.balance:
        return 80;
      case CompressionPreset.strong:
        return 55;
      case CompressionPreset.extreme:
        return 35;
      case CompressionPreset.custom:
        return 50;
    }
  }

  int get defaultMaxWidth {
    switch (this) {
      case CompressionPreset.balance:
        return 1440;
      case CompressionPreset.strong:
        return 1200;
      case CompressionPreset.extreme:
        return 960;
      case CompressionPreset.custom:
        return 1080;
    }
  }
}

/// Результат выбора пользователя при добавлении архивов
class AddedArchivesCompressionChoice {
  final bool shouldCompress;
  final bool deleteOriginal;
  final int quality;
  final int maxWidth;

  const AddedArchivesCompressionChoice({
    required this.shouldCompress,
    required this.deleteOriginal,
    this.quality = 55,
    this.maxWidth = 1200,
  });
}

/// Виджет выбора пресета и качества сжатия
class CompressionSettingsWidget extends StatelessWidget {
  final CompressionPreset preset;
  final int quality;
  final int maxWidth;
  final ValueChanged<CompressionPreset> onPresetChanged;
  final ValueChanged<int> onQualityChanged;
  final ValueChanged<int> onMaxWidthChanged;

  const CompressionSettingsWidget({
    super.key,
    required this.preset,
    required this.quality,
    required this.maxWidth,
    required this.onPresetChanged,
    required this.onQualityChanged,
    required this.onMaxWidthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Степень сжатия страниц:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: CompressionPreset.values.map((p) {
            final isSelected = p == preset;
            return ChoiceChip(
              label: Text(p.title),
              selected: isSelected,
              selectedColor: primary.withValues(alpha: 0.25),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? primary : Colors.white70,
              ),
              side: BorderSide(
                color: isSelected ? primary : Colors.white12,
              ),
              onSelected: (_) => onPresetChanged(p),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          preset.description,
          style: TextStyle(fontSize: 11, color: Colors.amber.withValues(alpha: 0.9)),
        ),
        if (preset == CompressionPreset.custom) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Качество WebP:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text('$quality%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              thumbColor: primary,
              activeTrackColor: primary,
              inactiveTrackColor: Colors.white12,
              trackHeight: 4,
            ),
            child: Slider(
              value: quality.toDouble(),
              min: 15,
              max: 90,
              divisions: 15,
              onChanged: (val) => onQualityChanged(val.toInt()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Макс. ширина:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              DropdownButton<int>(
                value: maxWidth,
                dropdownColor: const Color(0xFF222631),
                isDense: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 1440, child: Text('1440 px')),
                  DropdownMenuItem(value: 1200, child: Text('1200 px')),
                  DropdownMenuItem(value: 960, child: Text('960 px')),
                  DropdownMenuItem(value: 720, child: Text('720 px')),
                ],
                onChanged: (val) {
                  if (val != null) onMaxWidthChanged(val);
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Диалог с предложением сжать добавленные zip/cbz архивы
class PromptCompressAddedDialog extends StatefulWidget {
  final List<String> filePaths;
  final String? title;

  const PromptCompressAddedDialog({
    super.key,
    required this.filePaths,
    this.title,
  });

  static Future<AddedArchivesCompressionChoice?> show(
    BuildContext context, {
    required List<String> filePaths,
    String? title,
  }) {
    return showDialog<AddedArchivesCompressionChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PromptCompressAddedDialog(
        filePaths: filePaths,
        title: title,
      ),
    );
  }

  @override
  State<PromptCompressAddedDialog> createState() => _PromptCompressAddedDialogState();
}

class _PromptCompressAddedDialogState extends State<PromptCompressAddedDialog> {
  bool _deleteOriginal = true;
  CompressionPreset _preset = CompressionPreset.strong;
  late int _quality;
  late int _maxWidth;

  @override
  void initState() {
    super.initState();
    _quality = _preset.defaultQuality;
    _maxWidth = _preset.defaultMaxWidth;
  }

  int _calculateTotalBytes() {
    int total = 0;
    for (final p in widget.filePaths) {
      final f = File(p);
      if (f.existsSync()) {
        total += f.lengthSync();
      }
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 МБ';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final totalBytes = _calculateTotalBytes();

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
          Expanded(
            child: Text(
              widget.title ??
                  (widget.filePaths.length == 1
                      ? 'Сжать добавленный архив?'
                      : 'Сжать добавленные архивы?'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.filePaths.length == 1
                        ? 'Размер архива:'
                        : 'Выбрано архивов (${widget.filePaths.length}):',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  Text(
                    _formatBytes(totalBytes),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CompressionSettingsWidget(
              preset: _preset,
              quality: _quality,
              maxWidth: _maxWidth,
              onPresetChanged: (p) {
                setState(() {
                  _preset = p;
                  if (p != CompressionPreset.custom) {
                    _quality = p.defaultQuality;
                    _maxWidth = p.defaultMaxWidth;
                  }
                });
              },
              onQualityChanged: (q) => setState(() => _quality = q),
              onMaxWidthChanged: (w) => setState(() => _maxWidth = w),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_shared_rounded, color: primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Каталог сохранения: Загрузки/NeManga\n(виден в проводнике Android)',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _deleteOriginal,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.redAccent,
              title: const Text(
                'Удалить оригинальный zip-архив',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Освободит ${_formatBytes(totalBytes)} памяти устройства',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              onChanged: (val) {
                setState(() {
                  _deleteOriginal = val ?? true;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              const AddedArchivesCompressionChoice(
                shouldCompress: false,
                deleteOriginal: false,
              ),
            );
          },
          child: const Text('Добавить без сжатия', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            Navigator.pop(
              context,
              AddedArchivesCompressionChoice(
                shouldCompress: true,
                deleteOriginal: _deleteOriginal,
                quality: _quality,
                maxWidth: _maxWidth,
              ),
            );
          },
          child: const Text('Сжать и добавить'),
        ),
      ],
    );
  }
}

/// Диалог сжатия одной книги/главы
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
  bool _deleteOriginal = true;
  CompressionPreset _preset = CompressionPreset.strong;
  late int _quality;
  late int _maxWidth;
  CompressionResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quality = _preset.defaultQuality;
    _maxWidth = _preset.defaultMaxWidth;
  }

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
        maxWidth: _maxWidth,
        quality: _quality,
        saveToPublicFolder: true,
        deleteOriginal: _deleteOriginal,
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
      content: SingleChildScrollView(
        child: Column(
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Размер исходного архива:', style: TextStyle(color: Colors.grey)),
                    Text(
                      _formatBytes(widget.book.fileSize),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CompressionSettingsWidget(
                preset: _preset,
                quality: _quality,
                maxWidth: _maxWidth,
                onPresetChanged: (p) {
                  setState(() {
                    _preset = p;
                    if (p != CompressionPreset.custom) {
                      _quality = p.defaultQuality;
                      _maxWidth = p.defaultMaxWidth;
                    }
                  });
                },
                onQualityChanged: (q) => setState(() => _quality = q),
                onMaxWidthChanged: (w) => setState(() => _maxWidth = w),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_shared_rounded, color: primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Каталог сохранения: Загрузки/NeManga\n(виден в проводнике Android)',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _deleteOriginal,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.redAccent,
                title: const Text(
                  'Удалить оригинальный архив',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Освободит ${_formatBytes(widget.book.fileSize)} памяти устройства',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                onChanged: (val) {
                  setState(() {
                    _deleteOriginal = val ?? true;
                  });
                },
              ),
            ],
            if (_isCompressing) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Аппаратное сжатие страниц в WebP...',
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.greenAccent,
                          ),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Освобождено:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '${_result!.savedBytesFormatted} (-${_result!.savedPercent.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Сохранен в: ${_result!.targetPath}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    if (_deleteOriginal) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Оригинальный архив заменен для освобождения памяти.',
                        style: TextStyle(fontSize: 11, color: Colors.greenAccent),
                      ),
                    ],
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

/// Диалог пакетного сжатия всех глав манги
class BatchCompressDialog extends StatefulWidget {
  final MangaGroup group;
  final VoidCallback onCompressed;

  const BatchCompressDialog({
    super.key,
    required this.group,
    required this.onCompressed,
  });

  static Future<void> show(
    BuildContext context, {
    required MangaGroup group,
    required VoidCallback onCompressed,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => BatchCompressDialog(group: group, onCompressed: onCompressed),
    );
  }

  @override
  State<BatchCompressDialog> createState() => _BatchCompressDialogState();
}

class _BatchCompressDialogState extends State<BatchCompressDialog> {
  bool _isCompressing = false;
  bool _deleteOriginal = true;
  CompressionPreset _preset = CompressionPreset.strong;
  late int _quality;
  late int _maxWidth;
  String _currentStepText = '';
  double _progress = 0.0;
  int _totalOriginal = 0;
  int _totalCompressed = 0;
  int _compressedCount = 0;
  bool _isFinished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quality = _preset.defaultQuality;
    _maxWidth = _preset.defaultMaxWidth;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 МБ';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  List<ChapterItem> get _uncompressedChapters =>
      widget.group.chapters.where((c) => !c.isOptimized).toList();

  int get _uncompressedTotalBytes {
    int total = 0;
    for (final c in _uncompressedChapters) {
      final f = File(c.filePath);
      if (f.existsSync()) {
        total += f.lengthSync();
      } else {
        total += c.fileSize;
      }
    }
    return total;
  }

  Future<void> _startBatchCompression() async {
    final targets = _uncompressedChapters;
    if (targets.isEmpty) return;

    setState(() {
      _isCompressing = true;
      _isFinished = false;
      _error = null;
      _totalOriginal = 0;
      _totalCompressed = 0;
      _compressedCount = 0;
      _progress = 0.0;
    });

    try {
      for (int i = 0; i < targets.length; i++) {
        if (!mounted) break;
        final ch = targets[i];
        setState(() {
          _progress = (i + 1) / targets.length;
          _currentStepText = 'Сжатие ${i + 1} из ${targets.length}: ${ch.title}...';
        });

        final res = await CompressorService.compressArchive(
          sourcePath: ch.filePath,
          subFolder: widget.group.title,
          maxWidth: _maxWidth,
          quality: _quality,
          saveToPublicFolder: true,
          deleteOriginal: _deleteOriginal,
        );

        _totalOriginal += res.originalSize;
        _totalCompressed += res.compressedSize;
        _compressedCount++;
      }

      if (mounted) {
        setState(() {
          _isCompressing = false;
          _isFinished = true;
        });
        widget.onCompressed();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCompressing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final uncompressed = _uncompressedChapters;
    final totalBytes = _uncompressedTotalBytes;

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
              'Сжать главы манги',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            if (!_isCompressing && !_isFinished) ...[
              if (uncompressed.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Все главы этой манги уже сжаты в WebP.',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                  ),
                ),
              ] else ...[
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
                          const Text('Глав к сжатию:',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                          Text('${uncompressed.length} из ${widget.group.chapters.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Исходный объём:',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                          Text(_formatBytes(totalBytes),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CompressionSettingsWidget(
                  preset: _preset,
                  quality: _quality,
                  maxWidth: _maxWidth,
                  onPresetChanged: (p) {
                    setState(() {
                      _preset = p;
                      if (p != CompressionPreset.custom) {
                        _quality = p.defaultQuality;
                        _maxWidth = p.defaultMaxWidth;
                      }
                    });
                  },
                  onQualityChanged: (q) => setState(() => _quality = q),
                  onMaxWidthChanged: (w) => setState(() => _maxWidth = w),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_shared_rounded, color: primary, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Каталог сохранения: Загрузки/NeManga\n(виден в проводнике Android)',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _deleteOriginal,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.redAccent,
                  title: const Text(
                    'Удалить оригинальные архивы',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Освободит ${_formatBytes(totalBytes)} памяти устройства',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _deleteOriginal = val ?? true;
                    });
                  },
                ),
              ],
            ],
            if (_isCompressing) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: primary,
                  backgroundColor: Colors.white12,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _currentStepText,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (_isFinished) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
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
                          'Все главы успешно сжаты!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Сжато глав:', style: TextStyle(color: Colors.grey)),
                        Text('$_compressedCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Было:', style: TextStyle(color: Colors.grey)),
                        Text(_formatBytes(_totalOriginal)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Стало:', style: TextStyle(color: Colors.grey)),
                        Text(
                          _formatBytes(_totalCompressed),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Освобождено:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          _formatBytes(_totalOriginal - _totalCompressed),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Сохранено в каталог: Загрузки/NeManga',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
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
      ),
      actions: [
        if (!_isCompressing && !_isFinished) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          if (uncompressed.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startBatchCompression,
              child: Text('Сжать (${uncompressed.length})'),
            ),
        ],
        if (_isFinished) ...[
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
      ],
    );
  }
}
