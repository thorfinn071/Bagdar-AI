import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:flutter_test/flutter_test.dart';

final stamp = DateTime.utc(2026, 10, 7);

// Deterministic planner inputs, not neural output or camera clearance proof.
RelativePolarGrid grid(
  int revision, {
  bool moving = true,
  bool hypothesis = false,
  double observed = 1,
  double unknown = 0,
  double surface = 1,
  double confidence = 1,
  double occupancy = 0,
  double drop = 0,
  double threat = 0,
  bool orientation = true,
  bool healthy = true,
  bool stale = false,
}) {
  final sector = RelativePolarSector(
    observedFraction: observed,
    occupancyProbability: occupancy,
    traversabilityProbability: surface,
    dropProbability: drop,
    movingThreatRisk: threat,
    unknownProbability: unknown,
    confidence: confidence,
    sourceMask: const {'test-current-corridor'},
    hazardIds: hypothesis ? ['unresolved-component'] : [],
    lastObservedAt: stamp,
  );
  return RelativePolarGrid(
    revision: revision,
    at: stale ? stamp.subtract(const Duration(seconds: 2)) : stamp,
    validUntil: stale
        ? stamp.subtract(const Duration(seconds: 1))
        : stamp.add(const Duration(milliseconds: 100)),
    orientationValid: orientation,
    sensingHealthy: healthy,
    userMoving: moving,
    sectors: {
      for (final direction in RelativeSectorDirection.values) direction: sector,
    },
  );
}

Map<String, Object?> actionFields(SafetyAction action) => {
  'id': action.actionId,
  'kind': action.kind,
  'priority': action.priority,
  'delivery': action.delivery,
  'revision': action.sceneRevision,
  'hazards': action.hazardIds,
  'summary': action.evidenceSummary,
  'direction': action.direction,
  'confidence': action.confidence,
  'created': action.createdAt,
  'expires': action.validUntil,
};

void sameAuthority(GuidanceDecision old, GuidanceDecision current) {
  expect(actionFields(current.action), actionFields(old.action));
  expect(current.state, old.state);
  expect(current.previousState, old.previousState);
  expect(current.proposedCorrection, old.proposedCorrection);
  expect(
    current.candidates.map((c) => c.hasPositiveEvidence).toList(),
    old.candidates.map((c) => c.hasPositiveEvidence).toList(),
  );
  expect(current.shadowAction?.kind, old.shadowAction?.kind);
}

void main() {
  final gaps = {
    'unknown body': grid(2, observed: .35, unknown: .65),
    'missing width': grid(2, observed: .35),
    'uncertain ground': grid(2, surface: .1),
    'low confidence': grid(2, confidence: .64),
  };
  for (final entry in gaps.entries) {
    test(
      'current ${entry.key} remains visible after the component disappears',
      () {
        final old = ConfidenceAuthorityGuidance();
        final current = CoverageAwareStopGuidance();
        final initial = grid(1, hypothesis: true, observed: .35, unknown: .65);
        sameAuthority(
          old.evaluate(initial, now: stamp),
          current.evaluate(initial, now: stamp),
        );
        final before = old.evaluate(entry.value, now: stamp);
        final after = current.evaluate(entry.value, now: stamp);
        expect(before.action.ruleId, 'SPATIAL-P0-AWAIT-STATIONARY');
        expect(
          after.action.ruleId,
          entry.key == 'unknown body' || entry.key == 'missing width'
              ? 'SPATIAL-P0-DEGRADED-MOVING'
              : 'SPATIAL-P0-FORWARD-UNCONFIRMED',
        );
        expect(after.action.kind, SafetyActionKind.stopNow);
        sameAuthority(before, after);
      },
    );
  }
  test('positive moving evidence still requires stationary release', () {
    final old = ConfidenceAuthorityGuidance();
    final current = CoverageAwareStopGuidance();
    for (final input in [grid(1, hypothesis: true, unknown: .65), grid(2)]) {
      final before = old.evaluate(input, now: stamp);
      final after = current.evaluate(input, now: stamp);
      sameAuthority(before, after);
      expect(after.action.ruleId, before.action.ruleId);
    }
    expect(
      current.evaluate(grid(3), now: stamp).action.ruleId,
      'SPATIAL-P0-AWAIT-STATIONARY',
    );
  });
  test(
    'two distinct positive stationary revisions release exactly as before',
    () {
      final old = ConfidenceAuthorityGuidance();
      final current = CoverageAwareStopGuidance();
      final sequence = [
        grid(1, hypothesis: true, unknown: .65),
        grid(2, observed: .35, unknown: .65),
        grid(3, moving: false),
        grid(3, moving: false),
        grid(4, moving: false),
      ];
      final kinds = <SafetyActionKind>[];
      for (final input in sequence) {
        final before = old.evaluate(input, now: stamp);
        final after = current.evaluate(input, now: stamp);
        sameAuthority(before, after);
        kinds.add(after.action.kind);
      }
      expect(kinds, [
        SafetyActionKind.stopNow,
        SafetyActionKind.stopNow,
        SafetyActionKind.holdAndScan,
        SafetyActionKind.holdAndScan,
        SafetyActionKind.continueForward,
      ]);
    },
  );
  test('missing, invalid and stale sensing preserve stop and expiry', () {
    for (final input in [
      grid(2, orientation: false),
      grid(2, healthy: false),
      grid(2, stale: true),
    ]) {
      final old = ConfidenceAuthorityGuidance();
      final current = CoverageAwareStopGuidance();
      final initial = grid(1, hypothesis: true, unknown: .65);
      old.evaluate(initial, now: stamp);
      current.evaluate(initial, now: stamp);
      final before = old.evaluate(input, now: stamp);
      final after = current.evaluate(input, now: stamp);
      sameAuthority(before, after);
      expect(after.action.ruleId, 'SPATIAL-P0-DEGRADED-MOVING');
      expect(after.action.kind, SafetyActionKind.stopNow);
    }
  });
  test(
    'obstacle, drop and moving-threat emergency precedence is unchanged',
    () {
      for (final input in [
        grid(2, occupancy: .9),
        grid(2, drop: .9),
        grid(2, threat: .9),
      ]) {
        final old = ConfidenceAuthorityGuidance();
        final current = CoverageAwareStopGuidance();
        final initial = grid(1, hypothesis: true, unknown: .65);
        old.evaluate(initial, now: stamp);
        current.evaluate(initial, now: stamp);
        final before = old.evaluate(input, now: stamp);
        final after = current.evaluate(input, now: stamp);
        sameAuthority(before, after);
        expect(after.action.ruleId, 'SPATIAL-P0-IMMINENT');
      }
    },
  );
  test('reset clears the same stop latch for a new session', () {
    final old = ConfidenceAuthorityGuidance();
    final current = CoverageAwareStopGuidance();
    final initial = grid(1, hypothesis: true, unknown: .65);
    old.evaluate(initial, now: stamp);
    current.evaluate(initial, now: stamp);
    old.reset();
    current.reset();
    final before = old.evaluate(grid(1), now: stamp);
    final after = current.evaluate(grid(1), now: stamp);
    sameAuthority(before, after);
    expect(after.action.kind, SafetyActionKind.continueForward);
  });
}
