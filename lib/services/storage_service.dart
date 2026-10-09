import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_models.dart';

class StorageService {
  static const String _keySettings = 'nemanga_reader_settings';
  static const String _keyRecentBooks = 'nemanga_recent_books';
  static const String _keyMangaGroups = 'nemanga_manga_groups';

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
          // Фильтруем главы, чьи файлы ещё существуют на диске
          final validChapters = group.chapters.where((c) => File(c.filePath).existsSync()).toList();
          if (validChapters.isNotEmpty) {
            groups.add(group.copyWith(chapters: validChapters));
          }
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
    final jsonList = groups.take(100).map((g) => g.toJson()).toList();
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

    final newGroup = MangaGroup(
      id: filePath,
      title: title,
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

  static Future<void> updateBook(BookMetadata updated) async {
    await saveMangaGroup(updated.toMangaGroup());
  }

  static Future<void> removeBook(String filePath) async {
    await removeMangaGroup(filePath);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRecentBooks);
    await prefs.remove(_keyMangaGroups);
  }
}
