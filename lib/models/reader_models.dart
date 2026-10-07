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

enum ColorTheme {
  pureBlack, // AMOLED черный (для максимальной энергоэффективности)
  darkGrey,  // Темно-серый
  light,     // Светлый
}

class BookMetadata {
  final String filePath;
  final String title;
  final int totalPages;
  final int lastPage;
  final DateTime lastReadTime;
  final int fileSize;

  BookMetadata({
    required this.filePath,
    required this.title,
    required this.totalPages,
    required this.lastPage,
    required this.lastReadTime,
    required this.fileSize,
  });

  BookMetadata copyWith({
    String? filePath,
    String? title,
    int? totalPages,
    int? lastPage,
    DateTime? lastReadTime,
    int? fileSize,
  }) {
    return BookMetadata(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      totalPages: totalPages ?? this.totalPages,
      lastPage: lastPage ?? this.lastPage,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      fileSize: fileSize ?? this.fileSize,
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
    );
  }

  String toJson() => json.encode(toMap());
  factory BookMetadata.fromJson(String source) =>
      BookMetadata.fromMap(json.decode(source));
}
