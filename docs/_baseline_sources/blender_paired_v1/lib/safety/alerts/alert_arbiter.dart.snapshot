import '../../core/core_health.dart';
import '../planning/safety_action.dart';
import 'feedback_command.dart';
import 'feedback_policy.dart';

enum AlertArbiterEventType { emitted, queued, replaced, suppressed, dropped }

class AlertArbiterEvent {
  final AlertArbiterEventType type;
  final FeedbackCommand? command;
  final String reason;
  final bool interruptCurrent;
  final String? replacedActionId;

  const AlertArbiterEvent({
    required this.type,
    required this.command,
    required this.reason,
    this.interruptCurrent = false,
    this.replacedActionId,
  });
}

class AlertArbiterTrace {
  final DateTime at;
  final AlertArbiterEventType type;
  final String actionId;
  final String reason;
  final String? replaceKey;
  final SafetyPriority? priority;

  const AlertArbiterTrace({
    required this.at,
    required this.type,
    required this.actionId,
    required this.reason,
    this.replaceKey,
    this.priority,
  });
}

/// Single admission point for spatial, health, emergency and on-demand
/// feedback. Risk is supplied by typed inputs and is never recomputed here.
class AlertArbiter {
  final FeedbackPolicy feedbackPolicy;
  final int maxBufferedCommands;
  final int maxTraceEntries;
  final Duration repeatCooldown;

  FeedbackCommand? _active;
  FeedbackCommand? _lastCritical;
  final List<FeedbackCommand> _pending = <FeedbackCommand>[];
  final List<AlertArbiterTrace> _traces = <AlertArbiterTrace>[];
  final Map<String, DateTime> _lastAcceptedAt = <String, DateTime>{};
  final Map<String, FeedbackCommand> _lastAcceptedByKey =
      <String, FeedbackCommand>{};

  AlertArbiter({
    this.feedbackPolicy = const FeedbackPolicy(),
    this.maxBufferedCommands = 4,
    this.maxTraceEntries = 128,
    this.repeatCooldown = const Duration(seconds: 2),
  }) : assert(maxBufferedCommands >= 1),
       assert(maxTraceEntries >= 1),
       assert(!repeatCooldown.isNegative);

  FeedbackCommand? get active => _active;
  FeedbackCommand? get lastCritical => _lastCritical;
  List<FeedbackCommand> get pending => List.unmodifiable(_pending);
  List<AlertArbiterTrace> get traces => List.unmodifiable(_traces);
  int get bufferedCount => (_active == null ? 0 : 1) + _pending.length;

  /// Drops session-owned commands and cooldown identities. Spatial actions
  /// from an old camera generation must never be promoted after restart.
  void reset() {
    _active = null;
    _lastCritical = null;
    _pending.clear();
    _traces.clear();
    _lastAcceptedAt.clear();
    _lastAcceptedByKey.clear();
  }

  AlertArbiterEvent submitAction(SafetyAction action, {required DateTime now}) {
    if (action.isExpiredAt(now)) {
      return _event(
        type: AlertArbiterEventType.dropped,
        command: null,
        reason: 'expired_action',
        actionId: action.actionId,
        now: now,
      );
    }
    final command = feedbackPolicy.commandFor(action);
    if (command == null) {
      return _event(
        type: AlertArbiterEventType.suppressed,
        command: null,
        reason: action.isShadowOnly
            ? 'shadow_action_not_deliverable'
            : 'silent_continue_forward',
        actionId: action.actionId,
        now: now,
      );
    }
    return _admit(command, now: now);
  }

  AlertArbiterEvent submitHealth(
    CoreHealthSnapshot snapshot, {
    required bool userMoving,
    required DateTime now,
  }) {
    final command = feedbackPolicy.commandForHealth(
      snapshot,
      userMoving: userMoving,
      now: now,
    );
    if (command == null) {
      return _event(
        type: AlertArbiterEventType.suppressed,
        command: null,
        reason: 'healthy_snapshot_no_feedback',
        actionId: 'health-${snapshot.at.microsecondsSinceEpoch}',
        now: now,
      );
    }
    return _admit(command, now: now);
  }

