import 'camera_passage_clearance_source.dart';
import 'passage_clearance.dart';
import 'single_camera_observability.dart';

/// An immutable cache snapshot, not a temporally registered evidence source.
class SingleCameraScanSnapshot {
  final List<CameraVisibleDepthFrame> frames;
  final String reason;
  final int inspectedAtUs;

  SingleCameraScanSnapshot._(
    List<CameraVisibleDepthFrame> frames,
    this.reason,
    this.inspectedAtUs,
  ) : frames = List.unmodifiable(frames);

  bool get canAuthorizeMovement => false;

  Map<String, Object?> toDiagnosticMap() => {
    'reason': reason,
    'inspectedAtUs': inspectedAtUs,
    'frameIds': frames.map((f) => f.frameId).toList(),
    'captureTimesUs': frames.map((f) => f.capturedAtUs).toList(),
    'oldestCaptureUs': frames.isEmpty ? null : frames.first.capturedAtUs,
    'canAuthorizeMovement': canAuthorizeMovement,
  };
}

/// Bounded diagnostic cache. Freshness is necessary, never a claim that an
/// earlier view still describes the current scene or that depth bounds are valid.
class SingleCameraScanWindow {
  static const maximumAgeUs = 100000;
  static const maximumFrames = 12;
  final PassageClearanceRequest request;
  final int sessionGeneration;
  final _frames = <CameraVisibleDepthFrame>[];
  List<Object>? _binding;
  int? _lastNowUs;
  int _lastFrameId = -1, _lastCaptureUs = -1;
  bool _ended = false;
  String _reason = 'empty';

  SingleCameraScanWindow({
    required this.request,
    required this.sessionGeneration,
  }) {
    if (sessionGeneration < 0) throw ArgumentError.value(sessionGeneration);
  }

  void endSession() {
    _ended = true;
    _invalidate('session_ended');
  }

  bool _invalidate(String reason) {
    _frames.clear();
    _binding = null;
    _reason = reason;
    // Deliberately retain ordering high-water marks after faults and expiry.
    return false;
  }

  bool _clock(int nowUs) {
    if (_ended) return false;
    if (nowUs < 0 || (_lastNowUs != null && nowUs < _lastNowUs!)) {
      _ended = true;
      return _invalidate('clock_rollback_or_invalid');
    }
    _lastNowUs = nowUs;
    return true;
  }

  void _expire(int nowUs) {
    _frames.removeWhere((f) => nowUs - f.capturedAtUs > maximumAgeUs);
    if (_frames.isEmpty && _reason == 'accepted') _reason = 'expired';
  }

  bool admit({
    required CameraVisibleDepthFrame frame,
    required PassageCalibration calibration,
    required PassageEvaluationContext context,
  }) {
    if (!_clock(context.nowUs)) return false;
    if (frame.sessionGeneration != sessionGeneration ||
        context.sessionGeneration != sessionGeneration) {
      return _invalidate('session_mismatch');
    }
    final preflight = const SingleCameraObservabilityPreflight().assess(
      frame: frame,
      calibration: calibration,
      request: request,
      context: context,
    );
    if (!preflight.inputsAdmitted) return _invalidate(preflight.reason);
    if (frame.frameId <= _lastFrameId || frame.capturedAtUs <= _lastCaptureUs) {
      return _invalidate('replayed_or_out_of_order');
    }
    final binding = <Object>[
      frame.cameraId,
      frame.width,
      frame.height,
      frame.fx,
      frame.fy,
      frame.cx,
      frame.cy,
      calibration.id,
      calibration.providerId,
      calibration.modelId,
      calibration.preprocessId,
      calibration.modelHash,
      calibration.referenceFrameId,
      calibration.transformId,
      calibration.timestampDomain,
    ];
    if (_binding != null &&
        List.generate(
          binding.length,
          (i) => binding[i] == _binding![i],
        ).any((same) => !same)) {
      _frames.clear();
    }
    _binding = binding;
    _lastFrameId = frame.frameId;
    _lastCaptureUs = frame.capturedAtUs;
    _expire(context.nowUs);
    _frames.add(frame);
    if (_frames.length > maximumFrames) _frames.removeAt(0);
    _reason = 'accepted';
    return true;
  }

  SingleCameraScanSnapshot inspect(int nowUs) {
    if (_clock(nowUs)) _expire(nowUs);
    return SingleCameraScanSnapshot._(_frames, _reason, nowUs);
  }
}
