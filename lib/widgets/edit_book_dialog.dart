import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/storage_service.dart';

class EditBookDialog extends StatefulWidget {
  final BookMetadata book;
  final VoidCallback onSaved;

  const EditBookDialog({
    super.key,
    required this.book,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required BookMetadata book,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => EditBookDialog(book: book, onSaved: onSaved),
    );
  }

  @override
  State<EditBookDialog> createState() => _EditBookDialogState();
}

class _EditBookDialogState extends State<EditBookDialog> {
  late TextEditingController _titleController;
  final TextEditingController _tagInputController = TextEditingController();
  late List<String> _tags;
  late ReadingStatus _status;
  List<String> _libraryTags = [];

  static const List<String> _genrePresets = [
    'Сёнэн',
    'Сэйнэн',
    'Сёдзё',
    'Романтика',
    'Комедия',
    'Экшен',
    'Фэнтези',
    'Драма',
    'Исекай',
    'Повседневность',
    'Мистика',
    'Хоррор',
    'Детектив',
    'Психология',
    'Триллер',
    'Научная фантастика',
    'Приключения',
    'Меха',
    'Сверхъестественное',
    'Боевик',
    'Этти',
    'Киберпанк',
    'Школа',
    'Спорт',
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _tags = List.from(widget.book.tags);
    _status = widget.book.status;
    _loadLibraryTags();
  }

  Future<void> _loadLibraryTags() async {
    final tags = await StorageService.getAllTags();
    if (mounted) {
      setState(() {
        _libraryTags = tags;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag(String rawTag) {
    final clean = rawTag.trim();
    if (clean.isNotEmpty && !_tags.contains(clean)) {
      setState(() {
        _tags.add(clean);
      });
      _tagInputController.clear();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _save() async {
    final newTitle = _titleController.text.trim();
    final updated = widget.book.copyWith(
      title: newTitle.isNotEmpty ? newTitle : widget.book.title,
      tags: _tags,
      status: _status,
    );
    await StorageService.updateBook(updated);
    widget.onSaved();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    // Теги, которые уже есть в других книгах библиотеки, но еще не добавлены в эту
    final availableLibraryTags = _libraryTags.where((t) => !_tags.contains(t)).toList();
    // Популярные жанры манги, которых еще нет ни в этой книге, ни среди тегов библиотеки
    final availableGenrePresets = _genrePresets.where((g) => !_tags.contains(g) && !_libraryTags.contains(g)).toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1B1E26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Редактировать мангу',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Название манги
            const Text(
              'Название',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Введите название',
                filled: true,
                fillColor: const Color(0xFF242833),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Статус чтения
            const Text(
              'Статус чтения',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusChip(ReadingStatus.reading, 'Читаю', primary),
                  const SizedBox(width: 8),
                  _buildStatusChip(ReadingStatus.planned, 'В планах', Colors.amber),
                  const SizedBox(width: 8),
                  _buildStatusChip(ReadingStatus.completed, 'Прочитано', Colors.greenAccent),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Теги и жанры
            const Text(
              'Теги и жанры',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputController,
                    onSubmitted: _addTag,
                    decoration: InputDecoration(
                      hintText: 'Добавить свой тег...',
                      filled: true,
                      fillColor: const Color(0xFF242833),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _addTag(_tagInputController.text),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Выбранные теги этой манги
            if (_tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tags.map((tag) {
                  return Chip(
                    backgroundColor: primary.withValues(alpha: 0.2),
                    side: BorderSide(color: primary.withValues(alpha: 0.4)),
                    label: Text(
                      '#$tag',
                      style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    deleteIcon: Icon(Icons.close, size: 14, color: primary),
                    onDeleted: () => _removeTag(tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // 1. Теги, уже добавленные в библиотеку
            if (availableLibraryTags.isNotEmpty) ...[
              const Text(
                'Уже добавленные в библиотеку:',
                style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: availableLibraryTags.map((tag) {
                  return ActionChip(
                    label: Text('#$tag', style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.amber.withValues(alpha: 0.12),
                    side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                    onPressed: () => _addTag(tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // 2. Популярные жанры манги
            if (availableGenrePresets.isNotEmpty) ...[
              const Text(
                'Жанры манги:',
                style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: availableGenrePresets.map((genre) {
                  return ActionChip(
                    label: Text(genre, style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: BorderSide.none,
                    onPressed: () => _addTag(genre),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
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
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildStatusChip(ReadingStatus status, String label, Color color) {
    final isSelected = _status == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.25),
      backgroundColor: const Color(0xFF242833),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? color : Colors.transparent,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _status = status;
          });
        }
      },
    );
  }
}
