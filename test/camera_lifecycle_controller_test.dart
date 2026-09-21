import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/camera_lifecycle_controller.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/field_logger.dart';
import 'package:bagdar/services/indoor_gate.dart';
import 'package:bagdar/services/tts_service.dart';

class _FakeHost implements CameraLifecycleHost {
  @override
  CameraController? cameraController;

  @override
  bool isCameraReady = true;

  int initCameraCalls = 0;
  int background = 0;
  int foreground = 0;
  int sessionStarts = 0;

  @override
  Future<void> initCamera() async {
    initCameraCalls++;
  }

  @override
  void onFrame(CameraImage image) {}

  @override
  void onBackgroundEntered() => background++;

  @override
  void onCameraSessionStarting() => sessionStarts++;

  @override
  void onForegroundResumed() => foreground++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paused then resumed with no controller uses cold initCamera', () async {
    final host = _FakeHost()..isCameraReady = false;
    var motion = MotionState.running;
    final life = CameraLifecycleController(
      host: host,
      tts: TtsService.forTesting(),
      fieldLog: FieldLogger.instance,
      indoorGate: IndoorGate(),
      motionStateProvider: () => motion,
    );

    life.handleStateChange(AppLifecycleState.paused);
    expect(host.background, 1);
    expect(host.isCameraReady, isFalse);

    await Future<void>.delayed(Duration.zero);
    life.handleStateChange(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(host.foreground, 1);
    expect(host.initCameraCalls, 1);
    life.dispose();
  });
}
