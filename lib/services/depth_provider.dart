import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/constants.dart';
import '../utils/depth_hazard.dart';
import '../utils/ground_plane_analyzer.dart';
import '../utils/midas_service.dart';
import 'device_capability.dart';
import 'hardware_depth_bridge.dart';

abstract class DepthProvider {
  DepthTier get tier;
  bool get isReady;
  Future<bool> init({int threads = 2});
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  });
  bool get nativeBridgeEnabled;
  bool get nativeBridgeAvailable;
  bool get lowConfidenceFallbackActive;
  double get lastConfidenceScore;
  double get lastPreprocessMs;
  double get lastInferenceMs;
  double get lastAnalyzeMs;
  bool get lastUsedNativeBridge;
  void setNativeBridgeEnabled(bool enabled);
  void dispose();
}

class MidasDepthProvider implements DepthProvider {
  final bool useNnApi;

  MidasDepthProvider({required this.useNnApi});

  final MidasService _service = MidasService();

  @override
  DepthTier get tier => useNnApi ? DepthTier.midasNnapi : DepthTier.midasCpu;

  @override
  bool get isReady => _service.isReady;

  @override
  bool get nativeBridgeEnabled => _service.nativeBridgeEnabled;

  @override
  bool get nativeBridgeAvailable => _service.nativeBridgeAvailable;

  @override
  bool get lowConfidenceFallbackActive => false;

  @override
  double get lastConfidenceScore => 0;

  @override
  double get lastPreprocessMs => _service.lastPreprocessMs;

  @override
  double get lastInferenceMs => _service.lastInferenceMs;

  @override
  double get lastAnalyzeMs => _service.lastAnalyzeMs;

  @override
  bool get lastUsedNativeBridge => _service.lastUsedNativeBridge;

  @override
  Future<bool> init({int threads = 2}) =>
      _service.init(threads: threads, useNnApi: useNnApi);

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) => _service.analyze(
    image,
    cropTopFrac: cropTopFrac,
    userStationary: userStationary,
    weatherDegraded: weatherDegraded,
  );

  @override
  void setNativeBridgeEnabled(bool enabled) =>
      _service.setNativeBridgeEnabled(enabled);

  @override
  void dispose() => _service.dispose();
}

class HardwareDepthProvider implements DepthProvider {
  final bool useNnApiFallback;
  final HardwareDepthBridge _bridge;
  final GroundPlaneAnalyzer _analyzer;

  DepthProvider? _fallback;
  bool _ready = false;
  bool _hardwareStarted = false;
  DepthTier _effectiveTier = DepthTier.hardware;
  bool _lowConfidenceFallbackActive = false;
  double _lastConfidenceScore = 1.0;
  int _lowConfidenceFrameCount = 0;
  int _recoveredConfidenceFrameCount = 0;
  double _lastPreprocessMs = 0;
  double _lastInferenceMs = 0;
  double _lastAnalyzeMs = 0;
  bool _lastUsedNativeBridge = false;

  HardwareDepthProvider({
    required this.useNnApiFallback,
    HardwareDepthBridge? bridge,
    GroundPlaneAnalyzer? analyzer,
    DepthProvider? fallbackProvider,
  }) : _bridge = bridge ?? HardwareDepthBridge(),
       _analyzer = analyzer ?? GroundPlaneAnalyzer(),
       _fallback = fallbackProvider;

  @override
  DepthTier get tier => _effectiveTier;

  @override
  bool get isReady => _ready;

  @override
  bool get nativeBridgeEnabled => _fallback?.nativeBridgeEnabled ?? false;

  @override
  bool get nativeBridgeAvailable => _fallback?.nativeBridgeAvailable ?? false;

  @override
  bool get lowConfidenceFallbackActive => _lowConfidenceFallbackActive;

  @override
  double get lastConfidenceScore => _lastConfidenceScore;

  @override
  double get lastPreprocessMs => _lastPreprocessMs;

  @override
  double get lastInferenceMs => _lastInferenceMs;

  @override
  double get lastAnalyzeMs => _lastAnalyzeMs;

  @override
  bool get lastUsedNativeBridge => _lastUsedNativeBridge;

