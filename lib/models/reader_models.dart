import 'dart:convert';

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

  const ReaderSettings({
    this.mode = ReaderMode.webtoon,
    this.tapToNavigate = true,
    this.tapCenterForMenu = true,
    this.invertTap = false,
    this.imageFit = ImageFit.fitWidth,
    this.keepScreenOn = true,
    this.colorTheme = ColorTheme.pureBlack,
  });

  ReaderSettings copyWith({
    ReaderMode? mode,
    bool? tapToNavigate,
    bool? tapCenterForMenu,
    bool? invertTap,
    ImageFit? imageFit,
    bool? keepScreenOn,
    ColorTheme? colorTheme,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      tapToNavigate: tapToNavigate ?? this.tapToNavigate,
      tapCenterForMenu: tapCenterForMenu ?? this.tapCenterForMenu,
      invertTap: invertTap ?? this.invertTap,
      imageFit: imageFit ?? this.imageFit,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      colorTheme: colorTheme ?? this.colorTheme,
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
    };
  }

  factory ReaderSettings.fromMap(Map<String, dynamic> map) {
    return ReaderSettings(
      mode: ReaderMode.values[map['mode'] ?? 0],
      tapToNavigate: map['tapToNavigate'] ?? true,
      tapCenterForMenu: map['tapCenterForMenu'] ?? true,
      invertTap: map['invertTap'] ?? false,
      imageFit: ImageFit.values[map['imageFit'] ?? 0],
      keepScreenOn: map['keepScreenOn'] ?? true,
      colorTheme: ColorTheme.values[map['colorTheme'] ?? 0],
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

/// Группа / Тайтл манги (содержит одну или несколько глав-архивов)
class MangaGroup {
  final String id;
  final String title;
  final String? coverPath;
  final ReadingStatus status;
  final List<String> tags;
  final List<ChapterItem> chapters;
  final int currentChapterIndex;
  final DateTime updatedAt;

  MangaGroup({
    required this.id,
    required this.title,
    this.coverPath,
    this.status = ReadingStatus.reading,
    this.tags = const [],
    this.chapters = const [],
    this.currentChapterIndex = 0,
    required this.updatedAt,
  });

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
      final t = c.totalPages > 0 ? c.totalPages : 1;
      allPages += t;
      readPages += (c.isCompleted ? t : (c.lastPage + 1).clamp(0, t));
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
