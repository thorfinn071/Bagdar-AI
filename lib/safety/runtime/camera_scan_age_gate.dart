import '../perception/passage_clearance.dart';

enum CameraScanAgeStatus {
  admitted,
  invalidClock,
  invalidIdentity,
  rejectedSession,
  expiredBeforeCompute,
  expiredAfterCompute,
  expiredBeforeDispatch,
  computeFailed,
  unavailable,
  consumed,
}

class CameraScanAgeOutcome {
  final CameraScanAgeStatus status;
  final PassageClearanceObservation? observation;
  final PassageClearanceResult? decision;
  final int startedAtUs, finishedAtUs, revision;

  const CameraScanAgeOutcome({
    required this.status,
    required this.startedAtUs,
    required this.finishedAtUs,
    required this.revision,
    this.observation,
    this.decision,
  });
}

/// Synthetic shadow admission only. Capture times and the advancing monotonic
/// clock must already share a domain. This gate never changes a capture time.
/// A fresh latest view cannot renew the age of earlier contributing evidence.
class CameraScanAgeGate {
  static const maximumAgeUs = 100000;
  static const _policy = PassageClearancePolicy(
    maximumAgeUs: maximumAgeUs,
    maximumPairSkewUs: 50000,
    maximumProcessingLatencyUs: maximumAgeUs,
    minimumConfidence: .99,
  );
  final int Function() clockUs;
  int _session = -1, _revision = 0;
  int? _lastClock;
  CameraScanAgeOutcome? _pending;

  CameraScanAgeGate({required this.clockUs});

  void beginSession(int session) {
    if (session < 0) throw ArgumentError.value(session, 'session');
    invalidate();
    _session = session;
  }

  void invalidate() {
    _revision++;
    _pending = null;
  }

  void endSession() {
    invalidate();
    _session = -1;
  }

  bool _clockValid(int now) {
    final valid = now >= 0 && (_lastClock == null || now >= _lastClock!);
    if (valid) _lastClock = now;
    return valid;
  }

  CameraScanAgeOutcome process({
    required int oldestCaptureUs,
    required PassageEvaluationContext captureContext,
    required PassageCalibration calibration,
    required PassageClearanceRequest request,
    required PassageClearanceObservation? Function() compute,
  }) {
    invalidate();
    final revision = _revision, start = clockUs();
    CameraScanAgeOutcome reject(CameraScanAgeStatus status, int at) =>
        CameraScanAgeOutcome(
          status: status,
          startedAtUs: start,
          finishedAtUs: at,
          revision: revision,
        );
    if (!_clockValid(start)) {
      return reject(CameraScanAgeStatus.invalidClock, start);
    }
    if (_session < 0 || captureContext.sessionGeneration != _session) {
      return reject(CameraScanAgeStatus.rejectedSession, start);
    }
    if (oldestCaptureUs < 0 ||
        oldestCaptureUs > captureContext.rgbTimestampUs ||
        captureContext.rgbTimestampUs > start ||
        captureContext.timestampDomain != calibration.timestampDomain ||
        captureContext.transformId != calibration.transformId ||
        captureContext.frameId <= 0) {
      return reject(CameraScanAgeStatus.invalidIdentity, start);
    }
    if (start - oldestCaptureUs > maximumAgeUs) {
      return reject(CameraScanAgeStatus.expiredBeforeCompute, start);
    }
    PassageClearanceObservation? observation;
    try {
      observation = compute();
    } catch (_) {
      return reject(CameraScanAgeStatus.computeFailed, clockUs());
    }
    final finish = clockUs();
    if (!_clockValid(finish)) {
      return reject(CameraScanAgeStatus.invalidClock, finish);
    }
    if (_revision != revision || _session != captureContext.sessionGeneration) {
      return reject(CameraScanAgeStatus.rejectedSession, finish);
    }
    if (observation == null ||
        observation.oldestEvidenceTimestampUs != oldestCaptureUs ||
        observation.rgbTimestampUs != captureContext.rgbTimestampUs ||
        observation.depthTimestampUs != captureContext.rgbTimestampUs ||
        observation.frameId != captureContext.frameId ||
        observation.sessionGeneration != captureContext.sessionGeneration) {
      return reject(CameraScanAgeStatus.invalidIdentity, finish);
    }
    if (finish - oldestCaptureUs > maximumAgeUs) {
      return reject(CameraScanAgeStatus.expiredAfterCompute, finish);
    }
    final decision = const PassageClearanceEvaluator(policy: _policy).evaluate(
      request: request,
      context: _at(captureContext, finish),
      calibration: calibration,
      observation: observation,
    );
    if (decision.status == PassageClearanceStatus.unavailable) {
      return reject(CameraScanAgeStatus.unavailable, finish);
    }
    final outcome = CameraScanAgeOutcome(
      status: CameraScanAgeStatus.admitted,
      startedAtUs: start,
      finishedAtUs: finish,
      revision: revision,
      observation: observation,
      decision: decision,
    );
    _pending = outcome;
    return outcome;
  }

  /// Single-use recheck immediately before a shadow decision is consumed.
  CameraScanAgeOutcome release(CameraScanAgeOutcome outcome) {
    final now = clockUs();
    var status = outcome.status;
    if (!_clockValid(now)) {
      status = CameraScanAgeStatus.invalidClock;
    } else if (status == CameraScanAgeStatus.admitted) {
      if (_session < 0 || outcome.observation?.sessionGeneration != _session) {
        status = CameraScanAgeStatus.rejectedSession;
      } else if (!identical(_pending, outcome) ||
          outcome.revision != _revision) {
        status = CameraScanAgeStatus.consumed;
      } else if (now - outcome.observation!.oldestEvidenceTimestampUs >
          maximumAgeUs) {
        status = CameraScanAgeStatus.expiredBeforeDispatch;
      }
    }
    invalidate();
    return CameraScanAgeOutcome(
      status: status,
      startedAtUs: outcome.startedAtUs,
      finishedAtUs: now,
      revision: outcome.revision,
      observation: status == CameraScanAgeStatus.admitted
          ? outcome.observation
          : null,
      decision: status == CameraScanAgeStatus.admitted
          ? outcome.decision
          : null,
    );
  }
}

PassageEvaluationContext _at(PassageEvaluationContext c, int now) =>
    PassageEvaluationContext(
      nowUs: now,
      timestampDomain: c.timestampDomain,
      sessionGeneration: c.sessionGeneration,
      frameId: c.frameId,
      rgbTimestampUs: c.rgbTimestampUs,
      transformId: c.transformId,
    );
