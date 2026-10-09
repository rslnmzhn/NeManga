import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/compressor_service.dart';
import 'package:nemanga/services/storage_service.dart';
import 'package:nemanga/widgets/compress_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompressorService and Dialog models', () {
    test('CompressionResult calculates savedBytesFormatted correctly', () {
      const result1 = CompressionResult(
        originalSize: 104857600, // 100 MB
        compressedSize: 20971520, // 20 MB
        savedPercent: 80.0,
        targetPath: '/storage/emulated/0/Download/NeManga/test.cbz',
        totalImages: 45,
      );
      expect(result1.savedBytesFormatted, '80.0 МБ');

      const result2 = CompressionResult(
        originalSize: 1024,
        compressedSize: 1024,
        savedPercent: 0.0,
        targetPath: '/storage/emulated/0/Download/NeManga/test.cbz',
        totalImages: 1,
      );
      expect(result2.savedBytesFormatted, '0 КБ');
    });

    test('AddedArchivesCompressionChoice stores quality and maxWidth', () {
      const choice1 = AddedArchivesCompressionChoice(
        shouldCompress: true,
        deleteOriginal: true,
        quality: 35,
        maxWidth: 960,
      );
      expect(choice1.shouldCompress, isTrue);
      expect(choice1.deleteOriginal, isTrue);
      expect(choice1.quality, 35);
      expect(choice1.maxWidth, 960);
    });

    test('CompressionPreset returns correct default quality and maxWidth', () {
      expect(CompressionPreset.balance.defaultQuality, 80);
      expect(CompressionPreset.balance.defaultMaxWidth, 1440);

      expect(CompressionPreset.strong.defaultQuality, 55);
      expect(CompressionPreset.strong.defaultMaxWidth, 1200);

      expect(CompressionPreset.extreme.defaultQuality, 35);
      expect(CompressionPreset.extreme.defaultMaxWidth, 960);
    });

    test('StorageService.replaceChapterFilePath replaces chapter in-place', () async {
      SharedPreferences.setMockInitialValues({});
      const oldPath = '/path/to/archive.zip';
      const newPath = '/storage/emulated/0/Download/NeManga/archive.cbz';

      final group = MangaGroup(
        id: oldPath,
        title: 'Тестовая Манга',
        status: ReadingStatus.reading,
        chapters: [
          ChapterItem(
            id: oldPath,
            filePath: oldPath,
            title: 'Глава 1',
            totalPages: 20,
            lastPage: 5,
            lastReadTime: DateTime.now(),
            fileSize: 10000000,
          ),
        ],
        currentChapterIndex: 0,
        updatedAt: DateTime.now(),
      );

      await StorageService.saveAllGroups([group]);

      await StorageService.replaceChapterFilePath(
        oldPath: oldPath,
        newPath: newPath,
        newSize: 2000000,
        isOptimized: true,
      );

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('nemanga_manga_groups');
      expect(list, isNotNull);
      expect(list!.length, 1);

      final updatedGroup = MangaGroup.fromJson(list.first);
      expect(updatedGroup.id, newPath);
      expect(updatedGroup.chapters.first.filePath, newPath);
      expect(updatedGroup.chapters.first.id, newPath);
      expect(updatedGroup.chapters.first.fileSize, 2000000);
      expect(updatedGroup.chapters.first.isOptimized, isTrue);
    });
  });
}
