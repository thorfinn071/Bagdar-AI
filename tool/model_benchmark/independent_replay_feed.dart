import 'dart:async';
import 'dart:math' as math;

/// Preloaded immutable captures arrive on their original clock independently
/// of downstream completion. This models callback pacing, not sensor capture.
/// All launched callbacks are joined only after scheduling the entire stream.
Future<void> feedIndependentCaptures<T>({
  required List<T> frames,
  required int Function(T) capturedAtUs,
  required int Function() clockUs,
  required Future<void> Function(T) onCapture,
  int arrivalDelayUs = 2000,
}) async {
  if (arrivalDelayUs < 0) throw ArgumentError.value(arrivalDelayUs);
  var previous = -1;
  for (final frame in frames) {
    final stamp = capturedAtUs(frame);
    if (stamp < 0 || stamp <= previous) {
      throw ArgumentError('Capture timestamps must strictly increase');
    }
    previous = stamp;
  }
  final completed = [for (final _ in frames) Completer<void>()];
  final all = Future.wait(completed.map((c) => c.future), eagerError: true);
  final timers = <Timer>[];
  try {
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i], done = completed[i];
      final delay = math.max(
        0,
        capturedAtUs(frame) + arrivalDelayUs - clockUs(),
      );
      timers.add(
        Timer(Duration(microseconds: delay), () {
          Future<void>.sync(() => onCapture(frame)).then(
            (_) => done.complete(),
            onError: (Object error, StackTrace stack) =>
                done.completeError(error, stack),
          );
        }),
      );
    }
    await all;
  } finally {
    for (final timer in timers) {
      timer.cancel();
    }
  }
}
