import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/alert_manager.dart';
import 'package:bagdar/core/build_profile.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/safety/alerts/alert_arbiter.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
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
  List<String> hazardIds = const [],
}) => RelativePolarSector(
  observedFraction: observed,
  occupancyProbability: occupancy,
  traversabilityProbability: traversability,
  dropProbability: drop,
  movingThreatRisk: movingThreat,
  unknownProbability: unknown,
  confidence: confidence,
  sourceMask: const {'geometry', 'depth'},
  hazardIds: hazardIds,
  lastObservedAt: at,
);

RelativePolarSector _unknownSector(DateTime at) => _sector(
  at,
  observed: 0.25,
  traversability: 0.10,
  unknown: 0.90,
  confidence: 0.20,
);

RelativePolarGrid _grid(
  DateTime at, {
  required RelativePolarSector forward,
  RelativePolarSector? left,
  RelativePolarSector? right,
  bool moving = false,
  bool orientationValid = true,
  bool sensingHealthy = true,
  DateTime? validUntil,
}) => RelativePolarGrid(
  revision: 7,
  at: at,
  validUntil: validUntil ?? at.add(const Duration(seconds: 1)),
  orientationValid: orientationValid,
  sensingHealthy: sensingHealthy,
  userMoving: moving,
  sectors: {
    RelativeSectorDirection.left: left ?? _sector(at),
    RelativeSectorDirection.forward: forward,
    RelativeSectorDirection.right: right ?? _sector(at),
  },
);

FeedbackCommand _infoCommand(DateTime now) => FeedbackCommand(
  actionId: 'info-request',
  sceneRevision: 0,
  speechKey: 'core_health_status',
  earcon: FeedbackEarcon.none,
  hapticPattern: FeedbackHapticPattern.none,
  priority: SafetyPriority.p3Information,
  source: FeedbackCommandSource.onDemand,
  actionKind: null,
  direction: null,
  urgency: 0.2,
  canInterrupt: false,
  replaceKey: 'on-demand:status',
  createdAt: now,
  expiresAt: now.add(const Duration(seconds: 3)),
  ruleId: 'ON-DEMAND-STATUS',
  hazardIds: const [],
);

