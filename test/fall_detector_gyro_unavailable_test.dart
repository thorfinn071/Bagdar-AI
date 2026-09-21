import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:bagdar/services/fall_detector.dart';

void main() {
  group('FallDetector gyro-unavailable degraded profile', () {
    test('Class A tumble is confirmed via degraded profile (freefall + impact '
        'without gyro rotational peak) when gyro never produces events', () {
      final fd = FallDetector();
      FallClass? detected;
      fd.onFallDetected = (c) => detected = c;

      // Simulate gyroscope never starting — degraded profile from the outset.
      fd.setGyroAvailableForTesting(false);

      // 1) Freefall: magnitude below 3.5 m/s².
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 2.0, DateTime.now()));
      // 2) Impact: accelWithoutGravity > 30, within the 500 ms freefall window.
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 40.0, DateTime.now()));
      // 3) Stillness: 60 frames (degraded requirement = 40 * 1.5) of
      //    gravity-only accel (~9.81 → accelWithoutGravity ≈ 0).
      for (var i = 0; i < 60; i++) {
        fd.onAccelForTesting(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
      }

      expect(
        detected,
        FallClass.tumble,
        reason:
            'degraded profile must confirm a tumble on freefall + impact '
            '+ accel-only stillness without any gyro rotational peak',
      );
    });

    test('staleness watchdog switches to degraded profile after > 2 s without '
        'gyro events and fires onGyroUnavailable exactly once', () {
      final fd = FallDetector();
      var gyroUnavailableCalls = 0;
      fd.onGyroUnavailable = () => gyroUnavailableCalls++;

      // Gyro started successfully 3 s ago but never emitted since.
      fd.setGyroAvailableForTesting(
        true,
        lastEventAt: DateTime.now().subtract(const Duration(seconds: 3)),
      );
      expect(fd.isGyroAvailable, isTrue);

      // First accel tick after the staleness threshold triggers the watchdog.
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
      expect(
        fd.isGyroAvailable,
        isFalse,
        reason: 'gyro should be marked unavailable after 2 s staleness',
      );
      expect(
        gyroUnavailableCalls,
        1,
        reason: 'onGyroUnavailable must fire exactly once on transition',
      );

      // A second accel tick must NOT re-fire the callback (idempotent).
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
      expect(
        gyroUnavailableCalls,
        1,
        reason:
            'onGyroUnavailable must not fire again while already '
            'unavailable',
      );
    });

    test('full profile still rejects tumble when gyro reports no rotational '
        'impact (degradation is not silently weakening the normal path)', () {
      final fd = FallDetector();
      FallClass? detected;
      final stages = <String>[];
      fd.onFallDetected = (c) => detected = c;
      fd.onStageChange = (stage, {accel, gyro, stillFrames}) =>
          stages.add(stage);

      // Gyro available but reports near-zero rotation throughout.
      fd.setGyroAvailableForTesting(true);
      // Seed a recent gyro reading so the staleness watchdog does not fire.
      fd.onGyroForTesting(GyroscopeEvent(0, 0, 0.1, DateTime.now()));

      // Freefall + impact + 40 still frames (full-profile requirement).
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 2.0, DateTime.now()));
      fd.onAccelForTesting(AccelerometerEvent(0, 0, 40.0, DateTime.now()));
      // Keep gyro alive and quiet during stillness.
      for (var i = 0; i < 40; i++) {
        fd.onGyroForTesting(GyroscopeEvent(0, 0, 0.1, DateTime.now()));
        fd.onAccelForTesting(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
      }

      expect(
        detected,
        isNull,
        reason: 'full profile must still require rotational impact',
      );
      expect(
        stages,
        contains('aborted_no_rotation'),
        reason: 'low gyro peak should abort as no_rotation in full profile',
      );
    });
  });
}
