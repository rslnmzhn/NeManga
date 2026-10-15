import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/archive_service.dart';
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

    test('ReaderSettings splitDoublePages setting round-trip', () {
      const s1 = ReaderSettings(splitDoublePages: true);
      final json1 = s1.toJson();
      expect(ReaderSettings.fromJson(json1).splitDoublePages, isTrue);

      const s2 = ReaderSettings(splitDoublePages: false);
      final json2 = s2.toJson();
      expect(ReaderSettings.fromJson(json2).splitDoublePages, isFalse);
    });

    test('ArchiveService.parseComicInfoXml parses metadata correctly', () {
      const xml = '''<?xml version="1.0"?>
<ComicInfo>
  <Title>Chapter 1</Title>
  <Series>Berserk</Series>
  <Writer>Kentaro Miura</Writer>
  <Genre>Action, Dark Fantasy, Tragedy</Genre>
  <Summary>A grim tale of revenge.</Summary>
  <Volume>1</Volume>
  <Year>1989</Year>
</ComicInfo>''';

      final meta = ArchiveService.parseComicInfoXml(xml);
      expect(meta.title, 'Chapter 1');
      expect(meta.series, 'Berserk');
      expect(meta.author, 'Kentaro Miura');
      expect(meta.summary, 'A grim tale of revenge.');
      expect(meta.volume, '1');
      expect(meta.year, '1989');
      expect(meta.tags, contains('Action'));
      expect(meta.tags, contains('Dark'));
      expect(meta.tags, contains('Fantasy'));
      expect(meta.tags, contains('Tragedy'));
    });

    test('ReadingUserStats formatting and tracking in StorageService', () async {
      SharedPreferences.setMockInitialValues({});

      const stats1 = ReadingUserStats(
        totalPagesRead: 150,
        totalReadingSeconds: 45,
      );
      expect(stats1.totalTimeFormatted, '45 сек');

      const stats2 = ReadingUserStats(
        totalPagesRead: 150,
        totalReadingSeconds: 300,
      );
      expect(stats2.totalTimeFormatted, '5 мин');

      const stats3 = ReadingUserStats(
        totalPagesRead: 150,
        totalReadingSeconds: 3900, // 1h 5m
      );
      expect(stats3.totalTimeFormatted, '1ч 5м');

      // Storage recording
      await StorageService.recordPageRead();
      await StorageService.recordReadingTime(120);

      final loaded = await StorageService.loadReadingStats();
      expect(loaded.totalPagesRead, 1);
      expect(loaded.totalReadingSeconds, 120);
      expect(loaded.uniqueDaysCount, 1);
    });

    test('Bookmarks toggle and load round-trip', () async {
      SharedPreferences.setMockInitialValues({});

      final initial = await StorageService.loadBookmarks('manga_123');
      expect(initial, isEmpty);

      final added = await StorageService.toggleBookmark('manga_123', 5);
      expect(added, isTrue);

      final loaded = await StorageService.loadBookmarks('manga_123');
      expect(loaded, contains(5));

      final removed = await StorageService.toggleBookmark('manga_123', 5);
      expect(removed, isFalse);

      final afterRemoved = await StorageService.loadBookmarks('manga_123');
      expect(afterRemoved, isEmpty);
    });

    test('ReaderSettings smartMarginCrop setting round-trip', () {
      const s1 = ReaderSettings(smartMarginCrop: true);
      final json1 = s1.toJson();
      expect(ReaderSettings.fromJson(json1).smartMarginCrop, isTrue);

      const s2 = ReaderSettings(smartMarginCrop: false);
      final json2 = s2.toJson();
      expect(ReaderSettings.fromJson(json2).smartMarginCrop, isFalse);
    });

    test('StorageService Custom Shelves management round-trip', () async {
      SharedPreferences.setMockInitialValues({});

      // Defaults
      final defaultShelves = await StorageService.loadCustomShelves();
      expect(defaultShelves, contains('Любимое'));
      expect(defaultShelves, contains('Шедевры'));

      // Add shelf
      await StorageService.addShelf('Синглы');
      final updated = await StorageService.loadCustomShelves();
      expect(updated, contains('Синглы'));

      // Toggle manga shelf
      final manga = MangaGroup(
        id: 'm_shelf_1',
        title: 'Manga on Shelf',
        shelves: [],
        updatedAt: DateTime.now(),
      );
      await StorageService.saveMangaGroup(manga);

      await StorageService.toggleMangaShelf('m_shelf_1', 'Синглы');
      var loaded = await StorageService.getMangaGroups();
      expect(loaded.firstWhere((g) => g.id == 'm_shelf_1').shelves, contains('Синглы'));

      // Toggle off
      await StorageService.toggleMangaShelf('m_shelf_1', 'Синглы');
      loaded = await StorageService.getMangaGroups();
      expect(loaded.firstWhere((g) => g.id == 'm_shelf_1').shelves, isNot(contains('Синглы')));

      // Delete shelf
      await StorageService.deleteShelf('Синглы');
      final afterDelete = await StorageService.loadCustomShelves();
      expect(afterDelete, isNot(contains('Синглы')));
    });

    test('Duplicate Finder discovers duplicate chapters and calculates wasted size', () {
      final ch1 = ChapterItem(
        id: '/tmp/ch1.zip',
        filePath: '/tmp/ch1.zip',
        title: 'Глава 1',
        totalPages: 20,
        lastPage: 0,
        lastReadTime: DateTime.now(),
        fileSize: 10485760, // 10 MB
      );
      final ch1Duplicate = ChapterItem(
        id: '/tmp/ch1.cbz',
        filePath: '/tmp/ch1.cbz',
        title: 'Глава 1',
        totalPages: 20,
        lastPage: 0,
        lastReadTime: DateTime.now(),
        fileSize: 4194304, // 4 MB
      );
      final ch2 = ChapterItem(
        id: '/tmp/ch2.zip',
        filePath: '/tmp/ch2.zip',
        title: 'Глава 2',
        totalPages: 20,
        lastPage: 0,
        lastReadTime: DateTime.now(),
        fileSize: 10485760,
      );

      final group = MangaGroup(
        id: 'm_dup',
        title: 'Berserk',
        chapters: [ch1, ch1Duplicate, ch2],
        updatedAt: DateTime.now(),
      );

      final duplicates = StorageService.findDuplicateChapters([group]);
      expect(duplicates.length, 1);
      expect(duplicates.first.duplicates.length, 2);
      expect(duplicates.first.totalWastedBytes, 4194304); // smaller copy counted as waste
    });

    test('StorageService Backup v2 exports and imports full metadata ecosystem', () async {
      SharedPreferences.setMockInitialValues({});

      await StorageService.saveCustomShelves(['Шедевры', 'Синглы']);
      await StorageService.saveAuthorTags('Kentaro Miura', ['Тёмное фэнтези']);
      await StorageService.saveAuthorBlacklist(['bad-author*']);
      await StorageService.saveTitleCleanupPatterns(['mangasite-*']);

      final backupData = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': const ReaderSettings(appTheme: AppThemeMode.amoled).toMap(),
        'shelves': ['Шедевры', 'Синглы'],
        'authorTags': {'Kentaro Miura': ['Тёмное фэнтези']},
        'authorBlacklist': ['bad-author*'],
        'titleCleanupPatterns': ['mangasite-*'],
        'readingStats': const ReadingUserStats(totalPagesRead: 120, totalReadingSeconds: 3600).toMap(),
        'groups': [
          MangaGroup(
            id: 'g_v2',
            title: 'Berserk',
            author: 'Kentaro Miura',
            shelves: ['Шедевры'],
            tags: ['Тёмное фэнтези'],
            updatedAt: DateTime.now(),
          ).toMap(),
        ],
      };

      final jsonStr = json.encode(backupData);
      final count = await StorageService.importBackupFromJson(jsonStr);
      expect(count, 1);

      // Verify full restore
      final shelves = await StorageService.loadCustomShelves();
      expect(shelves, contains('Шедевры'));
      expect(shelves, contains('Синглы'));

      final authorTags = await StorageService.loadAllAuthorTags();
      expect(authorTags['Kentaro Miura'], contains('Тёмное фэнтези'));

      final blacklist = await StorageService.loadAuthorBlacklist();
      expect(blacklist, contains('bad-author*'));

      final patterns = await StorageService.loadTitleCleanupPatterns();
      expect(patterns, contains('mangasite-*'));

      final stats = await StorageService.loadReadingStats();
      expect(stats.totalPagesRead, 120);
      expect(stats.totalReadingSeconds, 3600);

      final groups = await StorageService.getMangaGroups();
      expect(groups.first.shelves, contains('Шедевры'));
      expect(groups.first.tags, contains('Тёмное фэнтези'));
    });

    test('Chapter gap detection identifies missing chapters in sequence', () {
      List<int> detectChapterGaps(List<String> titles) {
        final nums = <int>[];
        for (final t in titles) {
          final matches = RegExp(r'(?:ch|chapter|глава|том|vol)?\s*(\d+)', caseSensitive: false).allMatches(t);
          if (matches.isNotEmpty) {
            final parsed = int.tryParse(matches.last.group(1) ?? '');
            if (parsed != null) nums.add(parsed);
          }
        }
        if (nums.length < 2) return [];
        final gaps = <int>[];
        for (int i = 0; i < nums.length - 1; i++) {
          final diff = nums[i + 1] - nums[i];
          if (diff > 1 && diff < 15) {
            for (int m = nums[i] + 1; m < nums[i + 1]; m++) {
              gaps.add(m);
            }
          }
        }
        return gaps;
      }

      expect(detectChapterGaps(['Глава 1', 'Глава 2', 'Глава 4']), [3]);
      expect(detectChapterGaps(['Vol 1 Ch 10', 'Vol 1 Ch 13']), [11, 12]);
      expect(detectChapterGaps(['Ch 1', 'Ch 2', 'Ch 3']), isEmpty);
    });
  });
}
