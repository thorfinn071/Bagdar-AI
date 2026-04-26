import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/alert_manager.dart';
import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/models/app_mode.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/earcon_service.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/tracker/track.dart';

class _RecordingTts extends TtsService {
  final List<({String text, SpeechPriority priority})> calls = [];
  _RecordingTts() : super.forTesting();

  @override
  void say(
    String text,
    SpeechPriority priority, {
    double pan = 0.0,
    int? trackId,
  }) {
    calls.add((text: text, priority: priority));
  }
}

Track _veryCloseTrack({DateTime? lastSpoken}) {
  final t = Track(
    id: 1,
    label: 'person',
    cx: 320,
    cy: 240,
    x1: 220,
    y1: 140,
    x2: 420,
    y2: 340,
    dist: 'very close',
    distM: 0.5,
    initialConf: 0.9,
  )
    ..nearFrameCount = 5
    ..reliableFrames = 5
    ..avgConf = 0.9
    ..fastTrack = true;
  if (lastSpoken != null) t.lastSpoken = lastSpoken;
  return t;
}

int _criticalCount(_RecordingTts tts) =>
    tts.calls.where((c) => c.priority == SpeechPriority.critical).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
  });

  group('AlertManager critical cooldown — Safety A-1', () {
    test(
      'critical "СТОП" cooldown is NOT scaled by AlertFrequency.rare '
      '(multiplier 2.0 must not delay safety-critical alerts to 2.8 s)',
      () async {
        await Settings.instance.setAlertFrequency(AlertFrequency.rare);
        final tts = _RecordingTts();
        final mgr = AlertManager(tts: tts, earcon: EarconService());

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        mgr.processFrame(
          tracks: [_veryCloseTrack()],
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );
        expect(
          _criticalCount(tts),
          1,
          reason: 'first very-close track must trigger critical immediately',
        );

        
        
        final t1 = t0.add(const Duration(milliseconds: 1500));
        mgr.processFrame(
          tracks: [_veryCloseTrack(lastSpoken: t0)],
          imgW: 640,
          imgH: 480,
          now: t1,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );
        expect(
          _criticalCount(tts),
          2,
          reason:
              'A-1 regression: critical cooldown must remain '
              '${kCriticalCooldown.inMilliseconds} ms regardless of '
              'AlertFrequency. At 1.5 m/s walk pace, a 2.8 s gap creates a '
              '4.2 m collision corridor for dynamic obstacles.',
        );
      },
    );

    test(
      'critical fires every kCriticalCooldown across all AlertFrequency settings',
      () async {
        for (final freq in AlertFrequency.values) {
          await Settings.instance.setAlertFrequency(freq);
          final tts = _RecordingTts();
          final mgr = AlertManager(tts: tts, earcon: EarconService());

          final t0 = DateTime(2025, 1, 1, 12, 0, 0);
          for (int i = 0; i < 5; i++) {
            final now = t0.add(Duration(milliseconds: 1500 * i));
            mgr.processFrame(
              tracks: [_veryCloseTrack(lastSpoken: i == 0 ? null : t0)],
              imgW: 640,
              imgH: 480,
              now: now,
              mode: AppMode.street,
              isCalibrated: true,
              frameCount: i + 1,
            );
          }
          expect(
            _criticalCount(tts),
            5,
            reason:
                'AlertFrequency.$freq must NOT throttle critical alerts; '
                'expected 5 critical fires across 6 s of "very close" frames',
          );
        }
      },
    );

    test(
      'critical respects true cooldown floor (1400 ms) when frames arrive too fast',
      () async {
        await Settings.instance.setAlertFrequency(AlertFrequency.normal);
        final tts = _RecordingTts();
        final mgr = AlertManager(tts: tts, earcon: EarconService());

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        mgr.processFrame(
          tracks: [_veryCloseTrack()],
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );
        
        mgr.processFrame(
          tracks: [_veryCloseTrack(lastSpoken: t0)],
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(milliseconds: 500)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );
        expect(
          _criticalCount(tts),
          1,
          reason:
              'critical cooldown must still suppress duplicate alerts within '
              'kCriticalCooldown=${kCriticalCooldown.inMilliseconds} ms',
        );
      },
    );
  });
}
