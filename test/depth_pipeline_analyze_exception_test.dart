import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/services/depth_provider.dart';
import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

/// Minimal CameraImage stand-in — only width/height/planes are accessed
/// before the early-return branch in DepthPipelineController.analyze.
class _FakeCameraImage implements CameraImage {
  @override
  List<Plane> get planes => [_FakePlane()];
  @override
  int get width => 256;
  @override
  int get height => 256;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlane implements Plane {
  @override
  Uint8List get bytes => Uint8List(256 * 256);
  @override
  int get bytesPerRow => 256;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A DepthProvider whose analyze() always throws, simulating a permanently
/// broken platform/NCNN stack that never reaches the onSessionDisabled path.
/// isReady reports true and confidence is 0 so the controller passes both the
/// provider-available gate and the confidence gate and actually calls analyze.
class _ThrowingDepthProvider implements DepthProvider {
  @override
  DepthTier get tier => DepthTier.ncnnCpu;
  @override
  bool get isReady => true;
  @override
  bool get nativeBridgeEnabled => false;
  @override
  bool get nativeBridgeAvailable => false;
  @override
  bool get lowConfidenceFallbackActive => false;
  @override
  double get lastConfidenceScore => 0;
  @override
  double get lastPreprocessMs => 0;
  @override
  double get lastInferenceMs => 0;
  @override
  double get lastAnalyzeMs => 0;
  @override
  bool get lastUsedNativeBridge => false;
  @override
  bool get lastPlaneFitOk => true;
  @override
  Future<bool> init({int threads = 2}) async => true;
  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async {
    throw StateError('permanent analyze failure');
  }

  @override
  Future<DepthAnalysisResult> analyzeDetailed(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
    int sourceTimestampUs = 0,
    int rotationDegrees = 0,
    bool mirrored = false,
  }) => analyze(
    image,
    cropTopFrac: cropTopFrac,
    userStationary: userStationary,
    weatherDegraded: weatherDegraded,
    winterMode: winterMode,
  ).then(wrapHazardsAsLegacy);

  @override
  void setNativeBridgeEnabled(bool enabled) {}
  @override
  void dispose() {}
}

/// A DepthProvider that throws from analyze() only while [throwOnAnalyze] is
/// true, otherwise returns an empty hazard list. Used to verify the
/// consecutive-exception counter resets on a successful analyze so a single
/// transient error does not falsely accumulate toward a degradation notice.
class _FlakyDepthProvider implements DepthProvider {
  bool throwOnAnalyze = true;

  @override
  DepthTier get tier => DepthTier.ncnnCpu;
  @override
  bool get isReady => true;
  @override
  bool get nativeBridgeEnabled => false;
  @override
  bool get nativeBridgeAvailable => false;
  @override
  bool get lowConfidenceFallbackActive => false;
  @override
  double get lastConfidenceScore => 0;
  @override
  double get lastPreprocessMs => 0;
  @override
  double get lastInferenceMs => 0;
  @override
  double get lastAnalyzeMs => 0;
  @override
  bool get lastUsedNativeBridge => false;
  @override
  bool get lastPlaneFitOk => true;
  @override
  Future<bool> init({int threads = 2}) async => true;
  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async {
    if (throwOnAnalyze) {
      throw StateError('transient analyze failure');
    }
    return const <DepthHazard>[];
  }

  @override
  Future<DepthAnalysisResult> analyzeDetailed(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
    int sourceTimestampUs = 0,
    int rotationDegrees = 0,
    bool mirrored = false,
  }) => analyze(
    image,
    cropTopFrac: cropTopFrac,
    userStationary: userStationary,
    weatherDegraded: weatherDegraded,
    winterMode: winterMode,
  ).then(wrapHazardsAsLegacy);

  @override
  void setNativeBridgeEnabled(bool enabled) {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('Safety audit 2026-06: analyze() exceptions surface depth_degraded', () {
    test('a permanently throwing provider transitions to lowConfidence after 3 '
        'consecutive analyze() calls and fires onStatusChanged once', () async {
      final vm = CameraViewModel();
      final models = ModelService.instance;
      final controller = DepthPipelineController(vm: vm, models: models);
      controller.setProviderReady(true);
      models.debugInjectDepthProvider(_ThrowingDepthProvider());

      var statusFireCount = 0;
      DepthPipelineStatus? fromSeen;
      DepthPipelineStatus? toSeen;
      controller.onStatusChanged = (from, to) {
        statusFireCount++;
        fromSeen = from;
        toSeen = to;
      };

      final image = _FakeCameraImage();
      final now = DateTime(2025, 1, 1, 12, 0, 0);

      // Frame 1: exception counter=1, status still ok.
      await controller.analyze(image, now);
      expect(controller.status, DepthPipelineStatus.ok);
      expect(statusFireCount, 0);

      // Frame 2: exception counter=2, status still ok.
      await controller.analyze(image, now);
      expect(controller.status, DepthPipelineStatus.ok);
      expect(statusFireCount, 0);

      // Frame 3: exception counter=3 >= _kAnalyzeFailuresToAnnounce
      // → lowConfidence + onStatusChanged.
      await controller.analyze(image, now);
      expect(controller.status, DepthPipelineStatus.lowConfidence);
      expect(statusFireCount, 1);
      expect(fromSeen, DepthPipelineStatus.ok);
      expect(toSeen, DepthPipelineStatus.lowConfidence);

      // Frame 4: status already lowConfidence — _setStatus short-circuits,
      // no second announcement.
      await controller.analyze(image, now);
      expect(controller.status, DepthPipelineStatus.lowConfidence);
      expect(statusFireCount, 1);

      models.debugInjectDepthProvider(null);
    });

    test(
      'a single successful analyze() resets the consecutive-exception counter '
      'so transient errors do not falsely accumulate to a degradation notice',
      () async {
        final vm = CameraViewModel();
        final models = ModelService.instance;
        final controller = DepthPipelineController(vm: vm, models: models);
        controller.setProviderReady(true);
        final provider = _FlakyDepthProvider();
        models.debugInjectDepthProvider(provider);

        var statusFireCount = 0;
        controller.onStatusChanged = (from, to) => statusFireCount++;

        final image = _FakeCameraImage();
        final now = DateTime(2025, 1, 1, 12, 0, 0);

        // Two throwing frames: counter=2, no announcement yet.
        provider.throwOnAnalyze = true;
        await controller.analyze(image, now);
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.ok);
        expect(statusFireCount, 0);

        // One successful frame: counter resets to 0.
        provider.throwOnAnalyze = false;
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.ok);
        expect(statusFireCount, 0);

        // Two more throwing frames after the reset: counter only reaches 2,
        // still below the threshold → no degradation announcement.
        provider.throwOnAnalyze = true;
        await controller.analyze(image, now);
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.ok);
        expect(statusFireCount, 0);

        // A third throwing frame (counter=3) finally announces.
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.lowConfidence);
        expect(statusFireCount, 1);

        models.debugInjectDepthProvider(null);
      },
    );
  });
}
