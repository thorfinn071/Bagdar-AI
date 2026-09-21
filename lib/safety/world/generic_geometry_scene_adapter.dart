import '../../models/generic_obstacle.dart';
import '../../tracker/generic_obstacle_tracker.dart';
import '../../utils/depth_hazard.dart';
import '../perception/observation_header.dart';
import 'local_scene_model.dart';
import 'local_scene_snapshot.dart';
import 'scene_fusion_policy.dart';

/// Flutter-facing adapter kept separate so the core world model and replay CLI
/// remain pure Dart and do not inherit `dart:ui` through obstacle bounds.
extension GenericGeometrySceneAdapter on LocalSceneModel {
  /// Projects existing generic geometry tracks into coarse relative sectors.
  /// Calibrated metric cells require a separate metric evidence producer.
  LocalSceneUpdateResult ingestGenericGeometry({
    required ObservationHeader header,
    required GenericObstacleDetectResult detection,
    required List<GenericObstacleTrack> tracks,
    required DateTime at,
    required DateTime validUntil,
    required double poseQuality,
  }) {
    if (coordinateMode != SceneCoordinateMode.relative) {
      return LocalSceneUpdateResult(
        status: LocalSceneUpdateStatus.rejectedMetricCalibration,
        reason: 'generic_geometry_requires_relative_projection',
        snapshot: snapshotAt(at),
      );
    }

    final sensorState = _sensorStateFor(detection.rejectReason);
    final usable = sensorState == SceneSensorState.healthy;
    final observedFraction = usable
        ? detection.detectorQuality.clamp(0.0, 1.0)
        : 0.0;
    final evidence = <SpatialEvidence>[];
    for (final elementId in const <String>['left', 'forward', 'right']) {
      evidence.add(
        SpatialEvidence(
          elementId: elementId,
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'geometry:${header.providerId}',
          source: SpatialEvidenceSource.geometry,
          observedAt: at,
          validUntil: validUntil,
          observedFraction: observedFraction,
          confidence: usable ? detection.detectorQuality : 0,
          unknownProbability: 1 - observedFraction,
        ),
      );
    }

    final hazards = <HazardTrackSnapshot>[];
    final movingThreats = <MovingThreatSnapshot>[];
    for (final track in tracks) {
      final observation = track.last;
      final imminent = _isImminentUnconfirmed(observation);
      if (!track.confirmed && !imminent) continue;
      final elementId = _elementForZone(observation.zone);
      final occupancy = _max(
        observation.relativeProximity,
        observation.confidence,
      ).clamp(0.0, 1.0);
      final movingRisk = _movingRisk(track, observation);
      final hazardId = 'geometry:${track.id}';
      evidence.add(
        SpatialEvidence(
          elementId: elementId,
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'geometry:${header.providerId}',
          source: SpatialEvidenceSource.geometry,
          observedAt: at,
          validUntil: validUntil,
          observedFraction: _max(observedFraction, observation.corridorOverlap),
          confidence: observation.confidence,
          occupancyProbability: occupancy,
          movingThreatRisk: movingRisk,
          unknownProbability: 1 - observation.confidence,
          hazardIds: <String>[hazardId],
          motionVector: SceneMotionVector(
            lateral: _lateralForZone(observation.zone),
            forward: track.approachTrend(),
            metric: false,
          ),
        ),
      );
      final semantic = observation.semantic;
      if (semantic != null) {
        evidence.add(
          SpatialEvidence(
            elementId: elementId,
            coordinateMode: SceneCoordinateMode.relative,
            sourceId: 'semantic:${semantic.yoloTrackId}',
            source: SpatialEvidenceSource.semantic,
            observedAt: at,
            validUntil: validUntil,
            observedFraction: observation.corridorOverlap,
            confidence: semantic.confidence,
            occupancyProbability: occupancy,
            hazardIds: <String>[hazardId],
          ),
        );
      }
      hazards.add(
        HazardTrackSnapshot(
          id: hazardId,
          elementId: elementId,
          risk: _max(occupancy, movingRisk),
          sourceMask: <String>{'geometry:${header.providerId}'},
          lastObservedAt: at,
        ),
      );
      if (movingRisk >= 0.20) {
        movingThreats.add(
          MovingThreatSnapshot(
            id: 'moving:${track.id}',
            elementId: elementId,
            intersectionRisk: movingRisk,
            lastObservedAt: at,
          ),
        );
      }
    }

    return update(
      LocalSceneUpdate(
        coordinateMode: SceneCoordinateMode.relative,
        at: at,
        validUntil: validUntil,
        poseQuality: poseQuality,
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          header.providerId: sensorState,
        }),
        evidence: evidence,
        hazardTracks: hazards,
        movingThreats: movingThreats,
      ),
    );
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

bool _isImminentUnconfirmed(GenericObstacleObservation observation) =>
    _elementForZone(observation.zone) == 'forward' &&
    observation.relativeProximity >= 0.85 &&
    observation.confidence >= 0.80 &&
    observation.corridorOverlap >= 0.50;

double _movingRisk(
  GenericObstacleTrack track,
  GenericObstacleObservation observation,
) {
  final relativeTrend = (track.approachTrend() * 3).clamp(0.0, 1.0);
  final explicitApproach = observation.approachRateMps == null
      ? 0.0
      : (observation.approachRateMps! / 2).clamp(0.0, 1.0);
  return (_max(relativeTrend, explicitApproach) * observation.corridorOverlap)
      .clamp(0.0, 1.0);
}

String _elementForZone(HazardZone zone) => switch (zone) {
  HazardZone.left || HazardZone.centerLeft => 'left',
  HazardZone.center => 'forward',
  HazardZone.centerRight || HazardZone.right => 'right',
};

double _lateralForZone(HazardZone zone) => switch (zone) {
  HazardZone.left => -1,
  HazardZone.centerLeft => -0.5,
  HazardZone.center => 0,
  HazardZone.centerRight => 0.5,
  HazardZone.right => 1,
};

double _max(double a, double b) => a > b ? a : b;
