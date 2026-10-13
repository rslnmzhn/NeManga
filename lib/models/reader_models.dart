import 'dart:convert';
import 'package:flutter/material.dart';

/// Режим чтения
enum ReaderMode {
  webtoon,       // Вертикальная непрерывная лента
  verticalPage,  // Вертикальный постраничный свайп
  horizontalRtl, // Горизонтальный постраничный (справа налево - классическая манга)
  horizontalLtr, // Горизонтальный постраничный (слева направо - комиксы/манхва)
}

/// Направление свайпа для смены страницы
enum SwipeDirection {
  natural,  // Естественное (вверх/вправо = следующая)
  inverted, // Инвертированное
}

/// Тип подгонки изображения
enum ImageFit {
  fitWidth,   // По ширине (идеально для телефонов и манги)
  fitHeight,  // По высоте
  contain,    // Целиком на экране
}

enum ColorTheme {
  pureBlack, // AMOLED черный (для максимальной энергоэффективности)
  darkGrey,  // Темно-серый
  light,     // Светлый
}

/// Акцентный цвет интерфейса приложения
enum AppAccentColor {
  sakura,    // 0: 🌸 Сакура (#FF6B9D)
  cyberpunk, // 1: 💜 Киберпанк (#A855F7)
  mint,      // 2: 🍃 Неоновая мята (#10B981)
  amber,     // 3: ☀️ Янтарь (#F59E0B)
  blue,      // 4: ⚡ Электрик блю (#3B82F6)
}

extension AppAccentColorExt on AppAccentColor {
  Color get color {
    switch (this) {
      case AppAccentColor.sakura:
        return const Color(0xFFFF6B9D);
      case AppAccentColor.cyberpunk:
        return const Color(0xFFA855F7);
      case AppAccentColor.mint:
        return const Color(0xFF10B981);
      case AppAccentColor.amber:
        return const Color(0xFFF59E0B);
      case AppAccentColor.blue:
        return const Color(0xFF3B82F6);
    }
  }

  String get label {
    switch (this) {
      case AppAccentColor.sakura:
        return '🌸 Сакура';
      case AppAccentColor.cyberpunk:
        return '💜 Киберпанк';
      case AppAccentColor.mint:
        return '🍃 Мята';
      case AppAccentColor.amber:
        return '☀️ Янтарь';
      case AppAccentColor.blue:
        return '⚡ Электрик блю';
    }
  }
}

/// Тема оформления фона приложения
enum AppThemeMode {
  darkSlate, // Тёмный графит (#0F1115)
  amoled,    // Настоящий глубокий AMOLED (#000000)
}

extension AppThemeModeExt on AppThemeMode {
  Color get backgroundColor {
    switch (this) {
      case AppThemeMode.darkSlate:
        return const Color(0xFF0F1115);
      case AppThemeMode.amoled:
        return const Color(0xFF000000);
    }
  }

  Color get cardColor {
    switch (this) {
      case AppThemeMode.darkSlate:
        return const Color(0xFF161920);
      case AppThemeMode.amoled:
        return const Color(0xFF080808);
    }
  }

  String get label {
    switch (this) {
      case AppThemeMode.darkSlate:
        return 'Тёмный графит';
      case AppThemeMode.amoled:
        return 'True AMOLED (#000000)';
    }
  }
}

/// Порядок сортировки библиотечной манги
enum LibrarySortOrder {
  recent,   // По недавнему чтению
  title,    // По алфавиту (А–Я)
  progress, // По проценту прочтения
  author,   // По автору
}

extension LibrarySortOrderExt on LibrarySortOrder {
  String get label {
    switch (this) {
      case LibrarySortOrder.recent:
        return 'Недавние';
      case LibrarySortOrder.title:
        return 'По названию (А–Я)';
      case LibrarySortOrder.progress:
        return 'По прогрессу';
      case LibrarySortOrder.author:
        return 'По автору';
    }
  }
}

