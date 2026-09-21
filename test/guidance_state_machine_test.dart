import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/safety/alerts/feedback_policy.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';

RelativePolarSector _sector(
  DateTime at, {
  double observed = 0.95,
  double occupancy = 0.05,
  double traversability = 0.90,
  double drop = 0.02,
  double movingThreat = 0.02,
  double unknown = 0.05,
  double confidence = 0.90,
  List<String> hazards = const <String>[],
}) => RelativePolarSector(
  observedFraction: observed,
  occupancyProbability: occupancy,
  traversabilityProbability: traversability,
  dropProbability: drop,
  movingThreatRisk: movingThreat,
  unknownProbability: unknown,
  confidence: confidence,
  sourceMask: const <String>{'geometry', 'depth'},
  hazardIds: hazards,
  lastObservedAt: at,
);

RelativePolarSector _blocked(DateTime at) => _sector(
  at,
  occupancy: 0.70,
  traversability: 0.20,
  hazards: const <String>['geometry:center'],
);

RelativePolarSector _unknown(DateTime at) => _sector(
  at,
  observed: 0.25,
  traversability: 0.10,
  unknown: 0.90,
  confidence: 0.20,
);

RelativePolarGrid _grid(
  DateTime at, {
  required int revision,
  RelativePolarSector? left,
  RelativePolarSector? forward,
  RelativePolarSector? right,
  bool moving = false,
  bool orientationValid = true,
  bool sensingHealthy = true,
  DateTime? validUntil,
}) => RelativePolarGrid(
  revision: revision,
  at: at,
  validUntil: validUntil ?? at.add(const Duration(seconds: 1)),
  orientationValid: orientationValid,
  sensingHealthy: sensingHealthy,
  userMoving: moving,
  sectors: <RelativeSectorDirection, RelativePolarSector>{
    RelativeSectorDirection.left: left ?? _sector(at),
    RelativeSectorDirection.forward: forward ?? _sector(at),
    RelativeSectorDirection.right: right ?? _sector(at),
  },
);

