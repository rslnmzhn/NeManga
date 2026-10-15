import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_models.dart';
import 'archive_service.dart';
import 'compressor_service.dart';

class StorageStats {
  final int totalMangaCount;
  final int totalChaptersCount;
  final int optimizedChaptersCount;
  final int totalSizeBytes;
  final int estimatedSavedBytes;

  const StorageStats({
    required this.totalMangaCount,
    required this.totalChaptersCount,
    required this.optimizedChaptersCount,
    required this.totalSizeBytes,
    required this.estimatedSavedBytes,
  });

  String get savedFormatted => _formatBytes(estimatedSavedBytes);
  String get totalSizeFormatted => _formatBytes(totalSizeBytes);

  static String _formatBytes(int bytes) {
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
}

class StorageService {
  static const String _keySettings = 'nemanga_reader_settings';
  static const String _keyRecentBooks = 'nemanga_recent_books';
  static const String _keyMangaGroups = 'nemanga_manga_groups';
  static const String _keyAuthorsTags = 'nemanga_authors_tags';
  static const String _keyAuthorBlacklist = 'nemanga_author_blacklist';
  static const String _keyTitleCleanupPatterns = 'nemanga_title_cleanup_patterns';
  static const String _keyReadingStats = 'nemanga_reading_stats';
  static const String _keyBookmarks = 'nemanga_manga_bookmarks';
  static const String _keyCustomShelves = 'nemanga_custom_shelves';

