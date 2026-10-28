import 'dart:async';

import 'package:bagdar/core/performance/perception_scheduler.dart';

/// Diagnostic job only. It never supplies depth, identity or authority to the
/// fast-motion worker. Completed model output is kept for load validation.
class ReplayDepthLoadJob {
  final String layoutId;
  final PerceptionFrameIdentity frame;
  final int startedAtUs;
  final _done = Completer<void>();
  int? completedAtUs;
  Map? output;
  String status = 'running';

  ReplayDepthLoadJob(this.layoutId, this.frame, this.startedAtUs);
  Future<void> get done => _done.future;

  Map<String, Object?> toMap() => {
    'layoutId': layoutId,
    'frameId': frame.frameNumber,
    'capturedAtUs': frame.timing.callbackTimestampUs,
    'startedAtUs': startedAtUs,
    'completedAtUs': completedAtUs,
    'status': status,
    'output': output,
  };
}

/// Uses the app's depth-lane admission: one active call and no retained queue.
/// Busy captures are skipped; inference completion never gates frame delivery.
class ReplayDepthLoadLane {
  final Future<Map> Function(String layoutId, int frameId) infer;
  final int Function() clockUs;
  final scheduler = PerceptionScheduler();
  final jobs = <ReplayDepthLoadJob>[];
  ReplayDepthLoadJob? _active;
  Object? _failure;
  StackTrace? _failureStack;
  int offered = 0, skipped = 0, maximumActive = 0;

  ReplayDepthLoadLane({required this.infer, required this.clockUs});
  bool get busy => _active != null;

  void beginSession(int generation) => scheduler.beginSession(generation);

  ReplayDepthLoadJob? offer(String layoutId, PerceptionFrameIdentity frame) {
    if (_failure != null) Error.throwWithStackTrace(_failure!, _failureStack!);
    offered++;
    final ticket = scheduler.tryStart(
      frame: frame,
      yoloDue: false,
      depthDue: true,
    );
    if (ticket == null) {
      skipped++;
      return null;
    }
    final job = ReplayDepthLoadJob(layoutId, frame, clockUs());
    jobs.add(job);
    _active = job;
    if (scheduler.activeCount > maximumActive) {
      maximumActive = scheduler.activeCount;
    }
    _run(ticket, job);
    return job;
  }

  Future<void> _run(PerceptionTicket ticket, ReplayDepthLoadJob job) async {
    try {
      final output = await infer(job.layoutId, job.frame.frameNumber);
      job.output = output;
      job.status =
          scheduler.rejectionFor(
            ticket,
            generation: job.frame.generation,
            width: job.frame.width,
            height: job.frame.height,
            rotationDegrees: job.frame.rotationDegrees,
            mirrored: job.frame.mirrored,
          ) ??
          'validated_load_only';
    } catch (error, stack) {
      job.status = 'failed';
      _failure = error;
      _failureStack = stack;
    } finally {
      try {
        job.completedAtUs = clockUs();
      } catch (error, stack) {
        job.status = 'failed';
        _failure = error;
        _failureStack = stack;
      }
      scheduler.finish(ticket);
      if (identical(_active, job)) _active = null;
      job._done.complete();
    }
  }

  Future<void> drain() async {
    await _active?.done;
    if (_failure != null) Error.throwWithStackTrace(_failure!, _failureStack!);
  }
}
