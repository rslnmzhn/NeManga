import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Webtoon scroll calculation tests', () {
    test('Calculates detected page accurately across scroll positions', () {
      const pageCount = 20;
      const screenWidth = 360.0;
      const ratio = 1.4; // 360 * 1.4 = 504px per page
      const pageHeight = screenWidth * ratio; // 504.0

      final pageHeights = List.generate(pageCount, (_) => pageHeight);
      final totalContentHeight = pageCount * pageHeight; // 10080.0
      const screenHeight = 800.0;
      final maxScroll = totalContentHeight - screenHeight; // 9280.0

      int calculateDetectedPage(double offset) {
        if (offset <= 10.0) return 0;
        if (offset >= maxScroll - 15.0) return pageCount - 1;

        double accumulated = 0;
        int detected = 0;
        for (int i = 0; i < pageCount; i++) {
          final h = pageHeights[i];
          if (offset < accumulated + (h * 0.6)) {
            detected = i;
            break;
          }
          accumulated += h;
          detected = i;
        }
        return detected.clamp(0, pageCount - 1);
      }

      // At top
      expect(calculateDetectedPage(0.0), 0);
      expect(calculateDetectedPage(5.0), 0);

      // On first few pages
      expect(calculateDetectedPage(200.0), 0);
      expect(calculateDetectedPage(600.0), 1);
      expect(calculateDetectedPage(1100.0), 2);

      // In middle
      expect(calculateDetectedPage(4500.0), 9);

      // Near and at bottom (crucial: must hit last page 19, i.e. 20/20)
      expect(calculateDetectedPage(maxScroll - 10.0), 19);
      expect(calculateDetectedPage(maxScroll), 19);
    });

    test('Jump to page targets exact pixel offset', () {
      const pageCount = 20;
      const screenWidth = 360.0;
      const pageHeight = screenWidth * 1.5; // 540.0
      final pageHeights = List.generate(pageCount, (_) => pageHeight);
      const maxScroll = (pageCount * pageHeight) - 800.0;

      double calculateJumpOffset(int target) {
        if (target == 0) return 0.0;
        if (target == pageCount - 1) return maxScroll;

        double offset = 0;
        for (int i = 0; i < target; i++) {
          offset += pageHeights[i];
        }
        return offset.clamp(0.0, maxScroll);
      }

      expect(calculateJumpOffset(0), 0.0);
      expect(calculateJumpOffset(1), 540.0);
      expect(calculateJumpOffset(5), 2700.0);
      expect(calculateJumpOffset(19), maxScroll);
    });
  });
}