  /// Загрузка сохранённых настроек ридера
  static Future<ReaderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keySettings);
    if (jsonString != null) {
      try {
        return ReaderSettings.fromJson(jsonString);
      } catch (e) {
        // Игнорируем ошибку парсинга и возвращаем дефолтные
      }
    }
    return const ReaderSettings();
  }

  /// Сохранение настроек ридера
  static Future<void> saveSettings(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, settings.toJson());
  }

  /// Получение всех групп манги из хранилища (с миграцией)
  static Future<List<MangaGroup>> getMangaGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groupJsonList = prefs.getStringList(_keyMangaGroups);

    if (groupJsonList != null && groupJsonList.isNotEmpty) {
      final groups = <MangaGroup>[];
      for (final item in groupJsonList) {
        try {
          final group = MangaGroup.fromJson(item);
          // Недоступность файла не означает удаление из коллекции:
          // разрешение или внешний накопитель могут временно отсутствовать.
          groups.add(group);
        } catch (_) {}
      }
      groups.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return groups;
    }

    // Если групп нет, проверяем старый список _keyRecentBooks для миграции
    final oldBooks = await getRecentBooks();
    if (oldBooks.isNotEmpty) {
      final migrated = oldBooks.map((b) => b.toMangaGroup()).toList();
      await saveAllGroups(migrated);
      return migrated;
    }

    return [];
  }

  /// Сохранить полный список групп
  static Future<void> saveAllGroups(List<MangaGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = groups.map((g) => g.toJson()).toList();
    await prefs.setStringList(_keyMangaGroups, jsonList);
  }

  /// Сохранить или обновить группу манги
  static Future<void> saveMangaGroup(MangaGroup group) async {
    final current = await getMangaGroups();
    current.removeWhere((g) => g.id == group.id);
    current.insert(0, group);
    await saveAllGroups(current);
  }

  /// Атомарно заменить путь к файлу главы во всех сохраненных группах манги (при сжатии или перемещении)
  static Future<void> replaceChapterFilePath({
    required String oldPath,
    required String newPath,
    required int newSize,
    required bool isOptimized,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final groupJsonList = prefs.getStringList(_keyMangaGroups);
    if (groupJsonList == null || groupJsonList.isEmpty) return;

    final updatedJsonList = <String>[];
    for (final item in groupJsonList) {
      try {
        final group = MangaGroup.fromJson(item);
        bool changed = false;
        final chapters = group.chapters.map((ch) {
          if (ch.filePath == oldPath || ch.id == oldPath) {
            changed = true;
            return ch.copyWith(
              id: newPath,
              filePath: newPath,
              fileSize: newSize,
              isOptimized: isOptimized,
            );
          }
          return ch;
        }).toList();

        final newGroupId = (group.id == oldPath) ? newPath : group.id;

        if (changed || newGroupId != group.id) {
          final updatedGroup = group.copyWith(
            id: newGroupId,
            chapters: chapters,
            updatedAt: DateTime.now(),
          );
          updatedJsonList.add(updatedGroup.toJson());
        } else {
          updatedJsonList.add(item);
        }
      } catch (_) {
        updatedJsonList.add(item);
      }
    }

    await prefs.setStringList(_keyMangaGroups, updatedJsonList);
  }

  /// Найти или создать группу для открываемого архива
  static Future<MangaGroup> findOrCreateGroupForFile({
    required String filePath,
    required String title,
    required int totalPages,
    required int currentPage,
    String? coverPath,
  }) async {
    final groups = await getMangaGroups();

    // 1. Проверяем, не входит ли этот файл уже в какую-то группу
    for (final group in groups) {
      final existingChapterIdx = group.chapters.indexWhere((c) => c.filePath == filePath);
      if (existingChapterIdx != -1) {
        // Обновляем прогресс этой главы
        final chapter = group.chapters[existingChapterIdx];
        final updatedChapter = chapter.copyWith(
          lastPage: currentPage,
          totalPages: totalPages > 0 ? totalPages : chapter.totalPages,
          lastReadTime: DateTime.now(),
        );

        final updatedChapters = List<ChapterItem>.from(group.chapters);
        updatedChapters[existingChapterIdx] = updatedChapter;

        final updatedGroup = group.copyWith(
          chapters: updatedChapters,
          currentChapterIndex: existingChapterIdx,
          coverPath: group.coverPath ?? coverPath,
          updatedAt: DateTime.now(),
        );

        await saveMangaGroup(updatedGroup);
        return updatedGroup;
      }
    }

    // 2. Создаем новую группу для этого архива
    final fileSize = File(filePath).existsSync() ? File(filePath).lengthSync() : 0;
    final newChapter = ChapterItem(
      id: filePath,
      filePath: filePath,
      title: title,
      totalPages: totalPages,
      lastPage: currentPage,
      lastReadTime: DateTime.now(),
      fileSize: fileSize,
    );

    final cleanupPatterns = await loadTitleCleanupPatterns();
    final cleanTitle = ArchiveService.cleanTitleWithPatterns(title, cleanupPatterns);
    final comicInfo = await ArchiveService.extractComicInfo(filePath);
    final detectedAuthor = AuthorDetector.detectAuthor(cleanTitle);
    final finalAuthor = comicInfo?.author ?? detectedAuthor;
    final finalTags = comicInfo?.tags ?? [];

    final newGroup = MangaGroup(
      id: filePath,
      title: cleanTitle,
      author: finalAuthor,
      tags: finalTags,
      coverPath: coverPath,
      status: ReadingStatus.reading,
      chapters: [newChapter],
      currentChapterIndex: 0,
      updatedAt: DateTime.now(),
    );

    await saveMangaGroup(newGroup);
    return newGroup;
  }

  /// Добавить архивы-главы в существующую группу
  static Future<void> addChaptersToGroup({
    required String groupId,
    required List<ChapterItem> newChapters,
  }) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;

    final group = groups[idx];
    final existingPaths = group.chapters.map((c) => c.filePath).toSet();

    final chapters = List<ChapterItem>.from(group.chapters);
    for (final c in newChapters) {
      if (!existingPaths.contains(c.filePath)) {
        chapters.add(c);
      }
    }

    final updated = group.copyWith(
      chapters: chapters,
      updatedAt: DateTime.now(),
    );
    await saveMangaGroup(updated);
  }

  /// Удалить главу из группы
  static Future<void> removeChapterFromGroup({
    required String groupId,
    required String chapterId,
  }) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;

    final group = groups[idx];
    final updatedChapters = group.chapters.where((c) => c.id != chapterId).toList();

    if (updatedChapters.isEmpty) {
      // Если глав не осталось, удаляем группу целиком
      await removeMangaGroup(groupId);
    } else {
      final updated = group.copyWith(
        chapters: updatedChapters,
        currentChapterIndex: (group.currentChapterIndex).clamp(0, updatedChapters.length - 1),
        updatedAt: DateTime.now(),
      );
      await saveMangaGroup(updated);
    }
  }

  /// Удалить группу целиком
  static Future<void> removeMangaGroup(String groupId) async {
    final groups = await getMangaGroups();
    groups.removeWhere((g) => g.id == groupId);
    await saveAllGroups(groups);
  }

  /// Обновить статус прочтения (Читаю, В планах, Прочитано)
  static Future<void> updateGroupStatus(String groupId, ReadingStatus status) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      final updated = groups[idx].copyWith(status: status, updatedAt: DateTime.now());
      await saveMangaGroup(updated);
    }
  }

  /// Получить все используемые уникальные теги
  static Future<List<String>> getAllTags() async {
    final groups = await getMangaGroups();
    final tagsSet = <String>{};
    for (final group in groups) {
      tagsSet.addAll(group.tags);
    }
    final sorted = tagsSet.toList()..sort();
    return sorted;
  }

  // --- Методы обратной совместимости ---

  static Future<List<BookMetadata>> getRecentBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyRecentBooks) ?? [];
    final result = <BookMetadata>[];

    for (final item in list) {
      try {
        final book = BookMetadata.fromJson(item);
        if (File(book.filePath).existsSync()) {
          result.add(book);
        }
      } catch (_) {}
    }

    result.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    return result;
  }

  static Future<void> saveBookProgress({
    required String filePath,
    required int currentPage,
    required int totalPages,
    int? fileSize,
    String? coverPath,
  }) async {
    final title = p.basenameWithoutExtension(filePath);
    await findOrCreateGroupForFile(
      filePath: filePath,
      title: title,
      totalPages: totalPages,
      currentPage: currentPage,
      coverPath: coverPath,
    );
  }

  /// Обновить теги манги по id группы
  static Future<void> updateGroupTags(String groupId, List<String> tags) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      final updated = groups[idx].copyWith(tags: tags, updatedAt: DateTime.now());
      await saveMangaGroup(updated);
    }
  }

  static Future<void> updateBook(BookMetadata updated) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == updated.filePath);
    if (idx != -1) {
      final existing = groups[idx];
      final updatedGroup = existing.copyWith(
        title: updated.title,
        author: updated.author,
        tags: updated.tags,
        shelves: updated.shelves,
        status: updated.status,
        updatedAt: DateTime.now(),
      );
      await saveMangaGroup(updatedGroup);
    } else {
      await saveMangaGroup(updated.toMangaGroup());
    }
  }

  static Future<void> removeBook(String filePath) async {
    await removeMangaGroup(filePath);
  }

  /// Загрузить сохраненные теги для всех авторов
  static Future<Map<String, List<String>>> loadAllAuthorTags() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAuthorsTags);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = json.decode(jsonStr);
      return decoded.map((k, v) => MapEntry(k, List<String>.from(v ?? [])));
    } catch (_) {
      return {};
    }
  }

  /// Сохранить теги жанров конкретного автора
  static Future<void> saveAuthorTags(String authorName, List<String> tags) async {
    final cleanName = authorName.trim();
    if (cleanName.isEmpty) return;
    final all = await loadAllAuthorTags();
    all[cleanName] = tags;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthorsTags, json.encode(all));
  }

  /// Загрузить блеклист авторов и шаблонов слов
  static Future<List<String>> loadAuthorBlacklist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyAuthorBlacklist) ?? [];
  }

  /// Сохранить блеклист авторов и шаблонов слов
  static Future<void> saveAuthorBlacklist(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = list
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_keyAuthorBlacklist, clean);
  }

  /// Назначить автора для нескольких тайтлов манги
  static Future<void> assignAuthorToManga({
    required List<String> mangaIds,
    required String? authorName,
  }) async {
    final groups = await getMangaGroups();
    final updatedList = <MangaGroup>[];
    final cleanAuthor = authorName?.trim();

    for (final group in groups) {
      if (mangaIds.contains(group.id)) {
        updatedList.add(group.copyWith(
          author: (cleanAuthor != null && cleanAuthor.isNotEmpty) ? cleanAuthor : '',
          updatedAt: DateTime.now(),
        ));
      } else {
        updatedList.add(group);
      }
    }

    await saveAllGroups(updatedList);
  }

  /// Загрузить шаблоны очистки названий
  static Future<List<String>> loadTitleCleanupPatterns() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyTitleCleanupPatterns) ?? [];
  }

  /// Сохранить шаблоны очистки названий
  static Future<void> saveTitleCleanupPatterns(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = list
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_keyTitleCleanupPatterns, clean);
  }

  /// Массово обновить названия тайтлов манги в библиотеке
  static Future<int> batchUpdateMangaTitles(Map<String, String> newTitlesById) async {
    if (newTitlesById.isEmpty) return 0;
    final groups = await getMangaGroups();
    final updatedList = <MangaGroup>[];
    int updatedCount = 0;

    for (final group in groups) {
      if (newTitlesById.containsKey(group.id)) {
        final newTitle = newTitlesById[group.id]?.trim();
        if (newTitle != null && newTitle.isNotEmpty && newTitle != group.title) {
          updatedList.add(group.copyWith(
            title: newTitle,
            updatedAt: DateTime.now(),
          ));
          updatedCount++;
          continue;
        }
      }
      updatedList.add(group);
    }

    if (updatedCount > 0) {
      await saveAllGroups(updatedList);
    }
    return updatedCount;
  }

  /// Отвязать тайтл от автора (сделать автора не заданным)
  static Future<void> unassignMangaFromAuthor(String mangaId) async {
    await assignAuthorToManga(mangaIds: [mangaId], authorName: '');
  }

  /// Загрузить локальную статистику чтения
  static Future<ReadingUserStats> loadReadingStats() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyReadingStats);
    if (jsonStr == null || jsonStr.isEmpty) {
      return const ReadingUserStats();
    }
    try {
      return ReadingUserStats.fromJson(jsonStr);
    } catch (_) {
      return const ReadingUserStats();
    }
  }

  /// Зафиксировать прочитанную страницу
  static Future<void> recordPageRead() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadReadingStats();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final dates = List<String>.from(current.readDates);
    if (!dates.contains(today)) {
      dates.add(today);
    }
    final updated = ReadingUserStats(
      totalPagesRead: current.totalPagesRead + 1,
      totalReadingSeconds: current.totalReadingSeconds,
      completedChaptersCount: current.completedChaptersCount,
      readDates: dates,
    );
    await prefs.setString(_keyReadingStats, updated.toJson());
  }

  /// Зафиксировать время чтения (в секундах)
  static Future<void> recordReadingTime(int seconds) async {
    if (seconds <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await loadReadingStats();
    final updated = ReadingUserStats(
      totalPagesRead: current.totalPagesRead,
      totalReadingSeconds: current.totalReadingSeconds + seconds,
      completedChaptersCount: current.completedChaptersCount,
      readDates: current.readDates,
    );
    await prefs.setString(_keyReadingStats, updated.toJson());
  }

  /// Загрузить сохраненные закладки для тайтла
  static String _bookmarkKey(String mangaId, String? chapterId) => chapterId == null
      ? '${_keyBookmarks}_$mangaId'
      : '${_keyBookmarks}_v2_${json.encode([mangaId, chapterId])}';

  static Future<Set<int>> loadBookmarks(String mangaId, {String? chapterId}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_bookmarkKey(mangaId, chapterId));
    if (list == null) return {};
    return list.map(int.tryParse).whereType<int>().where((page) => page >= 0).toSet();
  }

  /// Добавить или убрать страницу из закладок
  static Future<bool> toggleBookmark(String mangaId, int pageIndex, {String? chapterId}) async {
    if (pageIndex < 0) throw ArgumentError.value(pageIndex, 'pageIndex');
    final prefs = await SharedPreferences.getInstance();
    final key = _bookmarkKey(mangaId, chapterId);
    final current = await loadBookmarks(mangaId, chapterId: chapterId);
    bool added = false;
    if (current.contains(pageIndex)) {
      current.remove(pageIndex);
    } else {
      current.add(pageIndex);
      added = true;
    }
    await prefs.setStringList(key, current.map((e) => e.toString()).toList());
    return added;
  }

  /// Загрузить список пользовательских полок
  static Future<List<String>> loadCustomShelves() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCustomShelves);
    if (list != null && list.isNotEmpty) return list;
    return ['Любимое', 'Шедевры', 'На перечитку'];
  }

  /// Сохранить список полок
  static Future<void> saveCustomShelves(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = list.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    await prefs.setStringList(_keyCustomShelves, clean);
  }

  /// Добавить полку
  static Future<void> addShelf(String name) async {
    final current = await loadCustomShelves();
    final clean = name.trim();
    if (clean.isNotEmpty && !current.contains(clean)) {
      current.add(clean);
      await saveCustomShelves(current);
    }
  }

  /// Удалить полку
  static Future<void> deleteShelf(String name) async {
    final current = await loadCustomShelves();
    current.remove(name.trim());
    await saveCustomShelves(current);

    final groups = await getMangaGroups();
    final updated = groups.map((g) {
      if (g.shelves.contains(name)) {
        return g.copyWith(
          shelves: g.shelves.where((s) => s != name).toList(),
          updatedAt: DateTime.now(),
        );
      }
      return g;
    }).toList();
    await saveAllGroups(updated);
  }

  /// Переключить наличие тайтла на полке
  static Future<void> toggleMangaShelf(String mangaId, String shelfName) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == mangaId);
    if (idx == -1) return;

    final group = groups[idx];
    final shelves = List<String>.from(group.shelves);
    if (shelves.contains(shelfName)) {
      shelves.remove(shelfName);
    } else {
      shelves.add(shelfName);
    }

    final updated = group.copyWith(shelves: shelves, updatedAt: DateTime.now());
    await saveMangaGroup(updated);
  }

  /// Поиск повторяющихся глав манги в библиотеке
  static List<DuplicateCluster> findDuplicateChapters(List<MangaGroup> groups) {
    final clustersMap = <String, List<DuplicateChapterItem>>{};

    for (final group in groups) {
      for (final chapter in group.chapters) {
        final simpleTitle = p.basenameWithoutExtension(chapter.filePath).toLowerCase().trim().replaceAll(RegExp(r'[\s_\-]+'), ' ');
        final key = '${group.title.toLowerCase().trim()}_$simpleTitle';

        clustersMap.putIfAbsent(key, () => []).add(
          DuplicateChapterItem(
            groupId: group.id,
            mangaTitle: group.title,
            chapter: chapter,
          ),
        );
      }
    }

    return clustersMap.entries
        .where((e) => e.value.length > 1)
        .map((e) => DuplicateCluster(title: e.value.first.chapter.title, duplicates: e.value))
        .toList();
  }

  /// Удаление разрешено только при наличии другой побайтово одинаковой копии.
  /// Ошибки файловой операции не должны приводить к потере записи библиотеки.
  static Future<void> deleteDuplicateChapter(String groupId, String filePath) async {
    final groups = await getMangaGroups();
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx == -1 || !groups[idx].chapters.any((c) => c.filePath == filePath)) {
      throw StateError('Глава больше не находится в выбранном тайтле.');
    }
    final file = File(filePath);
    final resolved = await file.resolveSymbolicLinks();
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    bool hasCopy = false;
    for (final group in groups) {
      for (final chapter in group.chapters) {
        if (group.id == groupId && chapter.filePath == filePath) continue;
        final candidate = File(chapter.filePath);
        if (!await candidate.exists()) continue;
        final otherResolved = await candidate.resolveSymbolicLinks();
        if (otherResolved == resolved) {
          throw StateError('Этот файл используется другой записью. Удаление отменено.');
        }
        if (await candidate.length() == size &&
            await sha256.bind(candidate.openRead()).first == digest) {
          hasCopy = true;
        }
      }
    }
    if (!hasCopy) {
      throw StateError('Точная копия не найдена. Совпадения названий недостаточно для удаления.');
    }
    await file.delete();
    final group = groups[idx];
    final currentId = group.currentChapter?.id;
    final chapters = group.chapters.where((c) => c.filePath != filePath).toList();
    final currentIndex = chapters.indexWhere((c) => c.id == currentId);
    groups[idx] = group.copyWith(
      chapters: chapters,
      currentChapterIndex: currentIndex < 0 ? 0 : currentIndex,
      updatedAt: DateTime.now(),
    );
    await saveAllGroups(groups);
  }

  /// Агрегировать список авторов со всеми тайтлами, обложками и тегами
  static List<AuthorData> buildAuthorsList({
    required List<MangaGroup> allGroups,
    required Map<String, List<String>> authorTagsMap,
    Iterable<String>? blacklist,
  }) {
    final allTitles = allGroups.map((g) => g.title).toList();
    final groupsByAuthor = <String, List<MangaGroup>>{};

    for (final group in allGroups) {
      var authorName = group.displayAuthor(allTitles, blacklist);
      if (authorName.trim().isEmpty || AuthorDetector.matchesBlacklist(authorName, blacklist)) {
        authorName = 'Неизвестный автор';
      } else {
        authorName = authorName.trim();
      }
      groupsByAuthor.putIfAbsent(authorName, () => []).add(group);
    }

    final result = <AuthorData>[];
    for (final entry in groupsByAuthor.entries) {
      final authorName = entry.key;
      final manga = List<MangaGroup>.from(entry.value);

      // Сортируем тайтлы автора по дате добавления (свежие сверху)
      manga.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // Картинка автора: первая страница из последнего добавленного архива
      String? cover;
      for (final m in manga) {
        if (m.coverPath != null && m.coverPath!.isNotEmpty) {
          cover = m.coverPath;
          break;
        }
        if (m.chapters.isNotEmpty) {
          cover = m.chapters.first.filePath;
          break;
        }
      }

      final tags = authorTagsMap[authorName] ?? [];

      result.add(AuthorData(
        name: authorName,
        tags: tags,
        coverPath: cover,
        mangaList: manga,
      ));
    }

    // Сортировка авторов по алфавиту (неизвестный автор в конце)
    result.sort((a, b) {
      if (a.name == 'Неизвестный автор') return 1;
      if (b.name == 'Неизвестный автор') return -1;
      return ArchiveService.naturalCompare(a.name, b.name);
    });

    return result;
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRecentBooks);
    await prefs.remove(_keyMangaGroups);
  }

  /// Получить сводную статистику хранилища и сэкономленного места
  static Future<StorageStats> getStorageStats() async {
    final groups = await getMangaGroups();
    int totalChapters = 0;
    int optChapters = 0;
    int totalBytes = 0;

    for (final g in groups) {
      for (final c in g.chapters) {
        totalChapters++;
        totalBytes += c.fileSize;
        if (c.isOptimized) {
          optChapters++;
        }
      }
    }

    // Если глава сжата в WebP, средняя экономия составляет ~75% (т.е. сжатый файл — это ~25%, сэкономлено ~3x размера)
    final savedEstimate = optChapters > 0 ? (totalBytes * 2.5).toInt() : 0;

    return StorageStats(
      totalMangaCount: groups.length,
      totalChaptersCount: totalChapters,
      optimizedChaptersCount: optChapters,
      totalSizeBytes: totalBytes,
      estimatedSavedBytes: savedEstimate,
    );
  }

  /// Автосканирование папки Download/NeManga и импорт всех найденных .cbz и .zip архивов
  static Future<int> scanAndImportPublicManga() async {
    final publicDir = await CompressorService.getPublicMangaDirectory();
    if (!await publicDir.exists()) return 0;

    final existingGroups = await getMangaGroups();
    final knownPaths = <String>{};
    for (final g in existingGroups) {
      for (final c in g.chapters) {
        knownPaths.add(c.filePath);
      }
    }

    final newFiles = <File>[];
    await for (final entity in publicDir.list(recursive: true)) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if ((lower.endsWith('.cbz') || lower.endsWith('.zip')) && !knownPaths.contains(entity.path)) {
          newFiles.add(entity);
        }
      }
    }

    if (newFiles.isEmpty) return 0;

    int importedCount = 0;
    final groupsMap = <String, List<File>>{};
    for (final f in newFiles) {
      final parent = p.basename(p.dirname(f.path));
      final groupName = (parent.isNotEmpty && parent != 'NeManga' && parent != '.')
          ? parent
          : p.basenameWithoutExtension(f.path);
      groupsMap.putIfAbsent(groupName, () => []).add(f);
    }

    final cleanupPatterns = await loadTitleCleanupPatterns();

    for (final entry in groupsMap.entries) {
      final rawTitle = entry.key;
      final title = ArchiveService.cleanTitleWithPatterns(rawTitle, cleanupPatterns);
      final files = entry.value;
      files.sort((a, b) => ArchiveService.naturalCompare(p.basename(a.path), p.basename(b.path)));

      final chapters = <ChapterItem>[];
      String? cover;
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final rawChTitle = p.basenameWithoutExtension(f.path);
        final chTitle = ArchiveService.cleanTitleWithPatterns(rawChTitle, cleanupPatterns);
        final size = f.existsSync() ? f.lengthSync() : 0;
        final isOpt = f.path.toLowerCase().endsWith('.cbz');
        if (i == 0) {
          cover = await ArchiveService.extractCoverOnly(f.path);
        }
        chapters.add(ChapterItem(
          id: f.path,
          filePath: f.path,
          title: chTitle,
          totalPages: 0,
          lastPage: 0,
          lastReadTime: DateTime.now(),
          fileSize: size,
          isOptimized: isOpt,
        ));
      }

      final existingIdx = existingGroups.indexWhere((g) => g.title.toLowerCase() == title.toLowerCase());
      if (existingIdx != -1) {
        await addChaptersToGroup(groupId: existingGroups[existingIdx].id, newChapters: chapters);
      } else {
        final author = AuthorDetector.detectAuthor(title);
        final newGroup = MangaGroup(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}_$importedCount',
          title: title,
          author: author,
          coverPath: cover,
          status: ReadingStatus.reading,
          chapters: chapters,
          currentChapterIndex: 0,
          updatedAt: DateTime.now(),
        );
        await saveMangaGroup(newGroup);
      }
      importedCount += files.length;
    }

    return importedCount;
  }

  /// Экспорт всей библиотеки и настроек в JSON файл в Загрузки/NeManga (версия 2 с полками, тегами и блеклистами)
  static Future<String> exportBackupToJson() async {
    final groups = await getMangaGroups();
    final settings = await loadSettings();
    final shelves = await loadCustomShelves();
    final authorTags = await loadAllAuthorTags();
    final authorBlacklist = await loadAuthorBlacklist();
    final titleCleanup = await loadTitleCleanupPatterns();
    final readingStats = await loadReadingStats();

    final data = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toMap(),
      'shelves': shelves,
      'authorTags': authorTags,
      'authorBlacklist': authorBlacklist,
      'titleCleanupPatterns': titleCleanup,
      'readingStats': readingStats.toMap(),
      'groups': groups.map((g) => g.toMap()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final publicDir = await CompressorService.getPublicMangaDirectory();
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final backupFile = File(p.join(publicDir.path, 'nemanga_backup_$dateStr.json'));
    await backupFile.writeAsString(jsonString);
    await CompressorService.scanMediaFile(backupFile.path);
    return backupFile.path;
  }

  /// Импорт библиотеки из JSON строки
  static Future<int> importBackupFromJson(String jsonString) async {
    final Map<String, dynamic> data = json.decode(jsonString);
    final groupsRaw = data['groups'] as List<dynamic>? ?? [];
    final importedGroups = <MangaGroup>[];

    for (final item in groupsRaw) {
      try {
        final g = MangaGroup.fromMap(item as Map<String, dynamic>);
        importedGroups.add(g);
      } catch (_) {}
    }

    if (data['settings'] != null) {
      try {
        final s = ReaderSettings.fromMap(data['settings'] as Map<String, dynamic>);
        await saveSettings(s);
      } catch (_) {}
    }

    if (data['shelves'] != null) {
      try {
        await saveCustomShelves(List<String>.from(data['shelves']));
      } catch (_) {}
    }

    if (data['authorTags'] != null) {
      try {
        final Map<String, dynamic> map = data['authorTags'];
        for (final entry in map.entries) {
          await saveAuthorTags(entry.key, List<String>.from(entry.value ?? []));
        }
      } catch (_) {}
    }

    if (data['authorBlacklist'] != null) {
      try {
        await saveAuthorBlacklist(List<String>.from(data['authorBlacklist']));
      } catch (_) {}
    }

    if (data['titleCleanupPatterns'] != null) {
      try {
        await saveTitleCleanupPatterns(List<String>.from(data['titleCleanupPatterns']));
      } catch (_) {}
    }

    if (data['readingStats'] != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final stats = ReadingUserStats.fromMap(data['readingStats'] as Map<String, dynamic>);
        await prefs.setString(_keyReadingStats, stats.toJson());
      } catch (_) {}
    }

    if (importedGroups.isNotEmpty) {
      await saveAllGroups(importedGroups);
    }
    return importedGroups.length;
  }
}
