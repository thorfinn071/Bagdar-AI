import 'package:bagdar/services/haptic_service.dart';
import 'package:bagdar/safety/alerts/haptic_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibration/vibration.dart';

class _VibrationPlatformDouble extends VibrationPlatform {
  bool available = true;
  bool fail = true;
  int requests = 0;
  @override
  Future<bool> hasVibrator() async => available;
  @override
  Future<bool> hasAmplitudeControl() async => false;
  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
  }) async {
    requests++;
    if (fail) throw PlatformException(code: 'device_failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VibrationPlatform original;
  late _VibrationPlatformDouble platform;
  final cue = HapticCue(
    semantic: HapticSemantic.immediateStop,
    pattern: [0, 80],
    intensities: null,
    critical: true,
  );
  setUp(() {
    original = VibrationPlatform.instance;
    platform = _VibrationPlatformDouble();
    VibrationPlatform.instance = platform;
  });
  tearDown(() {
    VibrationPlatform.instance = original;
  });

  test(
    'a failed platform vibration reply cannot be reported as delivered',
    () async {
      await HapticService.init();
      expect(await HapticService.emitSafetyCue(cue), false);
      platform.fail = false;
      expect(await HapticService.emitSafetyCue(cue), true);
      expect(platform.requests, 2);
    },
  );
  test('an absent vibrator is unavailable and receives no dispatch', () async {
    platform.available = false;
    await HapticService.init();
    expect(await HapticService.emitSafetyCue(cue), false);
    expect(platform.requests, 0);
  });
}
