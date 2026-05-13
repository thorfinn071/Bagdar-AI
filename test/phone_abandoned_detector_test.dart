import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/phone_abandoned_detector.dart';

void main() {
  group('PhoneAbandonedDetector (Safety follow-up M12)', () {
    late PhoneAbandonedDetector det;
    late DateTime t0;

    setUp(() {
      det = PhoneAbandonedDetector();
      t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
    });

    test('walking user never triggers critical or soft heartbeat', () {
      det.noteMotionState(MotionState.walking, now: t0);
      det.noteCameraFrozen(true);
      det.noteLumaNormal(true);
      for (var i = 0; i < 700; i++) {
        // 11+ minutes of walking
        final r = det.tick(now: t0.add(Duration(seconds: i)));
        expect(r.fireCriticalAlert, isFalse, reason: 'tick=$i');
        expect(r.fireSoftHeartbeat, isFalse, reason: 'tick=$i');
      }
    });

    test('stationary but camera not frozen never fires critical', () {
      det.noteMotionState(MotionState.stationary, now: t0);
      det.noteCameraFrozen(false);
      det.noteLumaNormal(true);
      var crit = 0;
      for (var i = 0; i < 90; i++) {
        final r = det.tick(now: t0.add(Duration(seconds: i)));
        if (r.fireCriticalAlert) crit++;
      }
      expect(crit, 0,
          reason:
              'frozen camera is a required pre-condition; a stationary user '
              'still actively using the camera must not be alerted');
    });

    test(
      'stationary + frozen + dark luma (pocketed) never fires critical',
      () {
        det.noteMotionState(MotionState.stationary, now: t0);
        det.noteCameraFrozen(true);
        det.noteLumaNormal(false);
        var crit = 0;
        for (var i = 0; i < 90; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          if (r.fireCriticalAlert) crit++;
        }
        expect(crit, 0,
            reason:
                'low luma = phone in pocket / table-down with screen covered: '
                'we cannot tell the phone is "lying down" vs "being carried '
                'in a dark pocket"; suppress the alert.');
      },
    );

    test(
      'all three conditions for >=60 s fires critical exactly once until '
      'the re-announce window elapses',
      () {
        det.noteMotionState(MotionState.stationary, now: t0);
        det.noteCameraFrozen(true);
        det.noteLumaNormal(true);

        var crit = 0;
        for (var i = 0; i < 60; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          expect(r.fireCriticalAlert, isFalse,
              reason: 'must not fire before 60 s, got at tick=$i');
        }
        // tick exactly at 60 s — should fire
        final atSixty = det.tick(now: t0.add(const Duration(seconds: 60)));
        expect(atSixty.fireCriticalAlert, isTrue);
        expect(atSixty.hapticEscalationLevel, 1,
            reason: 'first critical = escalation level 1');
        expect(atSixty.hapticPattern, isNotNull);

        // Next 89 seconds: no re-fire
        for (var i = 61; i < 60 + 90; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          if (r.fireCriticalAlert) crit++;
        }
        expect(crit, 0,
            reason: 're-announce window is 90 s, no re-fire in between');

        // At 60 + 90 = 150 s, re-announces with level 2
        final at150 =
            det.tick(now: t0.add(const Duration(seconds: 150)));
        expect(at150.fireCriticalAlert, isTrue);
        expect(at150.hapticEscalationLevel, 2,
            reason: 'second critical = escalation level 2');
      },
    );

    test(
      'haptic escalation caps at level 4 even on repeated criticals',
      () {
        det.noteMotionState(MotionState.stationary, now: t0);
        det.noteCameraFrozen(true);
        det.noteLumaNormal(true);

        final levelsSeen = <int>[];
        // run for 10 critical episodes (10 * 90 s + first 60 s = 960 s)
        for (var i = 0; i <= 960; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          if (r.fireCriticalAlert) {
            levelsSeen.add(r.hapticEscalationLevel);
          }
        }
        expect(levelsSeen.length, greaterThan(4),
            reason: 'multiple criticals should have fired');
        expect(
          levelsSeen.every((l) => l >= 1 && l <= 4),
          isTrue,
          reason: 'escalation levels must stay within 1..4',
        );
        expect(levelsSeen.last, 4,
            reason: 'late episodes must remain pinned at max level 4');
      },
    );

    test(
      'state resets to clean once user starts walking — next stationary '
      'period restarts the 60 s clock',
      () {
        det.noteMotionState(MotionState.stationary, now: t0);
        det.noteCameraFrozen(true);
        det.noteLumaNormal(true);

        // Get to a critical alert
        for (var i = 0; i < 60; i++) {
          det.tick(now: t0.add(Duration(seconds: i)));
        }
        final firstCritical =
            det.tick(now: t0.add(const Duration(seconds: 60)));
        expect(firstCritical.fireCriticalAlert, isTrue);

        // Now user starts walking again
        det.noteMotionState(
          MotionState.walking,
          now: t0.add(const Duration(seconds: 65)),
        );
        // ... walks for 30 s ...
        for (var i = 65; i < 95; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          expect(r.fireCriticalAlert, isFalse,
              reason: 'no alerts while walking');
        }

        // Stops again
        det.noteMotionState(
          MotionState.stationary,
          now: t0.add(const Duration(seconds: 95)),
        );

        // Must NOT alert at 95 + 1 = 96 s wall clock (only 1 s of stationary)
        for (var i = 96; i < 95 + 60; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          expect(r.fireCriticalAlert, isFalse,
              reason: 'fresh stationary at $i — too early');
        }

        // Must alert at 95 + 60 = 155 s wall clock (60 s of new stationary)
        final reFire =
            det.tick(now: t0.add(const Duration(seconds: 155)));
        expect(reFire.fireCriticalAlert, isTrue,
            reason: 'clock must have restarted on the new stationary episode');
        expect(reFire.hapticEscalationLevel, 1,
            reason: 'escalation also resets on motion change');
      },
    );

    test('soft heartbeat fires at 10 min intervals of stationary state', () {
      det.noteMotionState(MotionState.stationary, now: t0);
      // Even WITHOUT cameraFrozen / lumaNormal, the soft heartbeat is the
      // background presence reminder driven purely by stationary duration.
      det.noteCameraFrozen(false);
      det.noteLumaNormal(false);

      var softCount = 0;
      DateTime? lastSoftAt;
      for (var i = 0; i < 60 * 35; i++) {
        // 35 minutes
        final r = det.tick(now: t0.add(Duration(seconds: i)));
        if (r.fireSoftHeartbeat) {
          softCount++;
          lastSoftAt = t0.add(Duration(seconds: i));
        }
      }
      expect(softCount, 3,
          reason:
              '35 min of stationary state should produce a soft heartbeat at '
              '10, 20, and 30 minutes');
      expect(
        lastSoftAt!.difference(t0).inMinutes,
        30,
        reason: 'last soft heartbeat at exactly the 30 min mark',
      );
    });

    test(
      'soft heartbeat clock resets when user starts walking again, so a '
      'short bench-and-walk cycle does not accumulate to a beep',
      () {
        det.noteMotionState(MotionState.stationary, now: t0);
        var softCount = 0;

        // sit for 9 min ... no beep yet
        for (var i = 0; i < 60 * 9; i++) {
          final r = det.tick(now: t0.add(Duration(seconds: i)));
          if (r.fireSoftHeartbeat) softCount++;
        }
        expect(softCount, 0);

        // user walks for 30 s, then stationary again
        det.noteMotionState(
          MotionState.walking,
          now: t0.add(const Duration(minutes: 9)),
        );
        det.noteMotionState(
          MotionState.stationary,
          now: t0.add(const Duration(minutes: 9, seconds: 30)),
        );

        // sit for 9 more min ... still no beep, because the clock reset
        for (var i = 0; i < 60 * 9; i++) {
          final r = det.tick(
            now: t0.add(Duration(minutes: 9, seconds: 30 + i)),
          );
          if (r.fireSoftHeartbeat) softCount++;
        }
        expect(softCount, 0,
            reason:
                'two consecutive 9 min sits must not accumulate into a beep');
      },
    );

    test('public timing constants match the documented audit thresholds', () {
      expect(PhoneAbandonedDetector.kStationaryThreshold,
          const Duration(seconds: 60),
          reason: 'plan M12: 60 s of stationary state required for critical');
      expect(PhoneAbandonedDetector.kSoftHeartbeatInterval,
          const Duration(minutes: 10),
          reason: 'plan M12: soft tier earcon every 10 min');
      expect(PhoneAbandonedDetector.kSoftHeartbeatVolume, 0.3,
          reason: 'plan M12: soft earcon at 0.3 volume');
    });
  });
}
