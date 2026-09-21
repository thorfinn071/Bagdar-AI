import '../../core/core_health_coordinator.dart';
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

  FeedbackDispatcher({
    required this.healthCoordinator,
    HapticPolicy? hapticPolicy,
  }) : hapticPolicy = hapticPolicy ?? HapticPolicy();

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
    if (output.hapticAvailable && hapticDecision.cue != null) {
      hapticDelivered = await output.vibrate(hapticDecision.cue!);
    }
    if (effectiveHaptic != FeedbackHapticPattern.none) {
      healthCoordinator.note(
        component: CoreComponent.haptics,
        state: output.hapticAvailable
            ? ComponentState.available
            : ComponentState.unavailable,
        reasonCode: hapticDelivered
            ? 'feedback_haptic_delivered'
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
