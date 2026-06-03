import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart'
    show DepthPipelineStatus;
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/misalignment_watchdog.dart';
import 'package:bagdar/services/orientation_service.dart' show DevicePitch;

void main() {
  group('MisalignmentWatchdog (Safety follow-up H6)', () {
    late MisalignmentWatchdog wd;
    late DateTime t0;

    setUp(() {
      wd = MisalignmentWatchdog();
      t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
    });

    test('stationary user with optimal pitch never triggers', () {
      wd.notePitchState(DevicePitch.optimal);
      wd.noteMotionState(MotionState.stationary);
      for (var i = 0; i < 90; i++) {
        final r = wd.tick(now: t0.add(Duration(seconds: i)));
        expect(r.fireHaptic, isFalse);
        expect(r.shouldAnnounce, isFalse);
      }
    });

    test(
      'sustained-but-short (<10s) misalignment fires neither haptic nor speech',
      () {
        wd.notePitchState(DevicePitch.tooHigh);
        wd.noteMotionState(MotionState.walking);
        wd.noteDepthStatus(
          DepthPipelineStatus.lowConfidence,
          now: t0,
        );
        for (var i = 0; i < 9; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          expect(r.fireHaptic, isFalse);
          expect(r.shouldAnnounce, isFalse,
              reason: 'no announce before 10 s threshold');
        }
      },
    );

    test(
      'empty-scene path: 25 s sustained misalignment with depth OK fires '
      'haptic but NOT verbal (audit point 2)',
      () {
        wd.notePitchState(DevicePitch.flat);
        wd.noteMotionState(MotionState.walking);
        
        var hapticCount = 0;
        var announceCount = 0;
        for (var i = 0; i < 30; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          if (r.fireHaptic) hapticCount++;
          if (r.shouldAnnounce) announceCount++;
        }
        expect(hapticCount, greaterThanOrEqualTo(1),
            reason: 'haptic must fire once we are sustained');
        expect(announceCount, 0,
            reason: 'depth OK = empty scene, no verbal alert');
      },
    );

    test(
      'misaligned + walking + depth low \u226515 s + sustained \u226510 s '
      'fires warning verbal alert exactly once',
      () {
        wd.notePitchState(DevicePitch.tooLow);
        wd.noteMotionState(MotionState.walking);
        
        wd.noteDepthStatus(
          DepthPipelineStatus.lowConfidence,
          now: t0.subtract(const Duration(seconds: 16)),
        );

        var warnings = 0;
        for (var i = 0; i < 20; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          if (r.shouldAnnounce &&
              r.announcePriority == SpeechPriority.warning) {
            warnings++;
            expect(r.announceKey, MisalignmentWatchdog.kAnnounceKey);
          }
        }
        expect(warnings, 1,
            reason:
                'warning should fire exactly once at ~10 s and not repeat');
      },
    );

    test(
      'reaches critical priority at 35 s with depth-low confirmation',
      () {
        wd.notePitchState(DevicePitch.tooHigh);
        wd.noteMotionState(MotionState.walking);
        wd.noteDepthStatus(
          DepthPipelineStatus.planeFitFailed,
          now: t0.subtract(const Duration(seconds: 20)),
        );

        SpeechPriority? lastPriority;
        for (var i = 0; i < 40; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          if (r.shouldAnnounce) lastPriority = r.announcePriority;
        }
        expect(lastPriority, SpeechPriority.critical);
      },
    );

    test('a detection arrival inside the window resets the sustained timer',
        () {
      wd.notePitchState(DevicePitch.flat);
      wd.noteMotionState(MotionState.walking);
      wd.noteDepthStatus(
        DepthPipelineStatus.lowConfidence,
        now: t0.subtract(const Duration(seconds: 30)),
      );

      // Warning threshold is now 10s. Send detection at 8s to prevent it.
      for (var i = 0; i < 8; i++) {
        wd.tick(now: t0.add(Duration(seconds: i)));
      }
      
      wd.noteDetection(now: t0.add(const Duration(seconds: 8)));

      
      var announces = 0;
      for (var i = 8; i < 16; i++) {
        final r = wd.tick(now: t0.add(Duration(seconds: i)));
        if (r.shouldAnnounce) announces++;
      }
      expect(announces, 0,
          reason: 'detection within sustained window must reset the clock '
              'so we do not fire warning prematurely');
    });

    test('haptic re-fires every 15 s while sustained', () {
      wd.notePitchState(DevicePitch.tooHigh);
      wd.noteMotionState(MotionState.walking);
      
      final hapticTicks = <int>[];
      for (var i = 0; i < 90; i++) {
        final r = wd.tick(now: t0.add(Duration(seconds: i)));
        if (r.fireHaptic) hapticTicks.add(i);
      }
      
      expect(hapticTicks.first, 10);
      expect(hapticTicks.length, greaterThanOrEqualTo(4));
      for (var i = 1; i < hapticTicks.length; i++) {
        final delta = hapticTicks[i] - hapticTicks[i - 1];
        expect(delta, inInclusiveRange(14, 16),
            reason: 'haptic interval should be ~15 s');
      }
    });

    test(
      'returning to optimal pitch resets the watchdog and warning can '
      're-announce on a fresh episode',
      () {
        wd.notePitchState(DevicePitch.tooHigh);
        wd.noteMotionState(MotionState.walking);
        wd.noteDepthStatus(
          DepthPipelineStatus.lowConfidence,
          now: t0.subtract(const Duration(seconds: 20)),
        );

        
        for (var i = 0; i < 15; i++) {
          wd.tick(now: t0.add(Duration(seconds: i)));
        }
        
        wd.notePitchState(DevicePitch.optimal);
        for (var i = 15; i < 20; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          expect(r.shouldAnnounce, isFalse);
        }
        
        wd.notePitchState(DevicePitch.tooLow);

        var warnings = 0;
        for (var i = 20; i < 40; i++) {
          final r = wd.tick(now: t0.add(Duration(seconds: i)));
          if (r.shouldAnnounce &&
              r.announcePriority == SpeechPriority.warning) {
            warnings++;
          }
        }
        expect(warnings, 1,
            reason: 'a fresh sustained episode should produce another '
                'warning announcement');
      },
    );
  });
}
