import 'package:flutter/foundation.dart';

import 'fall_detector.dart' show MotionState;

/// Action proposed by [PhoneAbandonedDetector.tick] for a single tick.
class PhoneAbandonedTickResult {
  /// Fire the critical "your phone is lying down" TTS + haptic this tick.
  final bool fireCriticalAlert;

  /// Fire the soft 10-minute heartbeat earcon this tick.
  final bool fireSoftHeartbeat;

  /// Haptic vibration pattern to play together with [fireCriticalAlert].
  /// Escalates across consecutive criticals — the pattern grows longer /
  /// stronger each repeat so the user keeps escalating attention.
  final List<int>? hapticPattern;

  /// 1-based level (1..4) the haptic was emitted at this tick. Useful for
  /// tests and field logging.
  final int hapticEscalationLevel;

  const PhoneAbandonedTickResult({
    required this.fireCriticalAlert,
    required this.fireSoftHeartbeat,
    this.hapticPattern,
    this.hapticEscalationLevel = 0,
  });

  static const idle = PhoneAbandonedTickResult(
    fireCriticalAlert: false,
    fireSoftHeartbeat: false,
  );
}

/// "Phone left behind" detector (Safety follow-up M12).
///
/// Detects the silent failure mode where the user puts the phone down on a
/// bench / café table / bus seat and walks away while the app keeps
/// "detecting" the ceiling. The system is otherwise indistinguishable from
/// "all clear" for a blind user.
///
/// Critical criteria — all three must hold:
///   * [MotionState] held at [MotionState.stationary] for at least
///     [kStationaryThreshold] (phone itself has not moved);
///   * the camera frame hash has stopped changing for the
///     `FrameQualityGuard.kFrozenFrameThreshold` window (`cameraFrozen`);
///   * ambient luminance is normal (`lumaNormal` — not in a pocket, not in
///     total darkness — so we do not mistake a pocketed-but-carried phone
///     for an abandoned one).
///
/// While the critical conditions hold the detector re-announces every
/// [kCriticalReannounce] with an escalating haptic pattern (levels 1..4).
///
/// Soft tier: every [kSoftHeartbeatInterval] of stationary state (regardless
/// of frozen / luma), a quiet earcon is emitted as a background presence
/// reminder. Plan M12 spec: "earcon at 0.3 volume every 10 min".
///
/// All time arithmetic accepts an injectable `now` for deterministic tests.
class PhoneAbandonedDetector {
  static const Duration kStationaryThreshold = Duration(seconds: 60);
  static const Duration kSoftHeartbeatInterval = Duration(minutes: 10);
  static const Duration kCriticalReannounce = Duration(seconds: 90);
  static const int kMaxHapticEscalation = 4;
  static const double kSoftHeartbeatVolume = 0.3;
  static const String kAnnounceKey = 'phone_abandoned';

  MotionState _motion = MotionState.stationary;
  bool _cameraFrozen = false;
  bool _lumaNormal = true;

  DateTime? _stationarySinceAt;
  DateTime? _lastSoftEarconAt;
  DateTime? _lastCriticalAt;
  int _hapticEscalation = 0;

  void noteMotionState(MotionState state, {DateTime? now}) {
    if (state == _motion) return;
    _motion = state;
    if (state != MotionState.stationary) {
      _stationarySinceAt = null;
      _lastSoftEarconAt = null;
      _lastCriticalAt = null;
      _hapticEscalation = 0;
    } else {
      _stationarySinceAt = now ?? DateTime.now();
      _lastSoftEarconAt = null;
      _lastCriticalAt = null;
      _hapticEscalation = 0;
    }
  }

  void noteCameraFrozen(bool frozen) {
    _cameraFrozen = frozen;
  }

  void noteLumaNormal(bool normal) {
    _lumaNormal = normal;
  }

  /// Periodic tick — call at ~1 Hz from the host. Returns the action this
  /// tick should perform.
  PhoneAbandonedTickResult tick({DateTime? now}) {
    final t = now ?? DateTime.now();

    if (_motion != MotionState.stationary) {
      return PhoneAbandonedTickResult.idle;
    }

    _stationarySinceAt ??= t;
    final stationaryFor = t.difference(_stationarySinceAt!);

    bool fireCritical = false;
    List<int>? haptic;
    int hapticLevel = 0;
    if (_cameraFrozen &&
        _lumaNormal &&
        stationaryFor >= kStationaryThreshold) {
      final due = _lastCriticalAt == null ||
          t.difference(_lastCriticalAt!) >= kCriticalReannounce;
      if (due) {
        fireCritical = true;
        _lastCriticalAt = t;
        _hapticEscalation = (_hapticEscalation + 1)
            .clamp(1, kMaxHapticEscalation);
        haptic = _hapticForLevel(_hapticEscalation);
        hapticLevel = _hapticEscalation;
      }
    }

    bool fireSoft = false;
    if (_lastSoftEarconAt == null) {
      if (stationaryFor >= kSoftHeartbeatInterval) {
        fireSoft = true;
        _lastSoftEarconAt = t;
      }
    } else if (t.difference(_lastSoftEarconAt!) >= kSoftHeartbeatInterval) {
      fireSoft = true;
      _lastSoftEarconAt = t;
    }

    return PhoneAbandonedTickResult(
      fireCriticalAlert: fireCritical,
      fireSoftHeartbeat: fireSoft,
      hapticPattern: haptic,
      hapticEscalationLevel: hapticLevel,
    );
  }

  static List<int> _hapticForLevel(int level) {
    switch (level) {
      case 1:
        return const [0, 300];
      case 2:
        return const [0, 300, 150, 300];
      case 3:
        return const [0, 400, 150, 400, 150, 400];
      default:
        return const [0, 600, 150, 600, 150, 600, 150, 600];
    }
  }

  void reset() {
    _stationarySinceAt = null;
    _lastSoftEarconAt = null;
    _lastCriticalAt = null;
    _hapticEscalation = 0;
  }

  @visibleForTesting
  MotionState get motion => _motion;

  @visibleForTesting
  bool get cameraFrozen => _cameraFrozen;

  @visibleForTesting
  bool get lumaNormal => _lumaNormal;

  /// Public for callers that want to field-log the duration the phone has
  /// been stationary; null while motion is non-stationary.
  DateTime? get stationarySinceAt => _stationarySinceAt;

  @visibleForTesting
  DateTime? get lastSoftEarconAt => _lastSoftEarconAt;

  @visibleForTesting
  DateTime? get lastCriticalAt => _lastCriticalAt;

  @visibleForTesting
  int get hapticEscalation => _hapticEscalation;
}
