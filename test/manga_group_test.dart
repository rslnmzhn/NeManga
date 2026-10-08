import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';

void main() {
  group('MangaGroup & ReadingStatus model tests', () {
    test('ReadingStatus labels', () {
      expect(ReadingStatus.reading.label, 'Читаю');
      expect(ReadingStatus.planned.label, 'В планах');
      expect(ReadingStatus.completed.label, 'Прочитано');
      expect(ReadingStatus.none.label, 'Без статуса');
    });

    test('MangaGroup chapters and progress calculation', () {
      final ch1 = ChapterItem(
        id: 'ch1',
        filePath: '/tmp/ch1.zip',
        title: 'Глава 1',
        totalPages: 20,
        lastPage: 19, // completed
        lastReadTime: DateTime.now(),
        fileSize: 1024,
      );

      final ch2 = ChapterItem(
        id: 'ch2',
        filePath: '/tmp/ch2.zip',
        title: 'Глава 2',
        totalPages: 20,
        lastPage: 9, // half read
        lastReadTime: DateTime.now(),
        fileSize: 2048,
      );

      final group = MangaGroup(
        id: 'group1',
        title: 'Берсерк',
        status: ReadingStatus.reading,
        tags: ['Сэйнэн', 'Экшен'],
        chapters: [ch1, ch2],
        currentChapterIndex: 1,
        updatedAt: DateTime.now(),
      );

      expect(group.chapters.length, 2);
      expect(group.totalSize, 3072);
      expect(group.totalPages, 40);
      expect(group.completedChaptersCount, 1);
      expect(group.overallProgressPercent, greaterThan(70));

      final json = group.toJson();
      final parsed = MangaGroup.fromJson(json);
      expect(parsed.id, group.id);
      expect(parsed.title, group.title);
      expect(parsed.status, ReadingStatus.reading);
      expect(parsed.chapters.length, 2);
      expect(parsed.tags, ['Сэйнэн', 'Экшен']);
    });
  });
}
