import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/thermal_monitor.dart';
import 'package:bagdar/utils/performance_throttler.dart';

ThermalReadings _readings(ThermalSeverity severity) {
  switch (severity) {
    case ThermalSeverity.normal:
      return const ThermalReadings(
        batteryTempC: 30.0,
        thermalStatus: 0,
        severity: ThermalSeverity.normal,
      );
    case ThermalSeverity.warm:
      return const ThermalReadings(
        batteryTempC: 38.0,
        thermalStatus: 2,
        severity: ThermalSeverity.warm,
      );
    case ThermalSeverity.hot:
      return const ThermalReadings(
        batteryTempC: 41.0,
        thermalStatus: 3,
        severity: ThermalSeverity.hot,
      );
    case ThermalSeverity.critical:
      return const ThermalReadings(
        batteryTempC: 44.0,
        thermalStatus: 4,
        severity: ThermalSeverity.critical,
      );
  }
}

void main() {
  group('PerformanceThrottler midasInterval', () {
    test('doubles under thermal warm', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.normal), now: t0);
      final baseline = thr.midasInterval(500).inMilliseconds;

      thr.setThermal(_readings(ThermalSeverity.warm), now: t0);
      final warm = thr.midasInterval(500).inMilliseconds;

      expect(baseline, 500);
      expect(warm, greaterThanOrEqualTo(baseline * 2));
    });

    test('at least triples under thermal hot', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.hot), now: t0);
      expect(thr.midasInterval(500).inMilliseconds, greaterThanOrEqualTo(1500));
    });

    test('returns zero under critical memory pressure', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.normal), now: t0);
      thr.setMemoryPressure(MemoryPressureLevel.critical);
      expect(thr.midasInterval(500), Duration.zero);
    });
  });

  group('PerformanceThrottler thermal commit hysteresis', () {
    test('holds hot commitment for kThermalCommitDwell after recovery', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.hot), now: t0);
      expect(thr.effectiveSeverity, ThermalSeverity.hot);

      thr.setThermal(
        _readings(ThermalSeverity.normal),
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(
        thr.effectiveSeverity,
        ThermalSeverity.hot,
        reason: 'must stay hot inside commit-dwell window',
      );

      thr.setThermal(
        _readings(ThermalSeverity.normal),
        now: t0.add(kThermalCommitDwell + const Duration(seconds: 5)),
      );
      expect(thr.effectiveSeverity, ThermalSeverity.normal);
    });

    test('upgrades immediately to a worse severity', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.warm), now: t0);
      expect(thr.effectiveSeverity, ThermalSeverity.warm);

      thr.setThermal(
        _readings(ThermalSeverity.critical),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(thr.effectiveSeverity, ThermalSeverity.critical);
    });
  });

  group('PerformanceThrottler detectInterval memory bias', () {
    test('adds latency under low memory pressure', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final normal = PerformanceThrottler()
        ..setThermal(_readings(ThermalSeverity.normal), now: t0);
      final low = PerformanceThrottler()
        ..setThermal(_readings(ThermalSeverity.normal), now: t0)
        ..setMemoryPressure(MemoryPressureLevel.low);
      final critical = PerformanceThrottler()
        ..setThermal(_readings(ThermalSeverity.normal), now: t0)
        ..setMemoryPressure(MemoryPressureLevel.critical);

      final baseMs = normal.detectInterval(140).inMilliseconds;
      final lowMs = low.detectInterval(140).inMilliseconds;
      final critMs = critical.detectInterval(140).inMilliseconds;

      expect(lowMs, greaterThan(baseMs));
      expect(critMs, greaterThan(lowMs));
    });
  });

  group('PerformanceThrottler stallWatchdogThreshold', () {
    test('returns 1200 ms when normal and long-settled', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.normal), now: t0);
      final probe = t0.add(kThermalTransitionSilence + const Duration(seconds: 5));
      expect(
        thr.stallWatchdogThreshold(now: probe),
        kStallWatchdogThresholdNormal,
      );
    });

    test('relaxes to 1800 ms under thermal hot', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.hot), now: t0);
      final probe = t0.add(kThermalTransitionSilence + const Duration(seconds: 1));
      expect(
        thr.stallWatchdogThreshold(now: probe),
        kStallWatchdogThresholdHot,
      );
    });

    test('uses critical threshold inside the transition silence window', () {
      final t0 = DateTime(2025, 1, 1, 10, 0, 0);
      final thr = PerformanceThrottler();
      thr.setThermal(_readings(ThermalSeverity.warm), now: t0);
      final probe = t0.add(const Duration(milliseconds: 500));
      expect(
        thr.stallWatchdogThreshold(now: probe),
        kStallWatchdogThresholdCritical,
      );
    });
  });
}
