import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Roadmap Features Unit Tests', () {
    test('ReaderSettings serializes and deserializes all new roadmap settings', () {
      const settings = ReaderSettings(
        volumeKeysNavigation: true,
        hapticFeedback: true,
        dualPage: true,
        customBrightness: 0.45,
        warmFilter: true,
        appTheme: AppThemeMode.amoled,
        accentColor: AppAccentColor.sakura,
        sortOrder: LibrarySortOrder.title,
      );

      final jsonStr = settings.toJson();
      final restored = ReaderSettings.fromJson(jsonStr);

      expect(restored.volumeKeysNavigation, isTrue);
      expect(restored.hapticFeedback, isTrue);
      expect(restored.dualPage, isTrue);
      expect(restored.customBrightness, 0.45);
      expect(restored.warmFilter, isTrue);
      expect(restored.appTheme, AppThemeMode.amoled);
      expect(restored.accentColor, AppAccentColor.sakura);
      expect(restored.sortOrder, LibrarySortOrder.title);
    });

    test('AppThemeMode and AppAccentColor provide valid colors and labels', () {
      expect(AppThemeMode.amoled.backgroundColor.value, 0xFF000000);
      expect(AppThemeMode.darkSlate.backgroundColor.value, 0xFF0F1115);

      expect(AppAccentColor.sakura.color.value, 0xFFFF6B9D);
      expect(AppAccentColor.mint.color.value, 0xFF10B981);
      expect(AppAccentColor.amber.color.value, 0xFFF59E0B);
      expect(AppAccentColor.cyberpunk.color.value, 0xFFA855F7);
      expect(AppAccentColor.blue.color.value, 0xFF3B82F6);
    });

    test('LibrarySortOrder labels are defined', () {
      expect(LibrarySortOrder.recent.label, 'Недавние');
      expect(LibrarySortOrder.title.label, 'По названию (А–Я)');
      expect(LibrarySortOrder.progress.label, 'По прогрессу');
      expect(LibrarySortOrder.author.label, 'По автору');
    });

    test('StorageStats formatting', () {
      const stats = StorageStats(
        totalMangaCount: 5,
        totalChaptersCount: 20,
        optimizedChaptersCount: 15,
        totalSizeBytes: 104857600, // 100 MB
        estimatedSavedBytes: 314572800, // 300 MB
      );

      expect(stats.totalSizeFormatted, '100.0 МБ');
      expect(stats.savedFormatted, '300.0 МБ');
    });

    test('StorageService backup export and import round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('backup_test');
      final tempFile = File('${tempDir.path}/ch1.cbz')..writeAsStringSync('dummy');

      final group = MangaGroup(
        id: 'test_group_1',
        title: 'Roadmap Test Manga',
        status: ReadingStatus.reading,
        tags: ['Экшен', 'Сёнэн'],
        chapters: [
          ChapterItem(
            id: tempFile.path,
            filePath: tempFile.path,
            title: 'Глава 1',
            totalPages: 24,
            lastPage: 12,
            lastReadTime: DateTime.now(),
            fileSize: 5000000,
            isOptimized: true,
          ),
        ],
        currentChapterIndex: 0,
        updatedAt: DateTime.now(),
      );

      final dummyBackup = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': const ReaderSettings(appTheme: AppThemeMode.amoled).toMap(),
        'groups': [group.toMap()],
      };

      final jsonString = json.encode(dummyBackup);
      final importedCount = await StorageService.importBackupFromJson(jsonString);
      expect(importedCount, 1);

      final loadedGroups = await StorageService.getMangaGroups();
      expect(loadedGroups.length, 1);
      expect(loadedGroups.first.title, 'Roadmap Test Manga');
      expect(loadedGroups.first.chapters.first.isOptimized, isTrue);

      final loadedSettings = await StorageService.loadSettings();
      expect(loadedSettings.appTheme, AppThemeMode.amoled);

      tempDir.deleteSync(recursive: true);
    });
  });
}
