import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/archive_service.dart';
import 'package:nemanga/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthorDetector Tests', () {
    test('Extracts author from bracket notations', () {
      expect(AuthorDetector.detectAuthor('[Oda Eiichiro] One Piece'), 'Oda Eiichiro');
      expect(AuthorDetector.detectAuthor('(Inio Asano) Solanin'), 'Inio Asano');
      expect(AuthorDetector.detectAuthor('【Kentaro Miura】 Berserk'), 'Kentaro Miura');
      expect(AuthorDetector.detectAuthor('{CLAMP} Cardcaptor Sakura'), 'CLAMP');
    });

    test('Ignores common non-author bracket tokens', () {
      expect(AuthorDetector.detectAuthor('[RAW] Chainsaw Man'), isNull);
      expect(AuthorDetector.detectAuthor('[CBZ] Naruto'), isNull);
      expect(AuthorDetector.detectAuthor('[Vol 01] Bleach'), isNull);
    });

    test('Extracts author from dash delimiter "Author - Title"', () {
      expect(AuthorDetector.detectAuthor('Akira Toriyama - Dragon Ball'), 'Akira Toriyama');
      expect(AuthorDetector.detectAuthor('Naoki Urasawa - Monster'), 'Naoki Urasawa');
      // Should not treat chapter/volume designations as author
      expect(AuthorDetector.detectAuthor('Том 1 - Глава 2'), isNull);
    });

    test('Detects common repeating words/prefix across titles in library', () {
      final titles = [
        'Takehiko Inoue Real',
        'Takehiko Inoue Vagabond',
        'Slam Dunk Vol 1',
      ];

      expect(AuthorDetector.detectAuthor('Takehiko Inoue Real', titles), 'Takehiko Inoue');
      expect(AuthorDetector.detectAuthor('Takehiko Inoue Vagabond', titles), 'Takehiko Inoue');
      expect(AuthorDetector.detectAuthor('Slam Dunk Vol 1', titles), isNull);
    });
  });

  group('Manga Title Derivation and Progress Tests', () {
    test('deriveMangaTitle extracts common title and never names manga NeManga or Downloads', () {
      final files1 = [
        '/storage/emulated/0/Download/NeManga/One Piece - Ch 01.cbz',
        '/storage/emulated/0/Download/NeManga/One Piece - Ch 02.cbz',
        '/storage/emulated/0/Download/NeManga/One Piece - Ch 03.cbz',
      ];
      expect(ArchiveService.deriveMangaTitle(filePaths: files1), 'One Piece');

      final files2 = [
        '/storage/emulated/0/Download/Naruto_01.zip',
        '/storage/emulated/0/Download/Naruto_02.zip',
      ];
      expect(ArchiveService.deriveMangaTitle(filePaths: files2), 'Naruto');

      final files3 = [
        '/storage/emulated/0/Download/Berserk/ch1.zip',
        '/storage/emulated/0/Download/Berserk/ch2.zip',
      ];
      expect(ArchiveService.deriveMangaTitle(filePaths: files3), 'Berserk');
    });

    test('Unopened manga chapters calculate 0% progress and are not marked completed', () {
      final ch1 = ChapterItem(
        id: '1',
        filePath: '/tmp/1.cbz',
        title: 'Глава 1',
        totalPages: 0,
        lastPage: 0,
        lastReadTime: DateTime.now(),
        fileSize: 1000,
      );
      final ch2 = ChapterItem(
        id: '2',
        filePath: '/tmp/2.cbz',
        title: 'Глава 2',
        totalPages: 0,
        lastPage: 0,
        lastReadTime: DateTime.now(),
        fileSize: 1000,
      );

      final group = MangaGroup(
        id: 'group_test',
        title: 'New Manga',
        status: ReadingStatus.reading,
        chapters: [ch1, ch2],
        updatedAt: DateTime.now(),
      );

      expect(group.isCompleted, isFalse);
      expect(group.overallProgressFraction, 0.0);
      expect(group.overallProgressPercent, 0);
    });
  });

  group('MangaGroup Author and Sorting Tests', () {
    test('MangaGroup serializes and deserializes author', () {
      final group = MangaGroup(
        id: '1',
        title: 'One Piece',
        author: 'Eiichiro Oda',
        status: ReadingStatus.reading,
        updatedAt: DateTime.now(),
      );

      final map = group.toMap();
      expect(map['author'], 'Eiichiro Oda');

      final restored = MangaGroup.fromMap(map);
      expect(restored.author, 'Eiichiro Oda');
      expect(restored.displayAuthor(), 'Eiichiro Oda');
    });

    test('MangaGroup displayAuthor falls back to detected author when null', () {
      final group = MangaGroup(
        id: '2',
        title: '[Inio Asano] Oyasumi Punpun',
        author: null,
        status: ReadingStatus.reading,
        updatedAt: DateTime.now(),
      );

      expect(group.author, isNull);
      expect(group.displayAuthor(), 'Inio Asano');
    });

    test('LibrarySortOrder.author sorting groups authors alphabetically', () {
      expect(LibrarySortOrder.author.label, 'По автору');

      final mangaList = [
        MangaGroup(id: '1', title: 'Monster', author: 'Urasawa Naoki', updatedAt: DateTime.now()),
        MangaGroup(id: '2', title: 'Bleach', author: 'Kite Tite', updatedAt: DateTime.now()),
        MangaGroup(id: '3', title: '20th Century Boys', author: 'Urasawa Naoki', updatedAt: DateTime.now()),
        MangaGroup(id: '4', title: 'Berserk', author: 'Kentaro Miura', updatedAt: DateTime.now()),
      ];

      final allTitles = mangaList.map((g) => g.title).toList();
      mangaList.sort((a, b) {
        final authorA = a.displayAuthor(allTitles);
        final authorB = b.displayAuthor(allTitles);
        if (authorA.isEmpty && authorB.isNotEmpty) return 1;
        if (authorA.isNotEmpty && authorB.isEmpty) return -1;
        final cmp = ArchiveService.naturalCompare(authorA, authorB);
        if (cmp != 0) return cmp;
        return ArchiveService.naturalCompare(a.title, b.title);
      });

      expect(mangaList[0].displayAuthor(), 'Kentaro Miura');
      expect(mangaList[1].displayAuthor(), 'Kite Tite');
      expect(mangaList[2].displayAuthor(), 'Urasawa Naoki');
      expect(mangaList[2].title, '20th Century Boys');
      expect(mangaList[3].displayAuthor(), 'Urasawa Naoki');
      expect(mangaList[3].title, 'Monster');
    });

    test('StorageService saves and loads author tags and builds authors list', () async {
      SharedPreferences.setMockInitialValues({});

      await StorageService.saveAuthorTags('Inio Asano', ['Драма', 'Психология']);
      final tags = await StorageService.loadAllAuthorTags();
      expect(tags['Inio Asano'], ['Драма', 'Психология']);

      final m1 = MangaGroup(
        id: 'm1',
        title: '[Inio Asano] Solanin',
        status: ReadingStatus.reading,
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final m2 = MangaGroup(
        id: 'm2',
        title: '[Inio Asano] Oyasumi Punpun',
        coverPath: '/tmp/cover_punpun.jpg',
        status: ReadingStatus.reading,
        updatedAt: DateTime.now(), // latest!
      );

      final authors = StorageService.buildAuthorsList(
        allGroups: [m1, m2],
        authorTagsMap: tags,
      );

      expect(authors.length, 1);
      final author = authors.first;
      expect(author.name, 'Inio Asano');
      expect(author.tags, ['Драма', 'Психология']);
      expect(author.totalMangaCount, 2);
      expect(author.coverPath, '/tmp/cover_punpun.jpg'); // taken from latest added manga!
    });
  });
}
