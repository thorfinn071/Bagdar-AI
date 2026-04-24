import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/stall_watchdog.dart';

void main() {
  group('StallWatchdog', () {
    test('fires onStall once when gap exceeds threshold', () {
      int stallCount = 0;
      final wd = StallWatchdog(
        thresholdProvider: () => const Duration(milliseconds: 500),
        isActive: () => true,
        onStall: () => stallCount++,
      );
      final t0 = DateTime(2024);
      wd.notifyFrameArrived(now: t0);

      wd.evaluate(t0.add(const Duration(milliseconds: 400)));
      expect(stallCount, 0);
      expect(wd.isWarned, isFalse);

      wd.evaluate(t0.add(const Duration(milliseconds: 600)));
      expect(stallCount, 1);
      expect(wd.isWarned, isTrue);

      wd.evaluate(t0.add(const Duration(milliseconds: 700)));
      expect(stallCount, 1, reason: 'no re-fire while warned');
    });

    test('does not fire when inactive', () {
      int stallCount = 0;
      bool active = false;
      final wd = StallWatchdog(
        thresholdProvider: () => const Duration(milliseconds: 500),
        isActive: () => active,
        onStall: () => stallCount++,
      );
      final t0 = DateTime(2024);
      wd.notifyFrameArrived(now: t0);
      wd.evaluate(t0.add(const Duration(seconds: 5)));
      expect(stallCount, 0);

      active = true;
      wd.evaluate(t0.add(const Duration(seconds: 5)));
      expect(stallCount, 1);
    });

    test('clearWarning allows next stall to fire', () {
      int stallCount = 0;
      final wd = StallWatchdog(
        thresholdProvider: () => const Duration(milliseconds: 500),
        isActive: () => true,
        onStall: () => stallCount++,
      );
      final t0 = DateTime(2024);
      wd.notifyFrameArrived(now: t0);
      wd.evaluate(t0.add(const Duration(milliseconds: 600)));
      expect(stallCount, 1);
      expect(wd.isWarned, isTrue);

      wd.clearWarning();
      wd.evaluate(t0.add(const Duration(milliseconds: 700)));
      expect(stallCount, 2);
    });

    test('notifyFrameArrived resets gap', () {
      int stallCount = 0;
      final wd = StallWatchdog(
        thresholdProvider: () => const Duration(milliseconds: 500),
        isActive: () => true,
        onStall: () => stallCount++,
      );
      final t0 = DateTime(2024);
      wd.notifyFrameArrived(now: t0);

      wd.notifyFrameArrived(now: t0.add(const Duration(milliseconds: 400)));
      wd.evaluate(t0.add(const Duration(milliseconds: 800)));
      expect(stallCount, 0,
          reason: 'gap from last frame (400ms) is below threshold');
    });

    test('stop() clears warning', () {
      int stallCount = 0;
      final wd = StallWatchdog(
        thresholdProvider: () => const Duration(milliseconds: 500),
        isActive: () => true,
        onStall: () => stallCount++,
      );
      final t0 = DateTime(2024);
      wd.notifyFrameArrived(now: t0);
      wd.evaluate(t0.add(const Duration(milliseconds: 600)));
      expect(wd.isWarned, isTrue);

      wd.stop();
      expect(wd.isWarned, isFalse);
    });
  });
}
