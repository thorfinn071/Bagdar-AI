import '../world/relative_polar_grid.dart';
import 'corridor_candidate.dart';
import 'corridor_generator.dart';
import 'safety_action.dart';

enum GuidanceState {
  stopped,
  observing,
  movingStable,
  correctionPending,
  holdingForScan,
  emergencyStop,
  degraded,
  recovering,
}

class GuidanceDecision {
  final SafetyAction action;
  final SafetyAction? shadowAction;
  final CorridorDirection? proposedCorrection;
  final GuidanceState previousState;
  final GuidanceState state;
  final List<CorridorCandidate> candidates;

  GuidanceDecision({
    required this.action,
    required this.shadowAction,
    required this.proposedCorrection,
    required this.previousState,
    required this.state,
    required List<CorridorCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  /// A correction is exposed only after hysteresis confirms it. The primary
  /// [action] remains stop/hold/continue while spatial guidance is in shadow.
  CorridorDirection? get shadowCorrection => shadowAction?.direction;
}

/// Conservative relative-mode guidance with persistent state and hysteresis.
///
/// `adjustLeft` and `adjustRight` are produced only as [GuidanceDecision]
/// shadow actions. Runtime feedback must submit only [GuidanceDecision.action]
/// until the supervised assistive promotion gate is passed.
class GuidanceStateMachine {
  final CorridorGenerator corridorGenerator;
  final Duration actionTtl;
  final int correctionConfirmationRevisions;
  final int releaseConfirmationRevisions;
  final Duration correctionSwitchCooldown;
  final double correctionSwitchMargin;

  GuidanceState _state = GuidanceState.observing;
  int _actionSequence = 0;
  int? _lastAdvancedRevision;
  CorridorDirection? _pendingCorrection;
  int _pendingCorrectionRevisions = 0;
  CorridorDirection? _confirmedCorrection;
  DateTime? _lastCorrectionSwitchAt;
  int _safeReleaseRevisions = 0;

  GuidanceStateMachine({
    this.corridorGenerator = const CorridorGenerator(),
    this.actionTtl = const Duration(milliseconds: 900),
    this.correctionConfirmationRevisions = 3,
    this.releaseConfirmationRevisions = 2,
    this.correctionSwitchCooldown = const Duration(milliseconds: 1200),
    this.correctionSwitchMargin = 0.35,
  }) : assert(correctionConfirmationRevisions > 0),
       assert(releaseConfirmationRevisions > 0),
       assert(!correctionSwitchCooldown.isNegative),
       assert(correctionSwitchMargin >= 0);

  GuidanceState get state => _state;

  /// Clears every temporal/hysteresis latch at a physical camera-session
  /// boundary. A new camera owner must never inherit a correction or stop
  /// release counter from the previous stream.
  void reset() {
    _state = GuidanceState.observing;
    _actionSequence = 0;
    _lastAdvancedRevision = null;
    _pendingCorrection = null;
    _pendingCorrectionRevisions = 0;
    _confirmedCorrection = null;
    _lastCorrectionSwitchAt = null;
    _safeReleaseRevisions = 0;
  }

  GuidanceDecision evaluate(RelativePolarGrid grid, {required DateTime now}) {
    final previousState = _state;
    final advancesRevision = _advancesRevision(grid.revision);
    final candidates = corridorGenerator.generate(
      grid,
      now: now,
      incumbentDirection: _confirmedCorrection,
    );
    final forward = _candidate(candidates, CorridorDirection.forward);
    final forwardSector = grid.sector(RelativeSectorDirection.forward);
    final proposedCorrection = _bestProposedCorrection(
      forward: forward,
      candidates: candidates,
    );
    _updateConfirmedCorrection(
      proposedCorrection: proposedCorrection,
      candidates: candidates,
      advancesRevision: advancesRevision,
      now: now,
    );

    final imminentRisk =
        forwardSector.occupancyProbability >= 0.75 ||
        forwardSector.dropProbability >= 0.35 ||
        forwardSector.movingThreatRisk >= 0.55;
    final insufficientScene =
        grid.isStaleAt(now) ||
        !grid.orientationValid ||
        !grid.sensingHealthy ||
        forward.rejectionReasons.contains(
          CorridorRejectionReason.insufficientObservedWidth,
        ) ||
        forward.rejectionReasons.contains(CorridorRejectionReason.unknownArea);
    final forwardAccepted = forward.hasPositiveEvidence;
    final shadowAction = _buildShadowAction(
      grid: grid,
      candidates: candidates,
      forward: forward,
      now: now,
    );

    late final SafetyAction action;
    if (imminentRisk) {
      _safeReleaseRevisions = 0;
      _state = GuidanceState.emergencyStop;
      action = _primaryAction(
        grid: grid,
        now: now,
        kind: SafetyActionKind.stopNow,
        cause: 'imminent_forward_hazard',
        priority: SafetyPriority.p0Emergency,
        ruleId: 'SPATIAL-P0-IMMINENT',
        confidence: _maximumRisk(forwardSector),
      );
    } else if (grid.userMoving && insufficientScene) {
      _safeReleaseRevisions = 0;
      _state = GuidanceState.emergencyStop;
      action = _primaryAction(
        grid: grid,
        now: now,
        kind: SafetyActionKind.stopNow,
        cause: 'spatial_evidence_unavailable_while_moving',
        priority: SafetyPriority.p0Emergency,
        ruleId: 'SPATIAL-P0-DEGRADED-MOVING',
        confidence: 1,
      );
    } else if (previousState == GuidanceState.emergencyStop) {
      if (grid.userMoving) {
        _safeReleaseRevisions = 0;
        _state = GuidanceState.emergencyStop;
        action = _primaryAction(
          grid: grid,
          now: now,
          kind: SafetyActionKind.stopNow,
          cause: 'stop_release_requires_stationary_confirmation',
          priority: SafetyPriority.p0Emergency,
          ruleId: 'SPATIAL-P0-AWAIT-STATIONARY',
          confidence: 1,
        );
      } else {
        _safeReleaseRevisions = forwardAccepted && advancesRevision ? 1 : 0;
        _state = shadowAction == null
            ? GuidanceState.holdingForScan
            : GuidanceState.correctionPending;
        action = _holdAction(
          grid: grid,
          now: now,
          cause: 'post_stop_scene_reconfirmation',
          ruleId: 'SPATIAL-P2-POST-STOP-SCAN',
          confidence: forwardSector.confidence,
        );
      }
    } else if (grid.userMoving &&
        (forward.isHardRejected || !forwardAccepted)) {
      _safeReleaseRevisions = 0;
      _state = GuidanceState.emergencyStop;
      action = _primaryAction(
        grid: grid,
        now: now,
        kind: SafetyActionKind.stopNow,
        cause: 'forward_corridor_not_positively_confirmed_while_moving',
        priority: SafetyPriority.p0Emergency,
        ruleId: 'SPATIAL-P0-FORWARD-UNCONFIRMED',
        confidence: forwardSector.confidence,
      );
    } else if (insufficientScene) {
      _safeReleaseRevisions = 0;
      _state = GuidanceState.degraded;
      action = _holdAction(
        grid: grid,
        now: now,
        cause: 'spatial_evidence_insufficient',
        ruleId: 'SPATIAL-P2-HOLD-UNKNOWN',
        confidence: forwardSector.confidence,
      );
    } else if (forward.isHardRejected || !forwardAccepted) {
      _safeReleaseRevisions = 0;
      _state = shadowAction == null
          ? GuidanceState.holdingForScan
          : GuidanceState.correctionPending;
      action = _holdAction(
        grid: grid,
        now: now,
        cause: 'forward_corridor_rejected',
        ruleId: 'SPATIAL-P2-HOLD-BLOCKED',
        confidence: forwardSector.confidence,
      );
    } else if (_requiresRecovery(previousState)) {
      if (advancesRevision) _safeReleaseRevisions++;
      if (_safeReleaseRevisions < releaseConfirmationRevisions) {
        _state = GuidanceState.recovering;
        action = _holdAction(
          grid: grid,
          now: now,
          cause: 'healthy_scene_recovery_pending',
          ruleId: 'SPATIAL-P2-RECOVERY-PENDING',
          confidence: forwardSector.confidence,
        );
      } else {
        _state = grid.userMoving
            ? GuidanceState.movingStable
            : GuidanceState.observing;
        action = _continueAction(grid: grid, now: now);
      }
    } else {
      _safeReleaseRevisions = 0;
      _state = grid.userMoving
          ? GuidanceState.movingStable
          : GuidanceState.observing;
      action = _continueAction(grid: grid, now: now);
    }

    return GuidanceDecision(
      action: action,
      shadowAction: shadowAction,
      proposedCorrection: proposedCorrection,
      previousState: previousState,
      state: _state,
      candidates: candidates,
    );
  }

  bool _advancesRevision(int revision) {
    final previous = _lastAdvancedRevision;
    if (previous != null && revision <= previous) return false;
    _lastAdvancedRevision = revision;
    return true;
  }

  CorridorDirection? _bestProposedCorrection({
    required CorridorCandidate forward,
    required List<CorridorCandidate> candidates,
  }) {
    if (!_hasDirectionalBlocker(forward)) return null;
    final alternatives =
        candidates
            .where(
              (candidate) =>
                  candidate.direction != CorridorDirection.forward &&
                  candidate.hasPositiveEvidence,
            )
            .toList()
          ..sort((a, b) {
            final byCost = a.softCost.compareTo(b.softCost);
            return byCost != 0
                ? byCost
                : a.direction.index.compareTo(b.direction.index);
          });
    if (alternatives.isEmpty) return null;

    final incumbentDirection = _confirmedCorrection;
    if (incumbentDirection == null) return alternatives.first.direction;
    final incumbent = candidates
        .where((candidate) => candidate.direction == incumbentDirection)
        .firstOrNull;
    if (incumbent == null || !incumbent.hasPositiveEvidence) {
      return alternatives.first.direction;
    }
    final challenger = alternatives.first;
    if (challenger.direction == incumbentDirection ||
        challenger.softCost + correctionSwitchMargin >= incumbent.softCost) {
      return incumbentDirection;
    }
    return challenger.direction;
  }

  void _updateConfirmedCorrection({
    required CorridorDirection? proposedCorrection,
    required List<CorridorCandidate> candidates,
    required bool advancesRevision,
    required DateTime now,
  }) {
    final confirmed = _confirmedCorrection;
    if (confirmed != null) {
      final stillValid = _candidate(candidates, confirmed).hasPositiveEvidence;
      if (!stillValid) {
        _confirmedCorrection = null;
        _pendingCorrection = null;
        _pendingCorrectionRevisions = 0;
      }
    }
    if (proposedCorrection == null) {
      _confirmedCorrection = null;
      _pendingCorrection = null;
      _pendingCorrectionRevisions = 0;
      return;
    }
    if (proposedCorrection == _confirmedCorrection) {
      _pendingCorrection = null;
      _pendingCorrectionRevisions = 0;
      return;
    }
    if (!advancesRevision) return;

    if (_pendingCorrection != proposedCorrection) {
      _pendingCorrection = proposedCorrection;
      _pendingCorrectionRevisions = 1;
    } else {
      _pendingCorrectionRevisions++;
    }
    if (_pendingCorrectionRevisions < correctionConfirmationRevisions) return;

    final switchedAt = _lastCorrectionSwitchAt;
    if (_confirmedCorrection != null &&
        switchedAt != null &&
        now.difference(switchedAt) < correctionSwitchCooldown) {
      return;
    }
    _confirmedCorrection = proposedCorrection;
    _lastCorrectionSwitchAt = now;
    _pendingCorrection = null;
    _pendingCorrectionRevisions = 0;
  }

  SafetyAction? _buildShadowAction({
    required RelativePolarGrid grid,
    required List<CorridorCandidate> candidates,
    required CorridorCandidate forward,
    required DateTime now,
  }) {
    final direction = _confirmedCorrection;
    if (direction == null || !_hasDirectionalBlocker(forward)) return null;
    final target = _candidate(candidates, direction);
    if (!target.hasPositiveEvidence) return null;
    final sector = grid.sector(_sectorDirection(direction));
    return _action(
      grid: grid,
      now: now,
      kind: direction == CorridorDirection.left
          ? SafetyActionKind.adjustLeft
          : SafetyActionKind.adjustRight,
      cause: 'stable_alternative_corridor_shadow_only',
      priority: SafetyPriority.p1Correction,
      delivery: SafetyActionDelivery.shadow,
      ruleId: 'SPATIAL-P1-SHADOW-CORRECTION',
      direction: direction,
      confidence: sector.confidence,
      evidenceSector: sector,
      hazardIds: forward.hazardIds,
      extraEvidence: <String, Object?>{
        'shadowOnly': true,
        'confirmationRevisions': correctionConfirmationRevisions,
        'relativeSoftCost': target.softCost,
      },
    );
  }

  SafetyAction _continueAction({
    required RelativePolarGrid grid,
    required DateTime now,
  }) => _primaryAction(
    grid: grid,
    now: now,
    kind: SafetyActionKind.continueForward,
    cause: 'forward_corridor_positively_confirmed',
    priority: SafetyPriority.p3Information,
    ruleId: 'SPATIAL-P3-NO-CHANGE',
    confidence: grid.sector(RelativeSectorDirection.forward).confidence,
  );

  SafetyAction _holdAction({
    required RelativePolarGrid grid,
    required DateTime now,
    required String cause,
    required String ruleId,
    required double confidence,
  }) => _primaryAction(
    grid: grid,
    now: now,
    kind: SafetyActionKind.holdAndScan,
    cause: cause,
    priority: SafetyPriority.p2Degraded,
    ruleId: ruleId,
    confidence: confidence,
  );

  SafetyAction _primaryAction({
    required RelativePolarGrid grid,
    required DateTime now,
    required SafetyActionKind kind,
    required String cause,
    required SafetyPriority priority,
    required String ruleId,
    required double confidence,
  }) {
    final forward = grid.sector(RelativeSectorDirection.forward);
    return _action(
      grid: grid,
      now: now,
      kind: kind,
      cause: cause,
      priority: priority,
      ruleId: ruleId,
      direction: CorridorDirection.forward,
      confidence: confidence,
      evidenceSector: forward,
      hazardIds: forward.hazardIds,
    );
  }

  SafetyAction _action({
    required RelativePolarGrid grid,
    required DateTime now,
    required SafetyActionKind kind,
    required String cause,
    required SafetyPriority priority,
    SafetyActionDelivery delivery = SafetyActionDelivery.primary,
    required String ruleId,
    required CorridorDirection direction,
    required double confidence,
    required RelativePolarSector evidenceSector,
    required List<String> hazardIds,
    Map<String, Object?> extraEvidence = const <String, Object?>{},
  }) {
    final sequence = _actionSequence++;
    return SafetyAction(
      actionId: 'spatial-${grid.revision}-$sequence-${kind.name}',
      kind: kind,
      cause: cause,
      priority: priority,
      delivery: delivery,
      sceneRevision: grid.revision,
      hazardIds: hazardIds,
      evidenceSummary: <String, Object?>{
        'coordinateMode': 'relative',
        'observedFraction': evidenceSector.observedFraction,
        'occupancyProbability': evidenceSector.occupancyProbability,
        'traversabilityProbability': evidenceSector.traversabilityProbability,
        'dropProbability': evidenceSector.dropProbability,
        'movingThreatRisk': evidenceSector.movingThreatRisk,
        'unknownProbability': evidenceSector.unknownProbability,
        'orientationValid': grid.orientationValid,
        'sensingHealthy': grid.sensingHealthy,
        'sceneStale': grid.isStaleAt(now),
        ...extraEvidence,
      },
      direction: direction,
      confidence: confidence.clamp(0.0, 1.0),
      createdAt: now,
      validUntil: now.add(actionTtl),
      ruleId: ruleId,
    );
  }

  CorridorCandidate _candidate(
    List<CorridorCandidate> candidates,
    CorridorDirection direction,
  ) => candidates.singleWhere((candidate) => candidate.direction == direction);

  bool _hasDirectionalBlocker(CorridorCandidate candidate) =>
      candidate.rejectionReasons.any(
        (reason) =>
            reason == CorridorRejectionReason.confirmedObstacle ||
            reason == CorridorRejectionReason.dropBoundary ||
            reason == CorridorRejectionReason.movingThreatIntersection ||
            reason == CorridorRejectionReason.surfaceNotContinuous,
      );

  bool _requiresRecovery(GuidanceState state) =>
      state == GuidanceState.holdingForScan ||
      state == GuidanceState.correctionPending ||
      state == GuidanceState.degraded ||
      state == GuidanceState.recovering;

  RelativeSectorDirection _sectorDirection(CorridorDirection direction) =>
      switch (direction) {
        CorridorDirection.left => RelativeSectorDirection.left,
        CorridorDirection.forward => RelativeSectorDirection.forward,
        CorridorDirection.right => RelativeSectorDirection.right,
      };

  double _maximumRisk(RelativePolarSector sector) {
    var result = sector.occupancyProbability;
    if (sector.dropProbability > result) result = sector.dropProbability;
    if (sector.movingThreatRisk > result) result = sector.movingThreatRisk;
    return result;
  }
}