/// Статус прочтения манги
enum ReadingStatus {
  none,      // Без статуса
  reading,   // Читаю
  planned,   // В планах
  completed, // Прочитано
}

extension ReadingStatusExtension on ReadingStatus {
  String get label {
    switch (this) {
      case ReadingStatus.none:
        return 'Без статуса';
      case ReadingStatus.reading:
        return 'Читаю';
      case ReadingStatus.planned:
        return 'В планах';
      case ReadingStatus.completed:
        return 'Прочитано';
    }
  }
}

class ReaderSettings {
  final ReaderMode mode;
  final bool tapToNavigate;
  final bool tapCenterForMenu;
  final bool invertTap;
  final ImageFit imageFit;
  final bool keepScreenOn;
  final ColorTheme colorTheme;
  final bool volumeKeysNavigation;
  final bool hapticFeedback;
  final bool dualPage;
  final double customBrightness; // 0.0 .. 0.8 затемнение
  final bool warmFilter;         // тёплый ночной фильтр
  final AppThemeMode appTheme;
  final AppAccentColor accentColor;
  final LibrarySortOrder sortOrder;

  const ReaderSettings({
    this.mode = ReaderMode.webtoon,
    this.tapToNavigate = true,
    this.tapCenterForMenu = true,
    this.invertTap = false,
    this.imageFit = ImageFit.fitWidth,
    this.keepScreenOn = true,
    this.colorTheme = ColorTheme.pureBlack,
    this.volumeKeysNavigation = true,
    this.hapticFeedback = true,
    this.dualPage = false,
    this.customBrightness = 0.0,
    this.warmFilter = false,
    this.appTheme = AppThemeMode.darkSlate,
    this.accentColor = AppAccentColor.amber,
    this.sortOrder = LibrarySortOrder.recent,
  });

  ReaderSettings copyWith({
    ReaderMode? mode,
    bool? tapToNavigate,
    bool? tapCenterForMenu,
    bool? invertTap,
    ImageFit? imageFit,
    bool? keepScreenOn,
    ColorTheme? colorTheme,
    bool? volumeKeysNavigation,
    bool? hapticFeedback,
    bool? dualPage,
    double? customBrightness,
    bool? warmFilter,
    AppThemeMode? appTheme,
    AppAccentColor? accentColor,
    LibrarySortOrder? sortOrder,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      tapToNavigate: tapToNavigate ?? this.tapToNavigate,
      tapCenterForMenu: tapCenterForMenu ?? this.tapCenterForMenu,
      invertTap: invertTap ?? this.invertTap,
      imageFit: imageFit ?? this.imageFit,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      colorTheme: colorTheme ?? this.colorTheme,
      volumeKeysNavigation: volumeKeysNavigation ?? this.volumeKeysNavigation,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      dualPage: dualPage ?? this.dualPage,
      customBrightness: customBrightness ?? this.customBrightness,
      warmFilter: warmFilter ?? this.warmFilter,
      appTheme: appTheme ?? this.appTheme,
      accentColor: accentColor ?? this.accentColor,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mode': mode.index,
      'tapToNavigate': tapToNavigate,
      'tapCenterForMenu': tapCenterForMenu,
      'invertTap': invertTap,
      'imageFit': imageFit.index,
      'keepScreenOn': keepScreenOn,
      'colorTheme': colorTheme.index,
      'volumeKeysNavigation': volumeKeysNavigation,
      'hapticFeedback': hapticFeedback,
      'dualPage': dualPage,
      'customBrightness': customBrightness,
      'warmFilter': warmFilter,
      'appTheme': appTheme.index,
      'accentColor': accentColor.index,
      'sortOrder': sortOrder.index,
    };
  }

