import 'dart:async';
import 'dart:isolate';

import '../perception/camera_fast_metric_motion_packed.dart';
import 'camera_fast_motion_packed_transport.dart';
import 'camera_fast_motion_worker.dart'
    show FastMotionOutcome, FastMotionStatus;
export 'camera_fast_motion_worker.dart'
    show FastMotionOutcome, FastMotionStatus;
import '../perception/camera_fast_motion_types.dart';
import '../perception/camera_passage_clearance_source.dart';
import '../perception/passage_clearance.dart';

class _Request {
  final int id, nowUs;
  final CameraVisibleDepthFrame metadata;
  final FastRgbHeader header;
  final FastRgbGeometry geometry;
  final double positionErrorM, angularErrorRad;
  final TransferableTypedData storage;
  _Request._(
    this.id,
    this.nowUs,
    this.metadata,
    this.header,
    this.geometry,
    this.positionErrorM,
    this.angularErrorRad,
    this.storage,
  );
  factory _Request(int id, FastMetricMotionInput input, int nowUs) {
    final f = input.camera.depth;
    final storage = packFastMotionFrame(input);
    final metadata = CameraVisibleDepthFrame(
      width: f.width,
      height: f.height,
      frameId: f.frameId,
      capturedAtUs: f.capturedAtUs,
      sessionGeneration: f.sessionGeneration,
      fx: f.fx,
      fy: f.fy,
      cx: f.cx,
      cy: f.cy,
      errorM: f.errorM,
      poseQuality: f.poseQuality,
      cameraId: f.cameraId,
      modelHash: f.modelHash,
      transformId: f.transformId,
      referenceFrameId: f.referenceFrameId,
      units: f.units,
      providerHealthy: f.providerHealthy,
      rotation: f.rotation,
      originM: f.originM,
      rangeM: const [],
      freeZLowerM: const [],
      surfaceZUpperM: const [],
      valid: const [],
    );
    return _Request._(
      id,
      nowUs,
      metadata,
      input.camera.rgbHeader,
      input.camera.imageGeometry,
      input.positionErrorM,
      input.angularErrorRad,
      storage,
    );
  }
  FastMetricMotionInput materialize() {
    return FastMetricMotionInput.fromTransferable(
      storage: storage,
      metadata: metadata,
      header: header,
      geometry: geometry,
      positionErrorM: positionErrorM,
      angularErrorRad: angularErrorRad,
    );
  }
}

class _Reply {
  final int id, computeUs;
  final FastMetricMotionResult? result;
  final Map<String, int> stagesUs;
  const _Reply(this.id, this.result, this.computeUs, this.stagesUs);
}

class _PreparationReply {
  final int computeUs;
  const _PreparationReply(this.computeUs);
}

class _OwnerWork {
  final int id, revision;
  final FastMetricMotionInput input;
  final completer = Completer<FastMotionOutcome>();
  int startedAtUs = 0;
  int packingUs = 0;
  Timer? deadline;
  _OwnerWork(this.id, this.revision, this.input);
}

void _fastWorkerMain(List<Object> args) {
  final reply = args[0] as SendPort;
  final source = CameraFastMetricMotionPackedSource(
    calibration: args[1] as PassageCalibration,
    rgbContract: args[2] as FastRgbContract,
    profileStages: true,
    nativeLibraryPath: args.length > 3 ? args[3] as String : null,
  );
  final incoming = ReceivePort();
  reply.send(incoming.sendPort);
  incoming.listen((message) {
    if (message == 'close') {
      source.dispose();
      reply.send('closed');
      incoming.close();
      return;
    }
    if (message == 'reset') {
      source.invalidate();
      return;
    }
    if (message is! _Request) return;
    final watch = Stopwatch()..start();
    try {
      final input = message.materialize();
      final materializeUs = watch.elapsedMicroseconds;
      final result = source.observe(input, nowUs: message.nowUs);
      reply.send(
        _Reply(message.id, result, watch.elapsedMicroseconds, {
          ...source.stageTimesUs,
          'materialize': materializeUs,
        }),
      );
    } catch (_) {
      source.invalidate();
      reply.send(_Reply(message.id, null, watch.elapsedMicroseconds, const {}));
      return;
    }
    // The reply has already left the worker. Prepare only numeric caches for
    // this immutable frame during idle time before the next capture. A queued
    // reset invalidates them before the next request is processed.
    final preparation = Stopwatch()..start();
    try {
      if (source.prepareNextPair()) {
        reply.send(_PreparationReply(preparation.elapsedMicroseconds));
      }
    } catch (_) {
      source.invalidate();
    }
  });
}

