import '../../core/core_health.dart';
import '../planning/corridor_candidate.dart';
import '../planning/safety_action.dart';
import 'feedback_command.dart';

class FeedbackPolicy {
  const FeedbackPolicy();

  FeedbackCommand? commandFor(SafetyAction action) {
    if (action.isShadowOnly) {
      return null;
    }
    if (action.kind == SafetyActionKind.continueForward) {
      // Internal state only: never turn this into a "path clear" statement.
      return null;
    }

    final speechKey = switch (action.kind) {
      SafetyActionKind.stopNow => 'generic_obstacle_stop',
      SafetyActionKind.holdAndScan => 'spatial_analysis_limited',
      SafetyActionKind.adjustLeft => 'nav_slight_left',
      SafetyActionKind.adjustRight => 'nav_slight_right',
      SafetyActionKind.continueForward => throw StateError('handled above'),
    };
    final replaceKey = action.hazardIds.isNotEmpty
        ? 'hazard:${action.hazardIds.first}'
        : 'spatial:${action.kind.name}';

    return FeedbackCommand(
      actionId: action.actionId,
      sceneRevision: action.sceneRevision,
      speechKey: speechKey,
      earcon: switch (action.kind) {
        SafetyActionKind.stopNow => FeedbackEarcon.stop,
        SafetyActionKind.holdAndScan => FeedbackEarcon.degraded,
        _ => FeedbackEarcon.none,
      },
      hapticPattern: switch (action.kind) {
        SafetyActionKind.stopNow => FeedbackHapticPattern.immediateStop,
        SafetyActionKind.holdAndScan => FeedbackHapticPattern.sensingDegraded,
        _ => FeedbackHapticPattern.none,
      },
      priority: action.priority,
      source: FeedbackCommandSource.spatialAction,
      actionKind: action.kind,
      direction: action.direction,
      urgency: action.confidence,
      canInterrupt: action.priority == SafetyPriority.p0Emergency,
      replaceKey: replaceKey,
      createdAt: action.createdAt,
      expiresAt: action.validUntil,
      ruleId: action.ruleId,
      hazardIds: action.hazardIds,
    );
  }

  FeedbackCommand? commandForHealth(
    CoreHealthSnapshot snapshot, {
    required bool userMoving,
    required DateTime now,
    Duration ttl = const Duration(seconds: 2),
  }) {
    final mobility = snapshot.capability(CoreCapability.mobilityVision);
    final mobilityUnusable = mobility != ComponentState.available;
    if (mobilityUnusable && userMoving) {
      return FeedbackCommand(
        actionId: 'health-${snapshot.at.microsecondsSinceEpoch}-stop',
        sceneRevision: -1,
        speechKey: 'spatial_stop_sensing_unavailable',
        earcon: FeedbackEarcon.stop,
        hapticPattern: FeedbackHapticPattern.immediateStop,
        priority: SafetyPriority.p0Emergency,
        source: FeedbackCommandSource.coreHealth,
        actionKind: SafetyActionKind.stopNow,
        direction: CorridorDirection.forward,
        urgency: 1,
        canInterrupt: true,
        replaceKey: 'health:mobility_vision',
        createdAt: now,
        expiresAt: now.add(ttl),
        ruleId: 'HEALTH-P0-SENSING-LOST-MOVING',
        hazardIds: <String>['health:${snapshot.reasonCode}'],
      );
    }

    if (snapshot.runState == CoreRunState.operational) return null;
    final speechKey = switch (snapshot.reasonCode) {
      'alert_audio_unavailable' => 'core_health_sound_unavailable',
      'haptics_unavailable' => 'core_health_haptic_unavailable',
      'recovered' || 'recovering' => 'core_health_recovered',
      _ => 'spatial_analysis_limited',
    };
    final recovered =
        snapshot.runState == CoreRunState.recovering ||
        snapshot.reasonCode == 'recovered';
    return FeedbackCommand(
      actionId: 'health-${snapshot.at.microsecondsSinceEpoch}',
      sceneRevision: -1,
      speechKey: speechKey,
      earcon: recovered ? FeedbackEarcon.confirmation : FeedbackEarcon.degraded,
      hapticPattern: recovered
          ? FeedbackHapticPattern.confirmation
          : FeedbackHapticPattern.sensingDegraded,
      priority: recovered
          ? SafetyPriority.p3Information
          : SafetyPriority.p2Degraded,
      source: FeedbackCommandSource.coreHealth,
      actionKind: mobilityUnusable ? SafetyActionKind.holdAndScan : null,
      direction: mobilityUnusable ? CorridorDirection.forward : null,
      urgency: recovered ? 0.2 : 0.6,
      canInterrupt: false,
      replaceKey: 'health:${snapshot.reasonCode}',
      createdAt: now,
      expiresAt: now.add(ttl),
      ruleId: recovered ? 'HEALTH-P3-RECOVERED' : 'HEALTH-P2-DEGRADED',
      hazardIds: <String>['health:${snapshot.reasonCode}'],
    );
  }
}
