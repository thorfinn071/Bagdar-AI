import '../perception/camera_metric_motion.dart';

typedef CameraMotionCompute =
    CameraMetricMotionResult Function(
      CameraMetricMotionInput input, {
      required int nowUs,
    });

enum CameraProcessingStatus {
  admitted,
  rejectedSession,
  rejectedOrder,
  rejectedIdentity,
  rejectedClock,
  expiredBeforeCompute,
  expiredAfterCompute,
  expiredBeforeDispatch,
  computeFailed,
}

class CameraProcessingOutcome {
  final CameraProcessingStatus status;
  final CameraMetricMotionResult? result;
  final int startedAtUs, finishedAtUs;
  final int sessionGeneration, frameId;
  final int revision;

  const CameraProcessingOutcome({
    required this.status,
    required this.result,
    required this.startedAtUs,
    required this.finishedAtUs,
    required this.sessionGeneration,
    required this.frameId,
    required this.revision,
  });

  bool get admitted => status == CameraProcessingStatus.admitted;
}

/// Opt-in shadow gate. The clock must advance during computation and share the
/// capture timestamp domain (e.g. anchored monotonic time, not frame+2 ms).
/// Rechecks completion and consumption; expired results never leave this gate.
class CameraProcessingAgeGate {
  static const maximumCurrentAgeUs = 100000;
  final int Function() clockUs;
  final CameraMotionCompute compute;
  final void Function() invalidateProducer;
  int _session = -1, _revision = 0, _lastFrame = 0, _lastCapture = -1;
  int? _lastClock;

  CameraProcessingAgeGate({
    required this.clockUs,
    required this.compute,
    required this.invalidateProducer,
  });

  void beginSession(int generation) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    invalidate();
    _session = generation;
    _lastFrame = 0;
    _lastCapture = -1;
  }

  void invalidate() {
    _revision++;
    invalidateProducer();
  }

  void endSession() {
    invalidate();
    _session = -1;
  }

  ({int now, bool valid}) _time() {
    final now = clockUs();
    final valid = now >= 0 && (_lastClock == null || now >= _lastClock!);
    if (valid) _lastClock = now;
    return (now: now, valid: valid);
  }

  CameraProcessingOutcome process(CameraMetricMotionInput input) {
    final start = _time(), f = input.camera.depth, h = input.camera.rgbHeader;
    final revision = _revision;
    CameraProcessingOutcome outcome(
      CameraProcessingStatus status,
      int finished, [
      CameraMetricMotionResult? result,
    ]) => CameraProcessingOutcome(
      status: status,
      result: result,
      startedAtUs: start.now,
      finishedAtUs: finished,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      revision: revision,
    );
    CameraProcessingOutcome reject(CameraProcessingStatus status, int at) {
      invalidate();
      return outcome(status, at);
    }

    if (!start.valid) {
      return reject(CameraProcessingStatus.rejectedClock, start.now);
    }
    if (_session < 0 || f.sessionGeneration != _session) {
      return reject(CameraProcessingStatus.rejectedSession, start.now);
    }
    if (h.sessionGeneration != f.sessionGeneration ||
        h.frameId != f.frameId ||
        h.sourceTimestampUs != f.capturedAtUs ||
        h.transformId != f.transformId ||
        !f.structurallyValid) {
      return reject(CameraProcessingStatus.rejectedIdentity, start.now);
    }
    if (f.frameId <= _lastFrame || f.capturedAtUs <= _lastCapture) {
      return reject(CameraProcessingStatus.rejectedOrder, start.now);
    }
    _lastFrame = f.frameId;
    _lastCapture = f.capturedAtUs;
    if (start.now < f.capturedAtUs || h.producedAtUs > start.now) {
      return reject(CameraProcessingStatus.rejectedClock, start.now);
    }
    if (start.now - f.capturedAtUs > maximumCurrentAgeUs) {
      return reject(CameraProcessingStatus.expiredBeforeCompute, start.now);
    }
    CameraMetricMotionResult result;
    try {
      result = compute(input, nowUs: start.now);
    } catch (_) {
      return reject(CameraProcessingStatus.computeFailed, _time().now);
    }
    final finish = _time();
    if (!finish.valid) {
      return reject(CameraProcessingStatus.rejectedClock, finish.now);
    }
    if (_revision != revision || _session != f.sessionGeneration) {
      return reject(CameraProcessingStatus.rejectedSession, finish.now);
    }
    if (result.frameId != f.frameId ||
        result.sessionGeneration != f.sessionGeneration ||
        result.capturedAtUs != f.capturedAtUs ||
        result.transformId != f.transformId ||
        result.oldestEvidenceTimestampUs > result.capturedAtUs ||
        result.validUntilUs > f.capturedAtUs + maximumCurrentAgeUs ||
        result.validUntilUs > result.oldestEvidenceTimestampUs + 400000 ||
        result.reason.startsWith('invalid_')) {
      return reject(CameraProcessingStatus.rejectedIdentity, finish.now);
    }
    if (finish.now - f.capturedAtUs > maximumCurrentAgeUs ||
        !result.isLiveAt(finish.now)) {
      return reject(CameraProcessingStatus.expiredAfterCompute, finish.now);
    }
    return outcome(CameraProcessingStatus.admitted, finish.now, result);
  }

  /// Single-use release immediately before scene application. A result can
  /// expire while awaiting the rest of the pipeline even if compute was fast.
  CameraProcessingOutcome release(CameraProcessingOutcome outcome) {
    final time = _time();
    final result = outcome.result;
    var status = outcome.status;
    if (outcome.admitted) {
      if (!time.valid) {
        status = CameraProcessingStatus.rejectedClock;
      } else if (outcome.revision != _revision ||
          outcome.sessionGeneration != _session ||
          outcome.frameId != _lastFrame) {
        status = CameraProcessingStatus.rejectedSession;
      } else if (result == null || !result.isLiveAt(time.now)) {
        status = CameraProcessingStatus.expiredBeforeDispatch;
      }
      // Consumption invalidates all prior handles without discarding a healthy
      // source pair; a rejected completion also discards that pair.
      _revision++;
      if (status != CameraProcessingStatus.admitted) invalidateProducer();
    }
    return CameraProcessingOutcome(
      status: status,
      result: status == CameraProcessingStatus.admitted ? result : null,
      startedAtUs: outcome.startedAtUs,
      finishedAtUs: time.now,
      sessionGeneration: outcome.sessionGeneration,
      frameId: outcome.frameId,
      revision: outcome.revision,
    );
  }
}

