import '../../core/core_health_coordinator.dart';
import '../../models/generic_obstacle.dart';
import '../../tracker/generic_obstacle_tracker.dart';
import '../alerts/alert_arbiter.dart';
import '../perception/observation_header.dart';
import '../planning/guidance_state_machine.dart';
import '../planning/safety_action.dart';
import '../world/generic_geometry_scene_adapter.dart';
import '../world/local_scene_model.dart';
import '../world/local_scene_snapshot.dart';
import '../world/relative_polar_grid.dart';

enum SpatialRuntimeIngestStatus {
  accepted,
  providerStateAccepted,
  rejectedSession,
  rejectedOutOfOrder,
  rejectedStale,
  rejectedScene,
}

/// Privacy-safe, bounded trace for one runtime decision.
class SpatialRuntimeTrace {
  final DateTime at;
  final SpatialRuntimeIngestStatus status;
  final String reason;
  final int sessionGeneration;
  final int frameId;
  final String providerId;
  final String modelId;
  final String preprocessId;
  final int sceneRevision;
  final GuidanceState? plannerState;
  final SafetyActionKind? plannedAction;
  final SafetyActionDelivery? submittedDelivery;
  final String? plannedRuleId;
  final AlertArbiterEventType? arbiterEvent;
  final String? arbiterReason;

  const SpatialRuntimeTrace({
    required this.at,
    required this.status,
    required this.reason,
    required this.sessionGeneration,
    required this.frameId,
    required this.providerId,
    required this.modelId,
    required this.preprocessId,
    required this.sceneRevision,
    required this.plannerState,
    required this.plannedAction,
    required this.submittedDelivery,
    required this.plannedRuleId,
    required this.arbiterEvent,
    required this.arbiterReason,
  });

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'atUs': at.microsecondsSinceEpoch,
    'status': status.name,
    'reason': reason,
    'sessionGeneration': sessionGeneration,
    'frameId': frameId,
    'providerId': providerId,
    'modelId': modelId,
    'preprocessId': preprocessId,
    'sceneRevision': sceneRevision,
    'plannerState': plannerState?.name,
    'plannedAction': plannedAction?.name,
    'submittedDelivery': submittedDelivery?.name,
    'plannedRuleId': plannedRuleId,
    'arbiterEvent': arbiterEvent?.name,
    'arbiterReason': arbiterReason,
  };
}

class SpatialRuntimeResult {
  final SpatialRuntimeIngestStatus status;
  final String reason;
  final LocalSceneSnapshot snapshot;
  final GuidanceDecision? decision;
  final SafetyAction? submittedAction;
  final AlertArbiterEvent? arbiterEvent;
  final SpatialRuntimeTrace trace;

  const SpatialRuntimeResult({
    required this.status,
    required this.reason,
    required this.snapshot,
    required this.decision,
    required this.submittedAction,
    required this.arbiterEvent,
    required this.trace,
  });

  bool get accepted =>
      status == SpatialRuntimeIngestStatus.accepted ||
      status == SpatialRuntimeIngestStatus.providerStateAccepted;
}

/// The single runtime owner for scene fusion -> planning -> arbitration.
///
/// Stage 7 deliberately keeps every planner action in shadow delivery. The
/// runtime still exercises the real arbiter admission path, but the feedback
/// policy suppresses the command before UI/TTS/haptics. Promotion requires the
/// separate supervised gate from Stage 10.
class SpatialSafetyRuntime {
  final CoreHealthCoordinator healthCoordinator;
  final AlertArbiter arbiter;
  final LocalSceneModel sceneModel;
  final GuidanceStateMachine planner;
  final Duration observationTtl;
  final Duration minimumTickInterval;
  final Duration tickActionCooldown;
  final int maxTraceEntries;

  int _activeSessionGeneration = -1;
  int _lastFrameId = 0;
  final List<SpatialRuntimeTrace> _traces = <SpatialRuntimeTrace>[];
  DateTime? _lastTickAt;
  DateTime? _lastTickAdmissionAt;
  String? _lastTickActionSignature;
  String _lastProviderId = 'spatial';
  bool _providerLost = true;

  SpatialSafetyRuntime({
    required this.healthCoordinator,
    AlertArbiter? arbiter,
    LocalSceneModel? sceneModel,
    GuidanceStateMachine? planner,
    this.observationTtl = const Duration(milliseconds: 900),
    this.minimumTickInterval = const Duration(milliseconds: 200),
    this.tickActionCooldown = const Duration(seconds: 2),
    this.maxTraceEntries = 128,
  }) : assert(!observationTtl.isNegative && observationTtl > Duration.zero),
       assert(!minimumTickInterval.isNegative),
       assert(!tickActionCooldown.isNegative),
       assert(maxTraceEntries > 0),
       arbiter = arbiter ?? AlertArbiter(),
       sceneModel = sceneModel ?? LocalSceneModel.relative(),
       planner = planner ?? GuidanceStateMachine();

