import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

class StepService {
  StreamSubscription? _subscription;
  int _steps = 0;
  int get steps => _steps;

  static const double _stepThresholdSq = 12.5 * 12.5;
  static const int _stepCooldownMs = 350;
  DateTime _lastStepAt = DateTime.now();

  Future<void> init() async {
    _subscription =
        userAccelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 60),
        ).listen((event) {
          final accelerationSq =
              event.x * event.x + event.y * event.y + event.z * event.z;

          if (accelerationSq > _stepThresholdSq) {
            final now = DateTime.now();
            if (now.difference(_lastStepAt).inMilliseconds > _stepCooldownMs) {
              _steps++;
              _lastStepAt = now;
            }
          }
        });
  }

  void reset() {
    _steps = 0;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
