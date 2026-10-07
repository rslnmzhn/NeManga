import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_models.dart';

class StorageService {
  static const String _keySettings = 'nemanga_reader_settings';
  static const String _keyRecentBooks = 'nemanga_recent_books';

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

  /// Получение списка недавно прочитанных файлов
  static Future<List<BookMetadata>> getRecentBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyRecentBooks) ?? [];
    final result = <BookMetadata>[];

    for (final item in list) {
      try {
        final book = BookMetadata.fromJson(item);
        // Проверяем, существует ли еще файл
        if (File(book.filePath).existsSync()) {
          result.add(book);
        }
      } catch (e) {
        // пропускаем поврежденные записи
      }
    }

    // Сортировка: самые новые сверху
    result.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    return result;
  }

  /// Сохранить или обновить прогресс чтения книги
  static Future<void> saveBookProgress({
    required String filePath,
    required int currentPage,
    required int totalPages,
    int? fileSize,
    String? coverPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentList = await getRecentBooks();

    // Находим существующую запись, чтобы сохранить кастомный заголовок и теги
    final existingIndex = currentList.indexWhere((b) => b.filePath == filePath);
    final existing = existingIndex != -1 ? currentList[existingIndex] : null;

    final title = existing?.title ?? p.basenameWithoutExtension(filePath);
    final size = fileSize ?? (File(filePath).existsSync() ? File(filePath).lengthSync() : (existing?.fileSize ?? 0));
    final cover = coverPath ?? existing?.coverPath;
    final tags = existing?.tags ?? const [];
    final isOptimized = existing?.isOptimized ?? false;

    // Удаляем старую запись если была
    currentList.removeWhere((b) => b.filePath == filePath);

    // Добавляем обновленную в начало
    final newBook = BookMetadata(
      filePath: filePath,
      title: title,
      totalPages: totalPages,
      lastPage: currentPage,
      lastReadTime: DateTime.now(),
      fileSize: size,
      coverPath: cover,
      tags: tags,
      isOptimized: isOptimized,
    );

    currentList.insert(0, newBook);

    // Ограничиваем историю, например, 50 книгами
    final trimmed = currentList.take(50).map((b) => b.toJson()).toList();
    await prefs.setStringList(_keyRecentBooks, trimmed);
  }

  /// Обновить метаданные книги (название, теги, обложку)
  static Future<void> updateBook(BookMetadata updated) async {
    final prefs = await SharedPreferences.getInstance();
    final currentList = await getRecentBooks();

    final idx = currentList.indexWhere((b) => b.filePath == updated.filePath);
    if (idx != -1) {
      currentList[idx] = updated;
    } else {
      currentList.insert(0, updated);
    }

    final trimmed = currentList.take(50).map((b) => b.toJson()).toList();
    await prefs.setStringList(_keyRecentBooks, trimmed);
  }

  /// Получить все используемые уникальные теги
  static Future<List<String>> getAllTags() async {
    final books = await getRecentBooks();
    final tagsSet = <String>{};
    for (final book in books) {
      tagsSet.addAll(book.tags);
    }
    final sorted = tagsSet.toList()..sort();
    return sorted;
  }

  /// Удалить книгу из истории
  static Future<void> removeBook(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final currentList = await getRecentBooks();
    currentList.removeWhere((b) => b.filePath == filePath);
    final jsonList = currentList.map((b) => b.toJson()).toList();
    await prefs.setStringList(_keyRecentBooks, jsonList);
  }

  /// Очистить всю историю
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRecentBooks);
  }
}
