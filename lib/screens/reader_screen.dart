import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/reader_models.dart';
import '../services/archive_service.dart';
import '../services/compressor_service.dart';
import '../services/storage_service.dart';
import '../widgets/reader_settings_sheet.dart';
import 'manga_file_explorer_screen.dart';

class _ImageDimensionHelper {
  static (int, int)? getImageDimensions(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final raf = file.openSync(mode: FileMode.read);
      try {
        final header = Uint8List(1024);
        final bytesRead = raf.readIntoSync(header);
        if (bytesRead < 16) return null;

        // 1. PNG: 8 bytes signature, next chunk is IHDR
        if (header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4E &&
            header[3] == 0x47) {
          if (bytesRead >= 24) {
            final bd = ByteData.sublistView(header);
            final w = bd.getUint32(16, Endian.big);
            final h = bd.getUint32(20, Endian.big);
            return (w, h);
          }
        }

        // 2. WebP: RIFF....WEBP
        if (header[0] == 0x52 &&
            header[1] == 0x49 &&
            header[2] == 0x46 &&
            header[3] == 0x46 &&
            header[8] == 0x57 &&
            header[9] == 0x45 &&
            header[10] == 0x42 &&
            header[11] == 0x50) {
          final chunk = String.fromCharCodes(header.sublist(12, 16));
          final bd = ByteData.sublistView(header);
          if (chunk == 'VP8 ') {
            if (bytesRead >= 30) {
              final w = bd.getUint16(26, Endian.little) & 0x3FFF;
              final h = bd.getUint16(28, Endian.little) & 0x3FFF;
              return (w, h);
            }
          } else if (chunk == 'VP8L') {
            if (bytesRead >= 25) {
              final val = bd.getUint32(21, Endian.little);
              final w = 1 + (val & 0x3FFF);
              final h = 1 + ((val >> 14) & 0x3FFF);
              return (w, h);
            }
          } else if (chunk == 'VP8X') {
            if (bytesRead >= 30) {
              final w = 1 + (header[24] | (header[25] << 8) | (header[26] << 16));
              final h = 1 + (header[27] | (header[28] << 8) | (header[29] << 16));
              return (w, h);
            }
          }
        }

        // 3. JPEG: 0xFF, 0xD8
        if (header[0] == 0xFF && header[1] == 0xD8) {
          int offset = 2;
          while (offset < bytesRead - 8) {
            if (header[offset] != 0xFF) {
              offset++;
              continue;
            }
            final marker = header[offset + 1];
            if (marker >= 0xC0 && marker <= 0xC2) {
              final bd = ByteData.sublistView(header);
              final h = bd.getUint16(offset + 5, Endian.big);
              final w = bd.getUint16(offset + 7, Endian.big);
              return (w, h);
            }
            final bd = ByteData.sublistView(header);
            final length = bd.getUint16(offset + 2, Endian.big);
            offset += 2 + length;
          }
        }

        // 4. GIF
        if (header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46) {
          final bd = ByteData.sublistView(header);
          final w = bd.getUint16(6, Endian.little);
          final h = bd.getUint16(8, Endian.little);
          return (w, h);
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return null;
  }
}

class _DisplaySubPage {
  final int fileIndex;
  final String filePath;
  final bool isRightHalf;
  final bool isLeftHalf;

  const _DisplaySubPage({
    required this.fileIndex,
    required this.filePath,
    this.isRightHalf = false,
    this.isLeftHalf = false,
  });
}

class ReaderScreen extends StatefulWidget {
  final String title;
  final String archivePath;
  final List<String> pagePaths;
  final int initialPage;
  final ReaderSettings settings;
  final MangaGroup? mangaGroup;
  final int currentChapterIndex;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.archivePath,
    required this.pagePaths,
    this.initialPage = 0,
    required this.settings,
    this.mangaGroup,
    this.currentChapterIndex = 0,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late ReaderSettings _settings;
  late int _currentPage;
  late PageController _pageController;
  final ScrollController _webtoonScrollController = ScrollController();

  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Кэш соотношений сторон (height / width) и высот страниц для режима вебтун
  final Map<int, double> _pageRatios = {};
  final Map<int, double> _pageHeights = {};
  double _lastCalculatedWidth = 0;

  // Закладки и статистика времени
  Set<int> _bookmarkedPages = {};
  final DateTime _sessionStartTime = DateTime.now();

  // Автопрокрутка вебтуна
  bool _isAutoScrolling = false;
  double _autoScrollSpeed = 1.8;
  Timer? _autoScrollTimer;

  // Виртуальные страницы с учетом автосплита разворотов
  List<_DisplaySubPage> _displayPages = [];

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _currentPage = widget.initialPage.clamp(0, widget.pagePaths.length - 1);
    _pageController = PageController(initialPage: _currentPage);

    _initAspectRatios();
    _initDisplayPages();
    _loadBookmarks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheUpcomingPages(_currentPage);
    });

