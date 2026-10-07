import 'package:flutter_test/flutter_test.dart';

int naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+|\D+)');
  final matchesA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
  final matchesB = regExp.allMatches(b).map((m) => m.group(0)!).toList();

  final minLength = matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
  for (int i = 0; i < minLength; i++) {
    final partA = matchesA[i];
    final partB = matchesB[i];

    final numA = int.tryParse(partA);
    final numB = int.tryParse(partB);

    if (numA != null && numB != null) {
      final comp = numA.compareTo(numB);
      if (comp != 0) return comp;
    } else {
      final comp = partA.toLowerCase().compareTo(partB.toLowerCase());
      if (comp != 0) return comp;
    }
  }
  return matchesA.length.compareTo(matchesB.length);
}

void main() {
  test('natural sort test', () {
    final list = ['page_10.jpg', 'page_1.jpg', 'page_2.jpg', 'page_20.jpg', 'page_3.jpg'];
    list.sort(naturalCompare);
    expect(list, ['page_1.jpg', 'page_2.jpg', 'page_3.jpg', 'page_10.jpg', 'page_20.jpg']);
  });
}
