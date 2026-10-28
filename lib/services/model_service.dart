import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';

import '../core/build_profile.dart';
import '../models/model_bakeoff_contract.dart';
import 'settings_service.dart';
import 'depth_provider.dart';
import 'ncnn_depth_provider.dart';
import 'device_capability.dart';
import 'thermal_monitor.dart';

enum YoloInputTier { small, standard }

class ModelService {
  static final ModelService instance = ModelService._();
  ModelService._();

  // Safety audit 2026-06 fix A-1: callback when YOLO cannot be recovered
  void Function()? onYoloUnavailable;

  FlutterVision? _visionImpl;
  DepthProvider? _depthProvider;
  Future<bool>? _depthLoading;
  int _depthGeneration = 0;

  FlutterVision get _vision => _visionImpl ??= FlutterVision();

  bool _yoloLoaded = false;
  bool _midasLoaded = false;
  YoloInputTier _currentYoloTier = YoloInputTier.standard;
  Set<String>? _availableAssets;
  int _lastLoadThreads = 2;
  bool _lastLoadGpu = false;
  bool _yoloReloadBusy = false;

  static const String _standardYoloAsset = 'assets/yolov8n_int8.tflite';
  static const String _smallYoloAsset = 'assets/yolov8n_320_int8.tflite';

  FlutterVision get vision => _vision;
  bool get visionInstantiated => _visionImpl != null;
  DepthProvider? get depthProvider => _depthProvider;
  YoloInputTier get currentYoloTier => _currentYoloTier;

  bool get yoloLoaded => _yoloLoaded;
  bool get midasLoaded => _midasLoaded;
  ProductionModelSelection get productionSelection =>
      BagdarModelCatalog.productionSelection;
  List<ModelArtifactContract> get detectorExperiments =>
      BagdarModelCatalog.detectorExperiments;

  /// ARCore currently owns a second camera session and cannot be aligned to
  /// the Flutter image stream. Core therefore always keeps it disabled.
  /// Research builds require both a compile-time profile and explicit opt-in.
  static bool independentHardwareCameraAllowed({
    required BuildProfile profile,
    required bool userRequested,
  }) => profile.isResearch && userRequested;

  Future<void> init() async {}

  Future<bool> hasSmallYoloAsset() async {
    final assets = await _loadAssetManifest();
    return assets.contains(_smallYoloAsset);
  }

