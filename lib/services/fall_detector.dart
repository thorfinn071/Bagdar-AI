import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/constants.dart';

/// V1.2: `running` distinguishes sustained fast movement (high accel, low
/// gyro jitter) from `unstable` (high accel AND high gyro — e.g. bus ride).
/// The detection interval is halved when running to compensate for the shorter
/// time-to-collision at 3 m/s vs 1.5 m/s.
enum MotionState { stationary, walking, running, unstable }

enum FallClass { tumble, collapse }

class FallDetector {
  StreamSubscription<AccelerometerEvent>? _sub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  bool _ready = false;
  bool _gyroAvailable = false;
  DateTime? _lastGyroEventAt;

  void Function(FallClass fallClass)? onFallDetected;
  void Function()? onSecondFallDuringLockout;
  void Function(MotionState state)? onMotionStateChanged;

  /// Fired once when the gyroscope becomes unavailable (init failure, stream
  /// error, or staleness watchdog). Host should announce a degraded-accuracy
  /// TTS warning. Not fired again until gyro recovers and fails anew.
  void Function()? onGyroUnavailable;
  void Function(String stage, {double? accel, double? gyro, int? stillFrames})?
  onStageChange;

  DateTime _lastImpactAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFreeFallAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFreeFallLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _impactDetected = false;
  int _stillFrames = 0;
  MotionState _motionState = MotionState.stationary;
  double _accelMotionScore = 0;
  double _gyroMotionScore = 0;
  double _lastAccelDeviation = 0;
  double _lastGyroMagnitude = 0;

  double _postImpactGyroPeak = 0;
  bool _wasStationaryAtImpact = false;

  DateTime? _classBAboveStartedAt;
  bool _classBSustainQualified = false;
  DateTime? _classBPostImpactStartedAt;
  int _classBStillFrames = 0;
  bool _classBWasWalking = false;

  static const double _freeFallThreshold = 3.5;
  static const double _impactThreshold = 30.0;
  static const double _stillThreshold = 3.5;
  static const int _stillFramesRequired = 40;

  /// Compensates for the loss of the rotational-confirmation signal: without
  /// gyro we demand 50 % more still frames before declaring a tumble, to keep
  /// the false-positive rate roughly comparable.
  static const int _stillFramesRequiredDegraded = 60;
  static const Duration _freeFallWindow = Duration(milliseconds: 500);
  static const Duration _impactWindow = Duration(seconds: 5);
  static const Duration _cooldownAfterDetection = Duration(seconds: 20);
  static const Duration _cooldownAfterCancel = Duration(seconds: 5);

  /// If no gyroscope event arrives within this window while the accelerometer
  /// is alive, the gyro stream is considered hung and Class A switches to the
  /// degraded (accel-only) profile.
  static const Duration _gyroStalenessTimeout = Duration(seconds: 2);

  static const double _stillGyroMaxRadPerSec = 0.50;

  static const double _fallGyroImpactRadPerSec = 2.50;

  static const double _phoneDropGyroMaxRadPerSec = 1.00;

  static const double _classBImpactThreshold = 19.62;
  static const Duration _classBSustainMin = Duration(milliseconds: 200);
  static const int _classBStillFramesRequired = 100;
  static const Duration _classBPostImpactTimeout = Duration(seconds: 10);

  static const Duration _postCancelGraceWindow = Duration(seconds: 60);
  static const Duration _sosLockoutWindow = Duration(seconds: 20);

  DateTime _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _postCancelGraceUntil;
  DateTime? _sosLockoutEndAt;

