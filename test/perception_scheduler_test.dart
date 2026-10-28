import 'dart:async';

import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/core/performance/perception_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

PerceptionFrameIdentity _frame(
  int number, {
  int generation = 1,
  int ageUs = 0,
}) => PerceptionFrameIdentity(
  generation: generation,
  frameNumber: number,
  width: 320,
  height: 240,
  rotationDegrees: 90,
  mirrored: false,
  timing: CallbackFrameTiming.forTesting(number * 33000, () => ageUs),
);

String? _reject(
  PerceptionScheduler scheduler,
  PerceptionTicket ticket, {
  int generation = 1,
  int width = 320,
  int rotation = 90,
  bool mirrored = false,
}) => scheduler.rejectionFor(
  ticket,
  generation: generation,
  width: width,
  height: 240,
  rotationDegrees: rotation,
  mirrored: mirrored,
);

void main() {
  test(
    'depth starts on next fresh callback before pending YOLO completes',
    () async {
      final scheduler = PerceptionScheduler()..beginSession(1);
      final yoloReply = Completer<void>();
      final yolo = scheduler.tryStart(
        frame: _frame(1),
        yoloDue: true,
        depthDue: true,
      )!;
      expect(yolo.lane, PerceptionLane.yolo);
      final pendingYolo = yoloReply.future.whenComplete(
        () => scheduler.finish(yolo),
      );
      expect(
        scheduler.tryStart(frame: _frame(1), yoloDue: true, depthDue: true),
        isNull,
      );
      final depth = scheduler.tryStart(
        frame: _frame(2),
        yoloDue: true,
        depthDue: true,
      )!;
      expect(depth.lane, PerceptionLane.depth);
      expect(depth.frame.timing.callbackTimestampUs, 66000);
      expect(yoloReply.isCompleted, isFalse);
      expect(scheduler.activeCount, 2);
      scheduler.finish(depth);
      yoloReply.complete();
      await pendingYolo;
      expect(scheduler.activeCount, 0);
    },
  );

  test('YOLO unavailable or faulted does not prevent depth', () {
    final scheduler = PerceptionScheduler()..beginSession(1);
    final depth = scheduler.tryStart(
      frame: _frame(1),
      yoloDue: false,
      depthDue: true,
    )!;
    expect(depth.lane, PerceptionLane.depth);
    scheduler.finish(depth);
    final yolo = scheduler.tryStart(
      frame: _frame(2),
      yoloDue: true,
      depthDue: false,
    )!;
    scheduler.finish(yolo); // same finally path on a failed native Future
    expect(
      scheduler
          .tryStart(frame: _frame(3), yoloDue: false, depthDue: true)
          ?.lane,
      PerceptionLane.depth,
    );
  });

  test(
    'busy callback burst retains no frames and does not supersede active work',
    () {
      final scheduler = PerceptionScheduler()..beginSession(1);
      final yolo = scheduler.tryStart(
        frame: _frame(1),
        yoloDue: true,
        depthDue: true,
      )!;
      final depth = scheduler.tryStart(
        frame: _frame(2),
        yoloDue: true,
        depthDue: true,
      )!;
      for (var i = 3; i <= 10000; i++) {
        expect(
          scheduler.tryStart(frame: _frame(i), yoloDue: true, depthDue: true),
          isNull,
        );
      }
      expect(scheduler.queuedFrames, 0);
      expect(scheduler.activeCount, 2);
      expect(_reject(scheduler, yolo), isNull);
      expect(_reject(scheduler, depth), isNull);
    },
  );

  test('due lanes alternate without starving either model', () {
    final scheduler = PerceptionScheduler()..beginSession(1);
    final starts = <PerceptionLane>[];
    for (var i = 1; i <= 8; i++) {
      final ticket = scheduler.tryStart(
        frame: _frame(i),
        yoloDue: true,
        depthDue: true,
      )!;
      starts.add(ticket.lane);
      scheduler.finish(ticket);
    }
    expect(starts, [
      for (var i = 0; i < 4; i++) ...[
        PerceptionLane.yolo,
        PerceptionLane.depth,
      ],
    ]);
    expect(
      scheduler.tryStart(frame: _frame(9), yoloDue: false, depthDue: false),
      isNull,
    );
  });

  test(
    'background/restart invalidates results without releasing native ownership',
    () {
      final scheduler = PerceptionScheduler()..beginSession(1);
      final old = scheduler.tryStart(
        frame: _frame(1),
        yoloDue: true,
        depthDue: false,
      )!;
      scheduler.suspend();
      expect(scheduler.acceptsFrames(1), isFalse);
      expect(_reject(scheduler, old), 'session_or_ownership_mismatch');
      expect(
        scheduler.tryStart(frame: _frame(2), yoloDue: false, depthDue: true),
        isNull,
      );
      scheduler.beginSession(2);
      expect(scheduler.acceptsFrames(1), isFalse);
      expect(scheduler.acceptsFrames(2), isTrue);
      expect(
        scheduler.tryStart(
          frame: _frame(1, generation: 2),
          yoloDue: true,
          depthDue: false,
        ),
        isNull,
      );
      expect(
        _reject(scheduler, old, generation: 2),
        'session_or_ownership_mismatch',
      );
      scheduler.finish(old);
      final current = scheduler.tryStart(
        frame: _frame(2, generation: 2),
        yoloDue: true,
        depthDue: false,
      )!;
      scheduler.finish(old);
      expect(_reject(scheduler, current, generation: 2), isNull);
      expect(scheduler.activeCount, 1);
    },
  );

  test(
    'expired, future, changed-transform and released results cannot mutate state',
    () {
      var age = 0;
      final scheduler = PerceptionScheduler()..beginSession(1);
      final frame = PerceptionFrameIdentity(
        generation: 1,
        frameNumber: 1,
        width: 320,
        height: 240,
        rotationDegrees: 90,
        mirrored: false,
        timing: CallbackFrameTiming.forTesting(33000, () => age),
      );
      final ticket = scheduler.tryStart(
        frame: frame,
        yoloDue: true,
        depthDue: false,
      )!;
      expect(_reject(scheduler, ticket, width: 640), 'transform_mismatch');
      expect(_reject(scheduler, ticket, rotation: 0), 'transform_mismatch');
      expect(_reject(scheduler, ticket, mirrored: true), 'transform_mismatch');
      age = -1;
      expect(_reject(scheduler, ticket), 'clock_mismatch');
      age = 2000001;
      expect(_reject(scheduler, ticket), 'stale_result');
      expect(scheduler.activeCount, 1);
      scheduler.finish(ticket);
      age = 1;
      expect(_reject(scheduler, ticket), 'session_or_ownership_mismatch');
      expect(
        scheduler.tryStart(
          frame: _frame(2, ageUs: 2000001),
          yoloDue: true,
          depthDue: true,
        ),
        isNull,
      );
      expect(
        scheduler.tryStart(
          frame: _frame(3, ageUs: -1),
          yoloDue: true,
          depthDue: true,
        ),
        isNull,
      );
    },
  );
}
