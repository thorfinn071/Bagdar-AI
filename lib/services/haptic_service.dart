import 'package:vibration/vibration.dart';

class HapticService {
  HapticService._();

  static bool? _hasVibrator;
  static bool? _hasAmplitude;
  static double _strengthMultiplier = 1.0;

  static Future<void> init() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _hasAmplitude = await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitude = false;
    }
  }

  
  
  static void setStrengthMultiplier(double m) {
    _strengthMultiplier = m.clamp(0.3, 2.0);
  }

  static double get strengthMultiplier => _strengthMultiplier;

  static Future<void> vibrate(
    List<int> pattern, {
    List<int>? intensities,
  }) async {
    if (_hasVibrator == null) await init();
    if (!(_hasVibrator ?? false)) return;
    if (_strengthMultiplier <= 0.05) return;
    try {
      final scaledPattern = _strengthMultiplier == 1.0
          ? pattern
          : [
              for (int i = 0; i < pattern.length; i++)
                i == 0
                    ? pattern[i]
                    : (pattern[i] * _strengthMultiplier).round().clamp(0, 5000),
            ];
      if ((_hasAmplitude ?? false) && intensities != null) {
        final scaledIntens = _strengthMultiplier == 1.0
            ? intensities
            : [
                for (final a in intensities)
                  (a * _strengthMultiplier).round().clamp(1, 255),
              ];
        await Vibration.vibrate(
          pattern: scaledPattern,
          intensities: scaledIntens,
        );
      } else {
        await Vibration.vibrate(pattern: scaledPattern);
      }
    } catch (_) {}
  }
}