  factory ReaderSettings.fromMap(Map<String, dynamic> map) {
    return ReaderSettings(
      mode: ReaderMode.values[(map['mode'] ?? 0).clamp(0, ReaderMode.values.length - 1)],
      tapToNavigate: map['tapToNavigate'] ?? true,
      tapCenterForMenu: map['tapCenterForMenu'] ?? true,
      invertTap: map['invertTap'] ?? false,
      imageFit: ImageFit.values[(map['imageFit'] ?? 0).clamp(0, ImageFit.values.length - 1)],
      keepScreenOn: map['keepScreenOn'] ?? true,
      colorTheme: ColorTheme.values[(map['colorTheme'] ?? 0).clamp(0, ColorTheme.values.length - 1)],
      volumeKeysNavigation: map['volumeKeysNavigation'] ?? true,
      hapticFeedback: map['hapticFeedback'] ?? true,
      dualPage: map['dualPage'] ?? false,
      customBrightness: (map['customBrightness'] as num?)?.toDouble() ?? 0.0,
      warmFilter: map['warmFilter'] ?? false,
      appTheme: AppThemeMode.values[(map['appTheme'] ?? 0).clamp(0, AppThemeMode.values.length - 1)],
      accentColor: AppAccentColor.values[(map['accentColor'] ?? 3).clamp(0, AppAccentColor.values.length - 1)],
      sortOrder: LibrarySortOrder.values[(map['sortOrder'] ?? 0).clamp(0, LibrarySortOrder.values.length - 1)],
    );
  }

  String toJson() => json.encode(toMap());
  factory ReaderSettings.fromJson(String source) =>
      ReaderSettings.fromMap(json.decode(source));
}

/// Отдельная глава / том манги (привязанная к конкретному zip-архиву)
class ChapterItem {
  final String id;
  final String filePath;
  final String title;
  final int totalPages;
  final int lastPage;
  final DateTime lastReadTime;
  final int fileSize;
  final bool isOptimized;

  ChapterItem({
    required this.id,
    required this.filePath,
    required this.title,
    required this.totalPages,
    required this.lastPage,
    required this.lastReadTime,
    required this.fileSize,
    this.isOptimized = false,
  });

  bool get isCompleted => totalPages > 0 && lastPage >= totalPages - 1;
  double get progressFraction =>
      totalPages > 0 ? ((lastPage + 1) / totalPages).clamp(0.0, 1.0) : 0.0;
  int get progressPercent => (progressFraction * 100).toInt();