  AlertArbiterEvent submitEmergency(
    FeedbackCommand command, {
    required DateTime now,
  }) {
    if (command.source != FeedbackCommandSource.emergency ||
        command.priority != SafetyPriority.p0Emergency) {
      throw ArgumentError(
        'Emergency admission requires an emergency-source P0 command.',
      );
    }
    return _admit(command, now: now);
  }

  AlertArbiterEvent submitOnDemand(
    FeedbackCommand command, {
    required DateTime now,
  }) {
    if (command.source != FeedbackCommandSource.onDemand) {
      throw ArgumentError(
        'On-demand admission requires an onDemand-source command.',
      );
    }
    return _admit(command, now: now);
  }

  /// Admission for already-typed non-emergency safety commands such as
  /// object, depth, and camera-health alerts.
  AlertArbiterEvent admitTyped(
    FeedbackCommand command, {
    required DateTime now,
  }) {
    if (command.source == FeedbackCommandSource.emergency ||
        command.source == FeedbackCommandSource.onDemand ||
        command.source == FeedbackCommandSource.coreHealth) {
      throw ArgumentError('Use the source-specific admission method.');
    }
    return _admit(command, now: now);
  }

  AlertArbiterEvent _admit(FeedbackCommand command, {required DateTime now}) {
    purgeExpired(now);
    if (command.isExpiredAt(now)) {
      return _eventForCommand(
        type: AlertArbiterEventType.dropped,
        command: command,
        reason: 'expired_command',
        now: now,
      );
    }

    final current = _active;
    if (current != null && current.replaceKey == command.replaceKey) {
      return _handleSameIdentity(current, command, now);
    }

    if (current == null) {
      _accept(command, now);
      _active = command;
      return _eventForCommand(
        type: AlertArbiterEventType.emitted,
        command: command,
        reason: 'idle_emit',
        now: now,
      );
    }

    if (command.priority == SafetyPriority.p0Emergency) {
      if (current.priority != SafetyPriority.p0Emergency) {
        _dropPendingLowerThanP0(now);
        _recordCommand(
          now,
          AlertArbiterEventType.dropped,
          current,
          'p0_preempted_active_lower_priority',
        );
        _active = command;
        _accept(command, now);
        return _eventForCommand(
          type: AlertArbiterEventType.emitted,
          command: command,
          reason: 'p0_preempts_lower_priority',
          now: now,
          interruptCurrent: true,
          replacedActionId: current.actionId,
        );
      }
      return _handleIndependentP0(current, command, now);
    }

    final prior = _lastAcceptedByKey[command.replaceKey];
    final priorAt = _lastAcceptedAt[command.replaceKey];
    if (prior != null &&
        priorAt != null &&
        now.difference(priorAt) < repeatCooldown &&
        !command.isMeaningfulEscalationOver(prior)) {
      return _eventForCommand(
        type: AlertArbiterEventType.suppressed,
        command: command,
        reason: 'repeat_cooldown_same_response',
        now: now,
      );
    }

    final replaceIndex = _pending.indexWhere(
      (candidate) => candidate.replaceKey == command.replaceKey,
    );
    if (replaceIndex >= 0) {
      final replaced = _pending[replaceIndex];
      if (!command.isMeaningfulEscalationOver(replaced)) {
        return _eventForCommand(
          type: AlertArbiterEventType.suppressed,
          command: command,
          reason: 'pending_same_hazard_not_escalated',
          now: now,
        );
      }
      _pending[replaceIndex] = command;
      _sortPending();
      _accept(command, now);
      return _eventForCommand(
        type: AlertArbiterEventType.replaced,
        command: command,
        reason: 'replace_pending_same_hazard_escalated',
        now: now,
        replacedActionId: replaced.actionId,
      );
    }

    return _enqueue(command, now: now);
  }