void main() {
  group('GuidanceStateMachine safety actions', () {
    test('imminent risk always emits stopNow', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final decision = GuidanceStateMachine().evaluate(
        _grid(now, revision: 1, forward: _sector(now, occupancy: 0.90)),
        now: now,
      );

      expect(decision.action.kind, SafetyActionKind.stopNow);
      expect(decision.state, GuidanceState.emergencyStop);
    });

    test('drop and moving-threat imminent risks also emit stopNow', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final sectors = <RelativePolarSector>[
        _sector(now, drop: 0.50),
        _sector(now, movingThreat: 0.70),
      ];

      for (var index = 0; index < sectors.length; index++) {
        final decision = GuidanceStateMachine().evaluate(
          _grid(now, revision: index + 1, forward: sectors[index]),
          now: now,
        );
        expect(decision.action.kind, SafetyActionKind.stopNow);
        expect(decision.action.ruleId, 'SPATIAL-P0-IMMINENT');
      }
    });

    test('degraded evidence stops motion and holds a stationary user', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final moving = GuidanceStateMachine().evaluate(
        _grid(now, revision: 1, forward: _unknown(now), moving: true),
        now: now,
      );
      final stopped = GuidanceStateMachine().evaluate(
        _grid(now, revision: 1, forward: _unknown(now)),
        now: now,
      );

      expect(moving.action.kind, SafetyActionKind.stopNow);
      expect(stopped.action.kind, SafetyActionKind.holdAndScan);
      expect(stopped.state, GuidanceState.degraded);
    });

    test(
      'correction needs three distinct revisions and remains shadow-only',
      () {
        final origin = DateTime.utc(2026, 9, 20, 10);
        final machine = GuidanceStateMachine();

        GuidanceDecision? decision;
        for (var revision = 1; revision <= 3; revision++) {
          final now = origin.add(Duration(milliseconds: revision * 300));
          decision = machine.evaluate(
            _grid(
              now,
              revision: revision,
              forward: _blocked(now),
              right: _unknown(now),
            ),
            now: now,
          );
          expect(decision.action.kind, SafetyActionKind.holdAndScan);
          if (revision < 3) expect(decision.shadowAction, isNull);
        }

        expect(decision!.proposedCorrection, CorridorDirection.left);
        expect(decision.shadowCorrection, CorridorDirection.left);
        expect(decision.shadowAction!.kind, SafetyActionKind.adjustLeft);
        expect(decision.shadowAction!.delivery, SafetyActionDelivery.shadow);
        expect(decision.shadowAction!.evidenceSummary['shadowOnly'], isTrue);
        expect(
          const FeedbackPolicy().commandFor(decision.shadowAction!),
          isNull,
        );
        expect(decision.action.kind, isNot(SafetyActionKind.adjustLeft));
        expect(decision.state, GuidanceState.correctionPending);
      },
    );

    test('re-evaluating one revision cannot satisfy hysteresis', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final machine = GuidanceStateMachine();
      final grid = _grid(
        now,
        revision: 1,
        forward: _blocked(now),
        right: _unknown(now),
      );

      final decisions = List<GuidanceDecision>.generate(
        4,
        (_) => machine.evaluate(grid, now: now),
      );

      expect(
        decisions.every((decision) => decision.shadowAction == null),
        isTrue,
      );
      expect(
        decisions.every(
          (decision) => decision.proposedCorrection == CorridorDirection.left,
        ),
        isTrue,
      );
    });

    test('right alternative produces only an adjustRight shadow action', () {
      final origin = DateTime.utc(2026, 9, 20, 10);
      final machine = GuidanceStateMachine(correctionConfirmationRevisions: 2);
      GuidanceDecision? decision;
      for (var revision = 1; revision <= 2; revision++) {
        final now = origin.add(Duration(milliseconds: revision * 300));
        decision = machine.evaluate(
          _grid(
            now,
            revision: revision,
            left: _unknown(now),
            forward: _blocked(now),
          ),
          now: now,
        );
      }

      expect(decision!.shadowCorrection, CorridorDirection.right);
      expect(decision.shadowAction!.kind, SafetyActionKind.adjustRight);
      expect(decision.action.kind, SafetyActionKind.holdAndScan);
    });

    test('one challenger frame cannot oscillate a confirmed direction', () {
      final origin = DateTime.utc(2026, 9, 20, 10);
      final machine = GuidanceStateMachine();
      for (var revision = 1; revision <= 3; revision++) {
        final now = origin.add(Duration(milliseconds: revision * 300));
        machine.evaluate(
          _grid(
            now,
            revision: revision,
            forward: _blocked(now),
            right: _unknown(now),
          ),
          now: now,
        );
      }

      final challengeAt = origin.add(const Duration(milliseconds: 1500));
      final challenged = machine.evaluate(
        _grid(
          challengeAt,
          revision: 4,
          forward: _blocked(challengeAt),
          left: _sector(
            challengeAt,
            occupancy: 0.25,
            traversability: 0.75,
            unknown: 0.10,
          ),
          right: _sector(challengeAt, occupancy: 0.01, unknown: 0.01),
        ),
        now: challengeAt,
      );

      expect(challenged.proposedCorrection, CorridorDirection.right);
      expect(challenged.shadowCorrection, CorridorDirection.left);
    });

    test(
      'confirmed correction is cleared immediately if it becomes unknown',
      () {
        final origin = DateTime.utc(2026, 9, 20, 10);
        final machine = GuidanceStateMachine();
        for (var revision = 1; revision <= 3; revision++) {
          final now = origin.add(Duration(milliseconds: revision * 300));
          machine.evaluate(
            _grid(
              now,
              revision: revision,
              forward: _blocked(now),
              right: _unknown(now),
            ),
            now: now,
          );
        }
        final now = origin.add(const Duration(milliseconds: 1200));
        final decision = machine.evaluate(
          _grid(
            now,
            revision: 4,
            forward: _blocked(now),
            left: _unknown(now),
            right: _unknown(now),
          ),
          now: now,
        );

        expect(decision.shadowAction, isNull);
        expect(decision.action.kind, SafetyActionKind.holdAndScan);
      },
    );

    test('stop release requires stationary and two healthy revisions', () {
      final origin = DateTime.utc(2026, 9, 20, 10);
      final machine = GuidanceStateMachine();

      final emergency = machine.evaluate(
        _grid(
          origin,
          revision: 1,
          forward: _sector(origin, occupancy: 0.90),
          moving: true,
        ),
        now: origin,
      );
      final stillMovingAt = origin.add(const Duration(milliseconds: 300));
      final stillMoving = machine.evaluate(
        _grid(stillMovingAt, revision: 2, moving: true),
        now: stillMovingAt,
      );
      final stoppedAt = origin.add(const Duration(milliseconds: 600));
      final stopped = machine.evaluate(
        _grid(stoppedAt, revision: 3),
        now: stoppedAt,
      );
      final confirmedAt = origin.add(const Duration(milliseconds: 900));
      final confirmed = machine.evaluate(
        _grid(confirmedAt, revision: 4),
        now: confirmedAt,
      );

      expect(emergency.action.kind, SafetyActionKind.stopNow);
      expect(stillMoving.action.kind, SafetyActionKind.stopNow);
      expect(stillMoving.action.ruleId, 'SPATIAL-P0-AWAIT-STATIONARY');
      expect(stopped.action.kind, SafetyActionKind.holdAndScan);
      expect(confirmed.action.kind, SafetyActionKind.continueForward);
      expect(confirmed.state, GuidanceState.observing);
    });

    test('degraded state recovers only on fresh healthy revisions', () {
      final origin = DateTime.utc(2026, 9, 20, 10);
      final machine = GuidanceStateMachine();
      final degraded = machine.evaluate(
        _grid(origin, revision: 1, sensingHealthy: false),
        now: origin,
      );
      final firstHealthyAt = origin.add(const Duration(milliseconds: 300));
      final firstHealthy = machine.evaluate(
        _grid(firstHealthyAt, revision: 2),
        now: firstHealthyAt,
      );
      final secondHealthyAt = origin.add(const Duration(milliseconds: 600));
      final secondHealthy = machine.evaluate(
        _grid(secondHealthyAt, revision: 3),
        now: secondHealthyAt,
      );

      expect(degraded.state, GuidanceState.degraded);
      expect(firstHealthy.state, GuidanceState.recovering);
      expect(firstHealthy.action.kind, SafetyActionKind.holdAndScan);
      expect(secondHealthy.state, GuidanceState.observing);
      expect(secondHealthy.action.kind, SafetyActionKind.continueForward);
    });
  });
}
