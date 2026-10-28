/// Machine-readable reason why the current depth frame was not admitted as a
/// trustworthy ground plane.
enum PlaneFitRejectionReason {
  none,
  notAnalyzed,
  insufficientValidPoints,
  noCandidatePlane,
  degenerate,
  lowInlierFraction,
  residualTooHigh,
  insufficientSpatialCoverage,
  temporalInconsistency,
}

/// Immutable quality evidence for one ground-plane fit.
///
/// All fractions and scores are normalized to 0..1. Residuals are relative to
/// the predicted positive depth value and may exceed 1 for a rejected frame.
class PlaneFitQuality {
  final double validPointFraction;
  final double inlierFraction;
  final double medianNormalizedResidual;
  final double p90NormalizedResidual;
  final double inlierRowCoverage;
  final double inlierColumnCoverage;
  final bool degenerate;
  final double? temporalConsistencyScore;
  final bool accepted;
  final PlaneFitRejectionReason rejectionReason;

  const PlaneFitQuality({
    required this.validPointFraction,
    required this.inlierFraction,
    required this.medianNormalizedResidual,
    required this.p90NormalizedResidual,
    required this.inlierRowCoverage,
    required this.inlierColumnCoverage,
    required this.degenerate,
    required this.temporalConsistencyScore,
    required this.accepted,
    required this.rejectionReason,
  }) : assert(validPointFraction >= 0 && validPointFraction <= 1),
       assert(inlierFraction >= 0 && inlierFraction <= 1),
       assert(inlierRowCoverage >= 0 && inlierRowCoverage <= 1),
       assert(inlierColumnCoverage >= 0 && inlierColumnCoverage <= 1),
       assert(
         temporalConsistencyScore == null ||
             (temporalConsistencyScore >= 0 && temporalConsistencyScore <= 1),
       ),
       assert(accepted == (rejectionReason == PlaneFitRejectionReason.none));

  static const notAnalyzed = PlaneFitQuality(
    validPointFraction: 0,
    inlierFraction: 0,
    medianNormalizedResidual: double.infinity,
    p90NormalizedResidual: double.infinity,
    inlierRowCoverage: 0,
    inlierColumnCoverage: 0,
    degenerate: false,
    temporalConsistencyScore: null,
    accepted: false,
    rejectionReason: PlaneFitRejectionReason.notAnalyzed,
  );

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'validPointFraction': validPointFraction,
    'inlierFraction': inlierFraction,
    'medianNormalizedResidual': medianNormalizedResidual,
    'p90NormalizedResidual': p90NormalizedResidual,
    'inlierRowCoverage': inlierRowCoverage,
    'inlierColumnCoverage': inlierColumnCoverage,
    'degenerate': degenerate,
    'temporalConsistencyScore': temporalConsistencyScore,
    'accepted': accepted,
    'rejectionReason': rejectionReason.name,
  };
}
