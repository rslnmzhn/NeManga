import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('nemanga_safety_');
  });
  tearDown(() async => temp.delete(recursive: true));
  ChapterItem chapter(String name) => ChapterItem(
    id: name, filePath: '${temp.path}/$name', title: name,
    totalPages: 3, lastPage: 1, lastReadTime: DateTime(2025), fileSize: 3,
  );
  MangaGroup group(String id, List<ChapterItem> chapters) => MangaGroup(
    id: id, title: id, chapters: chapters, updatedAt: DateTime(2025),
  );

  test('saving 150 titles never truncates the collection', () async {
    await StorageService.saveAllGroups(List.generate(150, (i) => group('$i', [])));
    expect((await StorageService.getMangaGroups()).length, 150);
  });
  test('unavailable chapters and current position survive read and save', () async {
    final a = chapter('available.cbz');
    final b = chapter('unavailable.cbz');
    await File(a.filePath).writeAsString('abc');
    await StorageService.saveAllGroups([group('g', [a, b]).copyWith(currentChapterIndex: 1)]);
    final loaded = await StorageService.getMangaGroups();
    expect(loaded.single.chapters.length, 2);
    expect(loaded.single.currentChapter?.id, b.id);
    await StorageService.saveAllGroups(loaded);
    expect((await StorageService.getMangaGroups()).single.chapters.length, 2);
  });
  test('similar names with different contents cannot be deleted', () async {
    final a = chapter('ch1.zip'), b = chapter('ch1.cbz');
    await File(a.filePath).writeAsString('abc');
    await File(b.filePath).writeAsString('xyz');
    await StorageService.saveAllGroups([group('g', [a, b])]);
    await expectLater(StorageService.deleteDuplicateChapter('g', a.filePath), throwsStateError);
    expect(await File(a.filePath).exists(), isTrue);
    expect((await StorageService.getMangaGroups()).single.chapters.length, 2);
  });
  test('shared archive reference prevents physical deletion', () async {
    final a = chapter('ch1.zip'), b = chapter('ch1.cbz');
    await File(a.filePath).writeAsString('abc');
    await File(b.filePath).writeAsString('abc');
    await StorageService.saveAllGroups([group('g', [a, b]), group('other', [a])]);
    await expectLater(StorageService.deleteDuplicateChapter('g', a.filePath), throwsStateError);
    expect(await File(a.filePath).exists(), isTrue);
  });
  test('confirmed exact duplicate removal preserves remaining position', () async {
    final a = chapter('ch1.zip'), b = chapter('ch1.cbz');
    await File(a.filePath).writeAsString('abc');
    await File(b.filePath).writeAsString('abc');
    await StorageService.saveAllGroups([group('g', [a, b]).copyWith(currentChapterIndex: 1)]);
    await StorageService.deleteDuplicateChapter('g', a.filePath);
    expect(await File(a.filePath).exists(), isFalse);
    final loaded = (await StorageService.getMangaGroups()).single;
    expect(loaded.chapters.length, 1);
    expect(loaded.currentChapter?.id, b.id);
  });
  test('missing source does not remove its library entry', () async {
    final a = chapter('missing.cbz');
    await StorageService.saveAllGroups([group('g', [a])]);
    await expectLater(StorageService.deleteDuplicateChapter('g', a.filePath), throwsA(isA<FileSystemException>()));
    expect((await StorageService.getMangaGroups()).single.chapters.single.id, a.id);
  });
}
