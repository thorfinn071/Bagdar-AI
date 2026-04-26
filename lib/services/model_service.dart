import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';

import 'settings_service.dart';
import 'depth_provider.dart';
import 'device_capability.dart';
import 'thermal_monitor.dart';


enum YoloInputTier { small, standard }

class ModelService {
  static final ModelService instance = ModelService._();
  ModelService._();

  FlutterVision? _visionImpl;
  DepthProvider? _depthProvider;

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
    try {
      await _loadYoloAtTier(
        tier: desired,
        gpu: _lastLoadGpu,
        threads: _lastLoadThreads,
      );
    } catch (e) {
      debugPrint('ModelService: thermal-aware YOLO reload failed ($e)');
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

  Future<bool> loadMidas({int? numThreads}) async {
    final threads = numThreads ?? Settings.instance.numThreads;
    final caps = await DeviceCapabilityProbe.probe();

    final provider = await DepthProviderFactory.createAndInit(
      caps,
      threads: threads,
    );
    _depthProvider = provider;
    _midasLoaded = provider.isReady;
    return provider.isReady;
  }

  Future<void> dispose() async {
    if (_visionImpl != null) {
      try {
        await _visionImpl!.closeYoloModel();
      } catch (_) {}
    }
    _depthProvider?.dispose();
    _yoloLoaded = false;
    _midasLoaded = false;
  }

  @visibleForTesting
  void debugInjectAvailableAssets(Set<String> assets) {
    _availableAssets = assets;
  }
}
