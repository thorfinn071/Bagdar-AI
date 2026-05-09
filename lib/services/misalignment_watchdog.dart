import '../camera/depth_pipeline_controller.dart' show DepthPipelineStatus;
import '../models/speech_job.dart';
import 'fall_detector.dart' show MotionState;
import 'orientation_service.dart' show DevicePitch;

/// Result returned by [MisalignmentWatchdog.tick] describing what action,
/// if any, the host should perform this tick.
class MisalignmentTickResult {
  final bool fireHaptic;
  final SpeechPriority? announcePriority;
  final String? announceKey;

  const MisalignmentTickResult({
    required this.fireHaptic,
    this.announcePriority,
    this.announceKey,
  });

  static const idle = MisalignmentTickResult(fireHaptic: false);

  bool get shouldAnnounce => announcePriority != null && announceKey != null;
}

/// Sustained-misalignment watchdog (Safety follow-up H6).
///
/// Detects the silent failure mode where the phone is held tooHigh / tooLow /
/// flat for many seconds while the user is walking and nothing is being
/// detected.
///
/// Distinguishes "empty scene" (depth pipeline OK, just nothing visible) from
/// "camera is blind" (depth pipeline reporting low confidence / plane-fit
/// failure for ≥ [kLowConfidenceConfirmation]). Only the latter is verbalized
/// — empty scenes stay silent so a quiet street does not trigger spurious
/// "raise the phone" alerts.
///
/// Outputs:
///   * verbal warning at [kWarningThreshold] (then critical at
///     [kCriticalThreshold], re-announced every [kCriticalReannounce]),
///     gated on the depth-low confirmation;
///   * tactile triple-tap haptic every [kHapticInterval] once the sustained
///     state has held for [kWarningThreshold], regardless of depth status —
///     so the user has a non-verbal channel even with earbuds in city noise.
///
/// All time arithmetic accepts an injectable `now` for deterministic tests.
class MisalignmentWatchdog {
  static const Duration kWarningThreshold = Duration(seconds: 20);
  static const Duration kCriticalThreshold = Duration(seconds: 60);
  static const Duration kLowConfidenceConfirmation = Duration(seconds: 30);
  static const Duration kHapticInterval = Duration(seconds: 15);
  static const Duration kCriticalReannounce = Duration(seconds: 60);
  static const Duration kDetectionFreshness = Duration(seconds: 5);
  static const String kAnnounceKey = 'pitch_misaligned_blind';

  DevicePitch _pitch = DevicePitch.optimal;
  MotionState _motion = MotionState.stationary;
  DepthPipelineStatus _depthStatus = DepthPipelineStatus.ok;
  DateTime? _depthLowSinceAt;
  DateTime _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _sustainedSinceAt;
  DateTime? _lastHapticAt;
  DateTime? _lastCriticalAt;
  bool _warningAnnouncedThisEpisode = false;

  void noteDetection({DateTime? now}) {
    _lastDetectionAt = now ?? DateTime.now();
  }

  void notePitchState(DevicePitch state) {
    _pitch = state;
  }

  void noteMotionState(MotionState state) {
    _motion = state;
  }

  void noteDepthStatus(DepthPipelineStatus status, {DateTime? now}) {
    if (status == _depthStatus) return;
    _depthStatus = status;
    final t = now ?? DateTime.now();
    if (status == DepthPipelineStatus.lowConfidence ||
        status == DepthPipelineStatus.planeFitFailed) {
      _depthLowSinceAt = t;
    } else {
      _depthLowSinceAt = null;
    }
  }

  /// Whether the depth pipeline has been reporting blindness long enough that
  /// we are confident this is a misalignment, not an empty scene.
  bool isDepthBlindAt(DateTime t) {
    final since = _depthLowSinceAt;
    if (since == null) return false;
    return t.difference(since) >= kLowConfidenceConfirmation;
  }

  /// Currently observed pitch / motion / depth state — exposed for tests.
  DevicePitch get pitch => _pitch;
  MotionState get motion => _motion;
  DepthPipelineStatus get depthStatus => _depthStatus;
  DateTime? get sustainedSinceAt => _sustainedSinceAt;

  /// Periodic tick — call ~1 Hz from the host. Returns the action this tick.
  MisalignmentTickResult tick({DateTime? now}) {
    final t = now ?? DateTime.now();
    final misaligned = _pitch != DevicePitch.optimal;
    final walking = _motion == MotionState.walking;
    final noRecentDetections =
        t.difference(_lastDetectionAt) >= kDetectionFreshness;
    final sustainedNow = misaligned && walking && noRecentDetections;

    if (!sustainedNow) {
      _sustainedSinceAt = null;
      _lastHapticAt = null;
      _warningAnnouncedThisEpisode = false;
      _lastCriticalAt = null;
      return MisalignmentTickResult.idle;
    }

    _sustainedSinceAt ??= t;
    final sustainedFor = t.difference(_sustainedSinceAt!);

    bool fireHaptic = false;
    if (sustainedFor >= kWarningThreshold) {
      if (_lastHapticAt == null ||
          t.difference(_lastHapticAt!) >= kHapticInterval) {
        fireHaptic = true;
        _lastHapticAt = t;
      }
    }

    SpeechPriority? announcePriority;
    String? announceKey;

    if (isDepthBlindAt(t)) {
      if (sustainedFor >= kCriticalThreshold) {
        if (_lastCriticalAt == null ||
            t.difference(_lastCriticalAt!) >= kCriticalReannounce) {
          announcePriority = SpeechPriority.critical;
          announceKey = kAnnounceKey;
          _lastCriticalAt = t;
          _warningAnnouncedThisEpisode = true;
        }
      } else if (sustainedFor >= kWarningThreshold &&
          !_warningAnnouncedThisEpisode) {
        announcePriority = SpeechPriority.warning;
        announceKey = kAnnounceKey;
        _warningAnnouncedThisEpisode = true;
      }
    }

    return MisalignmentTickResult(
      fireHaptic: fireHaptic,
      announcePriority: announcePriority,
      announceKey: announceKey,
    );
  }

  void reset() {
    _sustainedSinceAt = null;
    _lastHapticAt = null;
    _lastCriticalAt = null;
    _warningAnnouncedThisEpisode = false;
    _depthLowSinceAt = null;
    _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
