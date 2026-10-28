import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/core/performance/perception_scheduler.dart';

import '../tool/model_benchmark/independent_replay_feed.dart';
import '../tool/model_benchmark/replay_depth_load_lane.dart';

PerceptionFrameIdentity identity(
  int frame,
  int captured,
  int Function() clock, {
  int generation = 1,
}) => PerceptionFrameIdentity(
  generation: generation,
  frameNumber: frame,
  width: 384,
  height: 288,
  rotationDegrees: 0,
  mirrored: false,
  timing: CallbackFrameTiming.forTesting(captured, () => clock() - captured),
);

void main() {
  testWidgets(
    'capture feed advances while fast results and depth inference are unresolved',
    (tester) async {
      final clockStart = tester.binding.clock.now();
      int clock() =>
          1000000 +
          tester.binding.clock.now().difference(clockStart).inMicroseconds;
      final nn = Completer<Map>();
      final releases = <Completer<void>>[];
      final arrivals = <int>[];
      final lane = ReplayDepthLoadLane(
        infer: (_, _) => nn.future,
        clockUs: clock,
      )..beginSession(1);
      var finished = false;
      feedIndependentCaptures(
        frames: [1, 2, 3],
        capturedAtUs: (int frame) => 1000000 + (frame - 1) * 200000,
        clockUs: clock,
        onCapture: (int frame) {
          arrivals.add(clock());
          lane.offer(
            'layout',
            identity(frame, 1000000 + (frame - 1) * 200000, clock),
          );
          final release = Completer<void>();
          releases.add(release);
          return release.future;
        },
      ).then((_) => finished = true);
      await tester.pump(const Duration(microseconds: 402000));
      expect(arrivals, [1002000, 1202000, 1402000]);
      expect(lane.jobs.length, 1);
      expect(lane.skipped, 2);
      expect(lane.scheduler.queuedFrames, 0);
      expect(nn.isCompleted, false);
      expect(finished, false);
      for (final release in releases) {
        release.complete();
      }
      await tester.pump();
      expect(finished, true);
      expect(nn.isCompleted, false);
      nn.complete({'outputMatchesPinned': true});
      await tester.pump();
      expect(lane.busy, false);
    },
  );

  test(
    'depth starts only on a new capture after completion, with no old pending frame',
    () async {
      var now = 1002000;
      final gates = <Completer<Map>>[];
      final started = <int>[];
      final lane = ReplayDepthLoadLane(
        infer: (_, frame) {
          started.add(frame);
          final c = Completer<Map>();
          gates.add(c);
          return c.future;
        },
        clockUs: () => now,
      )..beginSession(1);
      lane.offer('layout', identity(1, 1000000, () => now));
      now = 1202000;
      expect(lane.offer('layout', identity(2, 1200000, () => now)), isNull);
      gates.first.complete({'outputMatchesPinned': true});
      await lane.drain();
      expect(started, [1]);
      now = 1402000;
      final job = lane.offer('layout', identity(3, 1400000, () => now))!;
      expect(started, [1, 3]);
      gates.last.complete({'outputMatchesPinned': true});
      await lane.drain();
      expect(job.status, 'validated_load_only');
      expect(lane.maximumActive, 1);
      expect(lane.scheduler.activeCount, 0);
    },
  );

  test(
    'inference failure is surfaced by drain and prevents subsequent offers',
    () async {
      var now = 1002000;
      final gate = Completer<Map>();
      final lane = ReplayDepthLoadLane(
        infer: (_, _) => gate.future,
        clockUs: () => now,
      )..beginSession(1);
      final job = lane.offer('layout', identity(1, 1000000, () => now))!;
      gate.completeError(StateError('pinned output drift'));
      await expectLater(lane.drain(), throwsStateError);
      expect(job.status, 'failed');
      expect(lane.busy, false);
      expect(lane.scheduler.activeCount, 0);
      now = 1202000;
      expect(
        () => lane.offer('layout', identity(2, 1200000, () => now)),
        throwsStateError,
      );
    },
  );

  test(
    'session change and stale NN output never become validated sensing',
    () async {
      var now = 1002000;
      final gate = Completer<Map>();
      final lane = ReplayDepthLoadLane(
        infer: (_, _) => gate.future,
        clockUs: () => now,
      )..beginSession(1);
      final job = lane.offer('layout', identity(1, 1000000, () => now))!;
      lane.beginSession(2);
      now = 3500000;
      gate.complete({'outputMatchesPinned': true});
      await lane.drain();
      expect(job.status, 'session_or_ownership_mismatch');
      expect(lane.scheduler.activeCount, 0);
    },
  );

  testWidgets('late replay callbacks retain original timestamps', (
    tester,
  ) async {
    final clockStart = tester.binding.clock.now();
    int clock() =>
        1000000 +
        tester.binding.clock.now().difference(clockStart).inMicroseconds;
    final captured = <int>[];
    final ages = <int>[];
    await tester.pump(const Duration(milliseconds: 150));
    feedIndependentCaptures(
      frames: [1000000, 1200000],
      capturedAtUs: (int frame) => frame,
      clockUs: clock,
      onCapture: (int frame) async {
        captured.add(frame);
        ages.add(clock() - frame);
      },
    );
    await tester.pump(const Duration(milliseconds: 52));
    expect(captured, [1000000, 1200000]);
    expect(ages, [150000, 2000]);
  });

  test(
    'unordered timestamps reject the entire feed before launching work',
    () async {
      var calls = 0;
      await expectLater(
        feedIndependentCaptures(
          frames: [1000000, 999999],
          capturedAtUs: (int frame) => frame,
          clockUs: () => 1002000,
          onCapture: (_) async {
            calls++;
          },
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );

  testWidgets('capture failure cancels remaining scheduled callbacks', (
    tester,
  ) async {
    final clockStart = tester.binding.clock.now();
    int clock() =>
        1000000 +
        tester.binding.clock.now().difference(clockStart).inMicroseconds;
    final called = <int>[];
    final failure = expectLater(
      feedIndependentCaptures(
        frames: [1000000, 1200000],
        capturedAtUs: (int frame) => frame,
        clockUs: clock,
        onCapture: (int frame) async {
          called.add(frame);
          throw StateError('provider unavailable');
        },
      ),
      throwsStateError,
    );
    await tester.pump(const Duration(milliseconds: 2));
    await failure;
    await tester.pump(const Duration(milliseconds: 300));
    expect(called, [1000000]);
  });

  test('stale depth output clears its slot and remains rejected', () async {
    var now = 1002000;
    final gate = Completer<Map>();
    final lane = ReplayDepthLoadLane(
      infer: (_, _) => gate.future,
      clockUs: () => now,
    )..beginSession(1);
    final job = lane.offer('layout', identity(1, 1000000, () => now))!;
    now = 3000001;
    gate.complete({'outputMatchesPinned': true});
    await lane.drain();
    expect(job.status, 'stale_result');
    expect(lane.busy, false);
    expect(lane.scheduler.activeCount, 0);
  });

  test(
    'completion clock failure is joined and cannot leave an active slot',
    () async {
      var clockFailed = false;
      int clock() {
        if (clockFailed) {
          throw StateError('clock failed');
        }
        return 1002000;
      }

      final gate = Completer<Map>();
      final lane = ReplayDepthLoadLane(
        infer: (_, _) => gate.future,
        clockUs: clock,
      )..beginSession(1);
      final job = lane.offer('layout', identity(1, 1000000, clock))!;
      clockFailed = true;
      gate.complete({'outputMatchesPinned': true});
      await expectLater(lane.drain(), throwsStateError);
      expect(job.status, 'failed');
      expect(lane.busy, false);
      expect(lane.scheduler.activeCount, 0);
    },
  );
}