  int get activeSessionGeneration => _activeSessionGeneration;
  int get lastFrameId => _lastFrameId;
  List<SpatialRuntimeTrace> get traces => List.unmodifiable(_traces);
  SpatialRuntimeTrace? get lastTrace => _traces.isEmpty ? null : _traces.last;

  void beginSession(int generation, {required DateTime now}) {
    if (generation < 0) {
      throw ArgumentError.value(generation, 'generation', 'Must be >= 0.');
    }
    _activeSessionGeneration = generation;
    _lastFrameId = 0;
    _lastTickAt = null;
    _lastTickAdmissionAt = null;
    _lastTickActionSignature = null;
    _lastProviderId = 'spatial';
    _providerLost = true;
    sceneModel.reset();
    planner.reset();
    arbiter.reset();
    _traces.clear();
    _record(
      SpatialRuntimeTrace(
        at: now,
        status: SpatialRuntimeIngestStatus.providerStateAccepted,
        reason: 'session_started',
        sessionGeneration: generation,
        frameId: 0,
        providerId: 'none',
        modelId: 'none',
        preprocessId: 'none',
        sceneRevision: sceneModel.revision,
        plannerState: planner.state,
        plannedAction: null,
        submittedDelivery: null,
        plannedRuleId: null,
        arbiterEvent: null,
        arbiterReason: null,
      ),
    );
  }

  void endSession({required DateTime now}) {
    final generation = _activeSessionGeneration;
    sceneModel.reset();
    planner.reset();
    arbiter.reset();
    _activeSessionGeneration = -1;
    _lastFrameId = 0;
    _lastTickAt = null;
    _lastTickAdmissionAt = null;
    _lastTickActionSignature = null;
    _providerLost = true;
    _record(
      SpatialRuntimeTrace(
        at: now,
        status: SpatialRuntimeIngestStatus.providerStateAccepted,
        reason: 'session_stopped',
        sessionGeneration: generation,
        frameId: 0,
        providerId: _lastProviderId,
        modelId: 'none',
        preprocessId: 'none',
        sceneRevision: sceneModel.revision,
        plannerState: planner.state,
        plannedAction: null,
        submittedDelivery: null,
        plannedRuleId: null,
        arbiterEvent: null,
        arbiterReason: null,
      ),
    );
  }

  LocalSceneSnapshot snapshotAt(DateTime now) => sceneModel.snapshotAt(now);

  SpatialRuntimeResult ingestGenericGeometry({
    required ObservationHeader header,
    required GenericObstacleDetectResult detection,
    required List<GenericObstacleTrack> tracks,
    required DateTime now,
    required bool orientationValid,
    required bool userMoving,
    required double poseQuality,
  }) {
    if (header.sessionGeneration != _activeSessionGeneration) {
      return _reject(
        status: SpatialRuntimeIngestStatus.rejectedSession,
        reason: 'observation_session_mismatch',
        now: now,
        header: header,
      );
    }
    if (header.frameId <= _lastFrameId) {
      return _reject(
        status: SpatialRuntimeIngestStatus.rejectedOutOfOrder,
        reason: 'frame_not_newer_than_runtime_scene',
        now: now,
        header: header,
      );
    }

    final producedAt = DateTime.fromMicrosecondsSinceEpoch(header.producedAtUs);
    final futureSkew = producedAt.difference(now);
    if (futureSkew > const Duration(milliseconds: 100) ||
        now.difference(producedAt) > observationTtl) {
      return _reject(
        status: SpatialRuntimeIngestStatus.rejectedStale,
        reason: futureSkew > const Duration(milliseconds: 100)
            ? 'observation_timestamp_in_future'
            : 'observation_expired_before_runtime',
        now: now,
        header: header,
      );
    }

    _lastFrameId = header.frameId;
    _lastProviderId = header.providerId;
    final recovered = _providerLost;
    _providerLost = false;
    final validUntil = producedAt.add(observationTtl);
    final sceneUpdate = sceneModel.ingestGenericGeometry(
      header: header,
      detection: detection,
      tracks: tracks,
      at: producedAt,
      validUntil: validUntil,
      poseQuality: poseQuality.clamp(0.0, 1.0),
    );
    if (!sceneUpdate.accepted) {
      return _reject(
        status: SpatialRuntimeIngestStatus.rejectedScene,
        reason: sceneUpdate.reason,
        now: now,
        header: header,
        snapshot: sceneUpdate.snapshot,
      );
    }

    _publishGeometryHealth(
      state: _sensorStateFor(detection.rejectReason),
      reason: 'geometry_${detection.rejectReason.name}',
      quality: detection.detectorQuality,
      now: now,
    );
    return _planAndAdmit(
      status: SpatialRuntimeIngestStatus.accepted,
      reason: recovered ? 'recovery' : 'observation',
      snapshot: sceneUpdate.snapshot,
      now: now,
      userMoving: userMoving,
      orientationValid: orientationValid,
      frameId: header.frameId,
      providerId: header.providerId,
      modelId: header.modelId,
      preprocessId: header.preprocessId,
    );
  }