/// Versioned transport correction: one owned packed buffer per dispatch.
/// The frozen load worker remains the comparison control.
/// Experimental persistent isolate. One in-flight and one newest pending input.
/// The owner clock advances in the original capture domain; transport, queue
/// and compute age are checked before completion and single-use consumption.
/// No NN dependency, user feedback, passage clearance or timestamp rewriting.
class CameraFastMotionPackedWorker {
  static const maximumCurrentAgeUs = 100000;
  final PassageCalibration calibration;
  final FastRgbContract rgbContract;
  final int Function() clockUs;
  final _incoming = ReceivePort(),
      _errors = ReceivePort(),
      _exit = ReceivePort();
  final _ready = Completer<void>();
  final _stopped = Completer<void>();
  Isolate? _isolate;
  SendPort? _commands;
  _OwnerWork? _active, _pending;
  int _session = -1,
      _revision = 0,
      _nextId = 0,
      _lastFrame = 0,
      _lastCapture = -1;
  int? _lastClock, _releaseId;
  FastMotionOutcome? _releaseOutcome;
  bool _closed = false, _healthy = false;
  int replacedFrames = 0, expiredFrames = 0, supersededFrames = 0;
  int preparedFrames = 0, preparationComputeUs = 0;
  int lastPackingUs = 0;
  Map<String, int> lastStagesUs = {};
  // Bounded, optional profiler samples; includes replies arriving after the
  // deadline, so failed work is not hidden by successful-return percentiles.
  final computationDiagnostics = <Map<String, Object?>>[];
  int diagnosticOverflow = 0;
  int get pendingCount => _pending == null ? 0 : 1;
  int get inFlightCount => _active == null ? 0 : 1;
  bool get healthy => _healthy && !_closed;

  CameraFastMotionPackedWorker._({
    required this.calibration,
    required this.rgbContract,
    required this.clockUs,
  });

  static Future<CameraFastMotionPackedWorker> start({
    required PassageCalibration calibration,
    required FastRgbContract rgbContract,
    required int Function() clockUs,
    String? nativeLibraryPath,
  }) async {
    final owner = CameraFastMotionPackedWorker._(
      calibration: calibration,
      rgbContract: rgbContract,
      clockUs: clockUs,
    );
    owner._incoming.listen(owner._receive);
    owner._errors.listen((_) => owner._failed());
    owner._exit.listen((_) {
      if (!owner._stopped.isCompleted) owner._stopped.complete();
      owner._failed();
    });
    try {
      owner._isolate = await Isolate.spawn<List<Object>>(
        _fastWorkerMain,
        [
          owner._incoming.sendPort,
          calibration,
          rgbContract,
          if (nativeLibraryPath != null) nativeLibraryPath,
        ],
        onError: owner._errors.sendPort,
        onExit: owner._exit.sendPort,
      );
      await owner._ready.future.timeout(const Duration(seconds: 10));
      return owner;
    } catch (_) {
      await owner.close();
      rethrow;
    }
  }

  ({int now, bool valid}) _time() {
    try {
      final now = clockUs();
      final valid = now >= 0 && (_lastClock == null || now >= _lastClock!);
      if (valid) _lastClock = now;
      return (now: now, valid: valid);
    } catch (_) {
      return (now: _lastClock ?? 0, valid: false);
    }
  }

