import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum MotionState { stationary, walking, unstable }

class FallDetector {
  StreamSubscription<AccelerometerEvent>? _sub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  bool _ready = false;

  void Function()? onFallDetected;
  void Function(MotionState state)? onMotionStateChanged;
  void Function(
    String stage, {
    double? accel,
    double? gyro,
    int? stillFrames,
  })? onStageChange;

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

  static const double _freeFallThreshold = 3.5;
  static const double _impactThreshold = 30.0;
  static const double _stillThreshold = 3.5;
  static const int _stillFramesRequired = 40;
  static const Duration _freeFallWindow = Duration(milliseconds: 500);
  static const Duration _impactWindow = Duration(seconds: 5);
  static const Duration _cooldownAfterDetection = Duration(seconds: 60);

  static const double _stillGyroMaxRadPerSec = 0.50;

  static const double _fallGyroImpactRadPerSec = 2.50;

  DateTime _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);

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
            },
          );
    } catch (e) {
      debugPrint('FallDetector: gyroscope init failed: $e');
    }

    if (_ready) {
      debugPrint('FallDetector: initialized');
    }
  }

  bool get isReady => _ready;

  MotionState get motionState => _motionState;

  void _onAccel(AccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    
    final accelWithoutGravity = (magnitude - 9.81).abs();
    _lastAccelDeviation = accelWithoutGravity;
    _updateMotionState();

    final now = DateTime.now();

    if (now.difference(_lastDetectionAt) < _cooldownAfterDetection) return;

    if (magnitude < _freeFallThreshold) {
      _lastFreeFallAt = now;
      if (now.difference(_lastFreeFallLogAt) >
          const Duration(seconds: 1)) {
        _lastFreeFallLogAt = now;
        onStageChange?.call(
          'freefall',
          accel: magnitude,
          gyro: _lastGyroMagnitude,
        );
      }
    }

    if (!_impactDetected) {
      if (accelWithoutGravity > _impactThreshold) {
        final wasRecentFreeFall =
            now.difference(_lastFreeFallAt) < _freeFallWindow;

        _impactDetected = true;
        _lastImpactAt = now;
        _stillFrames = 0;

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
    if (accelStill && gyroStill) {
      _stillFrames++;
    } else if (accelWithoutGravity > _impactThreshold * 0.5) {
      _stillFrames = 0;
    } else if (!gyroStill) { 
      _stillFrames = 0;
    }

    if (_stillFrames >= _stillFramesRequired) {
      final hadRotationalImpact =
          _postImpactGyroPeak >= _fallGyroImpactRadPerSec;
      final peak = _postImpactGyroPeak;
      onStageChange?.call(
        'stillness_reached',
        accel: accelWithoutGravity,
        gyro: peak,
        stillFrames: _stillFrames,
      );
      _impactDetected = false;
      _stillFrames = 0;
      _postImpactGyroPeak = 0;
      if (!hadRotationalImpact) {
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
      _lastDetectionAt = now;
      debugPrint('FallDetector: FALL CONFIRMED — triggering callback');
      onStageChange?.call(
        'confirmed',
        accel: accelWithoutGravity,
        gyro: peak,
      );
      onFallDetected?.call();
    }
  }

  void _onGyro(GyroscopeEvent event) {
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

    final nextState = combined < 0.12
        ? MotionState.stationary
        : combined < 0.45
        ? MotionState.walking
        : MotionState.unstable;

    if (nextState == _motionState) return;

    _motionState = nextState;
    onMotionStateChanged?.call(_motionState);
    debugPrint('FallDetector: motion → $_motionState');
  }

  void reset() {
    _impactDetected = false;
    _stillFrames = 0;
    _postImpactGyroPeak = 0;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _ready = false;
  }
}
