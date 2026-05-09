import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/alert_manager.dart';
import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/models/app_mode.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
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
    bool barge = false,
  }) {
    calls.add((text: text, priority: priority));
  }
}

Track _personClose({
  required int id,
  required double cx,
  double distM = 2.0,
}) {
  return Track(
    id: id,
    label: 'person',
    cx: cx,
    cy: 240,
    x1: cx - 40,
    y1: 200,
    x2: cx + 40,
    y2: 350,
    dist: 'close',
    distM: distM,
    initialConf: 0.8,
  )
    ..nearFrameCount = 5
    ..reliableFrames = 5
    ..avgConf = 0.8;
}

Track _carClose({
  required int id,
  required double distM,
  DateTime? lastSpoken,
}) {
  final t = Track(
    id: id,
    label: 'car',
    cx: 320,
    cy: 240,
    x1: 220,
    y1: 140,
    x2: 420,
    y2: 340,
    dist: 'close',
    distM: distM,
    initialConf: 0.9,
  )
    ..nearFrameCount = 5
    ..reliableFrames = 5
    ..avgConf = 0.9;
  if (lastSpoken != null) t.lastSpoken = lastSpoken;
  return t;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
    await Settings.instance.setAlertFrequency(AlertFrequency.normal);

    AppStrings.setAlertLanguage(AppLanguage.ru);
  });

  group('AlertManager outdoor crowd grouping — Safety audit 2.4', () {
    test(
      '5 outdoor persons emit one grouped "group ahead" alert, no individual '
      'person close warnings',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),

        );

        final tracks = [
          _personClose(id: 1, cx: 280),
          _personClose(id: 2, cx: 300),
          _personClose(id: 3, cx: 320),
          _personClose(id: 4, cx: 340),
          _personClose(id: 5, cx: 360),
        ];

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        mgr.processFrame(
          tracks: tracks,
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        final groupAheadPrefix = S.alert('group_ahead');
        final groupCalls = tts.calls
            .where((c) => c.text.contains(groupAheadPrefix))
            .toList();
        final closeWarnings = tts.calls
            .where((c) =>
                c.priority == SpeechPriority.warning &&
                c.text.contains(S.alert('close')))
            .toList();

        expect(
          groupCalls.length,
          1,
          reason: 'audit 2.4: outdoor crowd of ≥3 persons must emit one '
              'grouped "group ahead" alert on the first frame',
        );
        expect(
          groupCalls.first.text,
          contains('5'),
          reason: 'grouped alert must include the person count',
        );
        expect(
          closeWarnings.length,
          0,
          reason: 'audit 2.4: individual close-person warning alerts must be '
              'suppressed when the crowd threshold is met',
        );
      },
    );

    test(
      'crowd alert respects kCrowdAlertCooldown (~10 s) across repeated frames',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),
        );

        final tracks = [
          _personClose(id: 1, cx: 280),
          _personClose(id: 2, cx: 300),
          _personClose(id: 3, cx: 320),
          _personClose(id: 4, cx: 340),
          _personClose(id: 5, cx: 360),
        ];

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);

        mgr.processFrame(
          tracks: tracks,
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        mgr.processFrame(
          tracks: tracks,
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 5)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );

        final groupAheadPrefix = S.alert('group_ahead');
        final groupCallsAfter5s =
            tts.calls.where((c) => c.text.contains(groupAheadPrefix)).length;
        expect(
          groupCallsAfter5s,
          1,
          reason: 'crowd cooldown (10 s) must suppress a second crowd '
              'announcement at 5 s',
        );

        mgr.processFrame(
          tracks: tracks,
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 11)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 3,
        );

        final groupCallsAfter11s =
            tts.calls.where((c) => c.text.contains(groupAheadPrefix)).length;
        expect(
          groupCallsAfter11s,
          2,
          reason: 'once kCrowdAlertCooldown has elapsed, a second grouped '
              'alert must be allowed to fire',
        );
      },
    );

    test(
      'two persons (< kIndoorCrowdPersonThreshold) do not trigger crowd '
      'suppression — individual close warnings still fire',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),
        );

        final tracks = [
          _personClose(id: 1, cx: 280),
          _personClose(id: 2, cx: 360),
        ];

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        mgr.processFrame(
          tracks: tracks,
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        final groupAheadPrefix = S.alert('group_ahead');
        final groupCalls =
            tts.calls.where((c) => c.text.contains(groupAheadPrefix)).length;
        expect(
          groupCalls,
          0,
          reason: '2 persons is below crowd threshold — no grouped alert '
              'should fire',
        );
      },
    );
  });

  group('AlertManager sustained-hazard escalation — Safety audit 6.1', () {
    test(
      'close-warning track whose distM drops by ≥30 % is promoted to critical',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),
        );

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 5.0)],
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        final warningsAfterFrame1 = tts.calls
            .where((c) => c.priority == SpeechPriority.warning)
            .length;
        final criticalsAfterFrame1 = tts.calls
            .where((c) => c.priority == SpeechPriority.critical)
            .length;
        expect(
          warningsAfterFrame1,
          1,
          reason: 'first close announcement at 5 m must be a warning',
        );
        expect(
          criticalsAfterFrame1,
          0,
          reason: 'no critical must fire at the first 5 m close announcement',
        );

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 3.0, lastSpoken: t0)],
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 4)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );

        final criticalsAfterFrame2 = tts.calls
            .where((c) => c.priority == SpeechPriority.critical)
            .length;
        expect(
          criticalsAfterFrame2,
          1,
          reason: 'audit 6.1: 5 m → 3 m (40 % drop) must promote the next '
              'close announcement to critical priority',
        );
      },
    );

    test(
      'close-warning track whose distM drops by <30 % stays at warning',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),
        );

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 5.0)],
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 4.0, lastSpoken: t0)],
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 4)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );

        final criticals = tts.calls
            .where((c) => c.priority == SpeechPriority.critical)
            .length;
        expect(
          criticals,
          0,
          reason: 'a 20 % approach (5 m → 4 m) is below the 30 % escalation '
              'threshold; priority must remain warning',
        );
      },
    );

    test(
      'escalation baseline advances with each announcement — successive '
      '<30 % drops do not escalate even over long time',
      () {
        final tts = _RecordingTts();
        final mgr = AlertManager(
          tts: tts,
          earcon: EarconService(),
        );

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 5.0)],
          imgW: 640,
          imgH: 480,
          now: t0,
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 1,
        );

        mgr.processFrame(
          tracks: [_carClose(id: 1, distM: 4.0, lastSpoken: t0)],
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 4)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 2,
        );

        mgr.processFrame(
          tracks: [
            _carClose(
              id: 1,
              distM: 3.0,
              lastSpoken: t0.add(const Duration(seconds: 4)),
            ),
          ],
          imgW: 640,
          imgH: 480,
          now: t0.add(const Duration(seconds: 8)),
          mode: AppMode.street,
          isCalibrated: true,
          frameCount: 3,
        );

        final criticals = tts.calls
            .where((c) => c.priority == SpeechPriority.critical)
            .length;
        expect(
          criticals,
          0,
          reason: 'each successive step is <30 % of the previous announcement '
              'baseline, so escalation must not fire — matches design intent '
              'of promoting only *rapid* approaches',
        );
      },
    );
  });
}
