import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/alerts/feedback_dispatcher.dart';
import 'package:bagdar/safety/alerts/feedback_policy.dart';
import 'package:bagdar/safety/alerts/haptic_policy.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:flutter_test/flutter_test.dart';

SafetyAction _action(
  DateTime now, {
  SafetyActionKind kind = SafetyActionKind.stopNow,
  SafetyActionDelivery delivery = SafetyActionDelivery.primary,
}) => SafetyAction(
  actionId: 'action-${kind.name}',
  kind: kind,
  cause: 'test',
  priority: kind == SafetyActionKind.stopNow
      ? SafetyPriority.p0Emergency
      : SafetyPriority.p2Degraded,
  delivery: delivery,
  sceneRevision: 1,
  hazardIds: const <String>['hazard:center'],
  evidenceSummary: const <String, Object?>{'source': 'test'},
  direction: CorridorDirection.forward,
  confidence: 0.9,
  createdAt: now,
  validUntil: now.add(const Duration(seconds: 2)),
  ruleId: 'TEST-POLICY',
);

FeedbackCommand _command(
  DateTime now, {
  FeedbackHapticPattern hapticPattern = FeedbackHapticPattern.none,
  Duration ttl = const Duration(seconds: 2),
}) => FeedbackCommand(
  actionId: 'dispatch-stop',
  sceneRevision: 1,
  speechKey: 'generic_obstacle_stop',
  earcon: FeedbackEarcon.none,
  hapticPattern: hapticPattern,
  priority: SafetyPriority.p0Emergency,
  source: FeedbackCommandSource.spatialAction,
  actionKind: SafetyActionKind.stopNow,
  direction: CorridorDirection.forward,
  urgency: 0.9,
  canInterrupt: true,
  replaceKey: 'hazard:center',
  createdAt: now,
  expiresAt: now.add(ttl),
  ruleId: 'TEST-DISPATCH',
  hazardIds: const <String>['hazard:center'],
);

class _FakeOutput implements FeedbackOutputPort {
  @override
  final bool ttsAvailable;
  @override
  final bool hapticAvailable;
  @override
  final bool earconAvailable;
  @override
  final HapticDeviceCapabilities hapticCapabilities;

  int speechCalls = 0;
  int hapticCalls = 0;
  int earconCalls = 0;

  _FakeOutput({required this.ttsAvailable, required this.hapticAvailable})
    : earconAvailable = false,
      hapticCapabilities = HapticDeviceCapabilities(
        hasVibrator: hapticAvailable,
        hasAmplitudeControl: true,
      );

  @override
  Future<bool> speak(FeedbackCommand command) async {
    speechCalls++;
    return ttsAvailable;
  }

  @override
  Future<bool> playEarcon(FeedbackEarcon earcon) async {
    earconCalls++;
    return earconAvailable;
  }

  @override
  Future<bool> vibrate(HapticCue cue) async {
    hapticCalls++;
    return hapticAvailable;
  }

  @override
  Future<void> interruptCurrent() async {}

  @override
  Future<void> awaitCompletion(FeedbackCommand command) async {}
}