  FastMotionOutcome _outcome(
    _OwnerWork work,
    FastMotionStatus status, {
    FastMetricMotionResult? result,
    int computeUs = 0,
  }) {
    final f = work.input.camera.depth;
    return FastMotionOutcome(
      status: status,
      result: result,
      requestId: work.id,
      revision: work.revision,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      capturedAtUs: f.capturedAtUs,
      startedAtUs: work.startedAtUs,
      completedAtUs: _lastClock ?? 0,
      workerComputeUs: computeUs,
    );
  }

  void _complete(
    _OwnerWork work,
    FastMotionStatus status, {
    FastMetricMotionResult? result,
    int computeUs = 0,
  }) {
    if (!work.completer.isCompleted) {
      final outcome = _outcome(
        work,
        status,
        result: result,
        computeUs: computeUs,
      );
      if (status == FastMotionStatus.admitted) _releaseOutcome = outcome;
      work.completer.complete(outcome);
    }
  }

  void _invalidate(FastMotionStatus reason) {
    _revision++;
    _releaseId = null;
    _releaseOutcome = null;
    _commands?.send('reset');
    final pending = _pending;
    _pending = null;
    if (pending != null) _complete(pending, reason);
    final active = _active;
    if (active != null) {
      active.deadline?.cancel();
      _complete(active, reason);
    }
  }

  void beginSession(int generation) {
    if (generation < 0) throw ArgumentError.value(generation, 'generation');
    _invalidate(FastMotionStatus.invalidSession);
    _session = generation;
    _lastFrame = 0;
    _lastCapture = -1;
  }

  void providerLost() => _invalidate(FastMotionStatus.providerLost);
  void endSession() {
    providerLost();
    _session = -1;
  }

  bool _identity(FastMetricMotionInput input) {
    final f = input.camera.depth, h = input.camera.rgbHeader;
    return f.structurallyValid &&
        input.rgb.length == f.width * f.height * 3 &&
        input.rgb.every((v) => v >= 0 && v <= 255) &&
        rgbContract.valid &&
        h.providerId == rgbContract.providerId &&
        h.revision == rgbContract.revision &&
        h.preprocessId == rgbContract.preprocessId &&
        h.healthy &&
        h.confidence.isFinite &&
        h.confidence >= .9 &&
        h.confidence <= 1 &&
        h.frameId == f.frameId &&
        h.sessionGeneration == f.sessionGeneration &&
        h.sourceTimestampUs == f.capturedAtUs &&
        h.transformId == f.transformId &&
        h.producedAtUs >= f.capturedAtUs &&
        f.modelHash == calibration.modelHash &&
        f.transformId == calibration.transformId &&
        f.referenceFrameId == calibration.referenceFrameId &&
        calibration.metricScaleValidated &&
        calibration.alignmentValidated &&
        calibration.floorReferenceValidated &&
        calibration.timestampDomain ==
            PassageTimestampDomain.utcEpochMicroseconds;
  }

