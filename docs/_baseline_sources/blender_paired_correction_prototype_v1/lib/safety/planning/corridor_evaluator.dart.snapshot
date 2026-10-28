import '../world/relative_polar_grid.dart';
import 'corridor_candidate.dart';

/// Safety thresholds and relative soft-cost weights for bounded corridors.
///
/// All values are dimensionless. Relative mode must not derive metres from
/// these thresholds.
class CorridorEvaluationPolicy {
  final double minimumObservedFraction;
  final double maximumUnknownRisk;
  final double maximumCollisionRisk;
  final double maximumDropRisk;
  final double maximumMovingThreatRisk;
  final double minimumSurfaceContinuity;
  final double positiveMinimumObservedFraction;
  final double positiveMinimumClearance;
  final double positiveMinimumSurfaceContinuity;
  final double positiveMaximumUnknownRisk;
  final double positiveMinimumConfidence;

  const CorridorEvaluationPolicy({
    this.minimumObservedFraction = 0.80,
    this.maximumUnknownRisk = 0.25,
    this.maximumCollisionRisk = 0.65,
    this.maximumDropRisk = 0.35,
    this.maximumMovingThreatRisk = 0.55,
    this.minimumSurfaceContinuity = 0.55,
    this.positiveMinimumObservedFraction = 0.85,
    this.positiveMinimumClearance = 0.65,
    this.positiveMinimumSurfaceContinuity = 0.70,
    this.positiveMaximumUnknownRisk = 0.15,
    this.positiveMinimumConfidence = 0.65,
  });
}

/// Pure evaluator: hard rejects are independent from soft costs and therefore
/// can never be compensated by a favourable score in another dimension.
class CorridorEvaluator {
  final CorridorEvaluationPolicy policy;

  const CorridorEvaluator({this.policy = const CorridorEvaluationPolicy()});

  CorridorCandidate evaluate({
    required RelativePolarGrid grid,
    required CorridorDirection direction,
    required DateTime now,
    CorridorDirection? incumbentDirection,
  }) {
    final sector = grid.sector(_sectorDirection(direction));
    final clearance = 1 - sector.occupancyProbability;
    final headingChange = switch (direction) {
      CorridorDirection.left => -15.0,
      CorridorDirection.forward => 0.0,
      CorridorDirection.right => 15.0,
    };
    final rejections = <CorridorRejectionReason>[];

    if (grid.isStaleAt(now)) {
      rejections.add(CorridorRejectionReason.staleScene);
    }
    if (!grid.orientationValid) {
      rejections.add(CorridorRejectionReason.invalidOrientation);
    }
    if (!grid.sensingHealthy) {
      rejections.add(CorridorRejectionReason.unhealthySensing);
    }
    if (sector.observedFraction < policy.minimumObservedFraction) {
      rejections.add(CorridorRejectionReason.insufficientObservedWidth);
    }
    if (sector.unknownProbability > policy.maximumUnknownRisk) {
      rejections.add(CorridorRejectionReason.unknownArea);
    }
    if (sector.occupancyProbability >= policy.maximumCollisionRisk) {
      rejections.add(CorridorRejectionReason.confirmedObstacle);
    }
    if (sector.dropProbability >= policy.maximumDropRisk) {
      rejections.add(CorridorRejectionReason.dropBoundary);
    }
    if (sector.movingThreatRisk >= policy.maximumMovingThreatRisk) {
      rejections.add(CorridorRejectionReason.movingThreatIntersection);
    }
    if (sector.traversabilityProbability < policy.minimumSurfaceContinuity) {
      rejections.add(CorridorRejectionReason.surfaceNotContinuous);
    }

    final positiveEvidencePassed =
        sector.sourceMask.isNotEmpty &&
        sector.observedFraction >= policy.positiveMinimumObservedFraction &&
        clearance >= policy.positiveMinimumClearance &&
        sector.traversabilityProbability >=
            policy.positiveMinimumSurfaceContinuity &&
        sector.unknownProbability <= policy.positiveMaximumUnknownRisk &&
        sector.confidence >= policy.positiveMinimumConfidence;

    return CorridorCandidate(
      id: 'relative-${grid.revision}-${direction.name}',
      sceneRevision: grid.revision,
      direction: direction,
      observedFraction: sector.observedFraction,
      minimumClearance: clearance,
      surfaceContinuity: sector.traversabilityProbability,
      dropRisk: sector.dropProbability,
      collisionRisk: sector.occupancyProbability,
      movingThreatRisk: sector.movingThreatRisk,
      unknownRisk: sector.unknownProbability,
      requiredHeadingChange: headingChange,
      positiveEvidencePassed: positiveEvidencePassed,
      softCosts: <CorridorSoftCostKind, double>{
        CorridorSoftCostKind.lowClearance: sector.occupancyProbability * 1.5,
        CorridorSoftCostKind.partialObservability:
            (1 - sector.observedFraction) * 1.2,
        CorridorSoftCostKind.lowSurfaceConfidence:
            (1 - sector.traversabilityProbability) * 1.0,
        CorridorSoftCostKind.unknownArea: sector.unknownProbability * 2.0,
        CorridorSoftCostKind.headingChange: headingChange.abs() / 15.0 * 0.20,
        CorridorSoftCostKind.temporalInstability:
            incumbentDirection != null && direction != incumbentDirection
            ? 0.35
            : 0.0,
        CorridorSoftCostKind.collisionProximity:
            sector.occupancyProbability * 2.0,
        CorridorSoftCostKind.dropProximity: sector.dropProbability * 3.0,
        CorridorSoftCostKind.movingThreatProximity:
            sector.movingThreatRisk * 3.0,
      },
      validUntil: grid.validUntil,
      rejectionReasons: rejections,
      hazardIds: sector.hazardIds,
    );
  }

  RelativeSectorDirection _sectorDirection(CorridorDirection direction) =>
      switch (direction) {
        CorridorDirection.left => RelativeSectorDirection.left,
        CorridorDirection.forward => RelativeSectorDirection.forward,
        CorridorDirection.right => RelativeSectorDirection.right,
      };
}