/// One pending frame, replaced by the newest capture while a worker is busy.
/// Pure scheduling state: no stale frame is silently retimestamped or repeated.
class CameraLatestFrameQueue {
  CameraMetricMotionInput? _pending;
  int _session = -1, _lastFrame = 0, _lastCapture = -1;
  int replacedFrames = 0, expiredFrames = 0, rejectedFrames = 0;

  int get pendingCount => _pending == null ? 0 : 1;

  void beginSession(int generation) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    _session = generation;
    _lastFrame = 0;
    _lastCapture = -1;
    clear();
  }

  void clear() => _pending = null;

  void endSession() {
    clear();
    _session = -1;
  }

  bool offer(CameraMetricMotionInput input, {required int nowUs}) {
    final f = input.camera.depth, h = input.camera.rgbHeader;
    if (_session < 0 ||
        f.sessionGeneration != _session ||
        h.sessionGeneration != f.sessionGeneration ||
        h.frameId != f.frameId ||
        h.sourceTimestampUs != f.capturedAtUs ||
        f.frameId <= _lastFrame ||
        f.capturedAtUs <= _lastCapture ||
        f.capturedAtUs > nowUs) {
      rejectedFrames++;
      return false;
    }
    _lastFrame = f.frameId;
    _lastCapture = f.capturedAtUs;
    if (_pending != null) replacedFrames++;
    _pending = input;
    return true;
  }

  CameraMetricMotionInput? takeLatest({required int nowUs}) {
    final result = _pending;
    _pending = null;
    if (result == null) return null;
    final age = nowUs - result.camera.depth.capturedAtUs;
    if (age < 0 || age > CameraProcessingAgeGate.maximumCurrentAgeUs) {
      expiredFrames++;
      return null;
    }
    return result;
  }
}