  DepthProvider _ensureFallback() {
    _fallback ??= MidasDepthProvider(useNnApi: useNnApiFallback);
    return _fallback!;
  }

  @override
  Future<bool> init({int threads = 2}) async {
    _ready = false;
    _hardwareStarted = false;
    _lowConfidenceFallbackActive = false;
    _lastConfidenceScore = 1.0;
    _lowConfidenceFrameCount = 0;
    _recoveredConfidenceFrameCount = 0;

    final fallback = _ensureFallback();
    final fallbackInit = fallback.init(threads: threads);

    try {
      final supported = await _bridge.isSupported();
      if (supported) {
        final started = await _bridge.start(
          mapSize: GroundPlaneAnalyzer.kMapSize,
        );
        if (started) {
          _hardwareStarted = true;
          _effectiveTier = DepthTier.hardware;
          final fallbackOk = await fallbackInit;
          _ready = true;
          debugPrint(
            'HardwareDepthProvider: hardware depth active; MiDaS fallback '
            '${fallbackOk ? "ready" : "unavailable"}',
          );
          return true;
        }
        debugPrint(
          'HardwareDepthProvider: hardware start failed, using MiDaS fallback',
        );
      } else {
        debugPrint(
          'HardwareDepthProvider: hardware depth unavailable, using MiDaS fallback',
        );
      }
    } catch (e) {
      debugPrint(
        'HardwareDepthProvider: hardware init failed ($e), using MiDaS fallback',
      );
    }

    final fallbackOk = await fallbackInit;
    _effectiveTier = fallback.tier;
    _ready = fallbackOk;
    return fallbackOk;
  }

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) async {
    final analyzeSw = Stopwatch()..start();
    if (_hardwareStarted) {
      final depthMap = _bridge.latestDepthMap;
      if (depthMap != null &&
          depthMap.length ==
              GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize) {
        _updateConfidenceState(_computeDepthConfidence(depthMap));
        final fallback = _fallback;
        if (_lowConfidenceFallbackActive &&
            fallback != null &&
            fallback.isReady) {
          final hazards = await fallback.analyze(
            image,
            cropTopFrac: cropTopFrac,
            userStationary: userStationary,
            weatherDegraded: weatherDegraded,
          );
          _lastPreprocessMs = fallback.lastPreprocessMs;
          _lastInferenceMs = fallback.lastInferenceMs;
          _lastUsedNativeBridge = fallback.lastUsedNativeBridge;
          _effectiveTier = fallback.tier;
          analyzeSw.stop();
          _lastAnalyzeMs = fallback.lastAnalyzeMs;
          return hazards;
        }

        _lastPreprocessMs = 0;
        _lastInferenceMs = 0;
        _lastUsedNativeBridge = false;
        _effectiveTier = DepthTier.hardware;
        final hazards = _analyzer.analyze(
          depthMap,
          userStationary: userStationary,
          weatherDegraded: weatherDegraded,
        );
        analyzeSw.stop();
        _lastAnalyzeMs = analyzeSw.elapsedMicroseconds / 1000.0;
        return hazards;
      }
    }

    final fallback = _fallback;
    if (fallback != null && fallback.isReady) {
      final hazards = await fallback.analyze(
        image,
        cropTopFrac: cropTopFrac,
        userStationary: userStationary,
        weatherDegraded: weatherDegraded,
      );
      _lastPreprocessMs = fallback.lastPreprocessMs;
      _lastInferenceMs = fallback.lastInferenceMs;
      _lastUsedNativeBridge = fallback.lastUsedNativeBridge;
      _effectiveTier = fallback.tier;
      analyzeSw.stop();
      _lastAnalyzeMs = fallback.lastAnalyzeMs;
      return hazards;
    }

    analyzeSw.stop();
    _lastPreprocessMs = 0;
    _lastInferenceMs = 0;
    _lastAnalyzeMs = analyzeSw.elapsedMicroseconds / 1000.0;
    _lastUsedNativeBridge = false;
    return const [];
  }

  @override
  void setNativeBridgeEnabled(bool enabled) {
    _fallback?.setNativeBridgeEnabled(enabled);
  }

  @override
  void dispose() {
    try {
      _bridge.stop();
    } catch (_) {}
    try {
      _fallback?.dispose();
    } catch (_) {}
    _fallback = null;
    _hardwareStarted = false;
    _ready = false;
    _lowConfidenceFallbackActive = false;
    _lastConfidenceScore = 0;
    _lowConfidenceFrameCount = 0;
    _recoveredConfidenceFrameCount = 0;
    _lastPreprocessMs = 0;
    _lastInferenceMs = 0;
    _lastAnalyzeMs = 0;
    _lastUsedNativeBridge = false;
  }

  double _computeDepthConfidence(Float32List depthMap) {
    if (depthMap.isEmpty) return 0;
    var valid = 0;
    double sum = 0;
    for (final value in depthMap) {
      if (!value.isFinite || value <= 0) continue;
      if (value < kHardwareDepthMinMeanMeters / 4.0) continue;
      if (value > kHardwareDepthMaxMeanMeters * 1.5) continue;
      valid++;
      sum += value;
    }
    if (valid < 16) return 0;
    final coverage = valid / depthMap.length;
    final mean = sum / valid;

    if (mean < kHardwareDepthMinMeanMeters ||
        mean > kHardwareDepthMaxMeanMeters) {
      return coverage * 0.5;
    }
    return coverage.clamp(0.0, 1.0);
  }

  void _updateConfidenceState(double score) {
    _lastConfidenceScore = score;
    if (score < kHardwareDepthMinConfidence) {
      _lowConfidenceFrameCount++;
      _recoveredConfidenceFrameCount = 0;
      if (_lowConfidenceFrameCount >= kHardwareDepthLowConfFrames) {
        _lowConfidenceFallbackActive = true;
      }
      return;
    }

    _lowConfidenceFrameCount = 0;
    if (_lowConfidenceFallbackActive) {
      _recoveredConfidenceFrameCount++;
      if (_recoveredConfidenceFrameCount >= 3 &&
          score >= kHardwareDepthMinConfidence * 1.5) {
        _lowConfidenceFallbackActive = false;
        _recoveredConfidenceFrameCount = 0;
      }
    } else {
      _recoveredConfidenceFrameCount = 0;
    }
  }
}

