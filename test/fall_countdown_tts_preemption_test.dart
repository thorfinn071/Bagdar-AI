import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/fall_countdown_controller.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/sos_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/services/voice_command_service.dart';

FallCountdownController _makeController(TtsService tts) {
  return FallCountdownController(
    tts: tts,
    sos: SosService(),
    voice: VoiceCommandService(),
  );
}

/// Build the exact countdown-tick utterance the controller emits for [s].
String _tickText(int s) =>
    '${S.get('sos_fall_countdown')} $s ${S.get('sos_fall_seconds')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage(AppLanguage.en);
  });

  group('Safety audit 2026-06: fall countdown TTS preemption', () {
    test(
      'countdown tick is enqueued as critical+barge while active, so a later '
      'critical hazard cannot evict it via critical-preemption removeWhere',
      () {
        final tts = TtsService.forTesting();
        final c = _makeController(tts);
        c.initForTesting(secondsLeft: 11);

        // Tick → secondsLeft becomes 10 → countdown tick emitted.
        c.processTickForTesting();

        final tick = _tickText(10);
        final tickJobs = tts.queueSnapshot
            .where((j) => j.text == tick)
            .toList();
        expect(
          tickJobs,
          hasLength(1),
          reason: 'exactly one "10 seconds" tick should be enqueued',
        );
        expect(
          tickJobs.single.priority,
          SpeechPriority.critical,
          reason:
              'countdown tick must be promoted to critical while the '
              'countdown is active so it survives critical preemption',
        );

        // Simulate a recurring depth-hazard critical arriving during the
        // countdown (e.g. hazard_stairs_down).
        tts.say('hazard_stairs_down', SpeechPriority.critical);

        // Critical preemption runs removeWhere(j.priority != critical).
        // The tick (now critical) must survive.
        expect(
          tts.queueSnapshot.any((j) => j.text == tick),
          isTrue,
          reason:
              'countdown tick must NOT be evicted by a critical hazard '
              'arrival — the user must hear how many seconds remain before '
              'SOS is sent',
        );
        expect(
          tts.queueSnapshot.any((j) => j.text == 'hazard_stairs_down'),
          isTrue,
          reason: 'the hazard critical itself must also remain enqueued',
        );
      },
    );

    test('"Обнаружено падение" (critical) is not lost when countdown ticks and '
        'a hazard critical share the queue', () {
      final tts = TtsService.forTesting();

      // Simulate the very first utterance of start(): the fall-detected
      // critical with barge (spoken before any tick).
      const detectedKey = 'sos_fall_detected';
      tts.say(S.get(detectedKey), SpeechPriority.critical, barge: true);

      final c = _makeController(tts);
      c.initForTesting(secondsLeft: 11);
      c.processTickForTesting(); // tick at 10 s (critical)

      // A depth-hazard critical arrives mid-countdown.
      tts.say('hazard_stairs_down', SpeechPriority.critical);

      // The fall-detected announcement must still be in the queue.
      expect(
        tts.queueSnapshot.any((j) => j.text == S.get(detectedKey)),
        isTrue,
        reason:
            '"Обнаружено падение" (critical) must not be dropped when '
            'countdown ticks and hazard criticals are enqueued alongside it',
      );
      // The tick must still be present too.
      expect(
        tts.queueSnapshot.any((j) => j.text == _tickText(10)),
        isTrue,
        reason: 'the "10 seconds" countdown tick must still be present',
      );
    });

    test('new countdown ticks replace stale ticks while preserving an '
        'independent hazard critical', () {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);
      c.initForTesting(secondsLeft: 11);

      // Drive ticks down to 10, then send a hazard, then continue to 0.
      // secondsLeft: 11 → 10 (announce) → 9 → 8 → 7 → 6 → 5 (announce)
      //   → 4 → 3 (announce) → 2 (announce) → 1 (announce) → 0 (SOS).
      for (var i = 0; i < 11; i++) {
        if (!c.active) break;
        c.processTickForTesting();
        final s = c.secondsLeft;
        // After the tick that lands on 10, inject a hazard critical.
        if (s == 9) {
          tts.say('hazard_stairs_down', SpeechPriority.critical);
        }
      }

      final queuedTicks = tts.queueSnapshot
          .where((job) => job.text.contains(S.get('sos_fall_countdown')))
          .toList();
      expect(
        queuedTicks,
        hasLength(1),
        reason: 'only the latest countdown state may remain queued',
      );
      expect(queuedTicks.single.text, _tickText(1));
      expect(
        tts.queueSnapshot.any((job) => job.text == 'hazard_stairs_down'),
        isTrue,
        reason: 'replacement must not remove an independent critical hazard',
      );
      expect(
        tts.queueSnapshot.length,
        lessThanOrEqualTo(4),
        reason: 'critical queue stays bounded during the whole countdown',
      );
    });

    test('countdown tick priority and barge are gated by _active — when the '
        'controller is inactive the tick path is not taken at all', () {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);
      // Do NOT call initForTesting — _active stays false, no timer, no ticks.
      expect(c.active, isFalse);
      // No tick utterance should exist.
      expect(
        tts.queueSnapshot,
        isEmpty,
        reason: 'an inactive controller must not emit countdown ticks',
      );
    });
  });
}
