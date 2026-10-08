import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'archive_service.dart';
import 'storage_service.dart';

class CompressionResult {
  final int originalSize;
  final int compressedSize;
  final double savedPercent;
  final String targetPath;
  final int totalImages;

  const CompressionResult({
    required this.originalSize,
    required this.compressedSize,
    required this.savedPercent,
    required this.targetPath,
    required this.totalImages,
  });

  String get savedBytesFormatted {
    final bytes = originalSize - compressedSize;
    if (bytes <= 0) return '0 КБ';
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

class CompressorService {
  static const MethodChannel _channel = MethodChannel('com.nemanga.reader/compressor');

  /// Получить общедоступную папку 'NeManga', видимую в проводнике Android (Downloads/NeManga)
  static Future<Directory> getPublicMangaDirectory() async {
    try {
      if (Platform.isAndroid) {
        final path = await _channel.invokeMethod<String>('getPublicMangaDirectory');
        if (path != null) {
          final dir = Directory(path);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      }
    } catch (_) {}

    final extDir = await getExternalStorageDirectory();
    final fallback = Directory(
      p.join(extDir?.path ?? (await getApplicationDocumentsDirectory()).path, 'NeManga'),
    );
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  /// Уведомить Android MediaScanner о новом файле
  static Future<void> scanMediaFile(String path) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('scanMediaFile', {'path': path});
      }
    } catch (_) {}
  }

  /// Сжать архив манги в высокоэффективный формат WebP
  static Future<CompressionResult> compressArchive({
    required String sourcePath,
    int maxWidth = 1440,
    int quality = 80,
    bool saveToPublicFolder = true,
    bool deleteOriginal = false,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Файл архива не найден: $sourcePath');
    }

    final originalSize = await sourceFile.length();
    final baseName = p.basenameWithoutExtension(sourcePath);

    // Определяем конечное местоположение
    late String finalDestinationPath;
    if (saveToPublicFolder) {
      final publicDir = await getPublicMangaDirectory();
      finalDestinationPath = p.join(publicDir.path, '$baseName.cbz');
    } else {
      final dir = p.dirname(sourcePath);
      finalDestinationPath = p.join(dir, '$baseName.cbz');
    }

    // Временный файл сжатия
    final tempDir = await getTemporaryDirectory();
    final tempTargetPath = p.join(tempDir.path, '${baseName}_compressed_${DateTime.now().millisecondsSinceEpoch}.cbz');

    final result = await _channel.invokeMapMethod<String, dynamic>('compressArchive', {
      'sourcePath': sourcePath,
      'targetPath': tempTargetPath,
      'maxWidth': maxWidth,
      'quality': quality,
    });

    if (result == null) {
      throw Exception('Не удалось выполнить сжатие архива');
    }

    final compressedSize = (result['compressedSize'] as num).toInt();
    final savedPercent = (result['savedPercent'] as num).toDouble();
    final totalImages = (result['totalImages'] as num).toInt();

    final tempFile = File(tempTargetPath);

    // Перемещаем в итоговую папку
    if (finalDestinationPath == sourcePath) {
      // Перезапись исходного файла
      final backup = File('$sourcePath.bak');
      await sourceFile.rename(backup.path);
      await tempFile.copy(sourcePath);
      await tempFile.delete();
      if (await backup.exists()) {
        await backup.delete();
      }
    } else {
      final destFile = File(finalDestinationPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await tempFile.copy(finalDestinationPath);
      await tempFile.delete();

      // Если пользователь захотел удалить оригинальный архив для экономии памяти
      if (deleteOriginal && await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }

    // Уведомляем систему для отображения в проводнике
    await scanMediaFile(finalDestinationPath);

    // Очищаем старый кэш распакованных страниц
    final hash = ArchiveService.getArchiveHash(sourcePath, originalSize);
    final oldCache = Directory(p.join(tempDir.path, 'nemanga_cache', hash));
    if (await oldCache.exists()) {
      try {
        await oldCache.delete(recursive: true);
      } catch (e) {
        debugPrint('Ошибка очистки кэша: $e');
      }
    }

    // Обновляем метаданные в библиотеке и группах
    final groups = await StorageService.getMangaGroups();
    for (final group in groups) {
      bool groupChanged = false;
      final updatedChapters = group.chapters.map((ch) {
        if (ch.filePath == sourcePath) {
          groupChanged = true;
          return ch.copyWith(
            id: finalDestinationPath,
            filePath: finalDestinationPath,
            fileSize: compressedSize,
            isOptimized: true,
          );
        }
        return ch;
      }).toList();

      if (groupChanged) {
        final updatedGroup = group.copyWith(
          chapters: updatedChapters,
          updatedAt: DateTime.now(),
        );
        await StorageService.saveMangaGroup(updatedGroup);
      }
    }

    return CompressionResult(
      originalSize: originalSize,
      compressedSize: compressedSize,
      savedPercent: savedPercent,
      targetPath: finalDestinationPath,
      totalImages: totalImages,
    );
  }
}
