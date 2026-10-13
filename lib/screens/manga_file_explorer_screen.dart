import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import '../models/reader_models.dart';
import '../services/archive_service.dart';
import '../services/compressor_service.dart';

enum ExplorerViewMode {
  grid,
  list,
}

enum ExplorerSortOption {
  dateDesc, // Сначала новые
  nameAsc, // По названию А-Я
  sizeDesc, // По размеру (большие сверху)
}

extension ExplorerSortOptionExt on ExplorerSortOption {
  String get label {
    switch (this) {
      case ExplorerSortOption.dateDesc:
        return 'Сначала новые';
      case ExplorerSortOption.nameAsc:
        return 'По названию (А–Я)';
      case ExplorerSortOption.sizeDesc:
        return 'По размеру';
    }
  }
}

/// Виджет обложки архива манги — извлекает и отображает первую страницу из архива
class MangaArchiveThumbnail extends StatefulWidget {
  final String archivePath;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const MangaArchiveThumbnail({
    super.key,
    required this.archivePath,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<MangaArchiveThumbnail> createState() => _MangaArchiveThumbnailState();
}

class _MangaArchiveThumbnailState extends State<MangaArchiveThumbnail> {
  String? _coverPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant MangaArchiveThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.archivePath != widget.archivePath) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    try {
      final path = await ArchiveService.extractCoverOnly(widget.archivePath);
      if (mounted) {
        setState(() {
          _coverPath = path;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

    Widget content;
    if (_coverPath != null && File(_coverPath!).existsSync()) {
      content = Image.file(
        File(_coverPath!),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
      );
    } else if (_isLoading) {
      content = Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF1F232D),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          ),
        ),
      );
    } else {
      content = _buildFallbackIcon();
    }

    return ClipRRect(
      borderRadius: radius,
      child: content,
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1F232D),
      child: const Center(
        child: Icon(Icons.folder_zip_rounded, color: Colors.amber, size: 36),
      ),
    );
  }
}

/// Нативный экран проводника файлов манги
class MangaFileExplorerScreen extends StatefulWidget {
  final ReaderSettings settings;
  final String? initialDirectoryPath;
  final String? title;

  const MangaFileExplorerScreen({
    super.key,
    required this.settings,
    this.initialDirectoryPath,
    this.title,
  });

  /// Открыть проводник и вернуть список выбранных абсолютных путей архивов
  static Future<List<String>?> pickMangaArchives(
    BuildContext context, {
    required ReaderSettings settings,
    String? initialDirectoryPath,
    String? title,
  }) async {
    return Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (ctx) => MangaFileExplorerScreen(
          settings: settings,
          initialDirectoryPath: initialDirectoryPath,
          title: title,
        ),
      ),
    );
  }

  @override
  State<MangaFileExplorerScreen> createState() => _MangaFileExplorerScreenState();
}

class _MangaFileExplorerScreenState extends State<MangaFileExplorerScreen> with WidgetsBindingObserver {
  Directory _currentDirectory = Directory('/');
  static const _storageChannel = MethodChannel('com.nemanga.reader/compressor');
  String? _downloadsPath;
  String? _directoryError;
  int _loadRevision = 0;
  bool _checkingAccess = false;
  bool _requestingAccess = false;
  bool _isLoading = true;
  bool _hasStorageAccess = false;

  List<Directory> _subDirectories = [];
  List<File> _mangaFiles = [];