  AlertArbiterEvent _handleSameIdentity(
    FeedbackCommand current,
    FeedbackCommand incoming,
    DateTime now,
  ) {
    if (!incoming.isMeaningfulEscalationOver(current)) {
      final lastAcceptedAt = _lastAcceptedAt[incoming.replaceKey];
      if (lastAcceptedAt != null &&
          now.difference(lastAcceptedAt) >= repeatCooldown) {
        _active = incoming;
        _accept(incoming, now);
        return _eventForCommand(
          type: AlertArbiterEventType.replaced,
          command: incoming,
          reason: 'replace_active_after_repeat_cooldown',
          now: now,
          interruptCurrent: incoming.canInterrupt,
          replacedActionId: current.actionId,
        );
      }
      return _eventForCommand(
        type: AlertArbiterEventType.suppressed,
        command: incoming,
        reason: 'active_same_hazard_not_escalated',
        now: now,
      );
    }
    _active = incoming;
    _accept(incoming, now);
    return _eventForCommand(
      type: AlertArbiterEventType.replaced,
      command: incoming,
      reason: 'replace_active_same_hazard_escalated',
      now: now,
      interruptCurrent: incoming.canInterrupt,
      replacedActionId: current.actionId,
    );
  }

  AlertArbiterEvent _handleIndependentP0(
    FeedbackCommand current,
    FeedbackCommand incoming,
    DateTime now,
  ) {
    if (current.hasSameResponseAs(incoming)) {
      final merged = current.mergeHazards(incoming);
      _active = merged;
      _lastCritical = merged;
      _lastAcceptedAt[incoming.replaceKey] = now;
      _lastAcceptedByKey[incoming.replaceKey] = incoming;
      return _eventForCommand(
        type: AlertArbiterEventType.suppressed,
        command: incoming,
        reason: 'independent_p0_same_response_covered',
        now: now,
      );
    }

    if (incoming.urgency > current.urgency) {
      if (_makeRoomFor(incoming, now)) {
        _pending.add(current);
        _sortPending();
      } else {
        _recordCommand(
          now,
          AlertArbiterEventType.dropped,
          current,
          'bounded_queue_could_not_preserve_less_urgent_active_p0',
        );
      }
      _active = incoming;
      _accept(incoming, now);
      return _eventForCommand(
        type: AlertArbiterEventType.emitted,
        command: incoming,
        reason: 'more_urgent_independent_p0_preempts',
        now: now,
        interruptCurrent: true,
        replacedActionId: current.actionId,
      );
    }

    return _enqueue(
      incoming,
      now: now,
      reason: 'independent_p0_different_response_queued',
    );
  }

  AlertArbiterEvent _enqueue(
    FeedbackCommand command, {
    required DateTime now,
    String reason = 'queued_behind_active',
  }) {
    if (!_makeRoomFor(command, now)) {
      return _eventForCommand(
        type: AlertArbiterEventType.dropped,
        command: command,
        reason: 'bounded_queue_drop_incoming',
        now: now,
      );
    }
    _pending.add(command);
    _sortPending();
    _accept(command, now);
    return _eventForCommand(
      type: AlertArbiterEventType.queued,
      command: command,
      reason: reason,
      now: now,
    );
  }

  FeedbackCommand? completeCurrent({required DateTime now}) {
    _active = null;
    purgeExpired(now, promotePending: false);
    if (_pending.isEmpty) return null;
    _active = _pending.removeAt(0);
    _recordCommand(
      now,
      AlertArbiterEventType.emitted,
      _active!,
      'emit_next_pending',
    );
    return _active;
  }

  void purgeExpired(DateTime now, {bool promotePending = true}) {
    final active = _active;
    if (active != null && active.isExpiredAt(now)) {
      _recordCommand(
        now,
        AlertArbiterEventType.dropped,
        active,
        'purge_expired_active',
      );
      _active = null;
    }
    final expired = _pending
        .where((command) => command.isExpiredAt(now))
        .toList(growable: false);
    _pending.removeWhere((command) => command.isExpiredAt(now));
    for (final command in expired) {
      _recordCommand(
        now,
        AlertArbiterEventType.dropped,
        command,
        'purge_expired_pending',
      );
    }
    if (promotePending && _active == null && _pending.isNotEmpty) {
      _sortPending();
      _active = _pending.removeAt(0);
      _recordCommand(
        now,
        AlertArbiterEventType.emitted,
        _active!,
        'promote_pending_after_active_expiry',
      );
    }
  }