  ChapterItem copyWith({
    String? id,
    String? filePath,
    String? title,
    int? totalPages,
    int? lastPage,
    DateTime? lastReadTime,
    int? fileSize,
    bool? isOptimized,
  }) {
    return ChapterItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      totalPages: totalPages ?? this.totalPages,
      lastPage: lastPage ?? this.lastPage,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      fileSize: fileSize ?? this.fileSize,
      isOptimized: isOptimized ?? this.isOptimized,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'totalPages': totalPages,
      'lastPage': lastPage,
      'lastReadTime': lastReadTime.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'isOptimized': isOptimized,
    };
  }

  factory ChapterItem.fromMap(Map<String, dynamic> map) {
    return ChapterItem(
      id: map['id'] ?? (map['filePath'] ?? ''),
      filePath: map['filePath'] ?? '',
      title: map['title'] ?? '',
      totalPages: map['totalPages'] ?? 0,
      lastPage: map['lastPage'] ?? 0,
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(
        map['lastReadTime'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      fileSize: map['fileSize'] ?? 0,
      isOptimized: map['isOptimized'] ?? false,
    );
  }
}

/// Информация об авторе манги для каталога
class AuthorData {
  final String name;
  final List<String> tags;
  final String? coverPath;
  final List<MangaGroup> mangaList;

  AuthorData({
    required this.name,
    this.tags = const [],
    this.coverPath,
    this.mangaList = const [],
  });

  int get totalMangaCount => mangaList.length;
  int get totalChaptersCount => mangaList.fold(0, (sum, m) => sum + m.chapters.length);
  int get totalSizeBytes => mangaList.fold(0, (sum, m) => sum + m.totalSize);
}

/// Помощник для автоматической каталогизации и извлечения авторов манги
class AuthorDetector {
  static const Set<String> _ignoreTokens = {
    'manga', 'manhwa', 'manhua', 'comic', 'comics', 'raw', 'eng', 'rus',
    'ru', 'en', 'cbr', 'cbz', 'zip', 'pdf', 'vol', 'volume', 'ch', 'chapter',
    'digital', '1080p', 'complete', 'ongoing', 'webtoon'
  };

  /// Проверка строки кандидата на совпадение с шаблоном блеклиста (поддержка *, author-*, [site]*)
  static bool matchesBlacklist(String candidate, [Iterable<String>? blacklist]) {
    if (blacklist == null || blacklist.isEmpty) return false;
    final cand = candidate.trim().toLowerCase();
    if (cand.isEmpty) return false;

    for (final rawPattern in blacklist) {
      final pattern = rawPattern.trim().toLowerCase();
      if (pattern.isEmpty) continue;

      if (pattern == '*') return true;

      if (pattern.contains('*')) {
        try {
          final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
          final regex = RegExp('^$escaped\\\$', caseSensitive: false);
          if (regex.hasMatch(cand)) return true;
        } catch (_) {}

        if (pattern.endsWith('*') && !pattern.startsWith('*')) {
          final prefix = pattern.substring(0, pattern.length - 1);
          if (cand.startsWith(prefix)) return true;
        } else if (pattern.startsWith('*') && !pattern.endsWith('*')) {
          final suffix = pattern.substring(1);
          if (cand.endsWith(suffix)) return true;
        } else if (pattern.startsWith('*') && pattern.endsWith('*')) {
          final middle = pattern.substring(1, pattern.length - 1);
          if (cand.contains(middle)) return true;
        }
      } else {
        if (cand == pattern ||
            cand.startsWith('$pattern-') ||
            cand.startsWith('${pattern}_') ||
            cand.startsWith('$pattern.')) {
          return true;
        }
      }
    }
    return false;
  }

  /// Автоматическое определение автора из заголовка манги с учетом блеклиста
  static String? detectAuthor(
    String title, [
    Iterable<String>? allLibraryTitles,
    Iterable<String>? blacklist,
  ]) {
    final clean = title.trim();
    if (clean.isEmpty) return null;

    // 1. Паттерны скобок: [Автор] Название или (Автор) Название или 【Автор】 Название
    final bracketMatches = RegExp(r'[\[\(\【\{]([^\]\)\】\}]+)[\]\)\】\}]').allMatches(clean);
    for (final match in bracketMatches) {
      final candidate = match.group(1)?.trim();
      if (candidate != null && candidate.isNotEmpty && candidate.length >= 2) {
        final lower = candidate.toLowerCase();
        final isVolOrCh = RegExp(r'^(vol|volume|том|ch|chapter|глава|\d+)', caseSensitive: false).hasMatch(lower);
        if (!isVolOrCh && !_ignoreTokens.contains(lower) && !matchesBlacklist(candidate, blacklist)) {
          return candidate;
        }
      }
    }

    // 2. Паттерн разделителя: "Автор - Название" (но не "Том 1 - Глава 2")
    if (clean.contains(' - ')) {
      final parts = clean.split(' - ');
      if (parts.length >= 2) {
        final prefix = parts[0].trim();
        final lower = prefix.toLowerCase();
        final isVolOrCh = RegExp(r'^(vol|volume|том|ch|chapter|глава|\d+)', caseSensitive: false).hasMatch(lower);
        if (!isVolOrCh && prefix.isNotEmpty && prefix.length >= 2 && prefix.length <= 40) {
          if (!matchesBlacklist(prefix, blacklist)) {
            return prefix;
          }
        }
      }
    }

    // 3. Отслеживание повторяющихся первых слов / префиксов среди всех тайтлов библиотеки
    if (allLibraryTitles != null && allLibraryTitles.length >= 2) {
      final commonAuthor = _findCommonPrefixAuthor(clean, allLibraryTitles, blacklist);
      if (commonAuthor != null && commonAuthor.isNotEmpty) {
        if (!matchesBlacklist(commonAuthor, blacklist)) {
          return commonAuthor;
        }
      }
    }

    return null;
  }

  /// Поиск общего автора/префикса из повторяющихся слов в библиотеке
  static String? _findCommonPrefixAuthor(
    String title,
    Iterable<String> allTitles, [
    Iterable<String>? blacklist,
  ]) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return null;

    final maxLen = words.length >= 3 ? 3 : words.length - 1;
    for (int len = maxLen; len >= 1; len--) {
      final prefixWords = words.take(len).join(' ').trim();
      if (prefixWords.length < 3) continue;
      final lowerPrefix = prefixWords.toLowerCase();

      if (RegExp(r'^(vol|volume|том|ch|chapter|глава|\d+)', caseSensitive: false).hasMatch(lowerPrefix)) {
        continue;
      }

      if (matchesBlacklist(prefixWords, blacklist)) {
        continue;
      }

      int count = 0;
      for (final other in allTitles) {
        if (other == title) continue;
        final otherLower = other.trim().toLowerCase();
        if (otherLower.startsWith(lowerPrefix) ||
            otherLower.contains('[$lowerPrefix]') ||
            otherLower.contains('($lowerPrefix)')) {
          count++;
        }
      }

      if (count >= 1) {
        return prefixWords;
      }
    }
    return null;
  }
}

