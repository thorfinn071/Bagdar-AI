import 'dart:ui';

import '../utils/depth_hazard.dart';
import '../safety/perception/camera_track_association.dart';
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
  final CameraComponentSupport? cameraSupport;

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
    this.cameraSupport,
  });

  GenericObstacleObservation copyWith({
    int? trackId,
    SemanticMatch? semantic,
    bool clearSemantic = false,
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
    semantic: clearSemantic ? null : semantic ?? this.semantic,
    pixelCount: pixelCount,
    edgeOnly: edgeOnly,
    cameraSupport: cameraSupport,
  );
}

/// Positive evidence about the walkable surface inside the forward corridor.
///
/// This is deliberately separate from obstacle observations. A reliable
/// ground surface can raise traversability confidence, but it does not prove
/// that unobserved headroom is clear and it never cancels obstacle risk.
class CorridorSurfaceEvidence {
  final double observedFraction;
  final double continuity;
  final double confidence;

  const CorridorSurfaceEvidence({
    required this.observedFraction,
    required this.continuity,
    required this.confidence,
  }) : assert(observedFraction >= 0 && observedFraction <= 1),
       assert(continuity >= 0 && continuity <= 1),
       assert(confidence >= 0 && confidence <= 1);

  static const unavailable = CorridorSurfaceEvidence(
    observedFraction: 0,
    continuity: 0,
    confidence: 0,
  );

  bool get isAvailable =>
      observedFraction > 0 && continuity > 0 && confidence > 0;
}

/// Valid depth support in the forward image region, split above the ground
/// sample band. Coverage bounds observability; it is not clearance evidence.
/// A visible floor must not compensate for missing upper depth (or vice versa).
class CorridorDepthCoverage {
  final double upperObservedFraction;
  final double lowerObservedFraction;

  const CorridorDepthCoverage({
    required this.upperObservedFraction,
    required this.lowerObservedFraction,
  }) : assert(upperObservedFraction >= 0 && upperObservedFraction <= 1),
       assert(lowerObservedFraction >= 0 && lowerObservedFraction <= 1);

  double get minimumObservedFraction =>
      upperObservedFraction < lowerObservedFraction
      ? upperObservedFraction
      : lowerObservedFraction;
}

enum ObstacleUnknownReason { unverifiedAperture, groundModelDisagreement }

/// Optional image-space measurements for evaluating an opening hypothesis.
///
/// These describe depth support and a local ground fit, not body clearance.
/// Neither a filled relative map nor image width establishes width/headroom in
/// metres. The scene adapter must not ingest these as traversability evidence.
class CorridorOpeningDiagnostics {
  final Rect normalizedBounds;
  final CorridorDepthCoverage depthCoverage;
  final CorridorSurfaceEvidence surface;
  final int groundDisagreementPixels;
  final double? upperNearFraction;
  final double? lowerNearFraction;

  const CorridorOpeningDiagnostics({
    required this.normalizedBounds,
    required this.depthCoverage,
    required this.surface,
    required this.groundDisagreementPixels,
    required this.upperNearFraction,
    required this.lowerNearFraction,
  });

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'authority': 'diagnostic_only',
    'bounds': <double>[
      normalizedBounds.left,
      normalizedBounds.top,
      normalizedBounds.right,
      normalizedBounds.bottom,
    ],
    'imageWidthFraction': normalizedBounds.width,
    'widthM': null,
    'headroomM': null,
    'upperObservedFraction': depthCoverage.upperObservedFraction,
    'lowerObservedFraction': depthCoverage.lowerObservedFraction,
    'upperNearFraction': upperNearFraction,
    'lowerNearFraction': lowerNearFraction,
    'surfaceObservedFraction': surface.observedFraction,
    'surfaceContinuity': surface.continuity,
    'surfaceConfidence': surface.confidence,
    'groundDisagreementPixels': groundDisagreementPixels,
  };
}

class GenericObstacleDetectResult {
  final List<GenericObstacleObservation> observations;
  final ObstacleRejectReason rejectReason;
  final double detectorQuality;
  final double groundConfidence;
  final CorridorSurfaceEvidence surfaceEvidence;
  final CorridorDepthCoverage? corridorCoverage;
  final double unknownProbabilityFloor;
  final List<ObstacleUnknownReason> unknownReasons;
  final int groundDisagreementPixels;
  final CorridorOpeningDiagnostics? openingDiagnostics;

  const GenericObstacleDetectResult({
    required this.observations,
    required this.rejectReason,
    required this.detectorQuality,
    required this.groundConfidence,
    this.surfaceEvidence = CorridorSurfaceEvidence.unavailable,
    this.corridorCoverage,
    this.unknownProbabilityFloor = 0,
    this.unknownReasons = const <ObstacleUnknownReason>[],
    this.groundDisagreementPixels = 0,
    this.openingDiagnostics,
  }) : assert(unknownProbabilityFloor >= 0 && unknownProbabilityFloor <= 1);

  static const empty = GenericObstacleDetectResult(
    observations: <GenericObstacleObservation>[],
    rejectReason: ObstacleRejectReason.emptyCorridor,
    detectorQuality: 0,
    groundConfidence: 0,
    surfaceEvidence: CorridorSurfaceEvidence.unavailable,
    unknownProbabilityFloor: 0,
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
