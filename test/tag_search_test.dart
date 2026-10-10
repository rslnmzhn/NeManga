import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';

void main() {
  group('Tag parsing and Search matching tests', () {
    List<String> parseTags(String rawInput) {
      return rawInput
          .split(RegExp(r'[\s,]+'))
          .map((s) => s.trim().replaceAll(RegExp(r'^#+'), ''))
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    }

    test('Splits genres separated by commas', () {
      final tags = parseTags('Экшен, Романтика, Комедия');
      expect(tags, ['Экшен', 'Романтика', 'Комедия']);
    });

    test('Splits genres separated by spaces', () {
      final tags = parseTags('Сёнэн Драма Фэнтези');
      expect(tags, ['Сёнэн', 'Драма', 'Фэнтези']);
    });

    test('Splits mixed commas and spaces, stripping leading #', () {
      final tags = parseTags('#Исекай, #Приключения   #Магия');
      expect(tags, ['Исекай', 'Приключения', 'Магия']);
    });

    test('Multi-token search matching across title and tags', () {
      final manga = MangaGroup(
        id: '1',
        title: 'Solo Leveling',
        status: ReadingStatus.reading,
        tags: ['Экшен', 'Фэнтези', 'Сёнэн'],
        chapters: [],
        currentChapterIndex: 0,
        updatedAt: DateTime.now(),
      );

      bool matches(MangaGroup group, String query) {
        final tokens = query
            .toLowerCase()
            .split(RegExp(r'[\s,]+'))
            .map((t) => t.trim().replaceAll(RegExp(r'^#+'), ''))
            .where((t) => t.isNotEmpty)
            .toList();

        if (tokens.isEmpty) return true;

        final titleLower = group.title.toLowerCase();
        final tagsLower = group.tags.map((t) => t.toLowerCase()).toList();

        return tokens.every((token) {
          final matchesTitle = titleLower.contains(token);
          final matchesTag = tagsLower.any((tag) => tag.contains(token));
          return matchesTitle || matchesTag;
        });
      }

      // Search with comma separation
      expect(matches(manga, 'Экшен, Фэнтези'), isTrue);
      // Search with space separation
      expect(matches(manga, 'Solo Экшен'), isTrue);
      expect(matches(manga, 'Фэнтези Сёнэн'), isTrue);
      // Query that doesn't match
      expect(matches(manga, 'Экшен, Романтика'), isFalse);
    });
  });
}