  Future<FastMotionOutcome> offer(FastMetricMotionInput input) {
    final work = _OwnerWork(++_nextId, _revision, input);
    final time = _time(), f = input.camera.depth, h = input.camera.rgbHeader;
    FastMotionStatus? failure;
    if (_closed) {
      failure = FastMotionStatus.closed;
    } else if (!healthy) {
      failure = FastMotionStatus.workerFailed;
    } else if (!time.valid) {
      failure = FastMotionStatus.invalidClock;
    } else if (_session < 0 || f.sessionGeneration != _session) {
      failure = FastMotionStatus.invalidSession;
    } else if (!_identity(input)) {
      failure = FastMotionStatus.invalidIdentity;
    } else if (f.frameId <= _lastFrame || f.capturedAtUs <= _lastCapture) {
      failure = FastMotionStatus.invalidOrder;
    } else if (f.capturedAtUs > time.now || h.producedAtUs > time.now) {
      failure = FastMotionStatus.invalidClock;
    } else if (time.now - f.capturedAtUs > maximumCurrentAgeUs) {
      failure = FastMotionStatus.expiredBeforeCompute;
    }
    if (failure != null) {
      if (failure != FastMotionStatus.closed) _invalidate(failure);
      _complete(work, failure);
      return work.completer.future;
    }
    _lastFrame = f.frameId;
    _lastCapture = f.capturedAtUs;
    _releaseId = null;
    _releaseOutcome = null;
    if (_pending != null) {
      replacedFrames++;
      _complete(_pending!, FastMotionStatus.replaced);
    }
    _pending = work;
    _dispatch();
    return work.completer.future;
  }

  void _dispatch() {
    if (_closed || !healthy || _active != null || _pending == null) return;
    final work = _pending!;
    _pending = null;
    final time = _time(), f = work.input.camera.depth;
    if (!time.valid || time.now < f.capturedAtUs) {
      _complete(work, FastMotionStatus.invalidClock);
      _invalidate(FastMotionStatus.invalidClock);
      return;
    }
    if (time.now - f.capturedAtUs > maximumCurrentAgeUs) {
      expiredFrames++;
      _complete(work, FastMotionStatus.expiredBeforeCompute);
      _invalidate(FastMotionStatus.expiredBeforeCompute);
      return;
    }
    if (work.revision != _revision || f.sessionGeneration != _session) {
      _complete(work, FastMotionStatus.invalidSession);
      return;
    }
    work.startedAtUs = time.now;
    _active = work;
    work.deadline = Timer(
      Duration(
        microseconds: f.capturedAtUs + maximumCurrentAgeUs - time.now + 1,
      ),
      () {
        final current = _time();
        if (_active == work &&
            (!current.valid ||
                current.now > f.capturedAtUs + maximumCurrentAgeUs)) {
          expiredFrames++;
          _invalidate(
            current.valid
                ? FastMotionStatus.expiredAfterCompute
                : FastMotionStatus.invalidClock,
          );
        }
      },
    );
    try {
      final packing = Stopwatch()..start();
      final request = _Request(work.id, work.input, time.now);
      lastPackingUs = packing.elapsedMicroseconds;
      work.packingUs = lastPackingUs;
      final afterPacking = _time();
      if (!afterPacking.valid ||
          afterPacking.now > f.capturedAtUs + maximumCurrentAgeUs) {
        _active = null;
        work.deadline?.cancel();
        expiredFrames++;
        final failure = afterPacking.valid
            ? FastMotionStatus.expiredBeforeCompute
            : FastMotionStatus.invalidClock;
        _complete(work, failure);
        _invalidate(failure);
        return;
      }
      _commands!.send(request);
    } catch (_) {
      _active = null;
      work.deadline?.cancel();
      _complete(work, FastMotionStatus.workerFailed);
      _invalidate(FastMotionStatus.workerFailed);
    }
  }

