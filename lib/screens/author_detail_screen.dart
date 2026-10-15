import 'dart:io';
import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/storage_service.dart';
import 'manga_detail_screen.dart';
import 'manga_file_explorer_screen.dart';

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

  Future<void> _reloadAuthor() async {
    final allGroups = await StorageService.getMangaGroups();
    final authorTags = await StorageService.loadAllAuthorTags();
    final blacklist = await StorageService.loadAuthorBlacklist();
    final allAuthors = StorageService.buildAuthorsList(
      allGroups: allGroups,
      authorTagsMap: authorTags,
      blacklist: blacklist,
    );

    final updated = allAuthors.firstWhere(
      (a) => a.name == _currentAuthor.name,
      orElse: () => AuthorData(name: _currentAuthor.name),
    );

    if (mounted) {
      setState(() {
        _currentAuthor = updated;
      });
      widget.onAuthorUpdated();
    }
  }

  void _editTags() {
    final primary = widget.settings.accentColor.color;
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

  Future<void> _assignMangaDialog() async {
    final allGroups = await StorageService.getMangaGroups();
    final blacklist = await StorageService.loadAuthorBlacklist();
    final allTitles = allGroups.map((g) => g.title).toList();

    // Начальный список выбранных: все тайтлы, относящиеся к этому автору
    final selectedIds = allGroups
        .where((g) => g.displayAuthor(allTitles, blacklist) == _currentAuthor.name || g.author == _currentAuthor.name)
        .map((g) => g.id)
        .toSet();

    final initialBelonging = Set<String>.from(selectedIds);

    String query = '';
    int tab = 0; // 0: Все, 1: Неопределенные, 2: Текущего автора

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = allGroups.where((g) {
            final matchesQuery = query.isEmpty || g.title.toLowerCase().contains(query.toLowerCase());
            if (!matchesQuery) return false;

            if (tab == 1) {
              // Неопределенные
              final author = g.displayAuthor(allTitles, blacklist);
              return author.isEmpty || author == 'Неизвестный автор';
            } else if (tab == 2) {
              // Только выбранные для этого автора
              return selectedIds.contains(g.id);
            }
            return true;
          }).toList();

          final primary = widget.settings.accentColor.color;

          return AlertDialog(
            backgroundColor: const Color(0xFF1B1E26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            title: Row(
              children: [
                Icon(Icons.playlist_add_check_rounded, color: primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Привязать к: ${_currentAuthor.name}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск манги по названию...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: const Color(0xFF242833),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        query = val;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('Все (${allGroups.length})', style: const TextStyle(fontSize: 11)),
                          selected: tab == 0,
                          onSelected: (_) => setDialogState(() => tab = 0),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Неопределённые', style: TextStyle(fontSize: 11)),
                          selected: tab == 1,
                          onSelected: (_) => setDialogState(() => tab = 1),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('Выбрано (${selectedIds.length})', style: const TextStyle(fontSize: 11)),
                          selected: tab == 2,
                          onSelected: (_) => setDialogState(() => tab = 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Тайтлы не найдены', style: TextStyle(color: Colors.grey)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (ctx, idx) {
                              final manga = filtered[idx];
                              final isSelected = selectedIds.contains(manga.id);
                              final currentAuthor = manga.displayAuthor(allTitles, blacklist);
                              final hasCover = manga.coverPath != null && File(manga.coverPath!).existsSync();

                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      selectedIds.remove(manga.id);
                                    } else {
                                      selectedIds.add(manga.id);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  child: Row(
                                    children: [
                                      // Превью первой страницы архива
                                      SizedBox(
                                        width: 44,
                                        height: 60,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: hasCover
                                              ? Image.file(
                                                  File(manga.coverPath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => _buildFallbackThumbnail(primary),
                                                )
                                              : (manga.chapters.isNotEmpty)
                                                  ? MangaArchiveThumbnail(
                                                      archivePath: manga.chapters.first.filePath,
                                                      width: 44,
                                                      height: 60,
                                                      borderRadius: BorderRadius.circular(6),
                                                    )
                                                  : _buildFallbackThumbnail(primary),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Название тайтла и автор
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              manga.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              currentAuthor.isNotEmpty ? 'Автор: $currentAuthor' : 'Автор не определен',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: currentAuthor.isNotEmpty ? Colors.white60 : Colors.amber,
                                                fontWeight: currentAuthor.isNotEmpty ? FontWeight.normal : FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${manga.chapters.length} гл. • ${_formatFileSize(manga.totalSize)}',
                                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: primary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        onChanged: (val) {
                                          setDialogState(() {
                                            if (val == true) {
                                              selectedIds.add(manga.id);
                                            } else {
                                              selectedIds.remove(manga.id);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  // 1. Привязываем новые выбранные тайтлы
                  final newlyAdded = selectedIds.difference(initialBelonging);
                  if (newlyAdded.isNotEmpty) {
                    await StorageService.assignAuthorToManga(
                      mangaIds: newlyAdded.toList(),
                      authorName: _currentAuthor.name,
                    );
                  }
                  // 2. Отвязываем снятые с выбора тайтлы
                  final removed = initialBelonging.difference(selectedIds);
                  if (removed.isNotEmpty) {
                    for (final id in removed) {
                      await StorageService.unassignMangaFromAuthor(id);
                    }
                  }
                  await _reloadAuthor();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Привязка манги к "${_currentAuthor.name}" сохранена!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
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

  Widget _buildFallbackThumbnail(Color primary) {
    return Container(
      color: const Color(0xFF222631),
      child: Center(
        child: Icon(Icons.menu_book_rounded, color: primary.withValues(alpha: 0.5), size: 24),
      ),
    );
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
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_add_rounded),
                tooltip: 'Привязать тайтлы к автору',
                onPressed: _assignMangaDialog,
              ),
              IconButton(
                icon: const Icon(Icons.label_outline_rounded),
                tooltip: 'Жанры автора',
                onPressed: _editTags,
              ),
            ],
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

          // Блок тегов и действий автора
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary.withValues(alpha: 0.18),
                          foregroundColor: primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Привязать мангу'),
                        onPressed: _assignMangaDialog,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.label_outline_rounded, size: 16),
                        label: Text(_currentAuthor.tags.isEmpty ? 'Добавить жанры' : 'Жанры автора'),
                        onPressed: _editTags,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                                  // Меню отвязки тайтла от этого автора
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: PopupMenuButton<String>(
                                      icon: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.more_vert, size: 16, color: Colors.white),
                                      ),
                                      color: const Color(0xFF222631),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      onSelected: (val) async {
                                        if (val == 'unlink') {
                                          await StorageService.unassignMangaFromAuthor(group.id);
                                          await _reloadAuthor();
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                          value: 'unlink',
                                          child: Row(
                                            children: [
                                              Icon(Icons.link_off_rounded, size: 16, color: Colors.redAccent),
                                              SizedBox(width: 8),
                                              Text('Отвязать от автора'),
                                            ],
                                          ),
                                        ),
                                      ],
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
