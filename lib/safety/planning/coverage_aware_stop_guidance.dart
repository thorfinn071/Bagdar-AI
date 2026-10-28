import '../runtime/confidence_authority_spatial_runtime.dart';
import '../world/relative_polar_grid.dart';
import 'corridor_candidate.dart';
import 'guidance_state_machine.dart';
import 'safety_action.dart';

/// Explains the current clearance failure during uncertain-stop recovery.
/// The inherited policy still owns every action, risk threshold and latch.
/// This version changes only cause/rule when waiting for stillness would hide
/// an independently unresolved corridor. It grants no new movement authority.
class CoverageAwareStopGuidance extends ConfidenceAuthorityGuidance {
  @override
  GuidanceDecision evaluate(RelativePolarGrid grid, {required DateTime now}) {
    final decision = super.evaluate(grid, now: now);
    final old = decision.action;
    if (old.kind != SafetyActionKind.stopNow ||
        old.ruleId != 'SPATIAL-P0-AWAIT-STATIONARY') {
      return decision;
    }
    final forward = decision.candidates.singleWhere(
      (candidate) => candidate.direction == CorridorDirection.forward,
    );
    if (forward.hasPositiveEvidence) return decision;
    final unavailable = forward.rejectionReasons.any(
      const {
        CorridorRejectionReason.staleScene,
        CorridorRejectionReason.invalidOrientation,
        CorridorRejectionReason.unhealthySensing,
        CorridorRejectionReason.insufficientObservedWidth,
        CorridorRejectionReason.unknownArea,
      }.contains,
    );
    return GuidanceDecision(
      action: SafetyAction(
        actionId: old.actionId,
        kind: old.kind,
        cause: unavailable
            ? 'spatial_evidence_unavailable_while_moving'
            : 'forward_corridor_not_positively_confirmed_while_moving',
        priority: old.priority,
        delivery: old.delivery,
        sceneRevision: old.sceneRevision,
        hazardIds: old.hazardIds,
        evidenceSummary: old.evidenceSummary,
        direction: old.direction,
        confidence: old.confidence,
        createdAt: old.createdAt,
        validUntil: old.validUntil,
        ruleId: unavailable
            ? 'SPATIAL-P0-DEGRADED-MOVING'
            : 'SPATIAL-P0-FORWARD-UNCONFIRMED',
      ),
      shadowAction: decision.shadowAction,
      proposedCorrection: decision.proposedCorrection,
      previousState: decision.previousState,
      state: decision.state,
      candidates: decision.candidates,
    );
  }
}