  void _receive(dynamic message) {
    if (message == 'closed') {
      if (!_stopped.isCompleted) _stopped.complete();
      return;
    }
    if (_closed) return;
    if (message is _PreparationReply) {
      preparedFrames++;
      preparationComputeUs += message.computeUs;
      return;
    }
    if (message is SendPort) {
      _commands = message;
      _healthy = true;
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    if (message is! _Reply || _active?.id != message.id) return;
    lastStagesUs = message.stagesUs;
    final work = _active!;
    _active = null;
    work.deadline?.cancel();
    final time = _time(), result = message.result, f = work.input.camera.depth;
    if (computationDiagnostics.length < 128) {
      computationDiagnostics.add({
        'frameId': f.frameId,
        'workerComputeUs': message.computeUs,
        'packingUs': work.packingUs,
        'ageAtOwnerReceiveUs': time.now - f.capturedAtUs,
        'transportQueueAndDeliveryUs':
            time.now - work.startedAtUs - message.computeUs,
        'completedBeforeDeadline':
            time.valid && time.now <= f.capturedAtUs + maximumCurrentAgeUs,
        'stagesUs': message.stagesUs,
      });
    } else {
      diagnosticOverflow++;
    }
    var status = FastMotionStatus.admitted;
    if (!time.valid) {
      status = FastMotionStatus.invalidClock;
    } else if (work.revision != _revision || f.sessionGeneration != _session) {
      status = FastMotionStatus.invalidSession;
    } else if (result == null) {
      status = FastMotionStatus.workerFailed;
    } else if (result.reason.startsWith('invalid_') ||
        result.frameId != f.frameId ||
        result.sessionGeneration != f.sessionGeneration ||
        result.capturedAtUs != f.capturedAtUs ||
        result.transformId != f.transformId ||
        result.oldestEvidenceTimestampUs > f.capturedAtUs ||
        result.validUntilUs > f.capturedAtUs + maximumCurrentAgeUs ||
        result.validUntilUs > result.oldestEvidenceTimestampUs + 400000) {
      status = FastMotionStatus.invalidIdentity;
    } else if (!result.isLiveAt(time.now)) {
      status = FastMotionStatus.expiredAfterCompute;
      expiredFrames++;
    } else if (_pending != null || f.frameId != _lastFrame) {
      status = FastMotionStatus.superseded;
      supersededFrames++;
    }
    if (status == FastMotionStatus.admitted && !work.completer.isCompleted) {
      _releaseId = work.id;
    }
    if (status != FastMotionStatus.admitted &&
        status != FastMotionStatus.superseded) {
      // Preserve the newest pending request across a stale completion only if
      // it belongs to this session; it starts a new temporal pair after reset.
      _commands?.send('reset');
    }
    _complete(
      work,
      status,
      result: status == FastMotionStatus.admitted ? result : null,
      computeUs: message.computeUs,
    );
    _dispatch();
  }

  FastMotionOutcome release(FastMotionOutcome outcome) {
    final time = _time();
    if (!outcome.admitted) return outcome;
    var status = FastMotionStatus.admitted;
    if (!time.valid) {
      status = FastMotionStatus.invalidClock;
    } else if (_closed ||
        !healthy ||
        outcome.revision != _revision ||
        outcome.sessionGeneration != _session ||
        _releaseId != outcome.requestId ||
        !identical(_releaseOutcome, outcome) ||
        outcome.frameId != _lastFrame) {
      status = FastMotionStatus.invalidSession;
    } else if (outcome.result == null || !outcome.result!.isLiveAt(time.now)) {
      status = FastMotionStatus.expiredBeforeRelease;
    }
    _releaseId = null;
    _releaseOutcome = null;
    if (status != FastMotionStatus.admitted) _invalidate(status);
    return FastMotionOutcome(
      status: status,
      result: status == FastMotionStatus.admitted ? outcome.result : null,
      requestId: outcome.requestId,
      revision: outcome.revision,
      sessionGeneration: outcome.sessionGeneration,
      frameId: outcome.frameId,
      capturedAtUs: outcome.capturedAtUs,
      startedAtUs: outcome.startedAtUs,
      completedAtUs: time.now,
      workerComputeUs: outcome.workerComputeUs,
    );
  }

  void _failed() {
    if (_closed) return;
    _healthy = false;
    _invalidate(FastMotionStatus.workerFailed);
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Fast motion isolate unavailable'));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _healthy = false;
    _invalidate(FastMotionStatus.closed);
    _commands?.send('close');
    if (_isolate != null) {
      await _stopped.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _isolate?.kill(priority: Isolate.immediate);
        },
      );
    }
    _incoming.close();
    _errors.close();
    _exit.close();
  }
}
