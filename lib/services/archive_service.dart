import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MangaArchiveInfo {
  final String archivePath;
  final String title;
  final List<String> pagePaths;
  final String? coverPath;

  const MangaArchiveInfo({
    required this.archivePath,
    required this.title,
    required this.pagePaths,
    this.coverPath,
  });
}

class ArchiveService {
  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };

  /// Естественное сравнение строк (Natural Sort)
  static int naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+|\D+)');
    final matchesA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
    final matchesB = regExp.allMatches(b).map((m) => m.group(0)!).toList();

    final minLength =
        matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
    for (int i = 0; i < minLength; i++) {
      final partA = matchesA[i];
      final partB = matchesB[i];

      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);

      if (numA != null && numB != null) {
        final comp = numA.compareTo(numB);
        if (comp != 0) return comp;
      } else {
        final comp = partA.toLowerCase().compareTo(partB.toLowerCase());
        if (comp != 0) return comp;
      }
    }
    return matchesA.length.compareTo(matchesB.length);
  }

  /// Проверяет, является ли файл поддерживаемым изображением
  static bool isImageFile(String filename) {
    final lower = filename.toLowerCase();
    // Игнорируем метаданные macOS и скрытые системные файлы
    if (lower.contains('__macosx') ||
        lower.contains('/.') ||
        lower.startsWith('.') ||
        lower.endsWith('.db') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.txt')) {
      return false;
    }
    final ext = p.extension(lower);
    return _imageExtensions.contains(ext);
  }

  /// Получить хеш файла для уникальной папки кэша
  static String getArchiveHash(String filePath, int fileSizeBytes) {
    final input = '$filePath:$fileSizeBytes';
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Распаковать и подготовить страницы манги
  static Future<MangaArchiveInfo> loadManga(
    String archivePath, {
    void Function(double progress)? onProgress,
  }) async {
    final file = File(archivePath);
    if (!await file.exists()) {
      throw Exception('Файл архива не найден: $archivePath');
    }

    final fileSize = await file.length();
    final hash = getArchiveHash(archivePath, fileSize);
    final tempDir = await getTemporaryDirectory();
    final mangaCacheDir = Directory(p.join(tempDir.path, 'nemanga_cache', hash));

    final title = p.basenameWithoutExtension(archivePath);

    // Если уже было распаковано ранее, проверяем кэш
    if (await mangaCacheDir.exists()) {
      final cachedFiles = await mangaCacheDir
          .list()
          .where((entity) => entity is File && isImageFile(entity.path))
          .map((entity) => entity.path)
          .toList();

      if (cachedFiles.isNotEmpty) {
        cachedFiles.sort((a, b) => naturalCompare(p.basename(a), p.basename(b)));
        return MangaArchiveInfo(
          archivePath: archivePath,
          title: title,
          pagePaths: cachedFiles,
          coverPath: cachedFiles.first,
        );
      }
    }

    // Создаем директорию кэша
    await mangaCacheDir.create(recursive: true);

    // Распаковываем в фоновом изоляте
    final extractedPaths = await compute(_extractArchiveIsolate, {
      'archivePath': archivePath,
      'destDirPath': mangaCacheDir.path,
    });

    if (extractedPaths.isEmpty) {
      throw Exception('В архиве не найдено поддерживаемых изображений манги (JPG, PNG, WEBP и др.)');
    }

    return MangaArchiveInfo(
      archivePath: archivePath,
      title: title,
      pagePaths: extractedPaths,
      coverPath: extractedPaths.first,
    );
  }

  /// Фоновая функция распаковки архива
  static List<String> _extractArchiveIsolate(Map<String, dynamic> args) {
    final archivePath = args['archivePath'] as String;
    final destDirPath = args['destDirPath'] as String;

    final inputStream = InputFileStream(archivePath);
    final archive = ZipDecoder().decodeStream(inputStream);

    // Фильтруем только изображения
    final imageEntries = archive.where((file) {
      if (file.isFile && isImageFile(file.name)) {
        return true;
      }
      return false;
    }).toList();

    // Сортируем страницы по естественному порядку
    imageEntries.sort((a, b) => naturalCompare(a.name, b.name));

    final resultPaths = <String>[];
    for (int i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final ext = p.extension(entry.name);
      final paddedIndex = i.toString().padLeft(4, '0');
      final outputName = 'page_$paddedIndex$ext';
      final outputPath = p.join(destDirPath, outputName);

      final outputFile = File(outputPath);
      // Записываем байты изображения на диск
      final content = entry.content as List<int>;
      outputFile.writeAsBytesSync(content, flush: true);
      resultPaths.add(outputPath);
    }

    return resultPaths;
  }

  /// Очистка старого кэша
  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'nemanga_cache'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Ошибка очистки кэша: $e');
    }
  }
}
