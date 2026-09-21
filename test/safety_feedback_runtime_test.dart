import 'dart:async';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/safety/alerts/alert_arbiter.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/alerts/feedback_dispatcher.dart';
import 'package:bagdar/safety/alerts/haptic_policy.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/safety_feedback_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledOutput implements FeedbackOutputPort {
  @override
  bool ttsAvailable = true;
  @override
  bool hapticAvailable = true;
  @override
  bool earconAvailable = true;
  @override
  HapticDeviceCapabilities hapticCapabilities = const HapticDeviceCapabilities(
    hasVibrator: true,
    hasAmplitudeControl: true,
  );

  final List<String> spoken = <String>[];
  final List<FeedbackEarcon> earcons = <FeedbackEarcon>[];
  final List<HapticCue> haptics = <HapticCue>[];
  final Map<String, Completer<void>> completions = <String, Completer<void>>{};
  int interrupts = 0;

  @override
  Future<bool> speak(FeedbackCommand command) async {
    spoken.add(command.actionId);
    completions.putIfAbsent(command.actionId, Completer<void>.new);
    return true;
  }

  @override
  Future<bool> playEarcon(FeedbackEarcon earcon) async {
    earcons.add(earcon);
    return true;
  }

  @override
  Future<bool> vibrate(HapticCue cue) async {
    haptics.add(cue);
    return true;
  }

  @override
  Future<void> awaitCompletion(FeedbackCommand command) async {
    await completions.putIfAbsent(command.actionId, Completer<void>.new).future;
  }

  @override
  Future<void> interruptCurrent() async {
    interrupts++;
    for (final completer in completions.values) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  void complete(String actionId) {
    final completer = completions[actionId];
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}

FeedbackCommand _command(
  DateTime now, {
  required String id,
  required String key,
  required FeedbackCommandSource source,
  SafetyPriority priority = SafetyPriority.p3Information,
  SafetyActionKind? kind,
  CorridorDirection? direction,
  double urgency = 0.3,
  bool? canInterrupt,
}) => FeedbackCommand(
  actionId: id,
  sceneRevision: -1,
  speechKey: 'generic_obstacle_ahead',
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
  canInterrupt: canInterrupt ?? priority == SafetyPriority.p0Emergency,
  replaceKey: key,
  createdAt: now,
  expiresAt: now.add(const Duration(seconds: 5)),
  ruleId: 'TEST-${priority.name}',
  hazardIds: <String>[key],
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('object P0 interrupts active informational speech', () async {
    final now = DateTime.now();
    final output = _ControlledOutput();
    final runtime = SafetyFeedbackRuntime(
      arbiter: AlertArbiter(),
      dispatcher: FeedbackDispatcher(
        healthCoordinator: CoreHealthCoordinator(),
      ),
      output: output,
    );

    runtime.submitCommand(
      _command(
        now,
        id: 'info',
        key: 'on-demand:info',
        source: FeedbackCommandSource.onDemand,
      ),
      now: now,
    );
    await _settle();
    runtime.submitCommand(
      _command(
        now.add(const Duration(milliseconds: 10)),
        id: 'object-stop',
        key: 'object:7',
        source: FeedbackCommandSource.objectHazard,
        priority: SafetyPriority.p0Emergency,
        kind: SafetyActionKind.stopNow,
        urgency: 1,
      ),
      now: now.add(const Duration(milliseconds: 10)),
    );
    await _settle();

    expect(output.interrupts, 1);
    expect(output.spoken, containsAllInOrder(<String>['info', 'object-stop']));
    expect(runtime.arbiter.active?.actionId, 'object-stop');
  });

  test('depth P0 preempts object warning across sources', () async {
    final now = DateTime.now();
    final output = _ControlledOutput();
    final runtime = SafetyFeedbackRuntime(
      arbiter: AlertArbiter(),
      dispatcher: FeedbackDispatcher(
        healthCoordinator: CoreHealthCoordinator(),
      ),
      output: output,
    );
    runtime.submitCommand(
      _command(
        now,
        id: 'object-warning',
        key: 'object:3',
        source: FeedbackCommandSource.objectHazard,
        priority: SafetyPriority.p1Correction,
        urgency: 0.6,
      ),
      now: now,
    );
    await _settle();
    runtime.submitCommand(
      _command(
        now.add(const Duration(milliseconds: 5)),
        id: 'depth-stop',
        key: 'depth:stepDown',
        source: FeedbackCommandSource.depthHazard,
        priority: SafetyPriority.p0Emergency,
        kind: SafetyActionKind.stopNow,
        urgency: 0.95,
      ),
      now: now.add(const Duration(milliseconds: 5)),
    );
    await _settle();

    expect(output.interrupts, 1);
    expect(runtime.arbiter.active?.actionId, 'depth-stop');
  });

  test('completion promotes exactly one pending independent P0', () async {
    final now = DateTime.now();
    final output = _ControlledOutput();
    final runtime = SafetyFeedbackRuntime(
      arbiter: AlertArbiter(),
      dispatcher: FeedbackDispatcher(
        healthCoordinator: CoreHealthCoordinator(),
      ),
      output: output,
    );
    runtime.submitCommand(
      _command(
        now,
        id: 'left-stop',
        key: 'hazard:left',
        source: FeedbackCommandSource.emergency,
        priority: SafetyPriority.p0Emergency,
        kind: SafetyActionKind.stopNow,
        direction: CorridorDirection.left,
        urgency: 0.9,
      ),
      now: now,
    );
    await _settle();
    runtime.submitCommand(
      _command(
        now.add(const Duration(milliseconds: 5)),
        id: 'right-stop',
        key: 'hazard:right',
        source: FeedbackCommandSource.emergency,
        priority: SafetyPriority.p0Emergency,
        kind: SafetyActionKind.stopNow,
        direction: CorridorDirection.right,
        urgency: 0.8,
      ),
      now: now.add(const Duration(milliseconds: 5)),
    );
    await _settle();
    expect(runtime.arbiter.pending, hasLength(1));

    output.complete('left-stop');
    await _settle();
    await _settle();

    expect(output.spoken.where((id) => id == 'right-stop'), hasLength(1));
    expect(runtime.arbiter.active?.actionId, 'right-stop');
    expect(runtime.arbiter.pending, isEmpty);
  });

  test('session reset drops pending commands and bounds trace', () async {
    final now = DateTime.now();
    final output = _ControlledOutput();
    final runtime = SafetyFeedbackRuntime(
      arbiter: AlertArbiter(maxBufferedCommands: 4),
      dispatcher: FeedbackDispatcher(
        healthCoordinator: CoreHealthCoordinator(),
      ),
      output: output,
      maxTraceEntries: 8,
    );
    for (var i = 0; i < 10; i++) {
      runtime.submitCommand(
        _command(
          now.add(Duration(milliseconds: i)),
          id: 'object-$i',
          key: 'object:$i',
          source: FeedbackCommandSource.objectHazard,
          priority: SafetyPriority.p1Correction,
          urgency: 0.5,
        ),
        now: now.add(Duration(milliseconds: i)),
      );
    }
    await _settle();
    expect(runtime.arbiter.bufferedCount, lessThanOrEqualTo(4));

    await runtime.resetSession(now: now.add(const Duration(seconds: 1)));
    expect(runtime.arbiter.bufferedCount, 0);
    expect(runtime.dispatchingActionId, isNull);
    expect(runtime.traces.length, lessThanOrEqualTo(8));
    expect(runtime.traces.last.reason, 'session_reset');
  });
}
