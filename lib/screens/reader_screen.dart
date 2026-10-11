import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/reader_models.dart';
import '../services/archive_service.dart';
import '../services/storage_service.dart';
import '../widgets/reader_settings_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _currentPage = widget.initialPage.clamp(0, widget.pagePaths.length - 1);
    _pageController = PageController(initialPage: _currentPage);

    _initAspectRatios();

    // Скрываем системные бары через короткую паузу
    _scheduleHideControls();

    // Если начальная страница > 0 в режиме вебтун, после первой отрисовки скроллим
    if (_settings.mode == ReaderMode.webtoon && _currentPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToWebtoonPage(_currentPage);
      });
    }

    _webtoonScrollController.addListener(_onWebtoonScroll);
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

    if (_settings.mode == ReaderMode.webtoon) {
      _jumpToWebtoonPage(target);
    } else {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target);
      }
    }
    _saveCurrentProgress();
  }

  void _nextPage() {
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
      if (_currentPage < widget.pagePaths.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _prevPage() {
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
      if (_currentPage > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
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

        return ListView.builder(
          controller: _webtoonScrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: widget.pagePaths.length,
          itemBuilder: (context, index) {
            final filePath = widget.pagePaths[index];
            final ratio = _pageRatios[index] ?? 1.414;
            final expectedHeight = screenWidth * ratio;

            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.5,
              panEnabled: true,
              child: Image.file(
                File(filePath),
                fit: _getImageFit(),
                width: screenWidth,
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
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPageView() {
    final isVertical = _settings.mode == ReaderMode.verticalPage;
    final isRtl = _settings.mode == ReaderMode.horizontalRtl;

    return PageView.builder(
      controller: _pageController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      reverse: isRtl,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.pagePaths.length,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
        _saveCurrentProgress();
      },
      itemBuilder: (context, index) {
        final filePath = widget.pagePaths[index];
        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(filePath),
              fit: _getImageFit(),
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 250,
                  color: Colors.grey[900],
                  child: Center(
                    child: Text(
                      'Ошибка загрузки стр. ${index + 1}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
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
          // Быстрые кнопки режима чтения
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildQuickModeBtn(
                label: 'Вебтун',
                mode: ReaderMode.webtoon,
                icon: Icons.view_day_outlined,
              ),
              _buildQuickModeBtn(
                label: 'Вверх/Вниз',
                mode: ReaderMode.verticalPage,
                icon: Icons.swap_vert,
              ),
              _buildQuickModeBtn(
                label: 'Манга RTL',
                mode: ReaderMode.horizontalRtl,
                icon: Icons.keyboard_double_arrow_left,
              ),
              _buildQuickModeBtn(
                label: 'Комикс LTR',
                mode: ReaderMode.horizontalLtr,
                icon: Icons.keyboard_double_arrow_right,
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
