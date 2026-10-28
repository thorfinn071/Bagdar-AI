import 'perception_performance.dart';

enum PerceptionLane { yolo, depth }

/// Immutable identity of a camera callback; does not retain pixel buffers.
class PerceptionFrameIdentity {
  final int generation;
  final int frameNumber;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool mirrored;
  final CallbackFrameTiming timing;

  const PerceptionFrameIdentity({
    required this.generation,
    required this.frameNumber,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.mirrored,
    required this.timing,
  });
}

class PerceptionTicket {
  final PerceptionLane lane;
  final PerceptionFrameIdentity frame;

  PerceptionTicket._(this.lane, this.frame);
}

/// One start per callback, one active per model, no queued camera frames.
///
/// A free lane can start on a new callback while the other model runs. This
/// preserves the existing maximum of two overlapping models but removes the
/// dependency on completion/success of YOLO. If both are due they alternate;
/// busy callbacks neither supersede active work nor retain stale pixel data.
class PerceptionScheduler {
  final Duration maximumAge;
  final Map<PerceptionLane, PerceptionTicket> _active = {};
  int _generation = -1;
  int _lastFrameNumber = 0;
  PerceptionLane? _lastStarted;
  bool _enabled = false;

  PerceptionScheduler({this.maximumAge = const Duration(seconds: 2)}) {
    if (maximumAge <= Duration.zero) {
      throw ArgumentError.value(maximumAge, 'maximumAge');
    }
  }

  int get activeCount => _active.length;
  int get queuedFrames => 0;
  bool isBusy(PerceptionLane lane) => _active.containsKey(lane);
  bool acceptsFrames(int generation) => _enabled && generation == _generation;

  void beginSession(int generation) {
    _generation = generation;
    _lastFrameNumber = 0;
    _lastStarted = null;
    _enabled = true;
    // Old calls still own native work until they actually finish.
  }

  void suspend() => _enabled = false;

  PerceptionTicket? tryStart({
    required PerceptionFrameIdentity frame,
    required bool yoloDue,
    required bool depthDue,
  }) {
    if (!_enabled ||
        frame.generation != _generation ||
        frame.frameNumber <= _lastFrameNumber) {
      return null;
    }
    _lastFrameNumber = frame.frameNumber;
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        frame.timing.ageUs < 0 ||
        frame.timing.ageUs > maximumAge.inMicroseconds) {
      return null;
    }
    final yolo = yoloDue && !isBusy(PerceptionLane.yolo);
    final depth = depthDue && !isBusy(PerceptionLane.depth);
    if (!yolo && !depth) return null;
    final lane = yolo && depth
        ? (_lastStarted == PerceptionLane.yolo
              ? PerceptionLane.depth
              : PerceptionLane.yolo)
        : yolo
        ? PerceptionLane.yolo
        : PerceptionLane.depth;
    final ticket = PerceptionTicket._(lane, frame);
    _active[lane] = ticket;
    _lastStarted = lane;
    return ticket;
  }

  /// Use immediately before mutation/output, not only after native inference.
  String? rejectionFor(
    PerceptionTicket ticket, {
    required int generation,
    required int width,
    required int height,
    required int rotationDegrees,
    required bool mirrored,
  }) {
    if (!_enabled ||
        generation != _generation ||
        ticket.frame.generation != generation ||
        !identical(_active[ticket.lane], ticket)) {
      return 'session_or_ownership_mismatch';
    }
    final age = ticket.frame.timing.ageUs;
    if (age < 0) return 'clock_mismatch';
    if (age > maximumAge.inMicroseconds) return 'stale_result';
    if (width != ticket.frame.width ||
        height != ticket.frame.height ||
        rotationDegrees != ticket.frame.rotationDegrees ||
        mirrored != ticket.frame.mirrored) {
      return 'transform_mismatch';
    }
    return null;
  }

  void finish(PerceptionTicket ticket) {
    if (identical(_active[ticket.lane], ticket)) _active.remove(ticket.lane);
  }
}
