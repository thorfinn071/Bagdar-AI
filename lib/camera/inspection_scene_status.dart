import '../models/generic_obstacle.dart';
import '../safety/perception/observation_header.dart';
import '../safety/runtime/spatial_safety_runtime.dart';
import '../safety/world/local_scene_snapshot.dart';

enum InspectionObservationState {
  notChecked,
  unavailable,
  stale,
  adjustPhone,
  noObstacleReported,
  possibleObstacle,
}

/// Configuration describes an expected input, not a validated physical source.
enum InspectionClearanceCapability { notAvailable, experimentalOnly }

/// Read-only presentation of the ordinary stationary-inspection mode.
///
/// No planner action is translated into an obstacle observation. Conversely,
/// absence of detector components is never a clearance or movement permission.
class InspectionSceneStatus {
  final InspectionObservationState observation;
  final InspectionClearanceCapability clearance;

  const InspectionSceneStatus.notChecked()
    : observation = InspectionObservationState.notChecked,
      clearance = InspectionClearanceCapability.notAvailable;

  const InspectionSceneStatus.unavailable()
    : observation = InspectionObservationState.unavailable,
      clearance = InspectionClearanceCapability.notAvailable;

  const InspectionSceneStatus._(this.observation, this.clearance);

  /// This presentation cannot authorise movement, including experimental CLEAR.
  bool get mayAuthorizeMovement => false;

  factory InspectionSceneStatus.fromCamera({
    required SpatialSafetyRuntime runtime,
    required ObservationHeader? header,
    required GenericObstacleDetectResult? detection,
    required DateTime now,
    required bool cameraReady,
    required bool orientationValid,
  }) {
    final capability = runtime.shadowPassage == null
        ? InspectionClearanceCapability.notAvailable
        : InspectionClearanceCapability.experimentalOnly;
    InspectionSceneStatus state(InspectionObservationState value) =>
        InspectionSceneStatus._(value, capability);

    if (!cameraReady) return state(InspectionObservationState.unavailable);
    if (runtime.activeSessionGeneration < 0) {
      return state(InspectionObservationState.unavailable);
    }
    if (header == null || detection == null) {
      return state(
        runtime.lastFrameId == 0
            ? InspectionObservationState.notChecked
            : InspectionObservationState.unavailable,
      );
    }
    if (header.sessionGeneration != runtime.activeSessionGeneration ||
        header.frameId != runtime.lastFrameId ||
        header.frameId <= 0) {
      return state(InspectionObservationState.unavailable);
    }
    final nowUs = now.microsecondsSinceEpoch;
    if (header.sourceTimestampUs < 0 ||
        header.producedAtUs < header.sourceTimestampUs ||
        header.producedAtUs > nowUs ||
        nowUs < header.sourceTimestampUs) {
      return state(InspectionObservationState.unavailable);
    }
    // This uses the existing relative-observation lifetime. It neither renews
    // capture time nor changes the separate 100 ms metric-clearance age gate.
    if (nowUs - header.sourceTimestampUs >
        runtime.observationTtl.inMicroseconds) {
      return state(InspectionObservationState.stale);
    }
    if (!orientationValid) return state(InspectionObservationState.adjustPhone);
    final scene = runtime.snapshotAt(now);
    if (header.health != ObservationHealth.healthy ||
        !header.confidence.isFinite ||
        header.confidence <= 0 ||
        scene.isStaleAt(now) ||
        scene.sensorHealth.providers[header.providerId] !=
            SceneSensorState.healthy ||
        !detection.detectorQuality.isFinite ||
        detection.detectorQuality <= 0 ||
        (detection.rejectReason != ObstacleRejectReason.none &&
            detection.rejectReason != ObstacleRejectReason.emptyCorridor)) {
      return state(InspectionObservationState.unavailable);
    }
    return state(
      detection.observations.isEmpty
          ? InspectionObservationState.noObstacleReported
          : InspectionObservationState.possibleObstacle,
    );
  }

  Map<String, Object?> toDiagnosticMap() => {
    'observation': observation.name,
    'clearanceCapability': clearance.name,
    'mayAuthorizeMovement': mayAuthorizeMovement,
  };

  @override
  bool operator ==(Object other) =>
      other is InspectionSceneStatus &&
      observation == other.observation &&
      clearance == other.clearance;

  @override
  int get hashCode => Object.hash(observation, clearance);
}
