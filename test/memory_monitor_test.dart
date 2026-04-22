import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/memory_monitor.dart';
import 'package:bagdar/utils/performance_throttler.dart';

void main() {
  group('MemoryReadings.levelFor', () {
    test('normal when plenty of RAM', () {
      expect(
        MemoryReadings.levelFor(availMB: 1024, lowMemory: false),
        MemoryPressureLevel.normal,
      );
    });

    test('low when below warn threshold', () {
      expect(
        MemoryReadings.levelFor(
          availMB: kMemoryPressureLowMB - 1,
          lowMemory: false,
        ),
        MemoryPressureLevel.low,
      );
    });

    test('critical when below hard floor', () {
      expect(
        MemoryReadings.levelFor(
          availMB: kMemoryPressureCriticalMB - 1,
          lowMemory: false,
        ),
        MemoryPressureLevel.critical,
      );
    });

    test('critical whenever OS raises lowMemory flag', () {
      expect(
        MemoryReadings.levelFor(availMB: 2048, lowMemory: true),
        MemoryPressureLevel.critical,
      );
    });

    test('falls back to normal when readings unavailable', () {
      expect(
        MemoryReadings.levelFor(availMB: -1, lowMemory: false),
        MemoryPressureLevel.normal,
      );
    });
  });

  group('MemoryReadings.fromMap', () {
    test('parses full payload', () {
      final r = MemoryReadings.fromMap(<dynamic, dynamic>{
        'availMB': 350,
        'totalMB': 4096,
        'lowMemory': false,
      });
      expect(r.availMB, 350);
      expect(r.totalMB, 4096);
      expect(r.lowMemory, false);
      expect(r.level, MemoryPressureLevel.low);
    });

    test('returns unavailable when null', () {
      final r = MemoryReadings.fromMap(null);
      expect(r.isAvailable, isFalse);
      expect(r.level, MemoryPressureLevel.normal);
    });
  });

  group('MemoryMonitor debug hook', () {
    test('notifies listener only on level transitions', () {
      final mon = MemoryMonitor();
      final seen = <MemoryPressureLevel>[];
      mon.onChanged = (r) => seen.add(r.level);

      mon.debugSet(const MemoryReadings(
        availMB: 500,
        totalMB: 4096,
        lowMemory: false,
        level: MemoryPressureLevel.normal,
      ));
      mon.debugSet(const MemoryReadings(
        availMB: 480,
        totalMB: 4096,
        lowMemory: false,
        level: MemoryPressureLevel.normal,
      ));
      mon.debugSet(const MemoryReadings(
        availMB: 200,
        totalMB: 4096,
        lowMemory: false,
        level: MemoryPressureLevel.critical,
      ));

      expect(seen, [MemoryPressureLevel.critical]);
    });
  });
}