  /// Converts a missing/failed provider result into an explicit unknown scene.
  /// It never substitutes an empty, apparently-free corridor.
  SpatialRuntimeResult noteMissingObservation({
    required String providerId,
    required SceneSensorState providerState,
    required String reason,
    required DateTime now,
    required bool orientationValid,
    required bool userMoving,
  }) {
    if (_activeSessionGeneration < 0) {
      throw StateError('Spatial runtime session has not started.');
    }
    _lastProviderId = providerId;
    _providerLost = true;
    final snapshot = sceneModel.invalidateToUnknown(
      providerId: providerId,
      providerState: providerState,
      now: now,
    );
    _publishGeometryHealth(
      state: providerState,
      reason: reason,
      quality: 0,
      now: now,
    );
    return _planAndAdmit(
      status: SpatialRuntimeIngestStatus.providerStateAccepted,
      reason: 'provider_loss:$reason',
      snapshot: snapshot,
      now: now,
      userMoving: userMoving,
      orientationValid: orientationValid,
      frameId: 0,
      providerId: providerId,
      modelId: 'unavailable',
      preprocessId: 'unavailable',
    );
  }

  /// Advances decision-time expiry even when capture or inference is silent.
  /// It never performs inference and is safe to call from a bounded timer.
  SpatialRuntimeResult tick({
    required DateTime now,
    required bool userMoving,
    required bool orientationValid,
  }) {
    if (_activeSessionGeneration < 0) {
      throw StateError('Spatial runtime session has not started.');
    }
    arbiter.purgeExpired(now);
    final previousTick = _lastTickAt;
    if (previousTick != null &&
        now.difference(previousTick) < minimumTickInterval) {
      return _tickWithoutAdmission(now: now, reason: 'tick_rate_limited');
    }
    _lastTickAt = now;

    var snapshot = sceneModel.snapshotAt(now);
    final expired = snapshot.isStaleAt(now);
    final newlyExpired = expired && !_providerLost;
    if (newlyExpired) {
      _providerLost = true;
      snapshot = sceneModel.invalidateToUnknown(
        providerId: _lastProviderId,
        providerState: SceneSensorState.stale,
        now: now,
      );
      _publishGeometryHealth(
        state: SceneSensorState.stale,
        reason: 'expiry_tick',
        quality: 0,
        now: now,
      );
    }

    return _planAndAdmit(
      status: SpatialRuntimeIngestStatus.providerStateAccepted,
      reason: newlyExpired
          ? 'expiry_tick'
          : expired
          ? 'provider_loss'
          : 'tick_no_state_change',
      snapshot: snapshot,
      now: now,
      userMoving: userMoving,
      orientationValid: orientationValid,
      frameId: _lastFrameId,
      providerId: _lastProviderId,
      modelId: 'decision-clock',
      preprocessId: 'none',
      throttleDuplicateAdmission: true,
    );
  }

  SpatialRuntimeResult _planAndAdmit({
    required SpatialRuntimeIngestStatus status,
    required String reason,
    required LocalSceneSnapshot snapshot,
    required DateTime now,
    required bool userMoving,
    required bool orientationValid,
    required int frameId,
    required String providerId,
    required String modelId,
    required String preprocessId,
    bool throttleDuplicateAdmission = false,
  }) {
    final grid = RelativePolarGrid.fromSnapshot(
      snapshot,
      orientationValid: orientationValid,
      userMoving: userMoving,
    );
    final decision = planner.evaluate(grid, now: now);
    final submittedAction = _asShadow(decision.action);
    final signature =
        '${submittedAction.kind.name}:${submittedAction.direction?.name ?? 'none'}';
    final duplicateWithinCooldown =
        throttleDuplicateAdmission &&
        _lastTickActionSignature == signature &&
        _lastTickAdmissionAt != null &&
        now.difference(_lastTickAdmissionAt!) < tickActionCooldown;
    final event = duplicateWithinCooldown
        ? null
        : arbiter.submitAction(submittedAction, now: now);
    if (throttleDuplicateAdmission && !duplicateWithinCooldown) {
      _lastTickActionSignature = signature;
      _lastTickAdmissionAt = now;
    }
    final trace = SpatialRuntimeTrace(
      at: now,
      status: status,
      reason: reason,
      sessionGeneration: _activeSessionGeneration,
      frameId: frameId,
      providerId: providerId,
      modelId: modelId,
      preprocessId: preprocessId,
      sceneRevision: snapshot.revision,
      plannerState: decision.state,
      plannedAction: decision.action.kind,
      submittedDelivery: submittedAction.delivery,
      plannedRuleId: decision.action.ruleId,
      arbiterEvent: event?.type,
      arbiterReason: duplicateWithinCooldown
          ? 'tick_duplicate_action_cooldown'
          : event?.reason,
    );
    _record(trace);
    return SpatialRuntimeResult(
      status: status,
      reason: reason,
      snapshot: snapshot,
      decision: decision,
      submittedAction: duplicateWithinCooldown ? null : submittedAction,
      arbiterEvent: event,
      trace: trace,
    );
  }

