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
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MangaGroup> _allGroups = [];
  List<MangaGroup> _filteredGroups = [];
  List<String> _allTags = [];

  ReadingStatus? _selectedStatus;
  String? _selectedTag;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String _loadingMessage = '';
  ReaderSettings _settings = const ReaderSettings();

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate(silent: true);
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
    final tags = await StorageService.getAllTags();

    if (mounted) {
      setState(() {
        _settings = settings;
        _allGroups = groups;
        _allTags = tags;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    _filteredGroups = _allGroups.where((group) {
      final matchesSearch = _searchQuery.isEmpty ||
          group.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          group.tags.any((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));

      final matchesTag = _selectedTag == null || group.tags.contains(_selectedTag);
      final matchesStatus = _selectedStatus == null || group.status == _selectedStatus;

      return matchesSearch && matchesTag && matchesStatus;
    }).toList();
  }

  Future<void> _pickAndOpenArchives() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'cbz'],
        dialogTitle: 'Выберите архивы манги (.zip или .cbz)',
      );

      if (files.isNotEmpty) {
        await _processPickedArchives(files);
      }
    } catch (e) {
      try {
        final fallbackFiles = await FilePicker.pickFiles(
          type: FileType.any,
          dialogTitle: 'Выберите архивы манги (.zip или .cbz)',
        );
        if (fallbackFiles.isNotEmpty) {
          await _processPickedArchives(fallbackFiles);
        }
      } catch (fallbackError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка выбора файлов: $fallbackError'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _processPickedArchives(List<PlatformFile> files) async {
    final validPaths = files.map((f) => f.path).whereType<String>().toList();
    if (validPaths.isEmpty) return;

    if (!mounted) return;

    // Предлагаем сжатие добавленных zip/cbz архивов с опцией удаления оригинала
    final choice = await PromptCompressAddedDialog.show(
      context,
      filePaths: validPaths,
    );

    if (choice == null) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = choice.shouldCompress ? 'Сжатие архивов в WebP...' : 'Подготовка файлов...';
    });

    try {
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

        final group = await StorageService.findOrCreateGroupForFile(
          filePath: filePath,
          title: info.title,
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
        final firstPath = processedPaths.first;
        final parentDirName = p.basename(p.dirname(firstPath));
        final groupTitle = (parentDirName.isNotEmpty && parentDirName != '.' && parentDirName != '/')
            ? parentDirName
            : p.basenameWithoutExtension(firstPath);

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

        final newGroup = MangaGroup(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}',
          title: groupTitle,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш страниц успешно очищен')),
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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
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
            icon: const Icon(Icons.system_update_alt_rounded),
            tooltip: 'Проверить обновления',
            onPressed: () => _checkUpdate(silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Очистить кэш страниц',
            onPressed: _confirmClearCache,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'О приложении',
            onPressed: _showAboutDialog,
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
                        // Карточка добавления манги
                        _buildOpenArchiveCard(primary),
                        const SizedBox(height: 14),

                        // Поиск
                        if (_allGroups.isNotEmpty) ...[
                          _buildSearchBar(),
                          const SizedBox(height: 12),

                          // Вкладки статусов: Все, Читаю, В планах, Прочитано
                          _buildStatusTabs(primary),
                          const SizedBox(height: 10),

                          // Фильтры по тегам
                          if (_allTags.isNotEmpty) ...[
                            _buildTagsFilterRow(primary),
                            const SizedBox(height: 12),
                          ],
                        ],

                        // Заголовок библиотеки
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedStatus != null
                                  ? _selectedStatus!.label
                                  : (_selectedTag != null ? 'Тег: #$_selectedTag' : 'Библиотека манги'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_filteredGroups.isNotEmpty)
                              Text(
                                '${_filteredGroups.length} шт.',
                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // Сетка с большими обложками
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
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
        ],
      ),
    );
  }

  Widget _buildStatusTabs(Color primary) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatusFilterChip(null, 'Все', Icons.apps_rounded, primary),
          const SizedBox(width: 8),
          _buildStatusFilterChip(ReadingStatus.reading, 'Читаю', Icons.auto_stories_rounded, primary),
          const SizedBox(width: 8),
          _buildStatusFilterChip(ReadingStatus.planned, 'В планах', Icons.bookmark_border_rounded, Colors.amber),
          const SizedBox(width: 8),
          _buildStatusFilterChip(ReadingStatus.completed, 'Прочитано', Icons.check_circle_outline_rounded, Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(ReadingStatus? status, String label, IconData icon, Color activeColor) {
    final isSelected = _selectedStatus == status;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      side: BorderSide(
        color: isSelected ? activeColor : Colors.white12,
        width: isSelected ? 1.5 : 1,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedStatus = status;
            _applyFilter();
          });
        }
      },
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
        hintText: 'Поиск по названию или тегам...',
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

  Widget _buildTagsFilterRow(Color primary) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('Все теги'),
            selected: _selectedTag == null,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedTag = null;
                  _applyFilter();
                });
              }
            },
          ),
          const SizedBox(width: 8),
          ..._allTags.map((tag) {
            final isSelected = _selectedTag == tag;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('#$tag'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedTag = selected ? tag : null;
                    _applyFilter();
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOpenArchiveCard(Color primary) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.25),
            const Color(0xFF1E232D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _pickAndOpenArchives,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.folder_zip_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Открыть архив(ы) манги',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Поддерживается выбор нескольких глав сразу',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_outline,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 24,
                ),
              ],
            ),
          ),
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
            _searchQuery.isNotEmpty || _selectedTag != null || _selectedStatus != null
                ? 'По вашему запросу ничего не найдено.'
                : 'Нажмите кнопку выше, чтобы открыть первый zip/cbz архив с главами.',
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
        color: const Color(0xFF171A21),
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
