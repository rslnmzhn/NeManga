import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/reader_models.dart';
import '../services/archive_service.dart';
import '../services/compressor_service.dart';
import '../services/storage_service.dart';
import '../widgets/compress_dialog.dart';
import '../widgets/edit_book_dialog.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final MangaGroup manga;
  final ReaderSettings settings;

  const MangaDetailScreen({
    super.key,
    required this.manga,
    required this.settings,
  });

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  late MangaGroup _manga;
  bool _isLoading = false;
  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _manga = widget.manga;
  }

  Future<void> _refresh() async {
    final groups = await StorageService.getMangaGroups();
    final updated = groups.where((g) => g.id == _manga.id).firstOrNull;
    if (updated != null && mounted) {
      setState(() {
        _manga = updated;
      });
    }
  }

  String _formatFileSize(int bytes) {
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

  Color _getStatusColor(ReadingStatus status, Color primary) {
    switch (status) {
      case ReadingStatus.reading:
        return primary;
      case ReadingStatus.planned:
        return Colors.amber;
      case ReadingStatus.completed:
        return Colors.greenAccent;
      case ReadingStatus.none:
        return Colors.grey;
    }
  }

  Future<void> _addChapters() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'cbz'],
        dialogTitle: 'Выберите архивы глав (.zip или .cbz)',
      );

      if (files.isNotEmpty) {
        final validPaths = files.map((f) => f.path).whereType<String>().toList();
        if (validPaths.isEmpty) return;

        if (!mounted) return;

        // Предлагаем сжатие добавленных глав с опцией удаления оригиналов
        final choice = await PromptCompressAddedDialog.show(
          context,
          filePaths: validPaths,
          title: 'Сжать добавленные главы?',
        );

        if (choice == null) return;

        setState(() {
          _isLoading = true;
          _loadingMessage = choice.shouldCompress ? 'Сжатие глав в WebP...' : 'Добавление глав...';
        });

        final processedPaths = <String>[];
        int totalOriginal = 0;
        int totalCompressed = 0;

        if (choice.shouldCompress) {
          for (int i = 0; i < validPaths.length; i++) {
            if (!mounted) break;
            final path = validPaths[i];
            final title = p.basenameWithoutExtension(path);
            setState(() {
              _loadingMessage = 'Сжатие ${i + 1} из ${validPaths.length}: $title...';
            });

            try {
              final res = await CompressorService.compressArchive(
                sourcePath: path,
                subFolder: _manga.title,
                quality: choice.quality,
                maxWidth: choice.maxWidth,
                saveToPublicFolder: true,
                deleteOriginal: choice.deleteOriginal,
              );
              processedPaths.add(res.targetPath);
              totalOriginal += res.originalSize;
              totalCompressed += res.compressedSize;
            } catch (e) {
              debugPrint('Ошибка сжатия $path: $e');
              processedPaths.add(path);
            }
          }

          if (mounted && totalOriginal > totalCompressed) {
            final savedBytes = totalOriginal - totalCompressed;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Сжато глав: ${processedPaths.length}. Сохранено в Загрузки/NeManga. Освобождено: ${_formatFileSize(savedBytes)}',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          processedPaths.addAll(validPaths);
        }

        final newChapters = <ChapterItem>[];
        for (final path in processedPaths) {
          final title = p.basenameWithoutExtension(path);
          final size = File(path).existsSync() ? File(path).lengthSync() : 0;
          newChapters.add(ChapterItem(
            id: path,
            filePath: path,
            title: title,
            totalPages: 0,
            lastPage: 0,
            lastReadTime: DateTime.now(),
            fileSize: size,
            isOptimized: choice.shouldCompress,
          ));
        }

        // Естественная сортировка глав по названию
        newChapters.sort((a, b) => ArchiveService.naturalCompare(a.title, b.title));

        await StorageService.addChaptersToGroup(
          groupId: _manga.id,
          newChapters: newChapters,
        );

        await _refresh();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Добавлено глав: ${newChapters.length}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка добавления: $e')),
        );
      }
    }
  }

  Future<void> _openChapter(ChapterItem chapter, int chapterIndex) async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Загрузка главы...';
    });

    try {
      final info = await ArchiveService.loadManga(chapter.filePath);

      // Обновляем метаданные о страницах
      await StorageService.findOrCreateGroupForFile(
        filePath: chapter.filePath,
        title: chapter.title,
        totalPages: info.pagePaths.length,
        currentPage: chapter.lastPage,
        coverPath: _manga.coverPath ?? info.coverPath,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ReaderScreen(
            title: '${_manga.title} — ${chapter.title}',
            archivePath: chapter.filePath,
            pagePaths: info.pagePaths,
            initialPage: chapter.lastPage,
            settings: widget.settings,
            mangaGroup: _manga,
            currentChapterIndex: chapterIndex,
          ),
        ),
      );

      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ошибка открытия главы'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _changeStatus(ReadingStatus newStatus) async {
    await StorageService.updateGroupStatus(_manga.id, newStatus);
    await _refresh();
  }

  Future<void> _compressAllChapters() async {
    final uncompressed = _manga.chapters.where((c) => !c.isOptimized).toList();
    if (uncompressed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все главы уже сжаты в WebP')),
      );
      return;
    }

    BatchCompressDialog.show(
      context,
      group: _manga,
      onCompressed: _refresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final statusColor = _getStatusColor(_manga.status, primary);
    final hasCover = _manga.coverPath != null && File(_manga.coverPath!).existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. Красивый заголовок с обложкой
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF14171E),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Размытый фон обложки
                      if (hasCover)
                        Image.file(
                          File(_manga.coverPath!),
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: const Color(0xFF1E222B)),

                      // Градиентное затемнение
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              const Color(0xFF0F1115).withValues(alpha: 0.8),
                              const Color(0xFF0F1115),
                            ],
                          ),
                        ),
                      ),

                      // Контент шапки
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Обложка
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 95,
                                height: 135,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B1E26),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: hasCover
                                    ? Image.file(
                                        File(_manga.coverPath!),
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(Icons.menu_book, color: primary, size: 40),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Информация о тайтле
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _manga.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Селектор статуса (Читаю, В планах, Прочитано)
                                  PopupMenuButton<ReadingStatus>(
                                    onSelected: _changeStatus,
                                    color: const Color(0xFF222631),
                                    itemBuilder: (ctx) => [
                                      _buildStatusItem(ReadingStatus.reading, primary),
                                      _buildStatusItem(ReadingStatus.planned, Colors.amber),
                                      _buildStatusItem(ReadingStatus.completed, Colors.greenAccent),
                                      _buildStatusItem(ReadingStatus.none, Colors.grey),
                                    ],
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.bookmark_rounded, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            _manga.status.label,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.arrow_drop_down, size: 16, color: statusColor),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Статистика
                                  Text(
                                    '${_manga.chapters.length} глав • ${_formatFileSize(_manga.totalSize)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Редактировать',
                    onPressed: () {
                      EditBookDialog.show(
                        context,
                        book: BookMetadata(
                          filePath: _manga.id,
                          title: _manga.title,
                          totalPages: _manga.totalPages,
                          lastPage: 0,
                          lastReadTime: _manga.updatedAt,
                          fileSize: _manga.totalSize,
                          tags: _manga.tags,
                          coverPath: _manga.coverPath,
                          status: _manga.status,
                        ),
                        onSaved: _refresh,
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    color: const Color(0xFF222631),
                    onSelected: (val) async {
                      if (val == 'compress_all') {
                        _compressAllChapters();
                      } else if (val == 'delete_all') {
                        await StorageService.removeMangaGroup(_manga.id);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'compress_all',
                        child: Row(
                          children: [
                            Icon(Icons.speed_rounded, color: Colors.amber, size: 18),
                            SizedBox(width: 8),
                            Text('Сжать все главы (WebP)', style: TextStyle(color: Colors.amber)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text('Удалить тайтл', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 2. Теги и кнопка "Продолжить чтение"
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Теги и жанры
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Жанры и теги',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            icon: const Icon(Icons.label_outline_rounded, size: 16),
                            label: Text(
                              _manga.tags.isEmpty ? 'Добавить' : 'Изменить',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              EditBookDialog.show(
                                context,
                                book: BookMetadata(
                                  filePath: _manga.id,
                                  title: _manga.title,
                                  totalPages: _manga.totalPages,
                                  lastPage: 0,
                                  lastReadTime: _manga.updatedAt,
                                  fileSize: _manga.totalSize,
                                  tags: _manga.tags,
                                  coverPath: _manga.coverPath,
                                  status: _manga.status,
                                ),
                                onSaved: _refresh,
                              );
                            },
                          ),
                        ],
                      ),
                      if (_manga.tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _manga.tags.map((tag) {
                            return Chip(
                              backgroundColor: primary.withValues(alpha: 0.15),
                              side: BorderSide(color: primary.withValues(alpha: 0.3)),
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              label: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        const SizedBox(height: 8),
                      ],

                      // Кнопка "Продолжить чтение"
                      if (_manga.chapters.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 24),
                            label: Text(
                              'Продолжить: ${_manga.currentChapter?.title ?? "Глава 1"}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              final ch = _manga.currentChapter ?? _manga.chapters.first;
                              _openChapter(ch, _manga.currentChapterIndex);
                            },
                          ),
                        ),
                      const SizedBox(height: 18),

                      // Заголовок списка глав и кнопка добавления
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Главы (${_manga.chapters.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              side: BorderSide(color: primary.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить главы'),
                            onPressed: _addChapters,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // 3. Список глав в группе
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chapter = _manga.chapters[index];
                      return _buildChapterTile(chapter, index, primary);
                    },
                    childCount: _manga.chapters.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),

          // Загрузчик
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1E24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primary),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<ReadingStatus> _buildStatusItem(ReadingStatus status, Color color) {
    return PopupMenuItem(
      value: status,
      child: Row(
        children: [
          Icon(Icons.bookmark_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Text(status.label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChapterTile(ChapterItem chapter, int index, Color primary) {
    final isCurrent = index == _manga.currentChapterIndex;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent ? primary.withValues(alpha: 0.12) : const Color(0xFF161920),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        onTap: () => _openChapter(chapter, index),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: chapter.isCompleted ? Colors.green.withValues(alpha: 0.2) : Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: chapter.isCompleted
                ? const Icon(Icons.check, color: Colors.greenAccent, size: 20)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isCurrent ? primary : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        title: Text(
          chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Row(
          children: [
            if (chapter.totalPages > 0) ...[
              Text(
                chapter.isCompleted ? 'Прочитано' : 'Стр. ${chapter.lastPage + 1} / ${chapter.totalPages}',
                style: TextStyle(
                  color: chapter.isCompleted ? Colors.greenAccent : Colors.grey,
                  fontSize: 12,
                ),
              ),
              const Text(' • ', style: TextStyle(color: Colors.grey)),
            ],
            Text(
              _formatFileSize(chapter.fileSize),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (chapter.isOptimized) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'WebP',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
          color: const Color(0xFF222631),
          onSelected: (val) {
            if (val == 'compress') {
              CompressDialog.show(
                context,
                book: BookMetadata(
                  filePath: chapter.filePath,
                  title: chapter.title,
                  totalPages: chapter.totalPages,
                  lastPage: chapter.lastPage,
                  lastReadTime: chapter.lastReadTime,
                  fileSize: chapter.fileSize,
                  isOptimized: chapter.isOptimized,
                ),
                onCompressed: _refresh,
              );
            } else if (val == 'remove') {
              StorageService.removeChapterFromGroup(
                groupId: _manga.id,
                chapterId: chapter.id,
              ).then((_) => _refresh());
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'compress',
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text('Сжать главу (WebP)', style: TextStyle(color: Colors.amber)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Удалить из группы', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