class FocalLengthDepthProvider implements DepthProvider {
  bool _ready = false;

  @override
  DepthTier get tier => DepthTier.focalLength;

  @override
  bool get isReady => _ready;

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
  Future<bool> init({int threads = 2}) async {
    _ready = true;
    return true;
  }

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) async => const [];

  @override
  void setNativeBridgeEnabled(bool enabled) {}

  @override
  void dispose() {
    _ready = false;
  }
}

class DepthProviderFactory {
  DepthProviderFactory._();

  static DepthProvider create(DeviceCapabilities caps) {
    switch (caps.bestDepthTier) {
      case DepthTier.hardware:
        debugPrint(
          'DepthProviderFactory: HardwareDepthProvider (fallback nnapi=${caps.supportsNnApi})',
        );
        return HardwareDepthProvider(useNnApiFallback: caps.supportsNnApi);

      case DepthTier.midasNnapi:
        debugPrint('DepthProviderFactory: MidasDepthProvider(nnapi=true)');
        return MidasDepthProvider(useNnApi: true);

      case DepthTier.midasCpu:
        debugPrint('DepthProviderFactory: MidasDepthProvider(nnapi=false)');
        return MidasDepthProvider(useNnApi: false);

      case DepthTier.focalLength:
        debugPrint('DepthProviderFactory: FocalLengthDepthProvider');
        return FocalLengthDepthProvider();
    }
  }

  static DepthProvider createWithTier(DepthTier tier) {
    switch (tier) {
      case DepthTier.hardware:
        return HardwareDepthProvider(useNnApiFallback: true);
      case DepthTier.midasNnapi:
        return MidasDepthProvider(useNnApi: true);
      case DepthTier.midasCpu:
        return MidasDepthProvider(useNnApi: false);
      case DepthTier.focalLength:
        return FocalLengthDepthProvider();
    }
  }
}
