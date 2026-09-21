import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/fall_countdown_controller.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/sos_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/services/voice_command_service.dart';

FallCountdownController _makeController({
  MotionState Function()? motionStateProvider,
  VoidCallback? onCancelled,
  VoidCallback? onSosSent,
}) {
  return FallCountdownController(
    tts: TtsService.forTesting(),
    sos: SosService(),
    voice: VoiceCommandService(),
    onCancelled: onCancelled,
    onSosSent: onSosSent,
    motionStateProvider: motionStateProvider,
  );
}

/// Advance the countdown by [ticks] steps and return the controller for
/// chaining. Stops early if the controller becomes inactive (SOS fired or
/// cancelled) to avoid advancing past the terminal state.
void _advanceTicks(FallCountdownController c, int ticks) {
  for (var i = 0; i < ticks; i++) {
    if (!c.active) break;
    c.processTickForTesting();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage(AppLanguage.en);
  });

  group('Safety audit 4.2: dazed-user SOS path', () {
    test('dazed check fires at secondsLeft==12 for a 15-second countdown', () {
      final c = _makeController();
      c.initForTesting(secondsLeft: 15);

      expect(
        c.dazedCheckPendingForTesting,
        isFalse,
        reason: 'no dazed check before countdown starts',
      );

      _advanceTicks(c, 3);

      expect(
        c.secondsLeft,
        12,
        reason: 'should be at secondsLeft==12 after 3 ticks',
      );
      expect(
        c.dazedCheckPendingForTesting,
        isTrue,
        reason: 'dazed check must be pending at second 12',
      );
      expect(
        c.active,
        isTrue,
        reason: 'countdown must still be running after dazed trigger',
      );
    });

    test(
      'mobile user (MotionState.walking) auto-cancels SOS at secondsLeft==7',
      () {
        bool cancelled = false;
        final c = _makeController(
          motionStateProvider: () => MotionState.walking,
          onCancelled: () => cancelled = true,
        );
        c.initForTesting(secondsLeft: 15);

        _advanceTicks(c, 8);

        expect(
          c.active,
          isFalse,
          reason:
              'controller must be inactive after mobile-cancel at '
              'secondsLeft==7',
        );
        expect(
          cancelled,
          isTrue,
          reason:
              'onCancelled callback must fire when dazed-mobile path '
              'cancels the SOS',
        );
        expect(
          c.dazedCheckPendingForTesting,
          isFalse,
          reason: 'dazedCheckPending must be cleared after resolution',
        );
      },
    );

    test(
      'stationary unresponsive user triggers early SOS at secondsLeft==7',
      () {
        final c = _makeController(
          motionStateProvider: () => MotionState.stationary,
          onSosSent: () {},
        );
        c.initForTesting(secondsLeft: 15);

        _advanceTicks(c, 8);

        expect(
          c.active,
          isFalse,
          reason:
              'controller must be inactive after stationary-early-SOS '
              'at secondsLeft==7',
        );
        expect(
          c.dazedCheckPendingForTesting,
          isFalse,
          reason: 'dazedCheckPending must be cleared after SOS escalation',
        );
      },
    );

    test('two user taps before secondsLeft==7 clears dazedCheckPending and '
        'cancels (Safety audit C-3: a single tap only arms confirmation)', () {
      bool cancelled = false;
      final c = _makeController(
        motionStateProvider: () => MotionState.stationary,
        onCancelled: () => cancelled = true,
      );
      c.initForTesting(secondsLeft: 15);

      _advanceTicks(c, 3);
      expect(
        c.dazedCheckPendingForTesting,
        isTrue,
        reason: 'precondition: dazed check must be pending',
      );

      c.notifyTouch();
      expect(
        c.active,
        isTrue,
        reason:
            'C-3: a lone tap must not cancel — it only prompts a '
            'confirmation, so an accidental tap cannot abort a real SOS',
      );

      c.notifyTouch();

      expect(
        c.active,
        isFalse,
        reason: 'second confirming tap must cancel the countdown',
      );
      expect(
        cancelled,
        isTrue,
        reason: 'onCancelled must fire on confirmed cancel',
      );
      expect(
        c.dazedCheckPendingForTesting,
        isFalse,
        reason: 'dazedCheckPending must be cleared by cancel()',
      );
    });

    test('winter-mode countdown (11s) skips the dazed check — '
        'secondsLeft never reaches 12', () {
      final c = _makeController(motionStateProvider: () => MotionState.walking);
      c.initForTesting(
        secondsLeft: 11,
        duration: FallCountdownController.scaleDurationForTesting(
          FallCountdownController.kInitialDuration,
          FallCountdownController.kWinterCancelWindowScale,
        ),
      );

      _advanceTicks(c, 4);

      expect(
        c.dazedCheckPendingForTesting,
        isFalse,
        reason:
            'an 11-second countdown never hits secondsLeft==12, '
            'so the dazed check must be skipped entirely',
      );
      expect(
        c.active,
        isTrue,
        reason: 'countdown should still be running after 4 ticks of 11s',
      );
    });

    test(
      'no motionStateProvider → stationary path taken (null treated as stationary)',
      () {
        final c = _makeController();
        c.initForTesting(secondsLeft: 15);

        _advanceTicks(c, 8);

        expect(
          c.active,
          isFalse,
          reason:
              'null motionStateProvider defaults to stationary path '
              '(early SOS)',
        );
      },
    );

    test('dazed check does NOT fire on a Class B collapse countdown before '
        'secondsLeft reaches 12', () {
      final c = _makeController();
      c.initForTesting(
        secondsLeft: 30,
        duration: FallCountdownController.kCollapseDuration,
      );

      _advanceTicks(c, 5);

      expect(
        c.dazedCheckPendingForTesting,
        isFalse,
        reason:
            'at tick 5 of a 30s collapse countdown, secondsLeft is '
            '25 — no dazed check yet',
      );
      expect(c.active, isTrue);
    });

    test(
      'Class B collapse countdown triggers dazed check at secondsLeft==12',
      () {
        final c = _makeController();
        c.initForTesting(
          secondsLeft: 30,
          duration: FallCountdownController.kCollapseDuration,
        );

        _advanceTicks(c, 18);

        expect(
          c.secondsLeft,
          12,
          reason: 'after 18 ticks of 30s collapse: 30-18=12',
        );
        expect(
          c.dazedCheckPendingForTesting,
          isTrue,
          reason:
              'Class B collapse countdown must also fire dazed check '
              'at secondsLeft==12',
        );
      },
    );
  });
}
