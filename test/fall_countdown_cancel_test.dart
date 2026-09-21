import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/fall_countdown_controller.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage(AppLanguage.en);
  });

  group('Safety audit C-3: single accidental tap must not cancel SOS', () {
    test('a single tap during an active countdown does NOT cancel — it only '
        'prompts sos_cancel_confirm, and the countdown keeps running', () {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);
      c.initForTesting(secondsLeft: 11);

      c.notifyTouch();

      expect(
        c.active,
        isTrue,
        reason:
            'a single tap must arm a confirmation window, not '
            'cancel the countdown outright',
      );
      expect(
        tts.queueSnapshot.any((j) => j.text == S.get('sos_cancel_confirm')),
        isTrue,
        reason: 'the user must be told to tap again to confirm cancel',
      );
      expect(
        tts.queueSnapshot.any((j) => j.text == S.get('sos_fall_cancelled')),
        isFalse,
        reason: 'a lone tap must not cancel the fall SOS countdown',
      );
    });

    test('a second tap within kCancelConfirmWindow confirms the cancel', () {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);
      c.initForTesting(secondsLeft: 11);

      c.notifyTouch(); // arms confirmation
      c.notifyTouch(); // confirms within window

      expect(
        c.active,
        isFalse,
        reason: 'second deliberate tap must cancel the countdown',
      );
      expect(
        tts.queueSnapshot.any((j) => j.text == S.get('sos_fall_cancelled')),
        isTrue,
        reason: 'cancellation must be announced',
      );
    });

    test('a tap after kCancelConfirmWindow has elapsed is treated as a fresh '
        'first tap (re-prompts instead of cancelling)', () async {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);
      c.initForTesting(secondsLeft: 11);

      c.notifyTouch(); // arms confirmation at t0

      // Let the real confirmation window expire.
      await Future<void>.delayed(
        FallCountdownController.kCancelConfirmWindow +
            const Duration(milliseconds: 200),
      );

      c.notifyTouch(); // stale first tap — must NOT cancel

      expect(
        c.active,
        isTrue,
        reason:
            'a tap after the confirmation window expired must be '
            'treated as a new first tap, not a confirming second tap',
      );

      // A follow-up tap now (within a fresh window) must confirm the
      // cancel — proving the stale tap re-armed the confirmation state
      // rather than leaving it permanently confirmed or permanently dead.
      c.notifyTouch();
      expect(
        c.active,
        isFalse,
        reason:
            'the re-armed confirmation window must still accept a '
            'genuine second tap',
      );
    });

    test('notifyTouch() while inactive only records the timestamp and does '
        'nothing else', () {
      final tts = TtsService.forTesting();
      final c = _makeController(tts);

      expect(c.active, isFalse);
      c.notifyTouch();

      expect(tts.queueSnapshot, isEmpty);
    });
  });
}
