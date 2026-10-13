import 'dart:io';
import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/storage_service.dart';
import 'manga_detail_screen.dart';

class AuthorDetailScreen extends StatefulWidget {
  final AuthorData author;
  final ReaderSettings settings;
  final VoidCallback onAuthorUpdated;

  const AuthorDetailScreen({
    super.key,
    required this.author,
    required this.settings,
    required this.onAuthorUpdated,
  });

  @override
  State<AuthorDetailScreen> createState() => _AuthorDetailScreenState();
}

class _AuthorDetailScreenState extends State<AuthorDetailScreen> {
  late AuthorData _currentAuthor;

  @override
  void initState() {
    super.initState();
    _currentAuthor = widget.author;
  }

  void _editTags() {
    final primary = widget.settings.accentColor.color;

    // Диалог редактирования жанров и тегов автора
    final tagController = TextEditingController();
    final currentTags = List<String>.from(_currentAuthor.tags);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1B1E26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Жанры автора: ${_currentAuthor.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Присвойте автору характерные жанры и стили:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tagController,
                          onSubmitted: (val) {
                            final parts = val
                                .split(RegExp(r'[\s,]+'))
                                .map((s) => s.trim().replaceAll(RegExp(r'^#+'), ''))
                                .where((s) => s.isNotEmpty);
                            if (parts.isNotEmpty) {
                              setDialogState(() {
                                for (final p in parts) {
                                  if (!currentTags.contains(p)) {
                                    currentTags.add(p);
                                  }
                                }
                              });
                              tagController.clear();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Добавить жанр (через пробел/запятую)...',
                            hintStyle: const TextStyle(fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF242833),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          final val = tagController.text;
                          final parts = val
                              .split(RegExp(r'[\s,]+'))
                              .map((s) => s.trim().replaceAll(RegExp(r'^#+'), ''))
                              .where((s) => s.isNotEmpty);
                          if (parts.isNotEmpty) {
                            setDialogState(() {
                              for (final p in parts) {
                                if (!currentTags.contains(p)) {
                                  currentTags.add(p);
                                }
                              }
                            });
                            tagController.clear();
                          }
                        },
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (currentTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: currentTags.map((tag) {
                        return Chip(
                          backgroundColor: primary.withValues(alpha: 0.2),
                          side: BorderSide(color: primary.withValues(alpha: 0.4)),
                          label: Text(
                            '#$tag',
                            style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          deleteIcon: Icon(Icons.close, size: 14, color: primary),
                          onDeleted: () {
                            setDialogState(() {
                              currentTags.remove(tag);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await StorageService.saveAuthorTags(_currentAuthor.name, currentTags);
                  setState(() {
                    _currentAuthor = AuthorData(
                      name: _currentAuthor.name,
                      tags: currentTags,
                      coverPath: _currentAuthor.coverPath,
                      mangaList: _currentAuthor.mangaList,
                    );
                  });
                  widget.onAuthorUpdated();
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatFileSize(int bytes) {
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
    final primary = widget.settings.accentColor.color;
    final bg = widget.settings.appTheme.backgroundColor;
    final cardBg = widget.settings.appTheme.cardColor;
    final hasCover = _currentAuthor.coverPath != null && File(_currentAuthor.coverPath!).existsSync();

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Шапка автора с обложкой из последнего архива
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: const Color(0xFF14171E),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover)
                    Image.file(
                      File(_currentAuthor.coverPath!),
                      fit: BoxFit.cover,
                    )
                  else
                    Container(color: const Color(0xFF1E222B)),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          bg.withValues(alpha: 0.85),
                          bg,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.person_rounded, color: primary, size: 24),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _currentAuthor.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_currentAuthor.totalMangaCount} тайтл(ов) • ${_currentAuthor.totalChaptersCount} глав • ${_formatFileSize(_currentAuthor.totalSizeBytes)}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Блок тегов и жанров автора
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Жанры автора:',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.label_outline_rounded, size: 16),
                        label: Text(
                          _currentAuthor.tags.isEmpty ? 'Добавить жанры' : 'Изменить',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _editTags,
                      ),
                    ],
                  ),
                  if (_currentAuthor.tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _currentAuthor.tags.map((tag) {
                        return Chip(
                          backgroundColor: primary.withValues(alpha: 0.15),
                          side: BorderSide(color: primary.withValues(alpha: 0.3)),
                          label: Text(
                            '#$tag',
                            style: TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  Text(
                    'Все тайтлы автора (${_currentAuthor.mangaList.length}):',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Сетка тайтлов автора
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.58,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final group = _currentAuthor.mangaList[index];
                  final hasMangaCover = group.coverPath != null && File(group.coverPath!).existsSync();

                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => MangaDetailScreen(
                            manga: group,
                            settings: widget.settings,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (hasMangaCover)
                                    Image.file(
                                      File(group.coverPath!),
                                      fit: BoxFit.cover,
                                    )
                                  else
                                    Container(
                                      color: const Color(0xFF1E222B),
                                      child: const Center(
                                        child: Icon(Icons.menu_book_rounded, size: 40, color: Colors.white24),
                                      ),
                                    ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${group.chapters.length} гл.',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatFileSize(group.totalSize)} • ${group.status.label}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _currentAuthor.mangaList.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