  SpatialRuntimeResult _tickWithoutAdmission({
    required DateTime now,
    required String reason,
  }) {
    final snapshot = sceneModel.snapshotAt(now);
    final trace = SpatialRuntimeTrace(
      at: now,
      status: SpatialRuntimeIngestStatus.providerStateAccepted,
      reason: reason,
      sessionGeneration: _activeSessionGeneration,
      frameId: _lastFrameId,
      providerId: _lastProviderId,
      modelId: 'decision-clock',
      preprocessId: 'none',
      sceneRevision: snapshot.revision,
      plannerState: planner.state,
      plannedAction: null,
      submittedDelivery: null,
      plannedRuleId: null,
      arbiterEvent: null,
      arbiterReason: reason,
    );
    _record(trace);
    return SpatialRuntimeResult(
      status: SpatialRuntimeIngestStatus.providerStateAccepted,
      reason: reason,
      snapshot: snapshot,
      decision: null,
      submittedAction: null,
      arbiterEvent: null,
      trace: trace,
    );
  }

  SpatialRuntimeResult _reject({
    required SpatialRuntimeIngestStatus status,
    required String reason,
    required DateTime now,
    required ObservationHeader header,
    LocalSceneSnapshot? snapshot,
  }) {
    final current = snapshot ?? sceneModel.snapshotAt(now);
    final trace = SpatialRuntimeTrace(
      at: now,
      status: status,
      reason: reason,
      sessionGeneration: header.sessionGeneration,
      frameId: header.frameId,
      providerId: header.providerId,
      modelId: header.modelId,
      preprocessId: header.preprocessId,
      sceneRevision: current.revision,
      plannerState: planner.state,
      plannedAction: null,
      submittedDelivery: null,
      plannedRuleId: null,
      arbiterEvent: null,
      arbiterReason: null,
    );
    _record(trace);
    return SpatialRuntimeResult(
      status: status,
      reason: reason,
      snapshot: current,
      decision: null,
      submittedAction: null,
      arbiterEvent: null,
      trace: trace,
    );
  }

  void _publishGeometryHealth({
    required SceneSensorState state,
    required String reason,
    required double quality,
    required DateTime now,
  }) {
    final componentState = switch (state) {
      SceneSensorState.healthy => ComponentState.available,
      SceneSensorState.degraded ||
      SceneSensorState.stale => ComponentState.degraded,
      SceneSensorState.unavailable => ComponentState.unavailable,
    };
    healthCoordinator.note(
      component: CoreComponent.genericGeometry,
      state: componentState,
      reasonCode: reason,
      now: now,
      quality: quality.clamp(0.0, 1.0),
      announce: false,
    );
  }

  SafetyAction _asShadow(SafetyAction action) => SafetyAction(
    actionId: action.actionId,
    kind: action.kind,
    cause: action.cause,
    priority: action.priority,
    delivery: SafetyActionDelivery.shadow,
    sceneRevision: action.sceneRevision,
    hazardIds: action.hazardIds,
    evidenceSummary: action.evidenceSummary,
    direction: action.direction,
    confidence: action.confidence,
    createdAt: action.createdAt,
    validUntil: action.validUntil,
    ruleId: action.ruleId,
  );

  void _record(SpatialRuntimeTrace trace) {
    if (_traces.length >= maxTraceEntries) {
      _traces.removeAt(0);
    }
    _traces.add(trace);
  }
}

SceneSensorState _sensorStateFor(ObstacleRejectReason reason) =>
    switch (reason) {
      ObstacleRejectReason.none ||
      ObstacleRejectReason.emptyCorridor => SceneSensorState.healthy,
      ObstacleRejectReason.stale ||
      ObstacleRejectReason.unaligned => SceneSensorState.stale,
      ObstacleRejectReason.detectorOff ||
      ObstacleRejectReason.noFrame => SceneSensorState.unavailable,
      _ => SceneSensorState.degraded,
    };