void main() {
  group('spatial safety first slice — canonical scenarios', () {
    test('center obstacle emits stopNow with traceable evidence', () {
      final now = DateTime(2026, 9, 18, 12);
      final decision = GuidanceStateMachine().evaluate(
        _grid(
          now,
          forward: _sector(
            now,
            occupancy: 0.92,
            traversability: 0.20,
            confidence: 0.95,
            hazardIds: const ['geometry:center-bin'],
          ),
          moving: true,
        ),
        now: now,
      );

      expect(decision.action.kind, SafetyActionKind.stopNow);
      expect(decision.action.priority, SafetyPriority.p0Emergency);
      expect(decision.action.ruleId, 'SPATIAL-P0-IMMINENT');
      expect(decision.action.hazardIds, contains('geometry:center-bin'));
      expect(decision.action.evidenceSummary['coordinateMode'], 'relative');
      expect(decision.action.evidenceSummary, isNotEmpty);
      expect(
        decision.action.kind,
        isNot(anyOf(SafetyActionKind.adjustLeft, SafetyActionKind.adjustRight)),
      );
    });

    test('unknown center holds when stopped and stops while moving', () {
      final now = DateTime(2026, 9, 18, 12);
      final machine = GuidanceStateMachine();

      final stopped = machine.evaluate(
        _grid(now, forward: _unknownSector(now)),
        now: now,
      );
      final moving = machine.evaluate(
        _grid(now, forward: _unknownSector(now), moving: true),
        now: now,
      );

      expect(stopped.action.kind, SafetyActionKind.holdAndScan);
      expect(moving.action.kind, SafetyActionKind.stopNow);
      expect(stopped.shadowCorrection, isNull);
    });

    test(
      'center blocked and left observed keeps left correction in shadow',
      () {
        final now = DateTime(2026, 9, 18, 12);
        final decision = GuidanceStateMachine().evaluate(
          _grid(
            now,
            forward: _sector(
              now,
              occupancy: 0.85,
              traversability: 0.25,
              hazardIds: const ['geometry:center'],
            ),
            left: _sector(now),
            right: _unknownSector(now),
          ),
          now: now,
        );

        expect(decision.action.kind, SafetyActionKind.stopNow);
        expect(decision.proposedCorrection, CorridorDirection.left);
        expect(decision.shadowCorrection, isNull);
        expect(
          decision.action.kind,
          isNot(
            anyOf(SafetyActionKind.adjustLeft, SafetyActionKind.adjustRight),
          ),
        );
      },
    );

    test('center blocked and left unobserved never guides into unknown', () {
      final now = DateTime(2026, 9, 18, 12);
      final decision = GuidanceStateMachine().evaluate(
        _grid(
          now,
          forward: _sector(
            now,
            occupancy: 0.85,
            traversability: 0.25,
            hazardIds: const ['geometry:center'],
          ),
          left: _unknownSector(now),
          right: _unknownSector(now),
        ),
        now: now,
      );

      expect(decision.action.kind, SafetyActionKind.stopNow);
      expect(decision.shadowCorrection, isNull);
    });

    test('stale scene during motion emits stopNow, not an empty scene', () {
      final now = DateTime(2026, 9, 18, 12);
      final capturedAt = now.subtract(const Duration(seconds: 2));
      final decision = GuidanceStateMachine().evaluate(
        _grid(
          capturedAt,
          forward: _sector(capturedAt),
          moving: true,
          validUntil: now.subtract(const Duration(milliseconds: 1)),
        ),
        now: now,
      );

      expect(decision.action.kind, SafetyActionKind.stopNow);
      expect(
        decision.action.cause,
        'spatial_evidence_unavailable_while_moving',
      );
      expect(decision.action.evidenceSummary['sceneStale'], isTrue);
    });

    test('critical action interrupts active informational feedback', () {
      final now = DateTime(2026, 9, 18, 12);
      final arbiter = AlertArbiter();
      arbiter.submitOnDemand(_infoCommand(now), now: now);

      final stop = GuidanceStateMachine()
          .evaluate(
            _grid(
              now,
              forward: _sector(
                now,
                occupancy: 0.90,
                hazardIds: const ['geometry:center'],
              ),
              moving: true,
            ),
            now: now,
          )
          .action;
      final event = arbiter.submitAction(stop, now: now);

      expect(event.type, AlertArbiterEventType.emitted);
      expect(event.interruptCurrent, isTrue);
      expect(event.replacedActionId, 'info-request');
      expect(arbiter.active?.actionId, stop.actionId);
    });
  });

  group('spatial safety first slice — queue and speech invariants', () {
    test('expired action is dropped before it can become active speech', () {
      final now = DateTime(2026, 9, 18, 12);
      final action = GuidanceStateMachine(actionTtl: const Duration(seconds: 1))
          .evaluate(
            _grid(now, forward: _sector(now, occupancy: 0.90), moving: true),
            now: now,
          )
          .action;
      final arbiter = AlertArbiter();
      final event = arbiter.submitAction(
        action,
        now: now.add(const Duration(seconds: 2)),
      );

      expect(event.type, AlertArbiterEventType.dropped);
      expect(event.reason, 'expired_action');
      expect(arbiter.active, isNull);
    });

    test('arbiter remains bounded for independent P0 hazards', () {
      final now = DateTime(2026, 9, 18, 12);
      final arbiter = AlertArbiter(maxBufferedCommands: 4);
      for (var i = 0; i < 12; i++) {
        arbiter.submitEmergency(
          FeedbackCommand(
            actionId: 'critical-$i',
            sceneRevision: i,
            speechKey: 'generic_obstacle_stop',
            earcon: FeedbackEarcon.stop,
            hapticPattern: FeedbackHapticPattern.immediateStop,
            priority: SafetyPriority.p0Emergency,
            source: FeedbackCommandSource.emergency,
            actionKind: i.isEven
                ? SafetyActionKind.stopNow
                : SafetyActionKind.holdAndScan,
            direction: switch (i % 3) {
              0 => CorridorDirection.left,
              1 => CorridorDirection.forward,
              _ => CorridorDirection.right,
            },
            urgency: 0.60 + (i * 0.03),
            canInterrupt: true,
            replaceKey: 'hazard:$i',
            createdAt: now,
            expiresAt: now.add(const Duration(seconds: 2)),
            ruleId: 'TEST-P0',
            hazardIds: ['$i'],
          ),
          now: now,
        );
      }

      expect(arbiter.bufferedCount, lessThanOrEqualTo(4));
      expect(
        arbiter.traces.any(
          (trace) => trace.reason.startsWith('bounded_queue_evict'),
        ),
        isTrue,
      );
    });

    test('relative actions never create metric or path-clear speech', () {
      final now = DateTime(2026, 9, 18, 12);
      final action = GuidanceStateMachine()
          .evaluate(
            _grid(now, forward: _sector(now, occupancy: 0.90), moving: true),
            now: now,
          )
          .action;
      final command = const FeedbackPolicy().commandFor(action)!;

      expect(command.speechKey, 'generic_obstacle_stop');
      for (final language in AppLanguage.values) {
        AppStrings.setLanguage(language);
        final speech = AppStrings.get(command.speechKey).toLowerCase();
        expect(speech, isNot(contains(RegExp(r'\d'))));
        expect(speech, isNot(contains('метр')));
        expect(speech, isNot(contains('meter')));
        expect(speech, isNot(contains('путь свобод')));
        expect(speech, isNot(contains('path clear')));
      }
    });

    test('legacy pixel-gap corridor hints are disabled in Core', () {
      expect(
        AlertManager.legacyCorridorHintsEnabledFor(BuildProfile.core),
        isFalse,
      );
      expect(
        AlertManager.legacyCorridorHintsEnabledFor(BuildProfile.research),
        isTrue,
      );
    });
  });
}
