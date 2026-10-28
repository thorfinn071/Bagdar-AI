import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/core/performance/feedback_delivery_performance.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/alerts/feedback_dispatcher.dart';
import 'package:bagdar/safety/alerts/haptic_policy.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:flutter_test/flutter_test.dart';

class _Output implements FeedbackOutputPort {
  bool hapticReply = false;
  final void Function() speechReply;
  _Output(this.speechReply);
  @override
  bool get ttsAvailable => true;
  @override
  bool get hapticAvailable => true;
  @override
  bool get earconAvailable => false;
  @override
  HapticDeviceCapabilities get hapticCapabilities =>
      const HapticDeviceCapabilities(
        hasVibrator: true,
        hasAmplitudeControl: false,
      );
  @override
  Future<bool> speak(FeedbackCommand command) async {
    speechReply();
    return true;
  }

  @override
  Future<bool> vibrate(HapticCue cue) async => hapticReply;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'haptic request timing and failed reply are associated with an admitted command',
    () async {
      var clockUs = 0;
      final now = DateTime.utc(2026, 10, 5);
      final performance = FeedbackDeliveryPerformance(clockUs: () => clockUs);
      final dispatcher = FeedbackDispatcher(
        healthCoordinator: CoreHealthCoordinator(),
        deliveryPerformance: performance,
      );
      final command = FeedbackCommand(
        actionId: 'action-test',
        sceneRevision: 1,
        speechKey: 'test',
        earcon: FeedbackEarcon.none,
        hapticPattern: FeedbackHapticPattern.immediateStop,
        priority: SafetyPriority.p0Emergency,
        source: FeedbackCommandSource.emergency,
        actionKind: SafetyActionKind.stopNow,
        direction: null,
        urgency: 1,
        canInterrupt: true,
        replaceKey: 'test',
        createdAt: now,
        expiresAt: now.add(const Duration(seconds: 1)),
        ruleId: 'TEST',
        hazardIds: [],
      );
      final output = _Output(() {
        clockUs = 5000;
      });
      final result = await dispatcher.dispatch(
        command,
        output: output,
        now: now,
      );
      expect(result.hapticDelivered, false);
      expect(
        result.healthSnapshot.components[CoreComponent.haptics]?.state,
        ComponentState.unavailable,
      );
      expect(
        result.healthSnapshot.components[CoreComponent.haptics]?.reasonCode,
        'haptic_platform_failed',
      );
      final report = performance.takeWindow();
      expect((report['counts'] as Map)['hapticRequested'], 1);
      expect((report['counts'] as Map)['hapticReplyUnavailable'], 1);
      expect(
        ((report['timings'] as Map)['dispatchToHapticRequest'] as Map)['p95Ms'],
        5,
      );
      expect(report['actualVibrationMeasured'], false);
      final suppressed = await dispatcher.dispatch(
        command,
        output: output,
        now: now.add(const Duration(milliseconds: 1)),
      );
      expect(suppressed.hapticDelivered, false);
      expect(
        suppressed.healthSnapshot.components[CoreComponent.haptics]?.state,
        ComponentState.unavailable,
      );
      output.hapticReply = true;
      final recovered = await dispatcher.dispatch(
        command,
        output: output,
        now: now.add(const Duration(milliseconds: 800)),
        riskIncreased: true,
      );
      expect(recovered.hapticDelivered, true);
      expect(
        recovered.healthSnapshot.components[CoreComponent.haptics]?.state,
        ComponentState.available,
      );
      performance.takeWindow();
      await dispatcher.dispatch(
        command,
        output: output,
        now: now.add(const Duration(seconds: 2)),
      );
      expect(performance.takeWindow()['counts'], isEmpty);
    },
  );
}
