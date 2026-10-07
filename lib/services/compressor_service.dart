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

  /// Сжать архив манги в высокоэффективный формат WebP
  static Future<CompressionResult> compressArchive({
    required String sourcePath,
    int maxWidth = 1440,
    int quality = 80,
    bool replaceOriginal = true,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Файл архива не найден: $sourcePath');
    }

    final ext = p.extension(sourcePath);
    final dir = p.dirname(sourcePath);
    final baseName = p.basenameWithoutExtension(sourcePath);

    // Временный путь для сжатого файла
    final tempDir = await getTemporaryDirectory();
    final tempTargetPath = p.join(tempDir.path, '${baseName}_optimized$ext');

    final result = await _channel.invokeMapMethod<String, dynamic>('compressArchive', {
      'sourcePath': sourcePath,
      'targetPath': tempTargetPath,
      'maxWidth': maxWidth,
      'quality': quality,
    });

    if (result == null) {
      throw Exception('Не удалось выполнить сжатие архива');
    }

    final originalSize = (result['originalSize'] as num).toInt();
    final compressedSize = (result['compressedSize'] as num).toInt();
    final savedPercent = (result['savedPercent'] as num).toDouble();
    final totalImages = (result['totalImages'] as num).toInt();

    String finalPath = tempTargetPath;

    if (replaceOriginal) {
      final tempFile = File(tempTargetPath);
      final destPath = p.join(dir, '$baseName.cbz');

      if (destPath != sourcePath) {
        // Если меняем расширение на .cbz
        await tempFile.copy(destPath);
        await tempFile.delete();
        await sourceFile.delete();
        finalPath = destPath;
      } else {
        // Перезаписываем оригинальный файл
        final backupPath = '$sourcePath.tmp';
        await sourceFile.rename(backupPath);
        await tempFile.copy(sourcePath);
        await tempFile.delete();
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        finalPath = sourcePath;
      }
    }

    // Очищаем старый кэш распакованных страниц этой книги, так как файлы изменились на компактные WebP
    final hash = ArchiveService.getArchiveHash(sourcePath, originalSize);
    final oldCache = Directory(p.join(tempDir.path, 'nemanga_cache', hash));
    if (await oldCache.exists()) {
      try {
        await oldCache.delete(recursive: true);
      } catch (e) {
        debugPrint('Ошибка очистки кэша: $e');
      }
    }

    // Обновляем метаданные в библиотеке
    final recentBooks = await StorageService.getRecentBooks();
    final existing = recentBooks.where((b) => b.filePath == sourcePath || b.filePath == finalPath).firstOrNull;
    if (existing != null) {
      final updated = existing.copyWith(
        filePath: finalPath,
        fileSize: compressedSize,
        isOptimized: true,
      );
      await StorageService.updateBook(updated);
    }

    return CompressionResult(
      originalSize: originalSize,
      compressedSize: compressedSize,
      savedPercent: savedPercent,
      targetPath: finalPath,
      totalImages: totalImages,
    );
  }
}
