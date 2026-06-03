import 'package:vibration/vibration.dart';

import '../models/constants.dart'
    show kHapticTtsStallPattern, kHapticCriticalCooldownPattern;

class HapticService {
  HapticService._();

  static bool? _hasVibrator;
  static bool? _hasAmplitude;
  static double _strengthMultiplier = 1.0;

  
  static const double _kCriticalFloorMultiplier = 1.0;

  static Future<void> init() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _hasAmplitude = await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitude = false;
    }
  }

  /// Applies to both pulse durations (ms) and amplitudes (0–255).
  /// Range: 0.3–2.0. 1.0 = no change.
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
    
    
    final isCriticalPattern = identical(pattern, kHapticTtsStallPattern) ||
        identical(pattern, kHapticCriticalCooldownPattern);
    final effectiveMultiplier = isCriticalPattern
        ? (_strengthMultiplier < _kCriticalFloorMultiplier
            ? _kCriticalFloorMultiplier
            : _strengthMultiplier)
        : _strengthMultiplier;
    if (!isCriticalPattern && effectiveMultiplier <= 0.05) return;
    try {
      final scaledPattern = effectiveMultiplier == 1.0
          ? pattern
          : [
              for (int i = 0; i < pattern.length; i++)
                i == 0
                    ? pattern[i]
                    : (pattern[i] * effectiveMultiplier).round().clamp(0, 5000),
            ];
      if ((_hasAmplitude ?? false) && intensities != null) {
        final scaledIntens = effectiveMultiplier == 1.0
            ? intensities
            : [
                for (final a in intensities)
                  (a * effectiveMultiplier).round().clamp(1, 255),
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
