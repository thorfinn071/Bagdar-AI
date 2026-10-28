enum CorridorDirection { left, forward, right }

enum CorridorRejectionReason {
  confirmedObstacle,
  dropBoundary,
  movingThreatIntersection,
  insufficientObservedWidth,
  unknownArea,
  surfaceNotContinuous,
  staleScene,
  invalidOrientation,
  unhealthySensing,
}

enum CorridorSoftCostKind {
  lowClearance,
  partialObservability,
  lowSurfaceConfidence,
  unknownArea,
  headingChange,
  temporalInstability,
  collisionProximity,
  dropProximity,
  movingThreatProximity,
}

/// Evaluation of one of the three bounded Core 1.0 movement candidates.
///
/// [minimumClearance] is normalized relative clearance in relative mode. It
/// must never be rendered or logged as metres.
class CorridorCandidate {
  final String id;
  final int sceneRevision;
  final CorridorDirection direction;
  final double observedFraction;
  final double minimumClearance;
  final double surfaceContinuity;
  final double dropRisk;
  final double collisionRisk;
  final double movingThreatRisk;
  final double unknownRisk;
  final double requiredHeadingChange;
  final bool positiveEvidencePassed;
  final Map<CorridorSoftCostKind, double> softCosts;
  final DateTime validUntil;
  final List<CorridorRejectionReason> rejectionReasons;
  final List<String> hazardIds;

  CorridorCandidate({
    required this.id,
    required this.sceneRevision,
    required this.direction,
    required this.observedFraction,
    required this.minimumClearance,
    required this.surfaceContinuity,
    required this.dropRisk,
    required this.collisionRisk,
    required this.movingThreatRisk,
    required this.unknownRisk,
    required this.requiredHeadingChange,
    required this.positiveEvidencePassed,
    required Map<CorridorSoftCostKind, double> softCosts,
    required this.validUntil,
    required List<CorridorRejectionReason> rejectionReasons,
    required List<String> hazardIds,
  }) : assert(softCosts.values.every((value) => value.isFinite && value >= 0)),
       rejectionReasons = List.unmodifiable(rejectionReasons),
       softCosts = Map.unmodifiable(softCosts),
       hazardIds = List.unmodifiable(hazardIds);

  bool get isHardRejected => rejectionReasons.isNotEmpty;

  bool get hasPositiveEvidence => !isHardRejected && positiveEvidencePassed;

  double get softCost => softCosts.values.fold(0, (sum, value) => sum + value);

  /// Compatibility name used by the selection policy. This is a normalized
  /// relative cost, never a probability or a metric distance.
  double get riskScore => softCost;
}