  Future<void> init() async {
    _ready = false;
    try {
      _sub =
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 50),
          ).listen(
            _onAccel,
            onError: (e) {
              debugPrint('FallDetector: accelerometer error $e');
            },
          );
      _ready = true;
    } catch (e) {
      debugPrint('FallDetector: accelerometer init failed: $e');
    }

    try {
      _gyroSub =
          gyroscopeEventStream(
            samplingPeriod: const Duration(milliseconds: 50),
          ).listen(
            _onGyro,
            onError: (e) {
              debugPrint('FallDetector: gyroscope error $e');
              _markGyroUnavailable();
            },
          );
      _gyroAvailable = true;
      _lastGyroEventAt = DateTime.now();
    } catch (e) {
      debugPrint('FallDetector: gyroscope init failed: $e');
      _markGyroUnavailable();
    }

    if (_ready) {
      debugPrint('FallDetector: initialized (gyroAvailable=$_gyroAvailable)');
    }
  }

  bool get isReady => _ready;

  /// Whether the gyroscope stream is currently producing usable events.
  /// When false, Class A fall detection runs in a degraded accel-only profile
  /// (no rotational confirmation, raised still-frame requirement).
  bool get isGyroAvailable => _gyroAvailable;

  /// Marks the gyroscope as unavailable and fires [onGyroUnavailable] exactly
  /// once per true→false transition. Idempotent: no-op if already unavailable.
  void _markGyroUnavailable() {
    if (!_gyroAvailable) return;
    _gyroAvailable = false;
    debugPrint(
      'FallDetector: gyroscope unavailable — switching to degraded Class A profile',
    );
    onGyroUnavailable?.call();
  }

  MotionState get motionState => _motionState;

  @visibleForTesting
  bool isInPostCancelGraceAt(DateTime t) =>
      _postCancelGraceUntil != null && t.isBefore(_postCancelGraceUntil!);

  @visibleForTesting
  bool isInSosLockoutAt(DateTime t) =>
      _sosLockoutEndAt != null && t.isBefore(_sosLockoutEndAt!);

  @visibleForTesting
  Duration get postCancelGraceWindow => _postCancelGraceWindow;

  @visibleForTesting
  Duration get sosLockoutWindow => _sosLockoutWindow;

  @visibleForTesting
  void onAccelForTesting(AccelerometerEvent event) => _onAccel(event);

  @visibleForTesting
  void onGyroForTesting(GyroscopeEvent event) => _onGyro(event);

  /// Forces the gyro-availability state for testing. When [available] is true,
  /// [lastEventAt] defaults to now; pass an old timestamp to simulate a hung
  /// stream and exercise the staleness watchdog.
  @visibleForTesting
  void setGyroAvailableForTesting(bool available, {DateTime? lastEventAt}) {
    _gyroAvailable = available;
    _lastGyroEventAt = available ? (lastEventAt ?? DateTime.now()) : null;
  }

  @visibleForTesting
  void markGyroUnavailableForTesting() => _markGyroUnavailable();

  void _onAccel(AccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    final accelWithoutGravity = (magnitude - 9.81).abs();
    _lastAccelDeviation = accelWithoutGravity;
    _updateMotionState();

    final now = DateTime.now();

    // Staleness watchdog: if the gyro stream has not produced an event within
    // the timeout while the accelerometer is alive, treat gyro as dead and
    // switch Class A to the degraded accel-only profile.
    if (_gyroAvailable &&
        _lastGyroEventAt != null &&
        now.difference(_lastGyroEventAt!) > _gyroStalenessTimeout) {
      _markGyroUnavailable();
    }

    final inPostCancelGrace =
        _postCancelGraceUntil != null && now.isBefore(_postCancelGraceUntil!);
    final inSosLockout =
        _sosLockoutEndAt != null && now.isBefore(_sosLockoutEndAt!);
    final cooldownActive =
        now.difference(_lastDetectionAt) < _cooldownAfterDetection;
    if (!inPostCancelGrace && !inSosLockout && cooldownActive) return;
    if (_sosLockoutEndAt != null && !now.isBefore(_sosLockoutEndAt!)) {
      _sosLockoutEndAt = null;
    }

    if (magnitude < _freeFallThreshold) {
      _lastFreeFallAt = now;
      if (now.difference(_lastFreeFallLogAt) > const Duration(seconds: 1)) {
        _lastFreeFallLogAt = now;
        onStageChange?.call(
          'freefall',
          accel: magnitude,
          gyro: _lastGyroMagnitude,
        );
      }
    }

    _processClassB(now, accelWithoutGravity);

    if (!_impactDetected) {
      if (accelWithoutGravity > _impactThreshold) {
        final wasRecentFreeFall =
            now.difference(_lastFreeFallAt) < _freeFallWindow;

        _impactDetected = true;
        _lastImpactAt = now;
        _stillFrames = 0;
        _wasStationaryAtImpact = _motionState == MotionState.stationary;

        _postImpactGyroPeak = _lastGyroMagnitude;
        debugPrint(
          'FallDetector: impact detected (${magnitude.toStringAsFixed(1)} m/s², FF=$wasRecentFreeFall, gyro=${_lastGyroMagnitude.toStringAsFixed(2)})',
        );
        onStageChange?.call(
          'impact',
          accel: accelWithoutGravity,
          gyro: _lastGyroMagnitude,
        );
      }
      return;
    }

    if (now.difference(_lastImpactAt) > _impactWindow) {
      _impactDetected = false;
      _stillFrames = 0;
      onStageChange?.call(
        'aborted_timeout',
        accel: accelWithoutGravity,
        gyro: _postImpactGyroPeak,
        stillFrames: _stillFrames,
      );
      _postImpactGyroPeak = 0;
      return;
    }

    final accelStill = accelWithoutGravity < _stillThreshold;
    final gyroStill = _lastGyroMagnitude < _stillGyroMaxRadPerSec;
    // Degraded profile (no gyro): stillness is accel-only.
    final stillNow = _gyroAvailable ? (accelStill && gyroStill) : accelStill;
    if (stillNow) {
      _stillFrames++;
    } else if (accelWithoutGravity > _impactThreshold * 0.5) {
      _stillFrames = 0;
    } else if (_gyroAvailable && !gyroStill) {
      _stillFrames = 0;
    }

    final stillFramesRequired = _gyroAvailable
        ? _stillFramesRequired
        : _stillFramesRequiredDegraded;
    if (_stillFrames >= stillFramesRequired) {
      final hadRotationalImpact =
          _postImpactGyroPeak >= _fallGyroImpactRadPerSec;
      final peak = _postImpactGyroPeak;
      final hadRecentFreeFall =
          _lastImpactAt.difference(_lastFreeFallAt).abs() < _freeFallWindow;

      final isPhoneDrop =
          peak < _phoneDropGyroMaxRadPerSec && !hadRecentFreeFall;

      onStageChange?.call(
        'stillness_reached',
        accel: accelWithoutGravity,
        gyro: peak,
        stillFrames: _stillFrames,
      );
      _impactDetected = false;
      _stillFrames = 0;
      _postImpactGyroPeak = 0;

      // Phone-drop and rotational-impact checks rely on gyro data and are
      // skipped in the degraded profile — without gyro they would always
      // abort (peak stays 0), making Class A completely dead.
      if (_gyroAvailable && isPhoneDrop) {
        debugPrint(
          'FallDetector: stillness reached but classified as phone drop '
          '(peak=${peak.toStringAsFixed(2)}, freeFall=$hadRecentFreeFall) — ignoring.',
        );
        onStageChange?.call(
          'aborted_phone_drop',
          accel: accelWithoutGravity,
          gyro: peak,
        );
        return;
      }
      if (_gyroAvailable && !hadRotationalImpact) {
        debugPrint(
          'FallDetector: stillness reached but no rotational impact '
          '(peak=${peak.toStringAsFixed(2)}) — ignoring.',
        );
        onStageChange?.call(
          'aborted_no_rotation',
          accel: accelWithoutGravity,
          gyro: peak,
        );
        return;
      }
      if (_wasStationaryAtImpact && !hadRecentFreeFall) {
        debugPrint(
          'FallDetector: user was stationary and no freefall — '
          'likely placed down, ignoring.',
        );
        onStageChange?.call(
          'aborted_stationary_no_freefall',
          accel: accelWithoutGravity,
          gyro: peak,
        );
        return;
      }
      if (_sosLockoutEndAt != null && now.isBefore(_sosLockoutEndAt!)) {
        debugPrint(
          'FallDetector: Class A SECOND FALL DURING LOCKOUT — queueing follow-up',
        );
        onStageChange?.call(
          'confirmed_during_lockout',
          accel: accelWithoutGravity,
          gyro: peak,
        );
        _resetClassB();
        onSecondFallDuringLockout?.call();
        return;
      }
      _lastDetectionAt = now;
      debugPrint('FallDetector: FALL CONFIRMED — triggering callback');
      onStageChange?.call('confirmed', accel: accelWithoutGravity, gyro: peak);
      _resetClassB();
      onFallDetected?.call(FallClass.tumble);
    }
  }

  void _processClassB(DateTime now, double accelWithoutGravity) {
    if (accelWithoutGravity > _classBImpactThreshold) {
      _classBAboveStartedAt ??= now;
      if (!_classBSustainQualified &&
          now.difference(_classBAboveStartedAt!) >= _classBSustainMin) {
        _classBSustainQualified = true;
        _classBWasWalking =
            _motionState == MotionState.walking ||
            _motionState == MotionState.running;
        onStageChange?.call(
          'class_b_sustain',
          accel: accelWithoutGravity,
          gyro: _lastGyroMagnitude,
        );
      }
      _classBStillFrames = 0;
      return;
    }

    _classBAboveStartedAt = null;
    if (!_classBSustainQualified) return;

    if (_classBPostImpactStartedAt == null) {
      _classBPostImpactStartedAt = now;
      _classBStillFrames = 0;
    }

    if (now.difference(_classBPostImpactStartedAt!) >
        _classBPostImpactTimeout) {
      onStageChange?.call(
        'class_b_aborted_timeout',
        accel: accelWithoutGravity,
        gyro: _lastGyroMagnitude,
        stillFrames: _classBStillFrames,
      );
      _resetClassB();
      return;
    }

    final accelStill = accelWithoutGravity < _stillThreshold;
    final gyroStill = _lastGyroMagnitude < _stillGyroMaxRadPerSec;
    if (accelStill && gyroStill) {
      _classBStillFrames++;
    } else {
      _classBStillFrames = 0;
    }

    if (_classBStillFrames < _classBStillFramesRequired) return;

    if (!_classBWasWalking) {
      onStageChange?.call(
        'class_b_aborted_not_walking',
        accel: accelWithoutGravity,
        gyro: _lastGyroMagnitude,
        stillFrames: _classBStillFrames,
      );
      _resetClassB();
      return;
    }

    if (_sosLockoutEndAt != null && now.isBefore(_sosLockoutEndAt!)) {
      debugPrint(
        'FallDetector: Class B SECOND FALL DURING LOCKOUT — queueing follow-up',
      );
      onStageChange?.call(
        'class_b_confirmed_during_lockout',
        accel: accelWithoutGravity,
        gyro: _lastGyroMagnitude,
        stillFrames: _classBStillFrames,
      );
      _resetClassB();
      onSecondFallDuringLockout?.call();
      return;
    }
    _lastDetectionAt = now;
    debugPrint('FallDetector: CLASS B (slow collapse) CONFIRMED');
    onStageChange?.call(
      'class_b_confirmed',
      accel: accelWithoutGravity,
      gyro: _lastGyroMagnitude,
      stillFrames: _classBStillFrames,
    );
    _resetClassB();
    onFallDetected?.call(FallClass.collapse);
  }

  void _resetClassB() {
    _classBAboveStartedAt = null;
    _classBSustainQualified = false;
    _classBPostImpactStartedAt = null;
    _classBStillFrames = 0;
    _classBWasWalking = false;
  }

  void _onGyro(GyroscopeEvent event) {
    _lastGyroEventAt = DateTime.now();
    // Recovery: if gyro events resume after a staleness/error gap, exit the
    // degraded profile so full rotational confirmation is restored.
    if (!_gyroAvailable) {
      _gyroAvailable = true;
      debugPrint(
        'FallDetector: gyroscope recovered — exiting degraded Class A profile',
      );
    }

    _lastGyroMagnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    if (_impactDetected && _lastGyroMagnitude > _postImpactGyroPeak) {
      _postImpactGyroPeak = _lastGyroMagnitude;
    }

    if ((_lastGyroMagnitude - _gyroMotionScore).abs() > 0.1) {
      _updateMotionState();
    }
  }

  void _updateMotionState() {
    final accelScore = (_lastAccelDeviation / 9.81).clamp(0.0, 2.0);
    final gyroScore = (_lastGyroMagnitude / 1.2).clamp(0.0, 2.0);

    _accelMotionScore = (_accelMotionScore * 0.88) + (accelScore * 0.12);
    _gyroMotionScore = (_gyroMotionScore * 0.88) + (gyroScore * 0.12);

    final combined = (_accelMotionScore * 0.65) + (_gyroMotionScore * 0.35);

    final MotionState nextState;
    if (combined < 0.12) {
      nextState = MotionState.stationary;
    } else if (combined < 0.45) {
      nextState = MotionState.walking;
    } else if (_accelMotionScore > kRunningAccelScoreThreshold &&
        _gyroMotionScore < kRunningGyroScoreMax) {
      // High body-motion accel with low rotational jitter = running.
      // High gyro alongside high accel = being jostled (bus/unstable).
      nextState = MotionState.running;
    } else {
      nextState = MotionState.unstable;
    }

    if (nextState == _motionState) return;

    _motionState = nextState;
    onMotionStateChanged?.call(_motionState);
    debugPrint('FallDetector: motion → $_motionState');
  }

  void reset() {
    _impactDetected = false;
    _stillFrames = 0;
    _postImpactGyroPeak = 0;
    _wasStationaryAtImpact = false;
    _resetClassB();
  }

  void notifyCancelled() {
    final now = DateTime.now();
    _lastDetectionAt = now.subtract(
      _cooldownAfterDetection - _cooldownAfterCancel,
    );
    _postCancelGraceUntil = now.add(_postCancelGraceWindow);
    _sosLockoutEndAt = null;
    _impactDetected = false;
    _stillFrames = 0;
    _postImpactGyroPeak = 0;
    _wasStationaryAtImpact = false;
    _resetClassB();
  }

  /// Marks that the SOS for the just-confirmed fall has been delivered.
  /// Opens a [_sosLockoutWindow] during which any second confirmed fall is
  /// routed to [onSecondFallDuringLockout] instead of [onFallDetected],
  /// so the host can queue a follow-up SMS without re-triggering the
  /// countdown UI / a duplicate primary SOS.
  void notifyFallSosSent() {
    final now = DateTime.now();
    _sosLockoutEndAt = now.add(_sosLockoutWindow);
    _lastDetectionAt = now;
    _impactDetected = false;
    _stillFrames = 0;
    _postImpactGyroPeak = 0;
    _wasStationaryAtImpact = false;
    _resetClassB();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _ready = false;
    _gyroAvailable = false;
    _lastGyroEventAt = null;
  }
}
