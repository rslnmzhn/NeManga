import 'author_detail_screen.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/reader_models.dart';
import '../services/archive_service.dart';
import '../services/compressor_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../widgets/compress_dialog.dart';
import '../widgets/edit_book_dialog.dart';
import '../widgets/update_dialog.dart';
import 'manga_detail_screen.dart';
import 'manga_file_explorer_screen.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MangaGroup> _allGroups = [];
  List<MangaGroup> _filteredGroups = [];

  ReadingStatus? _selectedStatus;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String _loadingMessage = '';
  ReaderSettings _settings = const ReaderSettings();
  bool _showSplashIntro = true;
  bool _isAuthorsView = false;
  bool _showSizeInsteadOfCount = false;
  List<AuthorData> _authorsList = [];
  List<String> _authorBlacklist = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    UpdateService.cleanOldInstallers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate(silent: true);
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _showSplashIntro = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate({bool silent = false}) async {
    try {
      final update = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (update != null) {
        UpdateDialog.show(context, update);
      } else if (!silent) {
        final current = await UpdateService.getCurrentVersion();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('У вас установлена последняя версия NeManga (v$current)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка проверки обновлений: $e')),
        );
      }
    }
  }

  Future<void> _loadData() async {
    final settings = await StorageService.loadSettings();
    final groups = await StorageService.getMangaGroups();
    final authorTags = await StorageService.loadAllAuthorTags();
    final blacklist = await StorageService.loadAuthorBlacklist();
    final authors = StorageService.buildAuthorsList(
      allGroups: groups,
      authorTagsMap: authorTags,
      blacklist: blacklist,
    );

    if (mounted) {
      setState(() {
        _settings = settings;
        _allGroups = groups;
        _authorsList = authors;
        _authorBlacklist = blacklist;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    // Токены поиска по названию и жанрам (через пробел или запятую)
    final tokens = _searchQuery
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim().replaceAll(RegExp(r'^#+'), ''))
        .where((t) => t.isNotEmpty)
        .toList();

    final allTitles = _allGroups.map((g) => g.title).toList();

    _filteredGroups = _allGroups.where((group) {
      final matchesStatus = _selectedStatus == null || group.status == _selectedStatus;
      if (!matchesStatus) return false;

      if (tokens.isEmpty) return true;

      final titleLower = group.title.toLowerCase();
      final authorLower = group.displayAuthor(allTitles, _authorBlacklist).toLowerCase();
      final tagsLower = group.tags.map((t) => t.toLowerCase()).toList();

      return tokens.every((token) {
        final matchesTitle = titleLower.contains(token);
        final matchesAuthor = authorLower.contains(token);
        final matchesTag = tagsLower.any((tag) => tag.contains(token));
        return matchesTitle || matchesAuthor || matchesTag;
      });
    }).toList();

    // Сортировка библиотеки
    switch (_settings.sortOrder) {
      case LibrarySortOrder.recent:
        _filteredGroups.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case LibrarySortOrder.title:
        _filteredGroups.sort((a, b) => ArchiveService.naturalCompare(a.title, b.title));
        break;
      case LibrarySortOrder.progress:
        _filteredGroups.sort((a, b) => b.overallProgressPercent.compareTo(a.overallProgressPercent));
        break;
      case LibrarySortOrder.author:
        _filteredGroups.sort((a, b) {
          final authorA = a.displayAuthor(allTitles, _authorBlacklist);
          final authorB = b.displayAuthor(allTitles, _authorBlacklist);
          if (authorA.isEmpty && authorB.isNotEmpty) return 1;
          if (authorA.isNotEmpty && authorB.isEmpty) return -1;
          final cmp = ArchiveService.naturalCompare(authorA, authorB);
          if (cmp != 0) return cmp;
          return ArchiveService.naturalCompare(a.title, b.title);
        });
        break;
    }
  }

  Future<void> _pickAndOpenArchives() async {
    try {
      final selectedPaths = await MangaFileExplorerScreen.pickMangaArchives(
        context,
        settings: _settings,
        title: 'Добавить мангу',
      );

      if (selectedPaths != null && selectedPaths.isNotEmpty) {
        await _processPickedArchives(selectedPaths);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файлов: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _processPickedArchives(List<String> validPaths) async {
    if (validPaths.isEmpty) return;

    if (!mounted) return;

    // Предлагаем сжатие добавленных zip/cbz архивов с опцией удаления оригинала
    final choice = await PromptCompressAddedDialog.show(
      context,
      filePaths: validPaths,
    );

    if (choice == null) return;

    if (choice.deleteOriginal && !await CompressorService.hasAllFilesAccess()) {
      await CompressorService.requestAllFilesAccess();
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = choice.shouldCompress ? 'Сжатие архивов в WebP...' : 'Подготовка файлов...';
    });

    try {
      final processedPaths = <String>[];
      int totalOriginal = 0;
      int totalCompressed = 0;
      final groupTitle = ArchiveService.deriveMangaTitle(filePaths: validPaths);

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
              subFolder: groupTitle,
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
                'Сжато архивов: ${processedPaths.length}. Сохранено в Загрузки/NeManga. Освобождено: ${_formatFileSize(savedBytes)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        processedPaths.addAll(validPaths);
      }

      if (processedPaths.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (processedPaths.length == 1) {
        // Один архив: открываем сразу
        final filePath = processedPaths.first;
        final info = await ArchiveService.loadManga(filePath);
        final title = groupTitle.isNotEmpty && groupTitle != 'NeManga' ? groupTitle : info.title;

        final group = await StorageService.findOrCreateGroupForFile(
          filePath: filePath,
          title: title,
          totalPages: info.pagePaths.length,
          currentPage: 0,
          coverPath: info.coverPath,
        );

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => ReaderScreen(
              title: info.title,
              archivePath: filePath,
              pagePaths: info.pagePaths,
              initialPage: 0,
              settings: _settings,
              mangaGroup: group,
              currentChapterIndex: 0,
            ),
          ),
        );
      } else {
        // Несколько архивов: объединяем в одну группу манги
        processedPaths.sort(ArchiveService.naturalCompare);
        final chapters = <ChapterItem>[];
        String? groupCover;

        for (int i = 0; i < processedPaths.length; i++) {
          final path = processedPaths[i];
          final title = p.basenameWithoutExtension(path);
          final size = File(path).existsSync() ? File(path).lengthSync() : 0;

          if (i == 0) {
            groupCover = await ArchiveService.extractCoverOnly(path);
          }

          chapters.add(ChapterItem(
            id: path,
            filePath: path,
            title: title,
            totalPages: 0,
            lastPage: 0,
            lastReadTime: DateTime.now(),
            fileSize: size,
          ));
        }

        final author = AuthorDetector.detectAuthor(groupTitle);
        final newGroup = MangaGroup(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}',
          title: groupTitle,
          author: author,
          coverPath: groupCover,
          status: ReadingStatus.reading,
          chapters: chapters,
          currentChapterIndex: 0,
          updatedAt: DateTime.now(),
        );

        await StorageService.saveMangaGroup(newGroup);

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        // Открываем детальный экран созданной группы
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => MangaDetailScreen(
              manga: newGroup,
              settings: _settings,
            ),
          ),
        );
      }

      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ошибка открытия'),
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

  Future<void> _openReaderDirect(MangaGroup group) async {
    final chapter = group.currentChapter;
    if (chapter == null) {
      _openMangaDetail(group);
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Загрузка главы...';
    });

    try {
      final info = await ArchiveService.loadManga(chapter.filePath);

      await StorageService.findOrCreateGroupForFile(
        filePath: chapter.filePath,
        title: chapter.title,
        totalPages: info.pagePaths.length,
        currentPage: chapter.lastPage,
        coverPath: group.coverPath ?? info.coverPath,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ReaderScreen(
            title: group.chapters.length > 1 ? '${group.title} — ${chapter.title}' : group.title,
            archivePath: chapter.filePath,
            pagePaths: info.pagePaths,
            initialPage: chapter.lastPage,
            settings: _settings,
            mangaGroup: group,
            currentChapterIndex: group.currentChapterIndex,
          ),
        ),
      );

      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ошибка открытия'),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
            ],
          ),
        );
      }
    }
  }

  void _openMangaDetail(MangaGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => MangaDetailScreen(
          manga: group,
          settings: _settings,
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить кэш страниц?'),
        content: const Text(
          'Это освободит память устройства от извлеченных страниц. Ваши архивы, обложки и сохраненный прогресс останутся на месте.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ArchiveService.clearCache();
      await UpdateService.cleanOldInstallers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш страниц и старые обновления очищены')),
        );
      }
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

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: highlight ? Colors.greenAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanFolder() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Сканирование папки NeManga...';
    });

    try {
      final imported = await StorageService.scanAndImportPublicManga();
      await _loadData();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Синхронизация завершена. Найдено новых глав: $imported'
                : 'Новых архивов в папке Загрузки/NeManga не найдено',
          ),
          backgroundColor: imported > 0 ? Colors.green : Colors.blueGrey,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сканирования: $e')),
        );
      }
    }
  }

  Future<void> _showStorageDashboard() async {
    final stats = await StorageService.getStorageStats();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.pie_chart_outline_rounded, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Дашборд памяти', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatRow('Всего тайтлов:', '${stats.totalMangaCount}'),
            _buildStatRow('Всего глав:', '${stats.totalChaptersCount}'),
            _buildStatRow('Сжато в WebP:', '${stats.optimizedChaptersCount} из ${stats.totalChaptersCount}'),
            const Divider(height: 20),
            _buildStatRow('Объём на диске:', stats.totalSizeFormatted),
            _buildStatRow(
              'Сэкономлено памяти:',
              stats.savedFormatted,
              highlight: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupRestoreDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Резервное копирование', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Вы можете сохранить всю вашу библиотеку (статусы, главы, теги, настройки) в один файл или восстановить её.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Экспорт библиотеки в JSON'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final path = await StorageService.exportBackupToJson();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Бэкап сохранён в: $path'), backgroundColor: Colors.green),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Импорт библиотеки из JSON'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final res = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );
                    if (res.isNotEmpty && res.first.path != null) {
                      final str = await File(res.first.path!).readAsString();
                      final count = await StorageService.importBackupFromJson(str);
                      await _loadData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Импортировано тайтлов: $count'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка импорта: $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1B1E26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Оформление и темы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Фоновая тема:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: AppThemeMode.values.map((t) {
                      final sel = _settings.appTheme == t;
                      return ChoiceChip(
                        label: Text(t.label),
                        selected: sel,
                        onSelected: (val) async {
                          final updated = _settings.copyWith(appTheme: t);
                          await StorageService.saveSettings(updated);
                          setState(() => _settings = updated);
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Акцентный цвет (Аниме-палитра):', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppAccentColor.values.map((c) {
                      final sel = _settings.accentColor == c;
                      return ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: c.color, radius: 8),
                        label: Text(c.label),
                        selected: sel,
                        onSelected: (val) async {
                          final updated = _settings.copyWith(accentColor: c);
                          await StorageService.saveSettings(updated);
                          setState(() => _settings = updated);
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
            ],
          );
        },
      ),
    );
  }

  void _showAuthorBlacklistDialog() {
    final textController = TextEditingController();
    final currentBlacklist = List<String>.from(_authorBlacklist);
    final primary = _settings.accentColor.color;

    const suggestions = [
      'author-*',
      'mangalib*',
      'remanga*',
      'readmanga*',
      'slashlib*',
      '*scan*',
      '*team*',
      '*club*',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1B1E26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Блэклист слов и авторов',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Исключите названия сайтов, сканы и мусорные префиксы из списка авторов. Поддерживается знак * (например: author-*, [site]*, *scan*).',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textController,
                          onSubmitted: (val) {
                            final parts = val
                                .split(RegExp(r'[\s,]+'))
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty);
                            if (parts.isNotEmpty) {
                              setDialogState(() {
                                for (final p in parts) {
                                  if (!currentBlacklist.contains(p)) {
                                    currentBlacklist.add(p);
                                  }
                                }
                              });
                              textController.clear();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Шаблон (напр. author-*, site*)...',
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
                          final val = textController.text;
                          final parts = val
                              .split(RegExp(r'[\s,]+'))
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty);
                          if (parts.isNotEmpty) {
                            setDialogState(() {
                              for (final p in parts) {
                                if (!currentBlacklist.contains(p)) {
                                  currentBlacklist.add(p);
                                }
                              }
                            });
                            textController.clear();
                          }
                        },
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (currentBlacklist.isNotEmpty) ...[
                    const Text(
                      'Активные правила исключения:',
                      style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: currentBlacklist.map((rule) {
                        return Chip(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                          label: Text(
                            rule,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                          onDeleted: () {
                            setDialogState(() {
                              currentBlacklist.remove(rule);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Быстрые подсказки:',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: suggestions.where((s) => !currentBlacklist.contains(s)).map((s) {
                      return ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11)),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide.none,
                        onPressed: () {
                          setDialogState(() {
                            currentBlacklist.add(s);
                          });
                        },
                      );
                    }).toList(),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await StorageService.saveAuthorBlacklist(currentBlacklist);
                  await _loadData();
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Сортировка библиотеки', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LibrarySortOrder.values.map((order) {
            return RadioListTile<LibrarySortOrder>(
              title: Text(order.label),
              value: order,
              groupValue: _settings.sortOrder,
              onChanged: (val) async {
                if (val != null) {
                  final nav = Navigator.of(ctx);
                  final updated = _settings.copyWith(sortOrder: val);
                  await StorageService.saveSettings(updated);
                  if (mounted) {
                    setState(() {
                      _settings = updated;
                      _applyFilter();
                    });
                    nav.pop();
                  }
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showBatchRenameDialog() async {
    final savedPatterns = await StorageService.loadTitleCleanupPatterns();
    final currentPatterns = List<String>.from(savedPatterns);
    final textController = TextEditingController();
    final primary = _settings.accentColor.color;

    const defaultSuggestions = [
      'site-*',
      'mangasite-*',
      'remanga-*',
      'readmanga-*',
      'author-*',
      '*scan*',
    ];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Вычисляем затронутые манги для предпросмотра
          final affectedManga = <({MangaGroup manga, String newTitle})>[];
          if (currentPatterns.isNotEmpty) {
            for (final group in _allGroups) {
              final newTitle = ArchiveService.cleanTitleWithPatterns(group.title, currentPatterns);
              if (newTitle != group.title) {
                affectedManga.add((manga: group, newTitle: newTitle));
              }
            }
          }

          final samples = affectedManga.take(3).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1B1E26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            title: Row(
              children: [
                Icon(Icons.drive_file_rename_outline_rounded, color: primary, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Массовое переименование названий',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Удаление названий сайтов, номеров и лишних префиксов из всех тайтлов библиотеки. Поддерживается знак * (например: site-*, название-*).',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            onSubmitted: (val) {
                              final parts = val
                                  .split(RegExp(r'[\s,]+'))
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty);
                              if (parts.isNotEmpty) {
                                setDialogState(() {
                                  for (final p in parts) {
                                    if (!currentPatterns.contains(p)) {
                                      currentPatterns.add(p);
                                    }
                                  }
                                });
                                textController.clear();
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Шаблон (напр. site-*, author-*)...',
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
                            final val = textController.text;
                            final parts = val
                                .split(RegExp(r'[\s,]+'))
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty);
                            if (parts.isNotEmpty) {
                              setDialogState(() {
                                for (final p in parts) {
                                  if (!currentPatterns.contains(p)) {
                                    currentPatterns.add(p);
                                  }
                                }
                              });
                              textController.clear();
                            }
                          },
                          icon: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (currentPatterns.isNotEmpty) ...[
                      const Text(
                        'Шаблоны для удаления:',
                        style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: currentPatterns.map((pat) {
                          return Chip(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                            label: Text(
                              pat,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                            onDeleted: () {
                              setDialogState(() {
                                currentPatterns.remove(pat);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Быстрые подсказки:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: defaultSuggestions.where((s) => !currentPatterns.contains(s)).map((s) {
                        return ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide.none,
                          onPressed: () {
                            setDialogState(() {
                              currentPatterns.add(s);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Секция предпросмотра на 3 мангах
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF13151B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: affectedManga.isNotEmpty
                              ? Colors.greenAccent.withValues(alpha: 0.3)
                              : Colors.white10,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                affectedManga.isNotEmpty ? Icons.check_circle_outline : Icons.info_outline,
                                size: 16,
                                color: affectedManga.isNotEmpty ? Colors.greenAccent : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  affectedManga.isNotEmpty
                                      ? 'Предпросмотр (найдено: ${affectedManga.length} тайтлов):'
                                      : 'Предпросмотр:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: affectedManga.isNotEmpty ? Colors.greenAccent : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (currentPatterns.isEmpty)
                            const Text(
                              'Добавьте хотя бы один шаблон для очистки выше.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            )
                          else if (affectedManga.isEmpty)
                            const Text(
                              'Среди манги библиотеки нет названий, подходящих под указанные шаблоны.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            )
                          else ...[
                            for (final sample in samples) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Было: ${sample.manga.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.redAccent,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Станет: ${sample.newTitle}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (affectedManga.length > 3)
                              Text(
                                '...и ещё ${affectedManga.length - 3} тайтл(ов)',
                                style: const TextStyle(fontSize: 11, color: Colors.white60, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                label: Text(
                  affectedManga.isNotEmpty
                      ? 'Очистить названия (${affectedManga.length})'
                      : 'Очистить названия',
                ),
                onPressed: affectedManga.isEmpty
                    ? null
                    : () async {
                        final nav = Navigator.of(ctx);
                        final newTitlesMap = {for (final a in affectedManga) a.manga.id: a.newTitle};
                        final count = await StorageService.batchUpdateMangaTitles(newTitlesMap);
                        await StorageService.saveTitleCleanupPatterns(currentPatterns);
                        await _loadData();
                        nav.pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Успешно очищено названий манги: $count!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAboutDialog() async {
    final version = await UpdateService.getCurrentVersion();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'NeManga',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Версия v$version',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              'Быстрый и удобный оффлайн-ридер манги для Android с поддержкой сжатия архивов в WebP.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = _settings.accentColor.color;
    final bg = _settings.appTheme.backgroundColor;
    final cardBg = _settings.appTheme.cardColor;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: const CircleBorder(),
        tooltip: 'Добавить архивы манги',
        onPressed: _pickAndOpenArchives,
        child: const Icon(Icons.add_rounded, size: 36),
      ),
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'NeManga',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            tooltip: 'Массовая очистка названий',
            onPressed: _showBatchRenameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Сканировать папку NeManga',
            onPressed: _scanFolder,
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Оформление и темы',
            onPressed: _showThemeDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1B1E26),
            onSelected: (val) {
              if (val == 'batch_rename') {
                _showBatchRenameDialog();
              } else if (val == 'storage') {
                _showStorageDashboard();
              } else if (val == 'backup') {
                _showBackupRestoreDialog();
              } else if (val == 'clear_cache') {
                _confirmClearCache();
              } else if (val == 'update') {
                _checkUpdate(silent: false);
              } else if (val == 'about') {
                _showAboutDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'batch_rename',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline_rounded, size: 18, color: Colors.cyanAccent),
                    SizedBox(width: 10),
                    Text('Массовая очистка названий'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'storage',
                child: Row(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded, size: 18, color: Colors.amber),
                    SizedBox(width: 10),
                    Text('Дашборд памяти'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'backup',
                child: Row(
                  children: [
                    Icon(Icons.save_as_outlined, size: 18, color: Colors.blueAccent),
                    SizedBox(width: 10),
                    Text('Резервное копирование'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_cache',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 18, color: Colors.orangeAccent),
                    SizedBox(width: 10),
                    Text('Очистить кэш страниц'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'update',
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt_rounded, size: 18, color: Colors.greenAccent),
                    SizedBox(width: 10),
                    Text('Проверить обновления'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('О приложении'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadData,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Поиск
                        if (_allGroups.isNotEmpty) ...[
                          _buildSearchBar(),
                          const SizedBox(height: 12),
                        ],

                        // Заголовок библиотеки и таб-переключатель
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Переключатель [ Манга ]  [ Авторы ]
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF161920),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTabPill(
                                    label: 'Манга',
                                    icon: Icons.auto_stories_rounded,
                                    isSelected: !_isAuthorsView,
                                    onTap: () => setState(() => _isAuthorsView = false),
                                    primary: primary,
                                  ),
                                  _buildTabPill(
                                    label: 'Авторы',
                                    icon: Icons.person_rounded,
                                    isSelected: _isAuthorsView,
                                    onTap: () => setState(() => _isAuthorsView = true),
                                    primary: primary,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                if (!_isAuthorsView && _filteredGroups.isNotEmpty)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _showSizeInsteadOfCount = !_showSizeInsteadOfCount;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Text(
                                        _showSizeInsteadOfCount
                                            ? _formatFileSize(_filteredGroups.fold(0, (sum, g) => sum + g.totalSize))
                                            : '${_filteredGroups.length} шт.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _showSizeInsteadOfCount ? primary : Colors.grey,
                                          fontWeight: _showSizeInsteadOfCount ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (_isAuthorsView && _authorsList.isNotEmpty)
                                  Text(
                                    '${_authorsList.length} авт.',
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                const SizedBox(width: 4),
                                if (_isAuthorsView)
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, size: 22, color: Colors.amber),
                                    tooltip: 'Фильтры и блэклист авторов',
                                    onPressed: _showAuthorBlacklistDialog,
                                  )
                                else ...[
                                  IconButton(
                                    icon: Badge(
                                      isLabelVisible: _selectedStatus != null,
                                      child: Icon(
                                        Icons.filter_list_rounded,
                                        size: 20,
                                        color: _selectedStatus != null ? primary : Colors.white70,
                                      ),
                                    ),
                                    tooltip: _selectedStatus != null
                                        ? 'Фильтр: ${_selectedStatus!.label}'
                                        : 'Фильтры статуса',
                                    onPressed: _showFilterDialog,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.sort_rounded, size: 20, color: Colors.white70),
                                    tooltip: 'Сортировка: ${_settings.sortOrder.label}',
                                    onPressed: _showSortDialog,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // Сетка (Авторы или Манга)
                if (_isAuthorsView) ...[
                  if (_authorsList.isEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: const Text('В библиотеке пока нет авторов', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
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
                            final author = _authorsList[index];
                            return _buildAuthorCard(author, primary, cardBg);
                          },
                          childCount: _authorsList.length,
                        ),
                      ),
                    ),
                ] else ...[
                  if (_filteredGroups.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.54,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final group = _filteredGroups[index];
                            return _buildMangaGroupCard(group, primary);
                          },
                          childCount: _filteredGroups.length,
                        ),
                      ),
                    ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),

          // Оверлей загрузки
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

          // Анимированный сплэш-скрин при старте
          if (_showSplashIntro)
            AnimatedOpacity(
              opacity: _showSplashIntro ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              child: Container(
                color: bg,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 110,
                          height: 110,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'NeManga',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Приятного чтения!',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Фильтры статуса', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ReadingStatus?>(
              title: const Text('Все статусы'),
              value: null,
              groupValue: _selectedStatus,
              onChanged: (val) {
                setState(() {
                  _selectedStatus = null;
                  _applyFilter();
                });
                Navigator.pop(ctx);
              },
            ),
            ...ReadingStatus.values.where((s) => s != ReadingStatus.none).map((s) {
              return RadioListTile<ReadingStatus?>(
                title: Text(s.label),
                value: s,
                groupValue: _selectedStatus,
                onChanged: (val) {
                  setState(() {
                    _selectedStatus = val;
                    _applyFilter();
                  });
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color primary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? primary : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorCard(AuthorData author, Color primary, Color cardBg) {
    final hasCover = author.coverPath != null && File(author.coverPath!).existsSync();

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => AuthorDetailScreen(
              author: author,
              settings: _settings,
              onAuthorUpdated: _loadData,
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
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Картинка автора: первая страница из последнего добавленного архива
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      Image.file(
                        File(author.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackCover(primary),
                      )
                    else
                      Container(
                        color: const Color(0xFF1E222B),
                        child: Center(
                          child: Icon(Icons.person_rounded, size: 48, color: primary.withValues(alpha: 0.5)),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
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
                          '${author.totalMangaCount} тайтл(ов)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Информация об авторе
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Теги автора
                    if (author.tags.isNotEmpty)
                      SizedBox(
                        height: 18,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: author.tags.map((tag) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    else
                      Text(
                        'Нажмите, чтобы открыть тайтлы',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
          _applyFilter();
        });
      },
      decoration: InputDecoration(
        hintText: 'Поиск по названию или жанрам (через пробел или запятую)...',
        prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _applyFilter();
                  });
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF161920),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF16181E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'Библиотека пуста',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedStatus != null
                ? 'По вашему запросу ничего не найдено.'
                : 'Нажмите «+» внизу по центру, чтобы добавить первые zip/cbz архивы манги.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMangaGroupCard(MangaGroup group, Color primary) {
    final percent = group.overallProgressPercent;
    final hasCover = group.coverPath != null && File(group.coverPath!).existsSync();
    final statusColor = _getStatusColor(group.status, primary);

    return Container(
      decoration: BoxDecoration(
        color: _settings.appTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openMangaDetail(group),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. БОЛЬШАЯ ПРЕВЬЮШКА
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasCover)
                        Image.file(
                          File(group.coverPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildFallbackCover(primary),
                        )
                      else
                        _buildFallbackCover(primary),

                      // Градиент снизу
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 70,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Бейдж статуса слева сверху
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_rounded, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                group.status.label,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Число глав справа сверху
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Кнопка быстрого чтения по центру снизу
                      Positioned(
                        bottom: 6,
                        left: 8,
                        child: InkWell(
                          onTap: () => _openReaderDirect(group),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 3),
                                Text(
                                  'Читать',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Контекстное меню
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                          ),
                          color: const Color(0xFF222631),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          onSelected: (val) {
                            if (val == 'open') {
                              _openMangaDetail(group);
                            } else if (val == 'edit') {
                              EditBookDialog.show(
                                context,
                                book: BookMetadata(
                                  filePath: group.id,
                                  title: group.title,
                                  author: group.author,
                                  totalPages: group.totalPages,
                                  lastPage: 0,
                                  lastReadTime: group.updatedAt,
                                  fileSize: group.totalSize,
                                  tags: group.tags,
                                  coverPath: group.coverPath,
                                  status: group.status,
                                ),
                                onSaved: _loadData,
                              );
                            } else if (val == 'compress') {
                              if (group.chapters.length == 1) {
                                final ch = group.chapters.first;
                                CompressDialog.show(
                                  context,
                                  book: BookMetadata(
                                    filePath: ch.filePath,
                                    title: '${group.title} (${ch.title})',
                                    totalPages: ch.totalPages,
                                    lastPage: ch.lastPage,
                                    lastReadTime: ch.lastReadTime,
                                    fileSize: ch.fileSize,
                                    isOptimized: ch.isOptimized,
                                  ),
                                  onCompressed: _loadData,
                                );
                              } else if (group.chapters.length > 1) {
                                BatchCompressDialog.show(
                                  context,
                                  group: group,
                                  onCompressed: _loadData,
                                );
                              }
                            } else if (val == 'delete') {
                              StorageService.removeMangaGroup(group.id).then((_) => _loadData());
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'open',
                              child: Row(
                                children: [
                                  Icon(Icons.menu_book, size: 18, color: Colors.white70),
                                  SizedBox(width: 10),
                                  Text('Открыть тайтл', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18, color: Colors.white70),
                                  SizedBox(width: 10),
                                  Text('Переименовать / статус / теги', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'compress',
                              child: Row(
                                children: [
                                  Icon(Icons.speed_rounded, size: 18, color: Colors.amber),
                                  SizedBox(width: 10),
                                  Text('Сжать архив (WebP)', style: TextStyle(color: Colors.amber)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  SizedBox(width: 10),
                                  Text('Удалить из библиотеки', style: TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. ИНФОРМАЦИЯ О ТАЙТЛЕ
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final author = group.displayAuthor(_allGroups.map((g) => g.title), _authorBlacklist);
                          if (author.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(height: 4),

                      // Теги
                      if (group.tags.isNotEmpty)
                        SizedBox(
                          height: 18,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: group.tags.map((tag) {
                              return Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 6),

                      // Прогресс
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: group.overallProgressFraction,
                          backgroundColor: Colors.white12,
                          color: statusColor,
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 5),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            group.isCompleted ? 'Прочитано' : '$percent%',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatFileSize(group.totalSize),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackCover(Color primary) {
    return Container(
      color: const Color(0xFF1B1E26),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 48,
          color: primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
