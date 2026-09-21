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

/// A DepthProvider that reports not-ready, simulating an NCNN session that
/// has been permanently disabled (isReady == false after 3 invalid outputs).
class _DisabledDepthProvider implements DepthProvider {
  @override
  DepthTier get tier => DepthTier.ncnnCpu;
  @override
  bool get isReady => false;
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
  Future<bool> init({int threads = 2}) async => false;
  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async => const [];

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
  }) async => wrapHazardsAsLegacy(const <DepthHazard>[]);

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

  group('Safety audit 2026-06: NCNN session-disable surfaces depth_degraded', () {
    test('onNcnnSessionDisabled() immediately transitions to lowConfidence and '
        'fires onStatusChanged', () {
      final vm = CameraViewModel();
      final models = ModelService.instance;
      final controller = DepthPipelineController(vm: vm, models: models);

      DepthPipelineStatus? fromSeen;
      DepthPipelineStatus? toSeen;
      controller.onStatusChanged = (from, to) {
        fromSeen = from;
        toSeen = to;
      };

      expect(controller.status, DepthPipelineStatus.ok);

      controller.onNcnnSessionDisabled();

      expect(controller.status, DepthPipelineStatus.lowConfidence);
      expect(fromSeen, DepthPipelineStatus.ok);
      expect(toSeen, DepthPipelineStatus.lowConfidence);
    });

    test('onNcnnSessionDisabled() is idempotent — repeated calls do not re-fire '
        'onStatusChanged once already lowConfidence', () {
      final vm = CameraViewModel();
      final models = ModelService.instance;
      final controller = DepthPipelineController(vm: vm, models: models);

      var fireCount = 0;
      controller.onStatusChanged = (from, to) => fireCount++;

      controller.onNcnnSessionDisabled();
      expect(fireCount, 1);
      expect(controller.status, DepthPipelineStatus.lowConfidence);

      // Second call: status already lowConfidence — _setStatus short-circuits.
      controller.onNcnnSessionDisabled();
      expect(fireCount, 1);
    });

    test(
      'analyze() with a not-ready provider counts degraded frames and '
      'announces lowConfidence after _kDegradedFramesToAnnounce calls',
      () async {
        final vm = CameraViewModel();
        final models = ModelService.instance;
        final controller = DepthPipelineController(vm: vm, models: models);
        controller.setProviderReady(true);

        // Inject a disabled (not-ready) provider into the singleton so the
        // controller's early-return branch is exercised.
        models.debugInjectDepthProvider(_DisabledDepthProvider());

        var statusFireCount = 0;
        DepthPipelineStatus? toSeen;
        var frameRejectedCount = 0;
        controller.onStatusChanged = (from, to) {
          statusFireCount++;
          toSeen = to;
        };
        controller.onFrameRejected = (reason, confidence) {
          expect(reason, 'provider_unavailable');
          frameRejectedCount++;
        };

        final image = _FakeCameraImage();
        final now = DateTime(2025, 1, 1, 12, 0, 0);

        // Frame 1: counter=1, no announcement yet.
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.ok);
        expect(statusFireCount, 0);
        expect(frameRejectedCount, 1);

        // Frame 2: counter=2, no announcement yet.
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.ok);
        expect(statusFireCount, 0);
        expect(frameRejectedCount, 2);

        // Frame 3: counter=3 >= _kDegradedFramesToAnnounce → lowConfidence.
        await controller.analyze(image, now);
        expect(controller.status, DepthPipelineStatus.lowConfidence);
        expect(statusFireCount, 1);
        expect(toSeen, DepthPipelineStatus.lowConfidence);
        expect(frameRejectedCount, 3);

        models.debugInjectDepthProvider(null);
      },
    );

    test('analyze() with a null provider also counts degraded frames (no NPE, '
        'announces after threshold)', () async {
      final vm = CameraViewModel();
      final models = ModelService.instance;
      // No provider injected → models.depthProvider == null.
      models.debugInjectDepthProvider(null);

      final controller = DepthPipelineController(vm: vm, models: models);
      controller.setProviderReady(true);

      var statusFireCount = 0;
      controller.onStatusChanged = (from, to) => statusFireCount++;

      final image = _FakeCameraImage();
      final now = DateTime(2025, 1, 1, 12, 0, 0);

      for (var i = 0; i < 3; i++) {
        await controller.analyze(image, now);
      }
      expect(controller.status, DepthPipelineStatus.lowConfidence);
      expect(statusFireCount, 1);
    });
  });
}
