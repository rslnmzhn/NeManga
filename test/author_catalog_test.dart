import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/archive_service.dart';

void main() {
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

      // Expected order by author:
      // Kentaro Miura -> Berserk
      // Kite Tite -> Bleach
      // Urasawa Naoki -> 20th Century Boys, Monster
      expect(mangaList[0].displayAuthor(), 'Kentaro Miura');
      expect(mangaList[1].displayAuthor(), 'Kite Tite');
      expect(mangaList[2].displayAuthor(), 'Urasawa Naoki');
      expect(mangaList[2].title, '20th Century Boys');
      expect(mangaList[3].displayAuthor(), 'Urasawa Naoki');
      expect(mangaList[3].title, 'Monster');
    });
  });
}