/// Группа / Тайтл манги (содержит одну или несколько глав-архивов)
class MangaGroup {
  final String id;
  final String title;
  final String? author;
  final String? coverPath;
  final ReadingStatus status;
  final List<String> tags;
  final List<ChapterItem> chapters;
  final int currentChapterIndex;
  final DateTime updatedAt;

  MangaGroup({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    this.status = ReadingStatus.reading,
    this.tags = const [],
    this.chapters = const [],
    this.currentChapterIndex = 0,
    required this.updatedAt,
  });

  /// Получить автора манги (явно заданного или извлеченного из названия)
  String displayAuthor([Iterable<String>? allLibraryTitles, Iterable<String>? blacklist]) {
    if (author != null && author!.trim().isNotEmpty) {
      final explicit = author!.trim();
      if (AuthorDetector.matchesBlacklist(explicit, blacklist)) {
        return '';
      }
      return explicit;
    }
    return AuthorDetector.detectAuthor(title, allLibraryTitles, blacklist) ?? '';
  }

  int get totalSize => chapters.fold(0, (sum, c) => sum + c.fileSize);
  int get totalPages => chapters.fold(0, (sum, c) => sum + c.totalPages);
  int get completedChaptersCount => chapters.where((c) => c.isCompleted).length;
  bool get isOptimized => chapters.isNotEmpty && chapters.every((c) => c.isOptimized);

  bool get isCompleted =>
      status == ReadingStatus.completed ||
      (chapters.isNotEmpty && completedChaptersCount == chapters.length);

  double get overallProgressFraction {
    if (chapters.isEmpty) return 0.0;
    int readPages = 0;
    int allPages = 0;
    for (final c in chapters) {
      if (c.totalPages > 0) {
        allPages += c.totalPages;
        if (c.isCompleted) {
          readPages += c.totalPages;
        } else if (c.lastPage > 0) {
          readPages += (c.lastPage + 1).clamp(0, c.totalPages);
        }
      } else {
        // Не открытая еще глава
        allPages += 1;
        if (c.isCompleted) {
          readPages += 1;
        }
      }
    }
    return allPages > 0 ? (readPages / allPages).clamp(0.0, 1.0) : 0.0;
  }

  int get overallProgressPercent => (overallProgressFraction * 100).toInt();

  ChapterItem? get currentChapter =>
      chapters.isNotEmpty && currentChapterIndex < chapters.length
          ? chapters[currentChapterIndex]
          : (chapters.isNotEmpty ? chapters.first : null);

