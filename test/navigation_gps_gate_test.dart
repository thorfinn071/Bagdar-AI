import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/navigation_service.dart';

void main() {
  group('NavigationService.isGpsBad (Safety follow-up M11)', () {
    test('clean fix passes the gate (accuracy <= 25 m, age < 30 s)', () {
      final now = DateTime(2026, 5, 13, 12, 0, 0);
      final fresh = now.subtract(const Duration(seconds: 5));
      expect(NavigationService.isGpsBad(10.0, fresh, now), isFalse);
      expect(NavigationService.isGpsBad(25.0, fresh, now), isFalse,
          reason: 'boundary: accuracy exactly at max is still acceptable');
    });

    test('accuracy worse than 25 m trips the gate', () {
      final now = DateTime(2026, 5, 13, 12, 0, 0);
      final fresh = now.subtract(const Duration(seconds: 1));
      expect(NavigationService.isGpsBad(26.0, fresh, now), isTrue);
      expect(NavigationService.isGpsBad(60.0, fresh, now), isTrue,
          reason: 'urban-canyon style 60 m fix must mute turn-by-turn');
    });

    test('stale fix (timestamp age > 30 s) trips the gate even at good accuracy',
        () {
      final now = DateTime(2026, 5, 13, 12, 0, 0);
      final stale = now.subtract(const Duration(seconds: 31));
      expect(NavigationService.isGpsBad(5.0, stale, now), isTrue,
          reason:
              'a 5 m fix held for >30 s is still a tunnel/underpass cache, '
              'must not steer the user');
      final ancient = now.subtract(const Duration(minutes: 5));
      expect(NavigationService.isGpsBad(5.0, ancient, now), isTrue);
    });

    test('boundary: 30 s age is still accepted, 31 s is not', () {
      final now = DateTime(2026, 5, 13, 12, 0, 0);
      final exactly30 = now.subtract(const Duration(seconds: 30));
      final justOver = now.subtract(const Duration(seconds: 31));
      expect(NavigationService.isGpsBad(5.0, exactly30, now), isFalse);
      expect(NavigationService.isGpsBad(5.0, justOver, now), isTrue);
    });

    test('constants match the documented audit thresholds', () {
      expect(kNavGpsAccuracyMaxM, 25.0,
          reason: 'plan M11 mandates a 25 m accuracy ceiling');
      expect(kNavGpsMaxAgeSec, 30,
          reason: 'plan M11 mandates a 30 s fix-age ceiling');
    });
  });
}
