import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nemanga/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('same page in two chapters has independent bookmarks', () async {
    await StorageService.toggleBookmark('manga', 4, chapterId: 'chapter-a');
    expect(await StorageService.loadBookmarks('manga', chapterId: 'chapter-b'), isEmpty);
    await StorageService.toggleBookmark('manga', 4, chapterId: 'chapter-b');
    await StorageService.toggleBookmark('manga', 4, chapterId: 'chapter-a');
    expect(await StorageService.loadBookmarks('manga', chapterId: 'chapter-a'), isEmpty);
    expect(await StorageService.loadBookmarks('manga', chapterId: 'chapter-b'), {4});
  });
  test('ambiguous legacy bookmarks preserved, not assigned to arbitrary chapter', () async {
    await StorageService.toggleBookmark('manga', 7);
    expect(await StorageService.loadBookmarks('manga'), {7});
    expect(await StorageService.loadBookmarks('manga', chapterId: 'new'), isEmpty);
    await StorageService.toggleBookmark('manga', 2, chapterId: 'new');
    expect(await StorageService.loadBookmarks('manga'), {7});
  });
  test('invalid stored indexes ignored rather than moved to page zero', () async {
    SharedPreferences.setMockInitialValues({'nemanga_manga_bookmarks_manga': ['oops', '-1', '3']});
    expect(await StorageService.loadBookmarks('manga'), {3});
    await expectLater(StorageService.toggleBookmark('manga', -1), throwsArgumentError);
  });
  test('compound identifiers do not collide', () async {
    await StorageService.toggleBookmark('a_b', 1, chapterId: 'c');
    expect(await StorageService.loadBookmarks('a', chapterId: 'b_c'), isEmpty);
  });
}