void main() {
  group('FeedbackPolicy', () {
    test('primary stop is short, interruptible and action-first', () {
      final now = DateTime.utc(2026, 9, 20);
      final command = const FeedbackPolicy().commandFor(_action(now));

      expect(command, isNotNull);
      expect(command?.priority, SafetyPriority.p0Emergency);
      expect(command?.speechKey, 'generic_obstacle_stop');
      expect(command?.canInterrupt, isTrue);
      expect(command?.actionKind, SafetyActionKind.stopNow);
    });

    test('continue-forward and shadow actions never reach feedback', () {
      final now = DateTime.utc(2026, 9, 20);
      const policy = FeedbackPolicy();

      expect(
        policy.commandFor(_action(now, kind: SafetyActionKind.continueForward)),
        isNull,
      );
      expect(
        policy.commandFor(
          _action(
            now,
            kind: SafetyActionKind.adjustLeft,
            delivery: SafetyActionDelivery.shadow,
          ),
        ),
        isNull,
      );
    });

    test(
      'RU, KK and EN critical copy starts with an action and avoids claims',
      () {
        const keys = <String>[
          'generic_obstacle_stop',
          'spatial_stop_sensing_unavailable',
        ];
        for (final language in AppLanguage.values) {
          AppStrings.setLanguage(language);
          for (final key in keys) {
            final text = AppStrings.get(key).toLowerCase();
            expect(text, isNotEmpty, reason: '$language:$key');
            expect(text.split(RegExp(r'[.!?]')).first.trim(), isNotEmpty);
            expect(text, isNot(contains(RegExp(r'\d'))));
            expect(text, isNot(contains('метр')));
            expect(text, isNot(contains('meter')));
            expect(text, isNot(contains('путь свобод')));
            expect(text, isNot(contains('path clear')));
            expect(text, isNot(contains('всё безопасно')));
            expect(text, isNot(contains('бәрі қауіпсіз')));
          }
        }
        AppStrings.setLanguage(AppLanguage.ru);
      },
    );
  });

  group('FeedbackDispatcher fallback and health', () {
    test(
      'TTS unavailable triggers haptic fallback and health transition',
      () async {
        final now = DateTime.utc(2026, 9, 20);
        final health = CoreHealthCoordinator();
        final output = _FakeOutput(ttsAvailable: false, hapticAvailable: true);
        final result = await FeedbackDispatcher(
          healthCoordinator: health,
        ).dispatch(_command(now), output: output, now: now);

        expect(output.speechCalls, 0);
        expect(output.hapticCalls, 1);
        expect(result.fallbackUsed, isTrue);
        expect(result.reason, 'tts_unavailable_haptic_fallback');
        expect(
          result.healthSnapshot.components[CoreComponent.alertAudio]?.state,
          ComponentState.unavailable,
        );
        expect(
          result.healthSnapshot.components[CoreComponent.haptics]?.state,
          ComponentState.available,
        );
      },
    );

    test(
      'policy cooldown does not misreport working haptics unavailable',
      () async {
        final now = DateTime.utc(2026, 9, 20);
        final health = CoreHealthCoordinator();
        final output = _FakeOutput(ttsAvailable: false, hapticAvailable: true);
        final dispatcher = FeedbackDispatcher(healthCoordinator: health);
        await dispatcher.dispatch(_command(now), output: output, now: now);

        final second = await dispatcher.dispatch(
          _command(now.add(const Duration(milliseconds: 100))),
          output: output,
          now: now.add(const Duration(milliseconds: 100)),
        );

        expect(second.hapticDelivered, isFalse);
        expect(
          second.healthSnapshot.components[CoreComponent.haptics]?.state,
          ComponentState.available,
        );
        expect(
          second.healthSnapshot.components[CoreComponent.haptics]?.reasonCode,
          'haptic_policy_suppressed',
        );
      },
    );

    test('expired command is dropped before touching any output', () async {
      final createdAt = DateTime.utc(2026, 9, 20);
      final output = _FakeOutput(ttsAvailable: true, hapticAvailable: true);
      final result =
          await FeedbackDispatcher(
            healthCoordinator: CoreHealthCoordinator(),
          ).dispatch(
            _command(createdAt, ttl: const Duration(seconds: 1)),
            output: output,
            now: createdAt.add(const Duration(seconds: 2)),
          );

      expect(result.dropped, isTrue);
      expect(result.reason, 'expired_before_dispatch');
      expect(output.speechCalls, 0);
      expect(output.hapticCalls, 0);
      expect(output.earconCalls, 0);
    });

    test(
      'missing TTS and vibrator produces an explicit dropped result',
      () async {
        final now = DateTime.utc(2026, 9, 20);
        final result =
            await FeedbackDispatcher(
              healthCoordinator: CoreHealthCoordinator(),
            ).dispatch(
              _command(now),
              output: _FakeOutput(ttsAvailable: false, hapticAvailable: false),
              now: now,
            );

        expect(result.dropped, isTrue);
        expect(result.reason, 'no_feedback_output_available');
        expect(
          result.healthSnapshot.components[CoreComponent.haptics]?.state,
          ComponentState.unavailable,
        );
      },
    );
  });
}