  MangaGroup copyWith({
    String? id,
    String? title,
    String? author,
    String? coverPath,
    ReadingStatus? status,
    List<String>? tags,
    List<ChapterItem>? chapters,
    int? currentChapterIndex,
    DateTime? updatedAt,
  }) {
    return MangaGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      chapters: chapters ?? this.chapters,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      if (author != null) 'author': author,
      'coverPath': coverPath,
      'status': status.index,
      'tags': tags,
      'chapters': chapters.map((c) => c.toMap()).toList(),
      'currentChapterIndex': currentChapterIndex,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory MangaGroup.fromMap(Map<String, dynamic> map) {
    return MangaGroup(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] as String?,
      coverPath: map['coverPath'],
      status: ReadingStatus.values[(map['status'] ?? 1).clamp(0, ReadingStatus.values.length - 1)],
      tags: (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      chapters: (map['chapters'] as List<dynamic>?)
              ?.map((c) => ChapterItem.fromMap(Map<String, dynamic>.from(c)))
              .toList() ??
          const [],
      currentChapterIndex: map['currentChapterIndex'] ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  String toJson() => json.encode(toMap());
  factory MangaGroup.fromJson(String source) =>
      MangaGroup.fromMap(json.decode(source));
}

/// Совместимость с BookMetadata (предыдущая модель)
class BookMetadata {
  final String filePath;
  final String title;
  final String? author;
  final int totalPages;
  final int lastPage;
  final DateTime lastReadTime;
  final int fileSize;
  final String? coverPath;
  final List<String> tags;
  final bool isOptimized;
  final ReadingStatus status;

  BookMetadata({
    required this.filePath,
    required this.title,
    this.author,
    required this.totalPages,
    required this.lastPage,
    required this.lastReadTime,
    required this.fileSize,
    this.coverPath,
    this.tags = const [],
    this.isOptimized = false,
    this.status = ReadingStatus.reading,
  });

  BookMetadata copyWith({
    String? filePath,
    String? title,
    String? author,
    int? totalPages,
    int? lastPage,
    DateTime? lastReadTime,
    int? fileSize,
    String? coverPath,
    List<String>? tags,
    bool? isOptimized,
    ReadingStatus? status,
  }) {
    return BookMetadata(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      author: author ?? this.author,
      totalPages: totalPages ?? this.totalPages,
      lastPage: lastPage ?? this.lastPage,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      fileSize: fileSize ?? this.fileSize,
      coverPath: coverPath ?? this.coverPath,
      tags: tags ?? this.tags,
      isOptimized: isOptimized ?? this.isOptimized,
      status: status ?? this.status,
    );
  }

  MangaGroup toMangaGroup() {
    final chapter = ChapterItem(
      id: filePath,
      filePath: filePath,
      title: title,
      totalPages: totalPages,
      lastPage: lastPage,
      lastReadTime: lastReadTime,
      fileSize: fileSize,
      isOptimized: isOptimized,
    );
    return MangaGroup(
      id: filePath,
      title: title,
      author: author,
      coverPath: coverPath,
      status: status,
      tags: tags,
      chapters: [chapter],
      currentChapterIndex: 0,
      updatedAt: lastReadTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filePath': filePath,
      'title': title,
      if (author != null) 'author': author,
      'totalPages': totalPages,
      'lastPage': lastPage,
      'lastReadTime': lastReadTime.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'coverPath': coverPath,
      'tags': tags,
      'isOptimized': isOptimized,
      'status': status.index,
    };
  }

  factory BookMetadata.fromMap(Map<String, dynamic> map) {
    return BookMetadata(
      filePath: map['filePath'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] as String?,
      totalPages: map['totalPages'] ?? 0,
      lastPage: map['lastPage'] ?? 0,
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(
        map['lastReadTime'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      fileSize: map['fileSize'] ?? 0,
      coverPath: map['coverPath'],
      tags: (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      isOptimized: map['isOptimized'] ?? false,
      status: ReadingStatus.values[(map['status'] ?? 1).clamp(0, ReadingStatus.values.length - 1)],
    );
  }

  String toJson() => json.encode(toMap());
  factory BookMetadata.fromJson(String source) =>
      BookMetadata.fromMap(json.decode(source));
}
