import 'package:bagdar/core/core_health.dart';
import 'package:bagdar/safety/alerts/alert_arbiter.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:flutter_test/flutter_test.dart';

SafetyAction _action(
  DateTime now, {
  required String id,
  required String hazard,
  required SafetyActionKind kind,
  required SafetyPriority priority,
  double confidence = 0.7,
  CorridorDirection? direction,
  Duration ttl = const Duration(seconds: 3),
}) => SafetyAction(
  actionId: id,
  kind: kind,
  cause: 'test',
  priority: priority,
  sceneRevision: 1,
  hazardIds: <String>[hazard],
  evidenceSummary: const <String, Object?>{'source': 'test'},
  direction: direction,
  confidence: confidence,
  createdAt: now,
  validUntil: now.add(ttl),
  ruleId: 'TEST-ACTION',
);

FeedbackCommand _external(
  DateTime now, {
  required String id,
  required String key,
  required SafetyPriority priority,
  FeedbackCommandSource source = FeedbackCommandSource.emergency,
  SafetyActionKind? kind = SafetyActionKind.stopNow,
  CorridorDirection? direction = CorridorDirection.forward,
  double urgency = 0.8,
  Duration ttl = const Duration(seconds: 3),
}) => FeedbackCommand(
  actionId: id,
  sceneRevision: -1,
  speechKey: priority == SafetyPriority.p0Emergency
      ? 'generic_obstacle_stop'
      : 'core_health_status',
  earcon: priority == SafetyPriority.p0Emergency
      ? FeedbackEarcon.stop
      : FeedbackEarcon.none,
  hapticPattern: priority == SafetyPriority.p0Emergency
      ? FeedbackHapticPattern.immediateStop
      : FeedbackHapticPattern.none,
  priority: priority,
  source: source,
  actionKind: kind,
  direction: direction,
  urgency: urgency,
  canInterrupt: priority == SafetyPriority.p0Emergency,
  replaceKey: key,
  createdAt: now,
  expiresAt: now.add(ttl),
  ruleId: 'TEST-EXTERNAL',
  hazardIds: <String>[key],
);

CoreHealthSnapshot _health(
  DateTime now, {
  ComponentState mobility = ComponentState.unavailable,
  CoreRunState runState = CoreRunState.unavailable,
}) => CoreHealthSnapshot(
  runState: runState,
  reasonCode: 'camera_unavailable',
  at: now,
  components: const <CoreComponent, ComponentHealth>{},
  capabilities: <CoreCapability, ComponentState>{
    CoreCapability.mobilityVision: mobility,
  },
  mayAnnounceOperational: false,
);

