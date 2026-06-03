import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

enum DevicePitch { tooHigh, optimal, tooLow, flat }

class OrientationService {
  StreamSubscription? _subscription;
  double _pitch = 0;
  double _roll = 0;
  bool _firstSample = true;
  DevicePitch _state = DevicePitch.flat;
  bool _rollExcessive = false;

  void Function(DevicePitch state)? onPitchChanged;
  void Function(bool excessive)? onRollChanged;

  static const double _kCropMin = 0.20;
  static const double _kCropMid = 0.40;
  static const double _kCropMax = 0.55;
  static const double _kPitchLow = 30.0;
  static const double _kPitchHigh = 60.0;

  static const double kRollEnterThreshold = 35.0;
  static const double kRollExitThreshold = 25.0;
  static const double kRollExcessiveThreshold = kRollEnterThreshold;

  static double cropTopFracForPitch(double pitchDeg) {
    if (!pitchDeg.isFinite) return _kCropMid;
    if (pitchDeg <= _kPitchLow) return _kCropMin;
    if (pitchDeg >= _kPitchHigh) return _kCropMax;
    const span = _kPitchHigh - _kPitchLow;
    final t = (pitchDeg - _kPitchLow) / span;
    return _kCropMin + (_kCropMax - _kCropMin) * t;
  }

  static double computeRoll(double ax, double az) {
    final rad = math.atan2(ax, az);
    return rad * 180.0 / math.pi;
  }

  Future<void> init() async {
    _subscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 60),
        ).listen((event) {
          final pitchRad = math.atan2(event.y.abs(), event.z);
          final rawPitch = pitchRad * 180 / math.pi;
          final rawRoll = computeRoll(event.x, event.z);

          if (_firstSample) {
            _pitch = rawPitch;
            _roll = rawRoll;
            _firstSample = false;
          } else {
            _pitch = _pitch * 0.8 + rawPitch * 0.2;
            _roll = _roll * 0.85 + rawRoll * 0.15;
          }

          DevicePitch newState;
          if (_pitch > 75) {
            newState = DevicePitch.tooHigh;
          } else if (_pitch < 15) {
            newState = DevicePitch.tooLow;
          } else if (_pitch > 30 && _pitch < 60) {
            newState = DevicePitch.optimal;
          } else {
            newState = DevicePitch.flat;
          }

          if (newState != _state) {
            _state = newState;
            onPitchChanged?.call(_state);
          }

          final absRoll = _roll.abs();
          final bool nowExcessive;
          if (_rollExcessive) {
            nowExcessive = absRoll >= kRollExitThreshold;
          } else {
            nowExcessive = absRoll >= kRollEnterThreshold;
          }
          if (nowExcessive != _rollExcessive) {
            _rollExcessive = nowExcessive;
            onRollChanged?.call(_rollExcessive);
          }
        });
  }

  double get pitch => _pitch;
  double get roll => _roll;
  DevicePitch get state => _state;

  bool get isRollExcessive => _rollExcessive;

  void dispose() {
    _subscription?.cancel();
  }
}
