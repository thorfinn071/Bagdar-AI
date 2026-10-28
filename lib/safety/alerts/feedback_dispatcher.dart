import '../../core/core_health_coordinator.dart';
import '../../core/performance/feedback_delivery_performance.dart';
import '../../services/field_logger.dart';
import '../planning/safety_action.dart';
import 'feedback_command.dart';
import 'haptic_policy.dart';

abstract interface class FeedbackOutputPort {
  bool get ttsAvailable;
  bool get hapticAvailable;
  bool get earconAvailable;
  HapticDeviceCapabilities get hapticCapabilities;

  Future<bool> speak(FeedbackCommand command);
  Future<bool> playEarcon(FeedbackEarcon earcon);
  Future<bool> vibrate(HapticCue cue);
  Future<void> interruptCurrent();
  Future<void> awaitCompletion(FeedbackCommand command);
}

class FeedbackDispatchResult {
  final bool speechDelivered;
  final bool earconDelivered;
  final bool hapticDelivered;
  final bool fallbackUsed;
  final bool dropped;
  final String reason;
  final CoreHealthSnapshot healthSnapshot;

  const FeedbackDispatchResult({
    required this.speechDelivered,
    required this.earconDelivered,
    required this.hapticDelivered,
    required this.fallbackUsed,
    required this.dropped,
    required this.reason,
    required this.healthSnapshot,
  });
}

/// Executes an already-arbitrated command and records output-channel health.
/// It does not inspect scene geometry or change action priority.
class FeedbackDispatcher {
  final CoreHealthCoordinator healthCoordinator;
  final HapticPolicy hapticPolicy;
  final FeedbackDeliveryPerformance _delivery;

  FeedbackDispatcher({
    required this.healthCoordinator,
    HapticPolicy? hapticPolicy,
    FeedbackDeliveryPerformance? deliveryPerformance,
  }) : hapticPolicy = hapticPolicy ?? HapticPolicy(),
       _delivery = deliveryPerformance ?? FeedbackDeliveryPerformance.instance;

  Future<FeedbackDispatchResult> dispatch(
    FeedbackCommand command, {
    required FeedbackOutputPort output,
    required DateTime now,
    bool riskIncreased = false,
  }) async {
    if (command.isExpiredAt(now)) {
      return FeedbackDispatchResult(
        speechDelivered: false,
        earconDelivered: false,
        hapticDelivered: false,
        fallbackUsed: false,
        dropped: true,
        reason: 'expired_before_dispatch',
        healthSnapshot: healthCoordinator.snapshot(now),
      );
    }

    var speechDelivered = false;
    final delivery = _delivery;
    final dispatchAtUs = delivery.nowUs;
    delivery.count('feedbackCommands');
    if (output.ttsAvailable) {
      speechDelivered = await output.speak(command);
    }
    final ttsHealthy = output.ttsAvailable && speechDelivered;
    healthCoordinator.note(
      component: CoreComponent.alertAudio,
      state: ttsHealthy ? ComponentState.available : ComponentState.unavailable,
      reasonCode: ttsHealthy
          ? 'feedback_speech_delivered'
          : 'tts_unavailable_feedback_fallback',
      now: now,
      announce: false,
    );

    final effectiveHaptic =
        !ttsHealthy && command.hapticPattern == FeedbackHapticPattern.none
        ? command.priority == SafetyPriority.p0Emergency
              ? FeedbackHapticPattern.immediateStop
              : FeedbackHapticPattern.sensingDegraded
        : command.hapticPattern;
    final hapticDecision = hapticPolicy.decide(
      effectiveHaptic,
      now: now,
      device: output.hapticCapabilities,
      riskIncreased: riskIncreased,
    );
    var hapticDelivered = false;
    final hapticAttempted =
        output.hapticAvailable && hapticDecision.cue != null;
    if (hapticAttempted) {
      delivery.count('hapticRequested');
      delivery.record('dispatchToHapticRequest', delivery.nowUs - dispatchAtUs);
      FieldLogger.instance.log('feedback_haptic_request', {
        'action_id': command.actionId,
        'at_us': delivery.nowUs,
        'clock': 'dart_feedback_elapsed',
        'actual_vibration_measured': false,
      });
      hapticDelivered = await output.vibrate(hapticDecision.cue!);
      delivery.count(
        hapticDelivered ? 'hapticReplyAccepted' : 'hapticReplyUnavailable',
      );
      delivery.record('dispatchToHapticReply', delivery.nowUs - dispatchAtUs);
    }
    if (effectiveHaptic != FeedbackHapticPattern.none) {
      final previous = healthCoordinator
          .snapshot(now)
          .components[CoreComponent.haptics];
      final failed = hapticAttempted && !hapticDelivered;
      final retainFailure =
          output.hapticAvailable &&
          !hapticAttempted &&
          previous?.state == ComponentState.unavailable;
      healthCoordinator.note(
        component: CoreComponent.haptics,
        state: output.hapticAvailable && !failed && !retainFailure
            ? ComponentState.available
            : ComponentState.unavailable,
        reasonCode: hapticDelivered
            ? 'feedback_haptic_delivered'
            : failed
            ? 'haptic_platform_failed'
            : retainFailure
            ? previous!.reasonCode
            : output.hapticAvailable
            ? 'haptic_policy_suppressed'
            : 'haptic_fallback_unavailable',
        now: now,
        announce: false,
      );
    }

    var earconDelivered = false;
    if (command.earcon != FeedbackEarcon.none && output.earconAvailable) {
      earconDelivered = await output.playEarcon(command.earcon);
    }

    final fallbackUsed = !ttsHealthy && hapticDelivered;
    final noOutput = !speechDelivered && !hapticDelivered && !earconDelivered;
    return FeedbackDispatchResult(
      speechDelivered: speechDelivered,
      earconDelivered: earconDelivered,
      hapticDelivered: hapticDelivered,
      fallbackUsed: fallbackUsed,
      dropped: noOutput,
      reason: noOutput
          ? 'no_feedback_output_available'
          : fallbackUsed
          ? 'tts_unavailable_haptic_fallback'
          : 'delivered',
      healthSnapshot: healthCoordinator.snapshot(now),
    );
  }
}
