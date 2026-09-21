import 'dart:ui';

import '../utils/depth_hazard.dart';
import 'depth_frame.dart';

enum ObstacleGeometry {
  broadSurface,
  thinVertical,
  lowObstacle,
  overhead,
  unknown,
}

enum ObstacleRiskLevel { monitor, warning, critical }

enum ObstacleRejectReason {
  none,
  detectorOff,
  noFrame,
  unaligned,
  stale,
  lowCoverage,
  lowConfidence,
  degenerate,
  planeUnreliable,
  emptyCorridor,
}

class SemanticMatch {
  final int yoloTrackId;
  final String label;
  final double confidence;

  const SemanticMatch({
    required this.yoloTrackId,
    required this.label,
    required this.confidence,
  });
}

class GenericObstacleObservation {
  final int? trackId;
  final ObstacleGeometry geometry;
  final HazardZone zone;
  final Rect normalizedBounds;
  final double corridorOverlap;
  final double confidence;
  final double relativeProximity;
  final double? nearestDistanceM;
  final double? approachRateMps;
  final double? timeToCollisionS;
  final DepthProviderKind source;
  final SemanticMatch? semantic;
  final int pixelCount;
  final bool edgeOnly;

  const GenericObstacleObservation({
    required this.geometry,
    required this.zone,
    required this.normalizedBounds,
    required this.corridorOverlap,
    required this.confidence,
    required this.relativeProximity,
    required this.source,
    this.trackId,
    this.nearestDistanceM,
    this.approachRateMps,
    this.timeToCollisionS,
    this.semantic,
    this.pixelCount = 0,
    this.edgeOnly = false,
  });

  GenericObstacleObservation copyWith({
    int? trackId,
    SemanticMatch? semantic,
    double? approachRateMps,
    double? timeToCollisionS,
    double? relativeProximity,
    double? nearestDistanceM,
    double? confidence,
  }) => GenericObstacleObservation(
    trackId: trackId ?? this.trackId,
    geometry: geometry,
    zone: zone,
    normalizedBounds: normalizedBounds,
    corridorOverlap: corridorOverlap,
    confidence: confidence ?? this.confidence,
    relativeProximity: relativeProximity ?? this.relativeProximity,
    nearestDistanceM: nearestDistanceM ?? this.nearestDistanceM,
    approachRateMps: approachRateMps ?? this.approachRateMps,
    timeToCollisionS: timeToCollisionS ?? this.timeToCollisionS,
    source: source,
    semantic: semantic ?? this.semantic,
    pixelCount: pixelCount,
    edgeOnly: edgeOnly,
  );
}

class GenericObstacleDetectResult {
  final List<GenericObstacleObservation> observations;
  final ObstacleRejectReason rejectReason;
  final double detectorQuality;
  final double groundConfidence;

  const GenericObstacleDetectResult({
    required this.observations,
    required this.rejectReason,
    required this.detectorQuality,
    required this.groundConfidence,
  });

  static const empty = GenericObstacleDetectResult(
    observations: <GenericObstacleObservation>[],
    rejectReason: ObstacleRejectReason.emptyCorridor,
    detectorQuality: 0,
    groundConfidence: 0,
  );
}

class CollisionRiskDecision {
  final ObstacleRiskLevel? level;
  final String ruleId;
  final Map<String, Object?> inputs;
  final String speechKey;
  final bool speakDistance;
  final SemanticMatch? spokenSemantic;
  final GenericObstacleObservation observation;
  final bool emitUserAlert;

  const CollisionRiskDecision({
    required this.ruleId,
    required this.inputs,
    required this.speechKey,
    required this.observation,
    required this.emitUserAlert,
    this.level,
    this.speakDistance = false,
    this.spokenSemantic,
  });

  bool get hasAlert => level != null && level != ObstacleRiskLevel.monitor;
}