void main() {
  group('AlertArbiter priority and preemption', () {
    test('P0 immediately preempts P3, P2 and P1', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final lowerPriorityInputs = <void Function(AlertArbiter)>[
        (arbiter) => arbiter.submitOnDemand(
          _external(
            now,
            id: 'p3',
            key: 'request:status',
            priority: SafetyPriority.p3Information,
            source: FeedbackCommandSource.onDemand,
            kind: null,
            direction: null,
          ),
          now: now,
        ),
        (arbiter) =>
            arbiter.submitHealth(_health(now), userMoving: false, now: now),
        (arbiter) => arbiter.submitAction(
          _action(
            now,
            id: 'p1',
            hazard: 'edge',
            kind: SafetyActionKind.adjustLeft,
            priority: SafetyPriority.p1Correction,
            direction: CorridorDirection.left,
          ),
          now: now,
        ),
      ];

      for (final seed in lowerPriorityInputs) {
        final arbiter = AlertArbiter();
        seed(arbiter);
        final event = arbiter.submitEmergency(
          _external(
            now,
            id: 'p0',
            key: 'emergency:collision',
            priority: SafetyPriority.p0Emergency,
          ),
          now: now,
        );

        expect(event.type, AlertArbiterEventType.emitted);
        expect(event.interruptCurrent, isTrue);
        expect(event.reason, 'p0_preempts_lower_priority');
        expect(arbiter.active?.actionId, 'p0');
        expect(arbiter.pending, isEmpty);
      }
    });

    test('independent P0 with same response is covered and hazards merge', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      arbiter.submitEmergency(
        _external(
          now,
          id: 'car',
          key: 'hazard:car',
          priority: SafetyPriority.p0Emergency,
        ),
        now: now,
      );

      final event = arbiter.submitEmergency(
        _external(
          now,
          id: 'drop',
          key: 'hazard:drop',
          priority: SafetyPriority.p0Emergency,
        ),
        now: now,
      );

      expect(event.type, AlertArbiterEventType.suppressed);
      expect(event.reason, 'independent_p0_same_response_covered');
      expect(
        arbiter.active?.hazardIds,
        containsAll(<String>['hazard:car', 'hazard:drop']),
      );
      expect(arbiter.lastCritical?.hazardIds, hasLength(2));
    });

    test('more urgent independent P0 preempts but preserves prior P0', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter(maxBufferedCommands: 3);
      arbiter.submitEmergency(
        _external(
          now,
          id: 'left-stop',
          key: 'hazard:left',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.left,
          urgency: 0.7,
        ),
        now: now,
      );

      final event = arbiter.submitEmergency(
        _external(
          now,
          id: 'right-stop',
          key: 'hazard:right',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.right,
          urgency: 0.9,
        ),
        now: now,
      );

      expect(event.reason, 'more_urgent_independent_p0_preempts');
      expect(event.interruptCurrent, isTrue);
      expect(arbiter.active?.actionId, 'right-stop');
      expect(arbiter.pending.single.actionId, 'left-stop');
      expect(arbiter.lastCritical?.actionId, 'right-stop');
    });
  });

  group('AlertArbiter identity, cooldown and expiry', () {
    test('same hazard replaces only for risk or response change', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      arbiter.submitAction(
        _action(
          now,
          id: 'first',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
          confidence: 0.70,
        ),
        now: now,
      );

      final duplicate = arbiter.submitAction(
        _action(
          now,
          id: 'duplicate',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
          confidence: 0.73,
        ),
        now: now.add(const Duration(milliseconds: 100)),
      );
      final escalation = arbiter.submitAction(
        _action(
          now,
          id: 'escalated',
          hazard: 'wall',
          kind: SafetyActionKind.stopNow,
          priority: SafetyPriority.p0Emergency,
          confidence: 0.95,
        ),
        now: now.add(const Duration(milliseconds: 200)),
      );

      expect(duplicate.type, AlertArbiterEventType.suppressed);
      expect(escalation.type, AlertArbiterEventType.replaced);
      expect(escalation.replacedActionId, 'first');
      expect(arbiter.active?.actionId, 'escalated');
    });

    test('same response may repeat after cooldown', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter(repeatCooldown: const Duration(seconds: 2));
      arbiter.submitAction(
        _action(
          now,
          id: 'first',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
        ),
        now: now,
      );

      final repeated = arbiter.submitAction(
        _action(
          now.add(const Duration(seconds: 3)),
          id: 'repeat',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
        ),
        now: now.add(const Duration(seconds: 3)),
      );

      expect(repeated.type, AlertArbiterEventType.replaced);
      expect(repeated.reason, 'replace_active_after_repeat_cooldown');
    });

    test('P1 pending state is replaced by replaceKey, not accumulated', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      arbiter.submitEmergency(
        _external(
          now,
          id: 'active-p0',
          key: 'hazard:p0',
          priority: SafetyPriority.p0Emergency,
        ),
        now: now,
      );
      arbiter.submitAction(
        _action(
          now,
          id: 'left',
          hazard: 'curb',
          kind: SafetyActionKind.adjustLeft,
          priority: SafetyPriority.p1Correction,
          direction: CorridorDirection.left,
        ),
        now: now,
      );

      final event = arbiter.submitAction(
        _action(
          now,
          id: 'right',
          hazard: 'curb',
          kind: SafetyActionKind.adjustRight,
          priority: SafetyPriority.p1Correction,
          direction: CorridorDirection.right,
        ),
        now: now.add(const Duration(milliseconds: 100)),
      );

      expect(event.type, AlertArbiterEventType.replaced);
      expect(arbiter.pending, hasLength(1));
      expect(arbiter.pending.single.actionId, 'right');
    });

    test('expired actions and commands are dropped with reasons', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      final expiredAction = arbiter.submitAction(
        _action(
          now.subtract(const Duration(seconds: 2)),
          id: 'expired-action',
          hazard: 'old',
          kind: SafetyActionKind.stopNow,
          priority: SafetyPriority.p0Emergency,
          ttl: const Duration(seconds: 1),
        ),
        now: now,
      );
      final expiredCommand = arbiter.submitOnDemand(
        _external(
          now.subtract(const Duration(seconds: 2)),
          id: 'expired-command',
          key: 'request:old',
          priority: SafetyPriority.p3Information,
          source: FeedbackCommandSource.onDemand,
          kind: null,
          direction: null,
          ttl: const Duration(seconds: 1),
        ),
        now: now,
      );

      expect(expiredAction.reason, 'expired_action');
      expect(expiredCommand.reason, 'expired_command');
      expect(arbiter.active, isNull);
      expect(
        arbiter.traces.map((trace) => trace.reason),
        containsAll(<String>['expired_action', 'expired_command']),
      );
    });

    test('bounded queue records every eviction or incoming drop', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter(maxBufferedCommands: 2);
      arbiter.submitEmergency(
        _external(
          now,
          id: 'active',
          key: 'hazard:active',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.left,
          urgency: 0.9,
        ),
        now: now,
      );
      arbiter.submitEmergency(
        _external(
          now,
          id: 'queued',
          key: 'hazard:queued',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.right,
          urgency: 0.8,
        ),
        now: now,
      );
      final dropped = arbiter.submitEmergency(
        _external(
          now,
          id: 'incoming',
          key: 'hazard:incoming',
          priority: SafetyPriority.p0Emergency,
          kind: SafetyActionKind.holdAndScan,
          direction: CorridorDirection.forward,
          urgency: 0.7,
        ),
        now: now,
      );

      expect(dropped.type, AlertArbiterEventType.dropped);
      expect(dropped.reason, 'bounded_queue_drop_incoming');
      expect(arbiter.bufferedCount, 2);
      expect(arbiter.traces.last.reason, 'bounded_queue_drop_incoming');
    });

    test('trace keeps explicit emit, suppress, replace and drop reasons', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      arbiter.submitAction(
        _action(
          now,
          id: 'emit',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
          confidence: 0.60,
        ),
        now: now,
      );
      arbiter.submitAction(
        _action(
          now,
          id: 'suppress',
          hazard: 'wall',
          kind: SafetyActionKind.holdAndScan,
          priority: SafetyPriority.p2Degraded,
          confidence: 0.61,
        ),
        now: now.add(const Duration(milliseconds: 100)),
      );
      arbiter.submitAction(
        _action(
          now,
          id: 'replace',
          hazard: 'wall',
          kind: SafetyActionKind.stopNow,
          priority: SafetyPriority.p0Emergency,
          confidence: 0.95,
        ),
        now: now.add(const Duration(milliseconds: 200)),
      );
      arbiter.submitOnDemand(
        _external(
          now.subtract(const Duration(seconds: 2)),
          id: 'drop',
          key: 'request:expired',
          priority: SafetyPriority.p3Information,
          source: FeedbackCommandSource.onDemand,
          kind: null,
          direction: null,
          ttl: const Duration(seconds: 1),
        ),
        now: now,
      );

      final types = arbiter.traces.map((trace) => trace.type).toSet();
      expect(
        types,
        containsAll(<AlertArbiterEventType>[
          AlertArbiterEventType.emitted,
          AlertArbiterEventType.suppressed,
          AlertArbiterEventType.replaced,
          AlertArbiterEventType.dropped,
        ]),
      );
      expect(
        arbiter.traces.every((trace) => trace.reason.trim().isNotEmpty),
        isTrue,
      );
    });

    test('completing active command promotes exactly one pending command', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final arbiter = AlertArbiter();
      arbiter.submitEmergency(
        _external(
          now,
          id: 'active',
          key: 'hazard:active',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.left,
          urgency: 0.9,
        ),
        now: now,
      );
      arbiter.submitEmergency(
        _external(
          now,
          id: 'pending',
          key: 'hazard:pending',
          priority: SafetyPriority.p0Emergency,
          direction: CorridorDirection.right,
          urgency: 0.8,
        ),
        now: now,
      );

      final next = arbiter.completeCurrent(
        now: now.add(const Duration(milliseconds: 200)),
      );

      expect(next?.actionId, 'pending');
      expect(arbiter.active?.actionId, 'pending');
      expect(arbiter.pending, isEmpty);
    });
  });

  group('AlertArbiter health admission', () {
    test('lost sensing is P0 while moving and P2 while stationary', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final snapshot = _health(now);
      final moving = AlertArbiter().submitHealth(
        snapshot,
        userMoving: true,
        now: now,
      );
      final stationary = AlertArbiter().submitHealth(
        snapshot,
        userMoving: false,
        now: now,
      );

      expect(moving.command?.priority, SafetyPriority.p0Emergency);
      expect(moving.command?.actionKind, SafetyActionKind.stopNow);
      expect(stationary.command?.priority, SafetyPriority.p2Degraded);
      expect(stationary.command?.actionKind, SafetyActionKind.holdAndScan);
    });

    test('operational health snapshot produces no feedback', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final event = AlertArbiter().submitHealth(
        _health(
          now,
          mobility: ComponentState.available,
          runState: CoreRunState.operational,
        ),
        userMoving: false,
        now: now,
      );

      expect(event.type, AlertArbiterEventType.suppressed);
      expect(event.reason, 'healthy_snapshot_no_feedback');
    });
  });
}
