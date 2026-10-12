import 'dart:convert';
import 'dart:io';
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
        tags: updated.tags,
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

    for (final entry in groupsMap.entries) {
      final title = entry.key;
      final files = entry.value;
      files.sort((a, b) => ArchiveService.naturalCompare(p.basename(a.path), p.basename(b.path)));

      final chapters = <ChapterItem>[];
      String? cover;
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final chTitle = p.basenameWithoutExtension(f.path);
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
        final newGroup = MangaGroup(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}_$importedCount',
          title: title,
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

  /// Экспорт всей библиотеки и настроек в JSON файл в Загрузки/NeManga
  static Future<String> exportBackupToJson() async {
    final groups = await getMangaGroups();
    final settings = await loadSettings();
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toMap(),
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

    if (importedGroups.isNotEmpty) {
      await saveAllGroups(importedGroups);
    }
    return importedGroups.length;
  }
}
