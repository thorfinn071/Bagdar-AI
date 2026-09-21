import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/alerts/haptic_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const amplitudeDevice = HapticDeviceCapabilities(
    hasVibrator: true,
    hasAmplitudeControl: true,
  );
  const basicDevice = HapticDeviceCapabilities(
    hasVibrator: true,
    hasAmplitudeControl: false,
  );

  test('Core haptics expose exactly three non-directional semantics', () {
    expect(HapticSemantic.values, hasLength(3));
    expect(HapticSemantic.values.toSet(), <HapticSemantic>{
      HapticSemantic.immediateStop,
      HapticSemantic.sensingDegraded,
      HapticSemantic.confirmation,
    });
  });

  test('device without amplitude control gets a timing-only fallback', () {
    final result = HapticPolicy().decide(
      FeedbackHapticPattern.immediateStop,
      now: DateTime.utc(2026, 9, 20),
      device: basicDevice,
    );

    expect(result.cue, isNotNull);
    expect(result.cue?.intensities, isNull);
    expect(result.cue?.critical, isTrue);
  });

  test('cooldown suppresses repeats but permits faster risk escalation', () {
    final now = DateTime.utc(2026, 9, 20);
    final policy = HapticPolicy();
    final first = policy.decide(
      FeedbackHapticPattern.immediateStop,
      now: now,
      device: amplitudeDevice,
    );
    final duplicate = policy.decide(
      FeedbackHapticPattern.immediateStop,
      now: now.add(const Duration(milliseconds: 400)),
      device: amplitudeDevice,
    );
    final escalated = policy.decide(
      FeedbackHapticPattern.immediateStop,
      now: now.add(const Duration(milliseconds: 400)),
      device: amplitudeDevice,
      riskIncreased: true,
    );

    expect(first.reason, 'emit');
    expect(duplicate.reason, 'semantic_cooldown');
    expect(escalated.reason, 'emit');
  });

  test('duty-cycle budget suppresses non-critical cues', () {
    final now = DateTime.utc(2026, 9, 20);
    final policy = HapticPolicy(
      maxActiveMsPerWindow: 200,
      confirmationCooldown: Duration.zero,
    );
    expect(
      policy
          .decide(
            FeedbackHapticPattern.confirmation,
            now: now,
            device: amplitudeDevice,
          )
          .reason,
      'emit',
    );
    expect(
      policy
          .decide(
            FeedbackHapticPattern.sensingDegraded,
            now: now.add(const Duration(milliseconds: 1)),
            device: amplitudeDevice,
          )
          .reason,
      'duty_cycle_budget_exhausted',
    );
  });

  test(
    'critical cue degrades to perceptible floor within remaining budget',
    () {
      final now = DateTime.utc(2026, 9, 20);
      final policy = HapticPolicy(maxActiveMsPerWindow: 100);
      final result = policy.decide(
        FeedbackHapticPattern.immediateStop,
        now: now,
        device: amplitudeDevice,
      );

      expect(result.reason, 'emit');
      expect(result.cue?.activeDurationMs, 80);
      expect(result.cue?.intensities?.last, 255);
    },
  );

  test('missing vibrator is explicit and emits no cue', () {
    final result = HapticPolicy().decide(
      FeedbackHapticPattern.sensingDegraded,
      now: DateTime.utc(2026, 9, 20),
      device: const HapticDeviceCapabilities(
        hasVibrator: false,
        hasAmplitudeControl: false,
      ),
    );

    expect(result.cue, isNull);
    expect(result.reason, 'no_vibrator');
  });
}
