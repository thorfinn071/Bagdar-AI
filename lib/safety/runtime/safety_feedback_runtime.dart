import 'dart:async';

import '../../core/core_health.dart';
import '../alerts/alert_arbiter.dart';
import '../alerts/feedback_command.dart';
import '../alerts/feedback_dispatcher.dart';
import '../planning/safety_action.dart';

enum FeedbackDeliveryEventType {
  admitted,
  interrupted,
  delivered,
  failed,
  completed,
  promoted,
  reset,
}

class FeedbackDeliveryTrace {
  final DateTime at;
  final FeedbackDeliveryEventType type;
  final String actionId;
  final String reason;
  final FeedbackCommandSource source;

  const FeedbackDeliveryTrace({
    required this.at,
    required this.type,
    required this.actionId,
    required this.reason,
    required this.source,
  });

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'atUs': at.microsecondsSinceEpoch,
    'type': type.name,
    'actionId': actionId,
    'reason': reason,
    'source': source.name,
  };
}

/// The single production owner of safety admission and output delivery.
///
/// Risk remains owned by producers. This runtime only arbitrates typed
/// commands, interrupts lower-priority output, advances exactly one pending
/// command after completion, and keeps a bounded delivery trace.
class SafetyFeedbackRuntime {
  final AlertArbiter arbiter;
  final FeedbackDispatcher dispatcher;
  final FeedbackOutputPort output;
  final int maxTraceEntries;

  final List<FeedbackDeliveryTrace> _traces = <FeedbackDeliveryTrace>[];
  int _deliveryGeneration = 0;
  String? _dispatchingActionId;

  SafetyFeedbackRuntime({
    required this.arbiter,
    required this.dispatcher,
    required this.output,
    this.maxTraceEntries = 128,
  }) : assert(maxTraceEntries > 0);

  List<FeedbackDeliveryTrace> get traces => List.unmodifiable(_traces);
  String? get dispatchingActionId => _dispatchingActionId;

  AlertArbiterEvent submitCommand(
    FeedbackCommand command, {
    required DateTime now,
  }) {
    final event = switch (command.source) {
      FeedbackCommandSource.emergency => arbiter.submitEmergency(
        command,
        now: now,
      ),
      FeedbackCommandSource.onDemand => arbiter.submitOnDemand(
        command,
        now: now,
      ),
      FeedbackCommandSource.coreHealth => throw ArgumentError(
        'Use submitHealth for core-health snapshots.',
      ),
      _ => arbiter.admitTyped(command, now: now),
    };
    _record(
      now,
      FeedbackDeliveryEventType.admitted,
      command,
      '${event.type.name}:${event.reason}',
    );
    unawaited(_handleEvent(event, now: now));
    return event;
  }

  AlertArbiterEvent submitHealth(
    CoreHealthSnapshot snapshot, {
    required bool userMoving,
    required DateTime now,
  }) {
    final event = arbiter.submitHealth(
      snapshot,
      userMoving: userMoving,
      now: now,
    );
    final command = event.command;
    if (command != null) {
      _record(
        now,
        FeedbackDeliveryEventType.admitted,
        command,
        '${event.type.name}:${event.reason}',
      );
    }
    unawaited(_handleEvent(event, now: now));
    return event;
  }

  AlertArbiterEvent submitSpatialAction(
    SafetyAction action, {
    required DateTime now,
  }) {
    final event = arbiter.submitAction(action, now: now);
    unawaited(_handleEvent(event, now: now));
    return event;
  }

  Future<void> resetSession({required DateTime now}) async {
    final hadActiveDelivery =
        _dispatchingActionId != null || arbiter.bufferedCount > 0;
    _deliveryGeneration++;
    _dispatchingActionId = null;
    arbiter.reset();
    if (hadActiveDelivery) await output.interruptCurrent();
    final synthetic = FeedbackCommand(
      actionId: 'feedback-reset-${now.microsecondsSinceEpoch}',
      sceneRevision: -1,
      speechKey: 'spatial_analysis_limited',
      earcon: FeedbackEarcon.none,
      hapticPattern: FeedbackHapticPattern.none,
      priority: SafetyPriority.p3Information,
      source: FeedbackCommandSource.cameraHealth,
      actionKind: null,
      direction: null,
      urgency: 0,
      canInterrupt: false,
      replaceKey: 'feedback:reset',
      createdAt: now,
      expiresAt: now,
      ruleId: 'FEEDBACK-SESSION-RESET',
      hazardIds: const <String>[],
    );
    _record(now, FeedbackDeliveryEventType.reset, synthetic, 'session_reset');
  }

  Future<void> _handleEvent(
    AlertArbiterEvent event, {
    required DateTime now,
  }) async {
    final command = event.command;
    if (command == null) return;
    if (event.type != AlertArbiterEventType.emitted &&
        event.type != AlertArbiterEventType.replaced) {
      return;
    }
    final generation = ++_deliveryGeneration;
    if (event.interruptCurrent) {
      await output.interruptCurrent();
      _record(
        now,
        FeedbackDeliveryEventType.interrupted,
        command,
        event.reason,
      );
    }
    unawaited(_dispatch(command, generation: generation, now: now));
  }

  Future<void> _dispatch(
    FeedbackCommand command, {
    required int generation,
    required DateTime now,
  }) async {
    _dispatchingActionId = command.actionId;
    final result = await dispatcher.dispatch(command, output: output, now: now);
    if (generation != _deliveryGeneration) return;
    _record(
      now,
      result.dropped
          ? FeedbackDeliveryEventType.failed
          : FeedbackDeliveryEventType.delivered,
      command,
      result.reason,
    );
    if (!result.dropped) {
      await output.awaitCompletion(command);
      if (generation != _deliveryGeneration) return;
    }
    _dispatchingActionId = null;
    _record(
      DateTime.now(),
      FeedbackDeliveryEventType.completed,
      command,
      result.dropped ? 'delivery_failed_complete' : 'output_complete',
    );
    final next = arbiter.completeCurrent(now: DateTime.now());
    if (next == null) return;
    _record(
      DateTime.now(),
      FeedbackDeliveryEventType.promoted,
      next,
      'promote_exactly_one_pending',
    );
    final nextGeneration = ++_deliveryGeneration;
    unawaited(_dispatch(next, generation: nextGeneration, now: DateTime.now()));
  }

  void _record(
    DateTime at,
    FeedbackDeliveryEventType type,
    FeedbackCommand command,
    String reason,
  ) {
    if (_traces.length >= maxTraceEntries) _traces.removeAt(0);
    _traces.add(
      FeedbackDeliveryTrace(
        at: at,
        type: type,
        actionId: command.actionId,
        reason: reason,
        source: command.source,
      ),
    );
  }
}
