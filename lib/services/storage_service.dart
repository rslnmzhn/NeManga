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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentList = await getRecentBooks();

    final title = p.basenameWithoutExtension(filePath);
    final size = fileSize ?? (File(filePath).existsSync() ? File(filePath).lengthSync() : 0);

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
    );

    currentList.insert(0, newBook);

    // Ограничиваем историю, например, 30 книгами
    final trimmed = currentList.take(30).map((b) => b.toJson()).toList();
    await prefs.setStringList(_keyRecentBooks, trimmed);
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
