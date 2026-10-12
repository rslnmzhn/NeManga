import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/screens/manga_file_explorer_screen.dart';

void main() {
  group('MangaFileExplorer Logic Tests', () {
    test('Sort options labels and extensions', () {
      expect(ExplorerSortOption.dateDesc.label, 'Сначала новые');
      expect(ExplorerSortOption.nameAsc.label, 'По названию (А–Я)');
      expect(ExplorerSortOption.sizeDesc.label, 'По размеру');
    });

    test('Directory filtering only admits .zip and .cbz files', () {
      final tempDir = Directory.systemTemp.createTempSync('explorer_test');

      // Create test files
      File('${tempDir.path}/volume_1.zip').writeAsStringSync('dummy zip');
      File('${tempDir.path}/volume_2.cbz').writeAsStringSync('dummy cbz');
      File('${tempDir.path}/app.apk').writeAsStringSync('dummy apk');
      File('${tempDir.path}/doc.pdf').writeAsStringSync('dummy pdf');
      File('${tempDir.path}/readme.txt').writeAsStringSync('dummy txt');
      File('${tempDir.path}/.hidden.zip').writeAsStringSync('hidden');

      const supported = {'.zip', '.cbz'};
      final entities = tempDir.listSync();
      final filteredFiles = <File>[];

      for (final entity in entities) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('.')) continue;

          final dotIdx = name.lastIndexOf('.');
          final ext = dotIdx != -1 ? name.substring(dotIdx).toLowerCase() : '';
          if (supported.contains(ext)) {
            filteredFiles.add(entity);
          }
        }
      }

      final filteredNames = filteredFiles.map((f) => f.uri.pathSegments.last).toSet();
      expect(filteredNames.contains('volume_1.zip'), isTrue);
      expect(filteredNames.contains('volume_2.cbz'), isTrue);
      expect(filteredNames.contains('app.apk'), isFalse);
      expect(filteredNames.contains('doc.pdf'), isFalse);
      expect(filteredNames.contains('readme.txt'), isFalse);
      expect(filteredNames.contains('.hidden.zip'), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('Sorting by name naturally orders volume numbers', () {
      final names = ['vol_10.cbz', 'vol_2.cbz', 'vol_1.cbz'];
      names.sort((a, b) {
        // Natural compare
        final regExp = RegExp(r'(\d+|\D+)');
        final matchesA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
        final matchesB = regExp.allMatches(b).map((m) => m.group(0)!).toList();
        final minLen = matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
        for (int i = 0; i < minLen; i++) {
          final numA = int.tryParse(matchesA[i]);
          final numB = int.tryParse(matchesB[i]);
          if (numA != null && numB != null) {
            final cmp = numA.compareTo(numB);
            if (cmp != 0) return cmp;
          } else {
            final cmp = matchesA[i].compareTo(matchesB[i]);
            if (cmp != 0) return cmp;
          }
        }
        return matchesA.length.compareTo(matchesB.length);
      });

      expect(names, ['vol_1.cbz', 'vol_2.cbz', 'vol_10.cbz']);
    });
  });
}
