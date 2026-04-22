import 'package:vibration/vibration.dart';

class HapticService {
  HapticService._();

  static bool? _hasVibrator;
  static bool? _hasAmplitude;

  static Future<void> init() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _hasAmplitude = await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitude = false;
    }
  }

  static Future<void> vibrate(
    List<int> pattern, {
    List<int>? intensities,
  }) async {
    if (_hasVibrator == null) await init();
    if (!(_hasVibrator ?? false)) return;
    try {
      if ((_hasAmplitude ?? false) && intensities != null) {
        await Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else {
        await Vibration.vibrate(pattern: pattern);
      }
    } catch (_) {}
  }
}
