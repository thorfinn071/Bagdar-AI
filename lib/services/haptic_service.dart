import 'package:vibration/vibration.dart';

class HapticService {
  HapticService._();

  static bool? _hasVibrator;
  static bool? _hasAmplitude;
  static double _strengthMultiplier = 1.0;

  static DateTime _lastVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kGlobalCooldown = Duration(milliseconds: 300);

  static int _windowVibrateMs = 0;
  static DateTime _windowStart = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kWindowDurationMs = 10000;
  static const int _kWindowMaxVibrateMs = 3000;

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
    bool critical = false,
  }) async {
    if (_hasVibrator == null) await init();
    if (!(_hasVibrator ?? false)) return;
    if (_strengthMultiplier <= 0.05) return;

    final now = DateTime.now();

    if (!critical && now.difference(_lastVibrateAt) < _kGlobalCooldown) return;

    if (now.difference(_windowStart).inMilliseconds >= _kWindowDurationMs) {
      _windowStart = now;
      _windowVibrateMs = 0;
    }

    if (!critical && _windowVibrateMs >= _kWindowMaxVibrateMs) return;

    int patternDuration = 0;
    for (final p in pattern) {
      patternDuration += p;
    }
    _windowVibrateMs += patternDuration;
    _lastVibrateAt = now;

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

