import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/services/depth_provider.dart';
import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

class _FakeCameraImage implements CameraImage {
  @override
  int get width => 320;

  @override
  int get height => 240;

  @override
  List<Plane> get planes => <Plane>[_FakePlane()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlane implements Plane {
  @override
  Uint8List get bytes => Uint8List(320 * 240);

  @override
  int get bytesPerRow => 320;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledDepthProvider implements DepthProvider {
  final Completer<void> called = Completer<void>();
  final Completer<DepthAnalysisResult>? pending;
  final Duration delay;

  _ControlledDepthProvider.blocking()
    : pending = Completer<DepthAnalysisResult>(),
      delay = Duration.zero;

  _ControlledDepthProvider.immediate({this.delay = Duration.zero})
    : pending = null;

  @override
  DepthTier get tier => DepthTier.ncnnCpu;

  @override
  bool get isReady => true;

  @override
  Future<bool> init({int threads = 2}) async => true;

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async => const <DepthHazard>[];

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
  }) async {
    if (!called.isCompleted) called.complete();
    final blocked = pending;
    if (blocked != null) return blocked.future;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return _alignedResult(
      sourceTimestampUs: sourceTimestampUs,
      rotationDegrees: rotationDegrees,
      mirrored: mirrored,
      cropTopFrac: cropTopFrac,
    );
  }

  static DepthAnalysisResult _alignedResult({
    required int sourceTimestampUs,
    required int rotationDegrees,
    required bool mirrored,
    required double cropTopFrac,
  }) => DepthAnalysisResult(
    frame: DepthFrame(
      values: Float32List.fromList(<double>[0.8]),
      confidence01: Float32List.fromList(<double>[1]),
      width: 1,
      height: 1,
      timestampUs: sourceTimestampUs,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: 'test-depth',
      modelHash: 'test-hash',
      preprocessId: 'test-preprocess',
      cropTopFraction: cropTopFrac,
      frameQuality: 1,
      alignedToImage: true,
      rotationDegrees: rotationDegrees,
      mirrored: mirrored,
    ),
    legacyHazards: const <DepthHazard>[],
    health: DepthHealth.legacyOnly(
      provider: DepthProviderKind.ncnnRelative,
      reason: 'genericObstacleUnavailable',
    ),
  );

  static DepthAnalysisResult legacyResult() => DepthAnalysisResult(
    frame: null,
    legacyHazards: const <DepthHazard>[],
    health: DepthHealth.legacyOnly(
      provider: DepthProviderKind.ncnnRelative,
      reason: 'genericObstacleUnavailable',
    ),
  );

  @override
  bool get nativeBridgeEnabled => false;
  @override
  bool get nativeBridgeAvailable => false;
  @override
  bool get lowConfidenceFallbackActive => false;
  @override
  double get lastConfidenceScore => 1;
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
  void setNativeBridgeEnabled(bool enabled) {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('callback age includes waiting before provider starts', () async {
    final vm = CameraViewModel();
    final controller = DepthPipelineController(
      vm: vm,
      models: ModelService.instance,
      maxObservationLatency: const Duration(milliseconds: 100),
    )..setProviderReady(true);
    controller.beginSession(vm.cameraSession.beginNewSession());
    ModelService.instance.debugInjectDepthProvider(
      _ControlledDepthProvider.immediate(),
    );
    final samples = <DepthPerformanceSample>[];
    controller.onPerformanceSample = samples.add;
    final at = DateTime.utc(2026, 10, 5);
    final result = await controller.analyze(
      _FakeCameraImage(),
      at,
      timing: CallbackFrameTiming.forTesting(
        at.microsecondsSinceEpoch,
        () => 150000,
      ),
    );
    expect(result, isEmpty);
    expect(controller.lastAcceptedPacket, isNull);
    expect(controller.lastFrameRejectionReason, 'stale_observation_latency');
    expect(samples.single.callbackToDecisionUs, 150000);
    expect(samples.single.providerCalled, isTrue);
    expect(samples.single.accepted, isFalse);
    expect(samples.single.rejectionReason, 'stale_observation_latency');
  });

  test('release checks age again after generic postprocessing', () async {
    final vm = CameraViewModel();
    final controller = DepthPipelineController(
      vm: vm,
      models: ModelService.instance,
      maxObservationLatency: const Duration(milliseconds: 100),
    )..setProviderReady(true);
    controller.beginSession(vm.cameraSession.beginNewSession());
    ModelService.instance.debugInjectDepthProvider(
      _ControlledDepthProvider.immediate(),
    );
    var clockReads = 0;
    final at = DateTime.utc(2026, 10, 5);
    await controller.analyze(
      _FakeCameraImage(),
      at,
      timing: CallbackFrameTiming.forTesting(
        at.microsecondsSinceEpoch,
        () => ++clockReads <= 2 ? 0 : 200000,
      ),
    );
    expect(controller.lastAcceptedPacket, isNull);
    expect(controller.lastAcceptedObservationHeader, isNull);
    expect(controller.lastGenericDetection, isNull);
    expect(controller.lastGenericDecisions, isEmpty);
    expect(controller.lastFrameRejectionReason, 'stale_observation_latency');
    expect(controller.status, DepthPipelineStatus.unalignedStale);
  });

  test(
    'telemetry sink failure cannot reject an otherwise valid result',
    () async {
      final vm = CameraViewModel();
      final controller = DepthPipelineController(
        vm: vm,
        models: ModelService.instance,
      )..setProviderReady(true);
      controller.beginSession(vm.cameraSession.beginNewSession());
      ModelService.instance.debugInjectDepthProvider(
        _ControlledDepthProvider.immediate(),
      );
      controller.onPerformanceSample = (_) => throw StateError('sink failed');
      final at = DateTime.utc(2026, 10, 5);
      await controller.analyze(_FakeCameraImage(), at);
      expect(controller.lastAcceptedPacket, isNotNull);
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService.instance.init();
    ModelService.instance.debugInjectDepthProvider(null);
  });

  tearDown(() {
    ModelService.instance.debugInjectDepthProvider(null);
  });

  for (final initiallyHasCar in [false, true]) {
    test(
      'background result uses its submitted YOLO context: $initiallyHasCar',
      () async {
        final vm = CameraViewModel();
        final controller = DepthPipelineController(
          vm: vm,
          models: ModelService.instance,
        )..setProviderReady(true);
        controller.beginSession(vm.cameraSession.beginNewSession());
        final at = DateTime.utc(2026, 10, 5);
        final car = Track(
          id: 1,
          label: 'car',
          cx: 160,
          cy: 120,
          x1: 140,
          y1: 80,
          x2: 180,
          y2: 160,
          dist: 'close',
          distM: 1,
          initialConf: 0.9,
        );
        List<DepthHazardAlert> alerts = [];
        // Fusion requires three stable frames. Advance its history with the
        // same submitted context while replacing live YOLO during every await.
        for (var i = 0; i < 3; i++) {
          final provider = _ControlledDepthProvider.blocking();
          ModelService.instance.debugInjectDepthProvider(provider);
          final frameAt = at.add(Duration(seconds: i * 5));
          controller.updateYoloTracks(
            initiallyHasCar ? [car] : [],
            imgW: 320,
            now: frameAt,
          );
          final result = controller.analyze(_FakeCameraImage(), frameAt);
          await provider.called.future;
          controller.updateYoloTracks(
            initiallyHasCar ? [] : [car],
            imgW: 320,
            now: frameAt.add(const Duration(milliseconds: 50)),
          );
          provider.pending!.complete(
            DepthAnalysisResult(
              legacyHazards: const [
                DepthHazard(
                  midasScore: 0.5,
                  type: DepthHazardType.curb,
                  zone: HazardZone.center,
                  coverage: 1,
                ),
              ],
              health: DepthHealth.legacyOnly(
                provider: DepthProviderKind.ncnnRelative,
                reason: 'genericObstacleUnavailable',
              ),
            ),
          );
          alerts = await result;
        }
        expect(alerts, hasLength(1));
        expect(alerts.single.isCritical, initiallyHasCar);
      },
    );
  }

  test(
    'a superseded late inference cannot update current scene state',
    () async {
      final provider = _ControlledDepthProvider.blocking();
      final vm = CameraViewModel();
      final controller = DepthPipelineController(
        vm: vm,
        models: ModelService.instance,
      )..setProviderReady(true);
      final generation = vm.cameraSession.beginNewSession();
      controller.beginSession(generation);
      ModelService.instance.debugInjectDepthProvider(provider);
      final rejected = <String>[];
      controller.onFrameRejected = (reason, _) => rejected.add(reason);

      final at = DateTime.utc(2026, 9, 19, 10);
      final first = controller.analyze(_FakeCameraImage(), at);
      await provider.called.future;

      // The second request becomes the latest packet but cannot start another
      // heavy provider call while the first one remains in flight.
      await controller.analyze(
        _FakeCameraImage(),
        at.add(const Duration(milliseconds: 1)),
      );
      provider.pending!.complete(_ControlledDepthProvider.legacyResult());
      await first;

      expect(controller.lastAcceptedPacket, isNull);
      expect(controller.lastAcceptedObservationHeader, isNull);
      expect(controller.lastHealth, isNull);
      expect(controller.lastGenericDecisions, isEmpty);
      expect(rejected, contains('superseded_frame'));
    },
  );

  for (final changeMirror in [false, true]) {
    test(
      'camera transform changing during inference rejects result: mirror=$changeMirror',
      () async {
        final provider = _ControlledDepthProvider.blocking();
        final vm = CameraViewModel();
        final controller = DepthPipelineController(
          vm: vm,
          models: ModelService.instance,
        )..setProviderReady(true);
        controller.beginSession(vm.cameraSession.beginNewSession());
        ModelService.instance.debugInjectDepthProvider(provider);
        final result = controller.analyze(
          _FakeCameraImage(),
          DateTime.utc(2026, 10, 5),
        );
        await provider.called.future;
        if (changeMirror) {
          vm.cameraMirrored = true;
        } else {
          vm.cameraSensorRotationDeg = 90;
        }
        provider.pending!.complete(_ControlledDepthProvider.legacyResult());
        expect(await result, isEmpty);
        expect(controller.lastAcceptedPacket, isNull);
        expect(controller.lastGenericDetection, isNull);
        expect(controller.lastGenericDecisions, isEmpty);
        expect(
          controller.lastFrameRejectionReason,
          'active_camera_transform_mismatch',
        );
      },
    );
  }

  test('camera session restart rejects the old provider result', () async {
    final provider = _ControlledDepthProvider.blocking();
    final vm = CameraViewModel();
    final controller = DepthPipelineController(
      vm: vm,
      models: ModelService.instance,
    )..setProviderReady(true);
    final firstGeneration = vm.cameraSession.beginNewSession();
    controller.beginSession(firstGeneration);
    ModelService.instance.debugInjectDepthProvider(provider);

    final at = DateTime.utc(2026, 9, 19, 10);
    final pendingResult = controller.analyze(_FakeCameraImage(), at);
    await provider.called.future;
    final secondGeneration = vm.cameraSession.beginNewSession();
    controller.beginSession(secondGeneration);

    provider.pending!.complete(_ControlledDepthProvider.legacyResult());
    await pendingResult;

    expect(secondGeneration, firstGeneration + 1);
    expect(controller.lastAcceptedPacket, isNull);
    expect(controller.lastAcceptedObservationHeader, isNull);
    expect(controller.lastHealth, isNull);
  });

  test(
    'accepted observations carry model hash and preprocess identity',
    () async {
      final provider = _ControlledDepthProvider.immediate();
      final vm = CameraViewModel()
        ..cameraSensorRotationDeg = 90
        ..cameraMirrored = true;
      final controller = DepthPipelineController(
        vm: vm,
        models: ModelService.instance,
      )..setProviderReady(true);
      final generation = vm.cameraSession.beginNewSession();
      controller.beginSession(generation);
      ModelService.instance.debugInjectDepthProvider(provider);

      await controller.analyze(
        _FakeCameraImage(),
        DateTime.utc(2026, 9, 19, 10),
      );

      final header = controller.lastAcceptedObservationHeader;
      expect(header, isNotNull);
      expect(header!.modelId, 'test-depth');
      expect(header.modelHash, 'test-hash');
      expect(header.preprocessId, 'test-preprocess');
      expect(header.transformId, controller.lastAcceptedPacket!.transformId);
      expect(header.sessionGeneration, generation);
      expect(header.frameId, 1);
      expect(header.toDiagnosticMap(), isNot(contains('payload')));
    },
  );

  test('failed frame clears the previous accepted observation', () async {
    final provider = _ControlledDepthProvider.immediate();
    final vm = CameraViewModel();
    final controller = DepthPipelineController(
      vm: vm,
      models: ModelService.instance,
    )..setProviderReady(true);
    final generation = vm.cameraSession.beginNewSession();
    controller.beginSession(generation);
    ModelService.instance.debugInjectDepthProvider(provider);
    final at = DateTime.utc(2026, 9, 19, 10);

    await controller.analyze(_FakeCameraImage(), at);
    expect(controller.lastAcceptedObservationHeader, isNotNull);

    ModelService.instance.debugInjectDepthProvider(null);
    await controller.analyze(
      _FakeCameraImage(),
      at.add(const Duration(seconds: 1)),
    );

    expect(controller.lastAcceptedPacket, isNull);
    expect(controller.lastAcceptedObservationHeader, isNull);
    expect(controller.lastGenericDetection, isNull);
    expect(controller.lastGenericTracks, isEmpty);
    expect(controller.lastFrameRejectionReason, 'provider_unavailable');
  });

  test('over-latency observation is rejected and degrades status', () async {
    final provider = _ControlledDepthProvider.immediate(
      delay: const Duration(milliseconds: 2),
    );
    final vm = CameraViewModel();
    final controller = DepthPipelineController(
      vm: vm,
      models: ModelService.instance,
      maxObservationLatency: const Duration(milliseconds: 1),
    )..setProviderReady(true);
    final generation = vm.cameraSession.beginNewSession();
    controller.beginSession(generation);
    ModelService.instance.debugInjectDepthProvider(provider);

    await controller.analyze(_FakeCameraImage(), DateTime.utc(2026, 9, 19, 10));

    expect(controller.lastAcceptedObservationHeader, isNull);
    expect(controller.lastHealth, isNull);
    expect(controller.status, DepthPipelineStatus.unalignedStale);
  });
}