  Future<Set<String>> _loadAssetManifest() async {
    if (_availableAssets != null) return _availableAssets!;
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final parsed = <String>{};
      final trimmed = manifest.trim();
      if (trimmed.startsWith('{')) {
        final keyPattern = RegExp(r'"([^"]+)"\s*:');
        for (final m in keyPattern.allMatches(trimmed)) {
          parsed.add(m.group(1)!);
        }
      }
      _availableAssets = parsed;
    } catch (e) {
      debugPrint('ModelService: AssetManifest load failed ($e)');
      _availableAssets = <String>{};
    }
    return _availableAssets!;
  }

  Future<String> _resolveYoloModelPath(YoloInputTier tier) async {
    if (tier == YoloInputTier.small) {
      final haveSmall = await hasSmallYoloAsset();
      if (haveSmall) return _smallYoloAsset;
    }
    return _standardYoloAsset;
  }

  Future<YoloInputTier> _desiredTierForDevice() async {
    try {
      final caps = DeviceCapabilityProbe.cached;
      if (caps.isLowEnd) return YoloInputTier.small;
    } catch (_) {}
    return YoloInputTier.standard;
  }

  Future<void> loadYolo({bool? useGpu, int? numThreads}) async {
    final gpu = useGpu ?? Settings.instance.useGpu;
    final threads = numThreads ?? Settings.instance.numThreads;
    final tier = await _desiredTierForDevice();
    await _loadYoloAtTier(tier: tier, gpu: gpu, threads: threads);
  }

  Future<void> _loadYoloAtTier({
    required YoloInputTier tier,
    required bool gpu,
    required int threads,
  }) async {
    final modelPath = await _resolveYoloModelPath(tier);
    final effectiveTier = modelPath == _standardYoloAsset
        ? YoloInputTier.standard
        : tier;

    Future<void> tryLoad(bool gpuVal) async {
      await _vision.closeYoloModel();
      await _vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: modelPath,
        modelVersion: 'yolov8',
        numThreads: threads,
        useGpu: gpuVal,
      );
    }

    try {
      await tryLoad(gpu);
    } catch (_) {
      if (gpu) {
        await tryLoad(false);
      } else {
        rethrow;
      }
    }
    _yoloLoaded = true;
    _currentYoloTier = effectiveTier;
    _lastLoadThreads = threads;
    _lastLoadGpu = gpu;
    debugPrint(
      'ModelService: YOLO loaded tier=$effectiveTier '
      'path=$modelPath gpu=$gpu threads=$threads',
    );
  }

  /// B-1: Adaptive YOLO input size with thermal awareness.
  ///
  /// At `ThermalSeverity.hot/critical` we swap to a 320×320 small-tier
  /// model (~30-40% inference time reduction) so the burst-frame mechanism
  /// in `PerformanceThrottler` stays effective even under sustained heat.
  ///
  /// This thermal path remains on the pinned YOLOv8 family. Stage 6 does not
  /// infer candidate recall from resolution; promotion requires recorded-scene
  /// and named-device evidence.
  ///
  /// Asset requirement: `assets/yolov8n_320_int8.tflite` must be bundled
  /// (export via `yolo export model=yolov8n.pt format=tflite imgsz=320
  /// int8=True`). When the asset is absent, this method is a no-op and the
  /// pipeline continues with the standard 416×416 model — degraded perf
  /// but no functional regression.
  ///
  /// Hysteresis: `severity` here is already committed via `PerformanceThrottler`'s
  /// 60 s commit-dwell, so this method is safe from rapid warm↔hot flapping.
  /// The `_yoloReloadBusy` guard further prevents concurrent reloads.
  Future<void> adjustForThermal(ThermalSeverity severity) async {
    if (!_yoloLoaded || _yoloReloadBusy) return;
    final desired =
        severity == ThermalSeverity.hot || severity == ThermalSeverity.critical
        ? YoloInputTier.small
        : await _desiredTierForDevice();
    if (desired == _currentYoloTier) return;
    if (desired == YoloInputTier.small && !(await hasSmallYoloAsset())) {
      return;
    }
    _yoloReloadBusy = true;
    _yoloLoaded = false;
    try {
      await _loadYoloAtTier(
        tier: desired,
        gpu: _lastLoadGpu,
        threads: _lastLoadThreads,
      );
    } catch (e) {
      debugPrint('ModelService: thermal-aware YOLO reload failed ($e)');
      // Safety audit 2026-06 fix A-1: attempt rollback to previous tier
      // _currentYoloTier still holds the old value because _loadYoloAtTier
      // only updates it on success (line 124). The old model was already
      // closed inside _loadYoloAtTier, so we must reload it.
      try {
        await _loadYoloAtTier(
          tier: _currentYoloTier,
          gpu: _lastLoadGpu,
          threads: _lastLoadThreads,
        );
      } catch (e2) {
        debugPrint('ModelService: YOLO rollback also failed ($e2)');
        // Safety audit 2026-06 fix A-1: notify host that YOLO is dead
        onYoloUnavailable?.call();
      }
    } finally {
      _yoloReloadBusy = false;
    }
  }

  @visibleForTesting
  YoloInputTier? debugDesiredTierForThermal(
    ThermalSeverity severity, {
    required bool hasSmall,
    required bool isLowEnd,
  }) {
    final desired =
        severity == ThermalSeverity.hot || severity == ThermalSeverity.critical
        ? YoloInputTier.small
        : (isLowEnd ? YoloInputTier.small : YoloInputTier.standard);
    if (desired == YoloInputTier.small && !hasSmall) return null;
    return desired;
  }

  Future<bool> loadMidas({int? numThreads}) => _depthLoading ??= _loadMidas(
    numThreads: numThreads,
  ).whenComplete(() => _depthLoading = null);

  Future<bool> _loadMidas({int? numThreads}) async {
    final generation = ++_depthGeneration;
    final previous = _depthProvider;
    _depthProvider = null;
    _midasLoaded = false;
    previous?.dispose();
    if (previous is NcnnDepthProvider) await previous.shutdown();
    final threads = numThreads ?? Settings.instance.numThreads;
    final caps = await DeviceCapabilityProbe.probe();

    final provider = await DepthProviderFactory.createAndInit(
      caps,
      threads: threads,
      allowIndependentHardwareCamera: independentHardwareCameraAllowed(
        profile: BuildProfile.current,
        userRequested: Settings.instance.useHardwareDepthMode,
      ),
    );
    if (generation != _depthGeneration) {
      provider.dispose();
      if (provider is NcnnDepthProvider) await provider.shutdown();
      return false;
    }
    _depthProvider = provider;
    _midasLoaded = provider.isReady;
    return provider.isReady;
  }

  Future<void> dispose() async {
    _depthGeneration++;
    final provider = _depthProvider;
    _depthProvider = null;
    provider?.dispose();
    if (_visionImpl != null) {
      try {
        await _visionImpl!.closeYoloModel();
      } catch (_) {}
    }
    if (provider is NcnnDepthProvider) await provider.shutdown();
    _yoloLoaded = false;
    _midasLoaded = false;
  }

  @visibleForTesting
  void debugInjectAvailableAssets(Set<String> assets) {
    _availableAssets = assets;
  }

  /// Safety audit 2026-06 test hook: inject (or clear with null) the depth
  /// provider so unit tests can exercise DepthPipelineController without a
  /// real NCNN/hardware stack. Does not dispose any existing provider.
  @visibleForTesting
  void debugInjectDepthProvider(DepthProvider? provider) {
    _depthProvider = provider;
  }
}
