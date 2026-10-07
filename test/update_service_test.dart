import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/services/update_service.dart';

void main() {
  group('UpdateService version comparison', () {
    test('standard semver comparison', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.1.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '2.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('fix tag version comparison', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0_fix1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0_fix1', '1.0.0_fix2'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0_fix2', '1.0.0_fix1'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0_fix5', '1.0.1'), isTrue);
    });
  });
}