    // Скрываем системные бары через короткую паузу
    _scheduleHideControls();

    // Если начальная страница > 0 в режиме вебтун, после первой отрисовки скроллим
    if (_settings.mode == ReaderMode.webtoon && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToWebtoonPage(_currentPage);
      });
    }

    _webtoonScrollController.addListener(_onWebtoonScroll);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_settings.volumeKeysNavigation) return false;
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        _nextPage();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
        _prevPage();
        return true;
      }
    }
    return false;
  }

  void _vibrate() {
    if (_settings.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _loadBookmarks() async {
    final mangaId = widget.mangaGroup?.id ?? widget.title;
    final b = await StorageService.loadBookmarks(mangaId);
    if (mounted) {
      setState(() {
        _bookmarkedPages = b;
      });
    }
  }

  Future<void> _toggleBookmarkOnCurrentPage() async {
    final mangaId = widget.mangaGroup?.id ?? widget.title;
    final added = await StorageService.toggleBookmark(mangaId, _currentPage);
    final b = await StorageService.loadBookmarks(mangaId);
    if (mounted) {
      setState(() {
        _bookmarkedPages = b;
      });
      _vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added ? 'Страница ${_currentPage + 1} добавлена в закладки' : 'Закладка со страницы ${_currentPage + 1} удалена'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveCurrentPageSnapshot() async {
    try {
      final publicDir = await CompressorService.getPublicMangaDirectory();
      final snapshotsDir = Directory(p.join(publicDir.path, 'Snapshots'));
      if (!await snapshotsDir.exists()) {
        await snapshotsDir.create(recursive: true);
      }
      final currentFile = File(widget.pagePaths[_currentPage]);
      final ext = p.extension(currentFile.path);
      final cleanExt = ext.isNotEmpty ? ext : '.jpg';
      final cleanTitle = widget.title.replaceAll(RegExp(r'[^\w\d\-_]'), '_');
      final targetPath = p.join(
        snapshotsDir.path,
        '${cleanTitle}_page_${_currentPage + 1}_${DateTime.now().millisecondsSinceEpoch}$cleanExt',
      );
      await currentFile.copy(targetPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Кадр сохранён в Загрузки/NeManga/Snapshots/!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения кадра: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _precacheUpcomingPages(int currentIndex) {
    if (!mounted) return;
    StorageService.recordPageRead();
    for (int i = 1; i <= 4; i++) {
      final nextIdx = currentIndex + i;
      if (nextIdx < widget.pagePaths.length) {
        final path = widget.pagePaths[nextIdx];
        precacheImage(FileImage(File(path)), context);
      }
    }
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      _autoScrollTimer?.cancel();
      setState(() {
        _isAutoScrolling = false;
      });
    } else {
      setState(() {
        _isAutoScrolling = true;
      });
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_webtoonScrollController.hasClients) return;
        final next = _webtoonScrollController.offset + _autoScrollSpeed;
        if (next >= _webtoonScrollController.position.maxScrollExtent) {
          _toggleAutoScroll();
          return;
        }
        _webtoonScrollController.jumpTo(next);
      });
    }
  }

  void _initDisplayPages() {
    _displayPages = [];
    final isRtl = _settings.mode == ReaderMode.horizontalRtl;

    for (int i = 0; i < widget.pagePaths.length; i++) {
      final path = widget.pagePaths[i];
      final dims = _ImageDimensionHelper.getImageDimensions(path);
      final isWide = _settings.splitDoublePages &&
          _settings.mode != ReaderMode.webtoon &&
          dims != null &&
          dims.$1 > dims.$2 * 1.15;

      if (isWide) {
        if (isRtl) {
          _displayPages.add(_DisplaySubPage(fileIndex: i, filePath: path, isRightHalf: true));
          _displayPages.add(_DisplaySubPage(fileIndex: i, filePath: path, isLeftHalf: true));
        } else {
          _displayPages.add(_DisplaySubPage(fileIndex: i, filePath: path, isLeftHalf: true));
          _displayPages.add(_DisplaySubPage(fileIndex: i, filePath: path, isRightHalf: true));
        }
      } else {
        _displayPages.add(_DisplaySubPage(fileIndex: i, filePath: path));
      }
    }
  }

  void _initAspectRatios() {
    for (int i = 0; i < widget.pagePaths.length; i++) {
      final dims = _ImageDimensionHelper.getImageDimensions(widget.pagePaths[i]);
      if (dims != null && dims.$1 > 0) {
        _pageRatios[i] = dims.$2 / dims.$1; // height / width
      } else {
        _pageRatios[i] = 1.414;
      }
    }
  }

  void _calculateHeights(double width) {
    if (width <= 0) return;
    if (_lastCalculatedWidth == width && _pageHeights.length == widget.pagePaths.length) return;
    _lastCalculatedWidth = width;
    for (int i = 0; i < widget.pagePaths.length; i++) {
      final ratio = _pageRatios[i] ?? 1.414;
      _pageHeights[i] = width * ratio;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _autoScrollTimer?.cancel();
    final elapsedSeconds = DateTime.now().difference(_sessionStartTime).inSeconds;
    StorageService.recordReadingTime(elapsedSeconds);
    _hideControlsTimer?.cancel();
    _webtoonScrollController.removeListener(_onWebtoonScroll);
    _webtoonScrollController.dispose();
    _pageController.dispose();
    // Возвращаем системные бары при выходе на главный экран
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onWebtoonScroll() {
    if (_settings.mode != ReaderMode.webtoon) return;
    if (!_webtoonScrollController.hasClients) return;

    final position = _webtoonScrollController.position;
    final offset = position.pixels;
    final maxScroll = position.maxScrollExtent;
    final pageCount = widget.pagePaths.length;
    if (pageCount == 0) return;

    // 1. В самом верху ленты
    if (offset <= 10.0) {
      if (_currentPage != 0) {
        setState(() {
          _currentPage = 0;
        });
        _saveCurrentProgress();
      }
      return;
    }

    // 2. В самом низу ленты: ВСЕГДА фиксируем последнюю страницу
    if (offset >= maxScroll - 15.0 || position.extentAfter <= 15.0) {
      final lastPage = pageCount - 1;
      if (_currentPage != lastPage) {
        setState(() {
          _currentPage = lastPage;
        });
        _saveCurrentProgress();
      }
      return;
    }

    // 3. Вычисление текущей страницы по реальной накопленной высоте
    final screenWidth = MediaQuery.of(context).size.width;
    _calculateHeights(screenWidth);

    double accumulated = 0;
    int detectedPage = 0;

    for (int i = 0; i < pageCount; i++) {
      final height = _pageHeights[i] ?? (screenWidth * 1.414);
      if (offset < accumulated + (height * 0.6)) {
        detectedPage = i;
        break;
      }
      accumulated += height;
      detectedPage = i;
    }

    detectedPage = detectedPage.clamp(0, pageCount - 1);

    if (detectedPage != _currentPage) {
      setState(() {
        _currentPage = detectedPage;
      });
      _saveCurrentProgress();
    }
  }

  void _jumpToWebtoonPage(int page) {
    if (!_webtoonScrollController.hasClients) return;
    final pageCount = widget.pagePaths.length;
    if (pageCount == 0) return;

    final target = page.clamp(0, pageCount - 1);
    final maxScroll = _webtoonScrollController.position.maxScrollExtent;

    if (target == 0) {
      _webtoonScrollController.jumpTo(0.0);
      return;
    }

    if (target == pageCount - 1) {
      _webtoonScrollController.jumpTo(maxScroll);
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    _calculateHeights(screenWidth);

    double offset = 0;
    for (int i = 0; i < target; i++) {
      offset += (_pageHeights[i] ?? (screenWidth * 1.414));
    }

    _webtoonScrollController.jumpTo(
      offset.clamp(0.0, maxScroll),
    );
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls) {
        setState(() {
          _showControls = false;
        });
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _scheduleHideControls();
    } else {
      _hideControlsTimer?.cancel();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _saveCurrentProgress() async {
    await StorageService.saveBookProgress(
      filePath: widget.archivePath,
      currentPage: _currentPage,
      totalPages: widget.pagePaths.length,
      coverPath: widget.pagePaths.isNotEmpty ? widget.pagePaths.first : null,
    );
  }

  void _goToPage(int page) {
    final target = page.clamp(0, widget.pagePaths.length - 1);
    setState(() {
      _currentPage = target;
    });

    _vibrate();

    if (_settings.mode == ReaderMode.webtoon) {
      _jumpToWebtoonPage(target);
    } else {
      if (_pageController.hasClients) {
        if (_settings.dualPage && _settings.mode != ReaderMode.verticalPage) {
          final pairIdx = (target / 2).floor();
          _pageController.jumpToPage(pairIdx);
        } else {
          _pageController.jumpToPage(target);
        }
      }
    }
    _saveCurrentProgress();
  }

  void _nextPage() {
    _vibrate();
    if (_settings.mode == ReaderMode.webtoon) {
      if (!_webtoonScrollController.hasClients) return;
      final step = MediaQuery.of(context).size.height * 0.85;
      _webtoonScrollController.animateTo(
        (_webtoonScrollController.offset + step).clamp(
          0.0,
          _webtoonScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      if (_settings.dualPage && _settings.mode != ReaderMode.verticalPage) {
        final pairCount = (widget.pagePaths.length / 2).ceil();
        final currentPair = (_currentPage / 2).floor();
        if (currentPair < pairCount - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else if (widget.mangaGroup != null &&
            widget.currentChapterIndex < widget.mangaGroup!.chapters.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      } else {
        if (_currentPage < widget.pagePaths.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else if (widget.mangaGroup != null &&
            widget.currentChapterIndex < widget.mangaGroup!.chapters.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  void _prevPage() {
    _vibrate();
    if (_settings.mode == ReaderMode.webtoon) {
      if (!_webtoonScrollController.hasClients) return;
      final step = MediaQuery.of(context).size.height * 0.85;
      _webtoonScrollController.animateTo(
        (_webtoonScrollController.offset - step).clamp(
          0.0,
          _webtoonScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      if (_settings.dualPage && _settings.mode != ReaderMode.verticalPage) {
        final currentPair = (_currentPage / 2).floor();
        if (currentPair > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      } else {
        if (_currentPage > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  Future<void> _switchChapter(int targetIndex) async {
    final group = widget.mangaGroup;
    if (group == null || targetIndex < 0 || targetIndex >= group.chapters.length) return;

    await _saveCurrentProgress();

    final targetChapter = group.chapters[targetIndex];
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final info = await ArchiveService.loadManga(targetChapter.filePath);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (ctx) => ReaderScreen(
            title: '${group.title} — ${targetChapter.title}',
            archivePath: targetChapter.filePath,
            pagePaths: info.pagePaths,
            initialPage: targetChapter.lastPage,
            settings: _settings,
            mangaGroup: group,
            currentChapterIndex: targetIndex,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка открытия главы: $e')),
        );
      }
    }
  }

  void _handleScreenTap(TapUpDetails details) {
    final size = MediaQuery.of(context).size;
    final position = details.localPosition;

    // Зона по центру (34% ширины и 34% высоты) -> показать/скрыть меню
    if (_settings.tapCenterForMenu) {
      final centerRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.36,
        height: size.height * 0.36,
      );

      if (centerRect.contains(position)) {
        _toggleControls();
        return;
      }
    }

    // Если меню открыто, любой тап вне центра просто скрывает меню
    if (_showControls) {
      _toggleControls();
      return;
    }

    // Если включена навигация по тапу
    if (_settings.tapToNavigate) {
      final isVerticalMode = _settings.mode == ReaderMode.webtoon ||
          _settings.mode == ReaderMode.verticalPage;

      if (isVerticalMode) {
        // Тап в верхней или нижней половине экрана
        final isTopHalf = position.dy < size.height / 2;
        final isNext = _settings.invertTap ? isTopHalf : !isTopHalf;
        if (isNext) {
          _nextPage();
        } else {
          _prevPage();
        }
      } else {
        // Горизонтальный режим:
        // Для RTL (манга справа налево): тап слева = вперед, тап справа = назад
        // Для LTR (комикс слева направо): тап справа = вперед, тап слева = назад
        final isLeftHalf = position.dx < size.width / 2;
        bool isNext;
        if (_settings.mode == ReaderMode.horizontalRtl) {
          isNext = isLeftHalf;
        } else {
          isNext = !isLeftHalf;
        }

        if (_settings.invertTap) {
          isNext = !isNext;
        }

        if (isNext) {
          _nextPage();
        } else {
          _prevPage();
        }
      }
    }
  }

  Color _getBackgroundColor() {
    switch (_settings.colorTheme) {
      case ColorTheme.pureBlack:
        return Colors.black;
      case ColorTheme.darkGrey:
        return const Color(0xFF16191E);
      case ColorTheme.light:
        return const Color(0xFFF7F8FA);
    }
  }

  BoxFit _getImageFit() {
    switch (_settings.imageFit) {
      case ImageFit.fitWidth:
        return BoxFit.fitWidth;
      case ImageFit.fitHeight:
        return BoxFit.fitHeight;
      case ImageFit.contain:
        return BoxFit.contain;
    }
  }

  void _openSettings() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReaderSettingsSheet(
        settings: _settings,
        totalPages: widget.pagePaths.length,
        currentPage: _currentPage,
        onSettingsChanged: (newSettings) {
          setState(() {
            _settings = newSettings;
            _initDisplayPages();
            // Пересоздаем контроллер для синхронизации страницы
            if (_pageController.hasClients && _currentPage != _pageController.page?.round()) {
              _pageController = PageController(initialPage: _currentPage);
            }
          });
          StorageService.saveSettings(newSettings);
        },
        onPageJump: (page) {
          _goToPage(page);
        },
      ),
    ).then((_) {
      _scheduleHideControls();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ВАЖНОЕ ТРЕБОВАНИЕ:
    // Стандартный жест назад (Android back gesture / Predictive Back)
    // ВСЕГДА возвращает на главную страницу (HomeScreen), сохраняя прогресс,
    // а не листает на предыдущую страницу манги!
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        await _saveCurrentProgress();
      },
      child: Scaffold(
        backgroundColor: _getBackgroundColor(),
        body: GestureDetector(
          onTapUp: _handleScreenTap,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              // 1. Основное содержимое читалки
              Positioned.fill(
                child: _buildReaderContent(),
              ),

              // Фильтр глубокого затемнения и сепии
              if (_settings.customBrightness > 0.0 || _settings.warmFilter)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: _settings.warmFilter
                          ? Colors.amber.withValues(
                              alpha: 0.12 + (_settings.customBrightness * 0.45))
                          : Colors.black.withValues(alpha: _settings.customBrightness),
                    ),
                  ),
                ),

              // 2. Плавающий бейдж с номером страницы внизу справа
              if (!_showControls)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: 0.85,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '${_currentPage + 1} / ${widget.pagePaths.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. Верхняя панель (AppBar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  offset: _showControls ? Offset.zero : const Offset(0, -1),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _buildTopBar(),
                ),
              ),

              // Плавающая панель управления автопрокруткой
              if (_isAutoScrolling)
                Positioned(
                  bottom: 85,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _autoScrollSpeed = (_autoScrollSpeed - 0.5).clamp(0.5, 6.0);
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.remove, size: 16, color: Colors.white),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '${_autoScrollSpeed.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _autoScrollSpeed = (_autoScrollSpeed + 0.5).clamp(0.5, 6.0);
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.add, size: 16, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: _toggleAutoScroll,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.pause, size: 18, color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. Нижняя панель (Слайдер и кнопки)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  offset: _showControls ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _buildBottomBar(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderContent() {
    if (_settings.mode == ReaderMode.webtoon) {
      return _buildWebtoonView();
    } else {
      return _buildPageView();
    }
  }

  Widget _buildWebtoonView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        _calculateHeights(screenWidth);

        final hasGroup = widget.mangaGroup != null;
        final totalItems = widget.pagePaths.length + (hasGroup ? 1 : 0);

        return ListView.builder(
          controller: _webtoonScrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index == widget.pagePaths.length) {
              return _buildEndOfChapterWidget(screenWidth);
            }

            final filePath = widget.pagePaths[index];
            final ratio = _pageRatios[index] ?? 1.414;
            final expectedHeight = screenWidth * ratio;

            final cacheW = (screenWidth * 2).toInt();
            Widget pageWidget = Image.file(
              File(filePath),
              fit: _getImageFit(),
              width: screenWidth,
              cacheWidth: cacheW > 0 ? cacheW : null,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: expectedHeight > 0 ? expectedHeight : 250,
                  color: Colors.grey[900],
                  child: Center(
                    child: Text(
                      'Ошибка загрузки стр. ${index + 1}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              },
            );

            if (_settings.smartMarginCrop) {
              pageWidget = ClipRect(
                child: Transform.scale(
                  scale: 1.07,
                  child: pageWidget,
                ),
              );
            }

            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.5,
              panEnabled: true,
              child: pageWidget,
            );
          },
        );
      },
    );
  }

  Widget _buildPageView() {
    final isVertical = _settings.mode == ReaderMode.verticalPage;
    final isRtl = _settings.mode == ReaderMode.horizontalRtl;
    final hasGroup = widget.mangaGroup != null;
    final isDualPage = _settings.dualPage && !isVertical;

    if (isDualPage) {
      final pairCount = (widget.pagePaths.length / 2).ceil();
      final totalItems = pairCount + (hasGroup ? 1 : 0);

      return PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        reverse: isRtl,
        physics: const BouncingScrollPhysics(),
        itemCount: totalItems,
        onPageChanged: (pairIdx) {
          final singleIdx = (pairIdx * 2).clamp(0, widget.pagePaths.length - 1);
          setState(() {
            _currentPage = singleIdx;
          });
          _vibrate();
          _saveCurrentProgress();
        },
        itemBuilder: (context, pairIdx) {
          if (pairIdx == pairCount) {
            return Center(
              child: _buildEndOfChapterWidget(MediaQuery.of(context).size.width * 0.9),
            );
          }

          final p1Index = pairIdx * 2;
          final p2Index = p1Index + 1;
          final hasP2 = p2Index < widget.pagePaths.length;

          final firstPageWidget = Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Image.file(
                  File(widget.pagePaths[p1Index]),
                  fit: _getImageFit(),
                ),
              ),
            ),
          );

          if (!hasP2) {
            return Center(child: firstPageWidget);
          }

          final secondPageWidget = Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Image.file(
                  File(widget.pagePaths[p2Index]),
                  fit: _getImageFit(),
                ),
              ),
            ),
          );

          return Row(
            children: isRtl
                ? [secondPageWidget, const SizedBox(width: 4), firstPageWidget]
                : [firstPageWidget, const SizedBox(width: 4), secondPageWidget],
          );
        },
      );
    }

    final totalItems = _displayPages.length + (hasGroup ? 1 : 0);

    return PageView.builder(
      controller: _pageController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      reverse: isRtl,
      physics: const BouncingScrollPhysics(),
      itemCount: totalItems,
      onPageChanged: (index) {
        if (index < _displayPages.length) {
          final fileIdx = _displayPages[index].fileIndex;
          setState(() {
            _currentPage = fileIdx;
          });
          _vibrate();
          _saveCurrentProgress();
          _precacheUpcomingPages(fileIdx);
        }
      },
      itemBuilder: (context, index) {
        if (index == _displayPages.length) {
          return Center(
            child: _buildEndOfChapterWidget(MediaQuery.of(context).size.width * 0.9),
          );
        }

        final subPage = _displayPages[index];
        final filePath = subPage.filePath;

        final cacheW = (MediaQuery.of(context).size.width * 2).toInt();
        Widget pageImage;
        if (subPage.isRightHalf || subPage.isLeftHalf) {
          pageImage = ClipRect(
            child: Align(
              alignment: subPage.isRightHalf ? Alignment.centerRight : Alignment.centerLeft,
              widthFactor: 0.5,
              child: Image.file(
                File(filePath),
                fit: _getImageFit(),
                cacheWidth: cacheW > 0 ? cacheW : null,
              ),
            ),
          );
        } else {
          pageImage = Image.file(
            File(filePath),
            fit: _getImageFit(),
            cacheWidth: cacheW > 0 ? cacheW : null,
          );
        }

        if (_settings.smartMarginCrop) {
          pageImage = ClipRect(
            child: Transform.scale(
              scale: 1.07,
              child: pageImage,
            ),
          );
        }

        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: pageImage,
          ),
        );
      },
    );
  }

  Widget _buildEndOfChapterWidget(double width) {
    final group = widget.mangaGroup;
    final primary = Theme.of(context).colorScheme.primary;
    final hasNext = group != null && widget.currentChapterIndex < group.chapters.length - 1;
    final nextChapter = hasNext ? group.chapters[widget.currentChapterIndex + 1] : null;

    return Center(
      child: Container(
        width: width.clamp(280.0, 500.0),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E26),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasNext ? Icons.auto_stories_rounded : Icons.emoji_events_rounded,
                color: primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              hasNext ? 'Глава завершена' : 'Манга прочитана!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            if (hasNext && nextChapter != null) ...[
              Text(
                'Следующая: ${nextChapter.title}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: const Text('Следующая глава', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: () => _switchChapter(widget.currentChapterIndex + 1),
                ),
              ),
            ] else ...[
              const Text(
                '🎉 Вы прочитали все доступные главы этой манги!',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                  label: const Text('Отлично', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    if (group != null) {
                      StorageService.updateGroupStatus(group.id, ReadingStatus.completed);
                    }
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showThumbnailGrid() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14171E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Страницы главы (${widget.pagePaths.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: widget.pagePaths.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentPage;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _goToPage(index);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white12,
                            width: isCurrent ? 2.5 : 1,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(widget.pagePaths[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                                  ),
                                ),
                              ),
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
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  void _showChaptersList() {
    final group = widget.mangaGroup;
    if (group == null || group.chapters.isEmpty) return;

    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14171E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Главы (${group.chapters.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: group.chapters.length,
                  itemBuilder: (ctx, idx) {
                    final ch = group.chapters[idx];
                    final isCurrent = idx == widget.currentChapterIndex;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      selected: isCurrent,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      leading: SizedBox(
                        width: 36,
                        height: 48,
                        child: MangaArchiveThumbnail(
                          archivePath: ch.filePath,
                          width: 36,
                          height: 48,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      title: Text(
                        ch.title,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                        ),
                      ),
                      trailing: isCurrent ? const Icon(Icons.check, size: 18) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!isCurrent) {
                          _switchChapter(idx);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding, left: 8, right: 8, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.85),
            Colors.black.withOpacity(0.4),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Кнопка возврата на главную страницу
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'На главную',
            onPressed: () {
              _saveCurrentProgress();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_settings.mode == ReaderMode.webtoon)
            IconButton(
              icon: Icon(
                _isAutoScrolling ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded,
                color: _isAutoScrolling ? Colors.greenAccent : Colors.white,
              ),
              tooltip: _isAutoScrolling ? 'Приостановить автопрокрутку' : 'Автопрокрутка вебтуна',
              onPressed: _toggleAutoScroll,
            ),
          IconButton(
            icon: Icon(
              _bookmarkedPages.contains(_currentPage) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: _bookmarkedPages.contains(_currentPage) ? Colors.amber : Colors.white,
            ),
            tooltip: _bookmarkedPages.contains(_currentPage) ? 'Удалить закладку' : 'В закладки',
            onPressed: _toggleBookmarkOnCurrentPage,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Сохранить страницу в Загрузки',
            onPressed: _saveCurrentPageSnapshot,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'Настройки',
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottomPadding + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.9),
            Colors.black.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Слайдер страниц
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white70),
                onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
              ),
              Text(
                '${_currentPage + 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: Slider(
                    value: _currentPage.toDouble(),
                    min: 0,
                    max: (widget.pagePaths.length - 1).toDouble(),
                    onChanged: (val) {
                      _goToPage(val.round());
                    },
                  ),
                ),
              ),
              Text(
                '${widget.pagePaths.length}',
                style: const TextStyle(color: Colors.white70),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white70),
                onPressed: _currentPage < widget.pagePaths.length - 1
                    ? () => _goToPage(widget.pagePaths.length - 1)
                    : null,
              ),
            ],
          ),
          // Быстрые кнопки режима чтения и навигации
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.grid_view_rounded, color: Colors.white70),
                tooltip: 'Сетка страниц',
                onPressed: _showThumbnailGrid,
              ),
              if (widget.mangaGroup != null && widget.mangaGroup!.chapters.length > 1)
                IconButton(
                  icon: const Icon(Icons.list_alt_rounded, color: Colors.white70),
                  tooltip: 'Список глав',
                  onPressed: _showChaptersList,
                ),
              _buildQuickModeBtn(
                label: 'Вебтун',
                mode: ReaderMode.webtoon,
                icon: Icons.view_day_outlined,
              ),
              _buildQuickModeBtn(
                label: 'Манга RTL',
                mode: ReaderMode.horizontalRtl,
                icon: Icons.keyboard_double_arrow_left,
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                tooltip: 'Настройки',
                onPressed: _openSettings,
              ),
            ],
          ),
          if (widget.mangaGroup != null && widget.mangaGroup!.chapters.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: widget.currentChapterIndex > 0
                      ? () => _switchChapter(widget.currentChapterIndex - 1)
                      : null,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                  label: const Text('Пред. глава'),
                ),
                Text(
                  'Глава ${widget.currentChapterIndex + 1} из ${widget.mangaGroup!.chapters.length}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: widget.currentChapterIndex < widget.mangaGroup!.chapters.length - 1
                      ? () => _switchChapter(widget.currentChapterIndex + 1)
                      : null,
                  icon: const Icon(Icons.arrow_forward_ios, size: 14),
                  label: const Text('След. глава'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickModeBtn({
    required String label,
    required ReaderMode mode,
    required IconData icon,
  }) {
    final isSelected = _settings.mode == mode;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () {
        setState(() {
          _settings = _settings.copyWith(mode: mode);
          if (_pageController.hasClients) {
            _pageController = PageController(initialPage: _currentPage);
          }
        });
        StorageService.saveSettings(_settings);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primary.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? primary : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? primary : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