  ExplorerViewMode _viewMode = ExplorerViewMode.grid;
  ExplorerSortOption _sortOption = ExplorerSortOption.dateDesc;

  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const _supportedExtensions = {'.zip', '.cbz'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndInit();
    }
  }

  Future<void> _checkPermissionAndInit() async {
    if (_checkingAccess || !mounted) return;
    _checkingAccess = true;
    try {
      final hasAccess = await CompressorService.hasAllFilesAccess();
      if (!mounted) return;
      setState(() {
        _hasStorageAccess = hasAccess;
        _directoryError = null;
      });
      if (!hasAccess) {
        _loadRevision++;
        setState(() {
          _isLoading = false;
          _subDirectories = [];
          _mangaFiles = [];
          _selectedPaths.clear();
          _isSelectionMode = false;
        });
        return;
      }
      final path = _downloadsPath ??
          await _storageChannel.invokeMethod<String>('getDownloadsDirectory');
      if (path == null || path.isEmpty || !p.isAbsolute(path)) {
        throw const FileSystemException('Android не сообщил путь к Загрузкам');
      }
      if (!mounted) return;
      if (_downloadsPath == null) {
        _currentDirectory = Directory(widget.initialDirectoryPath ?? path);
      }
      _downloadsPath = path;
      await _loadDirectoryContents();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _directoryError = 'Не удалось открыть хранилище: $e';
        });
      }
    } finally {
      _checkingAccess = false;
    }
  }

  Future<void> _requestStorageAccess() async {
    if (_requestingAccess) return;
    _requestingAccess = true;
    try {
      final opened = await CompressorService.requestAllFilesAccess();
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось открыть настройки доступа к файлам'),
        ));
      }
      // Открытие настроек не означает, что пользователь выдал разрешение.
      await _checkPermissionAndInit();
    } finally {
      _requestingAccess = false;
    }
  }

  Future<void> _openDownloads() async {
    await _checkPermissionAndInit();
    if (!mounted) return;
    if (!_hasStorageAccess) {
      await _requestStorageAccess();
      return;
    }
    final path = _downloadsPath;
    if (path != null) _navigateTo(Directory(path));
  }

  Future<void> _loadDirectoryContents() async {
    if (!mounted || !_hasStorageAccess) return;
    final revision = ++_loadRevision;
    final directory = _currentDirectory;
    setState(() {
      _isLoading = true;
      _directoryError = null;
    });
    final subDirs = <Directory>[];
    final files = <File>[];
    String? error;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (p.basename(entity.path).startsWith('.')) continue;
        if (entity is Directory) {
          subDirs.add(entity);
        } else if (entity is File &&
            _supportedExtensions.contains(p.extension(entity.path).toLowerCase())) {
          files.add(entity);
        }
      }
      subDirs.sort((a, b) => ArchiveService.naturalCompare(
          p.basename(a.path), p.basename(b.path)));
      _sortFiles(files);
    } catch (e) {
      error = 'Не удалось прочитать папку ${directory.path}: $e';
      subDirs.clear();
      files.clear();
    }
    if (!mounted || revision != _loadRevision) return;
    setState(() {
      _subDirectories = subDirs;
      _mangaFiles = files;
      _directoryError = error;
      _isLoading = false;
    });
  }

  void _sortFiles(List<File> files) {
    switch (_sortOption) {
      case ExplorerSortOption.dateDesc:
        files.sort((a, b) {
          final m1 = a.existsSync() ? a.lastModifiedSync() : DateTime(1970);
          final m2 = b.existsSync() ? b.lastModifiedSync() : DateTime(1970);
          return m2.compareTo(m1);
        });
        break;
      case ExplorerSortOption.nameAsc:
        files.sort((a, b) => ArchiveService.naturalCompare(p.basename(a.path), p.basename(b.path)));
        break;
      case ExplorerSortOption.sizeDesc:
        files.sort((a, b) {
          final s1 = a.existsSync() ? a.lengthSync() : 0;
          final s2 = b.existsSync() ? b.lengthSync() : 0;
          return s2.compareTo(s1);
        });
        break;
    }
  }

  void _navigateTo(Directory dir) {
    if (!mounted || !_hasStorageAccess) return;
    _currentDirectory = dir;
    _searchQuery = '';
    _searchController.clear();
    _loadDirectoryContents();
  }

  void _navigateUp() {
    final parent = _currentDirectory.parent;
    if (parent.path != _currentDirectory.path && parent.existsSync()) {
      _navigateTo(parent);
    }
  }

  bool _canNavigateUp() {
    final parent = _currentDirectory.parent;
    if (parent.path == _currentDirectory.path) return false;
    if (_currentDirectory.path == '/storage/emulated/0' || _currentDirectory.path == '/') return false;
    return true;
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPaths.add(path);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAllFiltered(List<File> files) {
    setState(() {
      final allFilteredPaths = files.map((f) => f.path).toSet();
      if (_selectedPaths.containsAll(allFilteredPaths)) {
        _selectedPaths.removeAll(allFilteredPaths);
        if (_selectedPaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPaths.addAll(allFilteredPaths);
        _isSelectionMode = true;
      }
    });
  }

  void _confirmSelection() {
    if (_selectedPaths.isNotEmpty) {
      final sorted = _selectedPaths.toList()..sort(ArchiveService.naturalCompare);
      Navigator.of(context).pop(sorted);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 Б';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year) {
      return '$d, $t';
    }
    return '$d.${dt.year}';
  }

  List<File> get _filteredFiles {
    if (_searchQuery.trim().isEmpty) return _mangaFiles;
    final query = _searchQuery.trim().toLowerCase();
    return _mangaFiles.where((f) {
      return p.basename(f.path).toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.settings.accentColor.color;
    final bg = widget.settings.appTheme.backgroundColor;
    final cardBg = widget.settings.appTheme.cardColor;

    final filteredFiles = _filteredFiles;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedPaths.clear();
                    _isSelectionMode = false;
                  });
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: _isSelectionMode
            ? Text(
                'Выбрано: ${_selectedPaths.length}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              )
            : (_isSearching ? _buildSearchField() : Text(widget.title ?? 'Выбор манги')),
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: () => _selectAllFiltered(filteredFiles),
              child: Text(
                _selectedPaths.containsAll(filteredFiles.map((f) => f.path)) ? 'Снять все' : 'Все',
                style: TextStyle(color: primary, fontWeight: FontWeight.bold),
              ),
            ),
          ] else ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              tooltip: _isSearching ? 'Закрыть поиск' : 'Поиск в папке',
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(
                _viewMode == ExplorerViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
              tooltip: _viewMode == ExplorerViewMode.grid ? 'Вид: Список' : 'Вид: Сетка',
              onPressed: () {
                setState(() {
                  _viewMode = _viewMode == ExplorerViewMode.grid ? ExplorerViewMode.list : ExplorerViewMode.grid;
                });
              },
            ),
            PopupMenuButton<ExplorerSortOption>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Сортировка',
              color: const Color(0xFF1B1E26),
              onSelected: (opt) {
                setState(() {
                  _sortOption = opt;
                  _sortFiles(_mangaFiles);
                });
              },
              itemBuilder: (ctx) => ExplorerSortOption.values.map((opt) {
                final isSelected = opt == _sortOption;
                return PopupMenuItem(
                  value: opt,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: isSelected ? primary : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Text(opt.label),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
      floatingActionButton: _isSelectionMode && _selectedPaths.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.check_rounded),
              label: Text('Добавить (${_selectedPaths.length})'),
              onPressed: _confirmSelection,
            )
          : null,
      body: !_hasStorageAccess
          ? (_isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(child: _buildPermissionBanner(primary)))
          : Column(
        children: [
          if (!_hasStorageAccess) _buildPermissionBanner(primary),

          // 1. Хлебные крошки и панель навигации по папкам
          if (_downloadsPath != null) _buildNavigationBreadcrumbs(primary),

          // 2. Быстрые закладки папок (Downloads, NeManga, etc.)
          if (_downloadsPath != null) _buildQuickFolderShortcuts(primary),

          const Divider(height: 1, color: Colors.white12),

          // 3. Основное содержимое: папки + архивы манги
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primary))
                : RefreshIndicator(
                    onRefresh: _loadDirectoryContents,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        // Папки в текущей директории
                        if (_subDirectories.isNotEmpty && _searchQuery.isEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Text(
                                'Папки (${_subDirectories.length}):',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, idx) => _buildFolderTile(_subDirectories[idx], primary, cardBg),
                                childCount: _subDirectories.length,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        ],

                        // Заголовок найденных архивов
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Архивы манги (${filteredFiles.length}):',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                                ),
                                if (_isSelectionMode)
                                  Text(
                                    'Выбрано: ${_selectedPaths.length}',
                                    style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Пустое состояние
                        if (filteredFiles.isEmpty)
                          SliverToBoxAdapter(
                            child: _buildEmptyState(primary),
                          )
                        else if (_viewMode == ExplorerViewMode.grid)
                          // Сетка обложек архивов
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.58,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (ctx, idx) => _buildMangaGridCard(filteredFiles[idx], primary, cardBg),
                                childCount: filteredFiles.length,
                              ),
                            ),
                          )
                        else
                          // Детальный список архивов
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, idx) => _buildMangaListTile(filteredFiles[idx], primary, cardBg),
                                childCount: filteredFiles.length,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: const InputDecoration(
        hintText: 'Поиск по имени архива...',
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
        });
      },
    );
  }

  Widget _buildPermissionBanner(Color primary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_special_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Доступ к хранилищу ограничен',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Чтобы открывать папку «Загрузки» смартфона, просматривать архивы и удалять оригиналы после сжатия, Android требует системное разрешение «Доступ ко всем файлам».',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.settings_suggest_rounded, size: 18),
              label: const Text('Разрешить доступ ко всем файлам'),
              onPressed: _requestStorageAccess,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBreadcrumbs(Color primary) {
    final parts = _currentDirectory.path.split('/').where((s) => s.isNotEmpty).toList();
    final isInsideSandbox = _currentDirectory.path.contains('/data/user/0') ||
        _currentDirectory.path.contains('/app_flutter') ||
        _currentDirectory.path.contains('/Android/data');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white.withValues(alpha: 0.03),
      child: Row(
        children: [
          if (_canNavigateUp())
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              tooltip: 'Вверх на уровень',
              onPressed: _navigateUp,
            ),
          const Icon(Icons.folder_open_rounded, size: 20, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (int i = 0; i < parts.length; i++) ...[
                    if (i > 0) const Text(' / ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    InkWell(
                      onTap: () {
                        final targetPath = '/${parts.sublist(0, i + 1).join('/')}';
                        final targetDir = Directory(targetPath);
                        if (targetDir.existsSync()) {
                          _navigateTo(targetDir);
                        }
                      },
                      child: Text(
                        parts[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == parts.length - 1 ? FontWeight.bold : FontWeight.normal,
                          color: i == parts.length - 1 ? primary : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isInsideSandbox)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.download_rounded, size: 14, color: Colors.amber),
                label: const Text('В Загрузки', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
                side: const BorderSide(color: Colors.amber),
                onPressed: _openDownloads,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickFolderShortcuts(Color primary) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildShortcutChip('📁 Downloads', _downloadsPath!, primary),
          const SizedBox(width: 8),
          _buildShortcutChip('📁 NeManga', p.join(_downloadsPath!, 'NeManga'), primary),
          const SizedBox(width: 8),
          _buildShortcutChip('📁 Документы', p.join(p.dirname(_downloadsPath!), 'Documents'), primary),
          const SizedBox(width: 8),
          _buildShortcutChip('📱 Память', p.dirname(_downloadsPath!), primary),
        ],
      ),
    );
  }

  Widget _buildShortcutChip(String label, String path, Color primary) {
    final isCurrent = _currentDirectory.path == path;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isCurrent,
      selectedColor: primary.withValues(alpha: 0.25),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: TextStyle(
        color: isCurrent ? primary : Colors.white70,
        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: isCurrent ? primary : Colors.white12),
      onSelected: (_) {
        if (path == _downloadsPath) {
          _openDownloads();
        } else {
          _navigateTo(Directory(path));
        }
      },
    );
  }

  Widget _buildFolderTile(Directory dir, Color primary, Color cardBg) {
    final name = p.basename(dir.path);
    return Card(
      color: cardBg,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.white10),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.folder_rounded, color: Colors.amber, size: 28),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
        onTap: () => _navigateTo(dir),
      ),
    );
  }

  Widget _buildMangaGridCard(File file, Color primary, Color cardBg) {
    final path = file.path;
    final isSelected = _selectedPaths.contains(path);
    final title = p.basenameWithoutExtension(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final mtime = file.existsSync() ? file.lastModifiedSync() : DateTime.now();

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelect(path);
        } else {
          // Одиночный клик сразу выбирает и возвращает этот файл
          Navigator.of(context).pop([path]);
        }
      },
      onLongPress: () {
        _toggleSelect(path);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primary : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Обложка архива манги (всегда первая картинка)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MangaArchiveThumbnail(
                    archivePath: path,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  // Бейдж формата (.cbz / .zip)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        p.extension(path).toUpperCase().replaceAll('.', ''),
                        style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  // Чекбокс при мультивыборе
                  if (_isSelectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? primary : Colors.black54,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isSelected ? Icons.check : Icons.circle_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Метаданные (название и размер)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatBytes(size),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      Text(
                        _formatDate(mtime),
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMangaListTile(File file, Color primary, Color cardBg) {
    final path = file.path;
    final isSelected = _selectedPaths.contains(path);
    final title = p.basenameWithoutExtension(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final mtime = file.existsSync() ? file.lastModifiedSync() : DateTime.now();

    return Card(
      color: cardBg,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? primary : Colors.white10,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelect(path);
          } else {
            Navigator.of(context).pop([path]);
          }
        },
        onLongPress: () => _toggleSelect(path),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Превью первой страницы архива
              SizedBox(
                width: 52,
                height: 72,
                child: MangaArchiveThumbnail(
                  archivePath: path,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              // Название и детали
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            p.extension(path).toUpperCase().replaceAll('.', ''),
                            style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_formatBytes(size), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 8),
                        Text('•  ${_formatDate(mtime)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isSelectionMode)
                Checkbox(
                  value: isSelected,
                  activeColor: primary,
                  onChanged: (_) => _toggleSelect(path),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Icon(Icons.folder_zip_outlined, size: 54, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            _directoryError == null ? 'Архивов манги не найдено' : 'Папка недоступна',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            _directoryError ?? 'В этой папке нет файлов с расширением .zip или .cbz. Перейдите в другую папку выше.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Перейти в Загрузки'),
            onPressed: _openDownloads,
          ),
        ],
      ),
    );
  }
}