  void _dropPendingLowerThanP0(DateTime now) {
    final dropped = _pending
        .where((candidate) => candidate.priority != SafetyPriority.p0Emergency)
        .toList(growable: false);
    _pending.removeWhere(
      (candidate) => candidate.priority != SafetyPriority.p0Emergency,
    );
    for (final command in dropped) {
      _recordCommand(
        now,
        AlertArbiterEventType.dropped,
        command,
        'p0_preemption_purged_lower_priority_pending',
      );
    }
  }

  bool _makeRoomFor(FeedbackCommand incoming, DateTime now) {
    if (bufferedCount < maxBufferedCommands) return true;
    if (_pending.isEmpty) return false;

    var evictionIndex = -1;
    for (var i = _pending.length - 1; i >= 0; i--) {
      final candidate = _pending[i];
      final lowerPriority = candidate.priority.index < incoming.priority.index;
      final lessUrgentP0 =
          candidate.priority == SafetyPriority.p0Emergency &&
          incoming.priority == SafetyPriority.p0Emergency &&
          candidate.urgency < incoming.urgency;
      if (lowerPriority || lessUrgentP0) {
        evictionIndex = i;
        break;
      }
    }
    if (evictionIndex < 0) return false;

    final evicted = _pending.removeAt(evictionIndex);
    _recordCommand(
      now,
      AlertArbiterEventType.dropped,
      evicted,
      'bounded_queue_evict_for_${incoming.priority.name}',
    );
    return true;
  }

  void _accept(FeedbackCommand command, DateTime now) {
    _lastAcceptedAt[command.replaceKey] = now;
    _lastAcceptedByKey[command.replaceKey] = command;
    if (command.priority == SafetyPriority.p0Emergency) {
      _lastCritical = command;
    }
  }

  void _sortPending() {
    _pending.sort((a, b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      final byUrgency = b.urgency.compareTo(a.urgency);
      if (byUrgency != 0) return byUrgency;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  AlertArbiterEvent _eventForCommand({
    required AlertArbiterEventType type,
    required FeedbackCommand command,
    required String reason,
    required DateTime now,
    bool interruptCurrent = false,
    String? replacedActionId,
  }) => _event(
    type: type,
    command: command,
    reason: reason,
    actionId: command.actionId,
    now: now,
    interruptCurrent: interruptCurrent,
    replacedActionId: replacedActionId,
  );

  AlertArbiterEvent _event({
    required AlertArbiterEventType type,
    required FeedbackCommand? command,
    required String reason,
    required String actionId,
    required DateTime now,
    bool interruptCurrent = false,
    String? replacedActionId,
  }) {
    _record(
      now,
      type,
      actionId,
      reason,
      replaceKey: command?.replaceKey,
      priority: command?.priority,
    );
    return AlertArbiterEvent(
      type: type,
      command: command,
      reason: reason,
      interruptCurrent: interruptCurrent,
      replacedActionId: replacedActionId,
    );
  }

  void _recordCommand(
    DateTime now,
    AlertArbiterEventType type,
    FeedbackCommand command,
    String reason,
  ) => _record(
    now,
    type,
    command.actionId,
    reason,
    replaceKey: command.replaceKey,
    priority: command.priority,
  );

  void _record(
    DateTime now,
    AlertArbiterEventType type,
    String actionId,
    String reason, {
    String? replaceKey,
    SafetyPriority? priority,
  }) {
    if (_traces.length >= maxTraceEntries) {
      _traces.removeAt(0);
    }
    _traces.add(
      AlertArbiterTrace(
        at: now,
        type: type,
        actionId: actionId,
        reason: reason,
        replaceKey: replaceKey,
        priority: priority,
      ),
    );
  }
}
