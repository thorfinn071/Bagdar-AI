import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/constants.dart';
import '../utils/depth_hazard.dart';
import '../utils/ground_plane_analyzer.dart';
import 'device_capability.dart';
import 'hardware_depth_bridge.dart';
import 'ncnn_depth_provider.dart';

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

class HardwareDepthProvider implements DepthProvider {
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

  
  DateTime? _highConfStreakStartedAt;
  bool _fallbackDisposedForBattery = false;
  bool _fallbackReinitInFlight = false;
  int _fallbackInitThreads = 2;

  HardwareDepthProvider({
    HardwareDepthBridge? bridge,
    GroundPlaneAnalyzer? analyzer,
    DepthProvider? fallbackProvider,
  }) : _bridge = bridge ?? HardwareDepthBridge(),
       _analyzer = analyzer ?? GroundPlaneAnalyzer(),
       _fallback = fallbackProvider;

  @visibleForTesting
  bool get debugFallbackDisposedForBattery => _fallbackDisposedForBattery;

  @visibleForTesting
  DateTime? get debugHighConfStreakStartedAt => _highConfStreakStartedAt;

  @visibleForTesting
  DepthProvider? get debugFallback => _fallback;

  @visibleForTesting
  void debugUpdateConfidence(double score, {DateTime? now}) =>
      _updateConfidenceState(score, now: now);

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

  Future<DepthProvider?> _ensureFallback({int threads = 2}) async {
    final existing = _fallback;
    if (existing != null) {
      if (existing.isReady) return existing;
      if (await existing.init(threads: threads)) return existing;
      return null;
    }
    final ncnn = await NcnnDepthProvider.tryCreate();
    if (ncnn == null) return null;
    if (await ncnn.init(threads: threads)) {
      _fallback = ncnn;
      return ncnn;
    }
    try {
      ncnn.dispose();
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> init({int threads = 2}) async {
    _ready = false;
    _hardwareStarted = false;
    _lowConfidenceFallbackActive = false;
    _lastConfidenceScore = 1.0;
    _lowConfidenceFrameCount = 0;
    _recoveredConfidenceFrameCount = 0;
    _highConfStreakStartedAt = null;
    _fallbackDisposedForBattery = false;
    _fallbackReinitInFlight = false;
    _fallbackInitThreads = threads;

    final fallbackFuture = _ensureFallback(threads: threads);

    try {
      final supported = await _bridge.isSupported();
      if (supported) {
        final started = await _bridge.start(
          mapSize: GroundPlaneAnalyzer.kMapSize,
        );
        if (started) {
          _hardwareStarted = true;
          _effectiveTier = DepthTier.hardware;
          final fallback = await fallbackFuture;
          _ready = true;
          debugPrint(
            'HardwareDepthProvider: hardware depth active; NCNN fallback '
            '${fallback != null ? "ready" : "unavailable"}',
          );
          return true;
        }
        debugPrint(
          'HardwareDepthProvider: hardware start failed, using NCNN fallback',
        );
      } else {
        debugPrint(
          'HardwareDepthProvider: hardware depth unavailable, using NCNN fallback',
        );
      }
    } catch (e) {
      debugPrint(
        'HardwareDepthProvider: hardware init failed ($e), using NCNN fallback',
      );
    }

    final fallback = await fallbackFuture;
    if (fallback == null) {
      _ready = false;
      return false;
    }
    _effectiveTier = fallback.tier;
    _ready = fallback.isReady;
    return _ready;
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

  void _updateConfidenceState(double score, {DateTime? now}) {
    _lastConfidenceScore = score;
    final t = now ?? DateTime.now();
    if (score < kHardwareDepthMinConfidence) {
      _lowConfidenceFrameCount++;
      _recoveredConfidenceFrameCount = 0;
      _highConfStreakStartedAt = null;
      if (_lowConfidenceFrameCount >= kHardwareDepthLowConfFrames) {
        _lowConfidenceFallbackActive = true;
      }
      
      
      _maybeReinitFallback();
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

    
    if (score >= kHardwareDepthHighConfThreshold) {
      _highConfStreakStartedAt ??= t;
      if (!_fallbackDisposedForBattery &&
          t.difference(_highConfStreakStartedAt!) >=
              kHardwareDepthHighConfStreakForDispose) {
        _disposeFallbackForBattery();
      }
    } else {
      _highConfStreakStartedAt = null;
    }
  }

  void _disposeFallbackForBattery() {
    if (_fallbackDisposedForBattery) return;
    final fb = _fallback;
    if (fb == null) {
      _fallbackDisposedForBattery = true;
      return;
    }
    debugPrint(
      'HardwareDepthProvider: 30s high-conf streak — disposing NCNN '
      'fallback to save battery (B-3)',
    );
    try {
      fb.dispose();
    } catch (_) {}
    _fallback = null;
    _fallbackDisposedForBattery = true;
  }

  void _maybeReinitFallback() {
    if (!_fallbackDisposedForBattery) return;
    if (_fallbackReinitInFlight) return;
    _fallbackReinitInFlight = true;
    debugPrint(
      'HardwareDepthProvider: low-conf detected — reinitializing NCNN '
      'fallback (B-3)',
    );
    unawaited(_reinitFallback());
  }

  Future<void> _reinitFallback() async {
    try {
      final fb = await NcnnDepthProvider.tryCreate();
      if (fb == null) return;
      final ok = await fb.init(threads: _fallbackInitThreads);
      if (ok) {
        _fallback = fb;
        _fallbackDisposedForBattery = false;
      } else {
        try {
          fb.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('HardwareDepthProvider: fallback reinit failed ($e)');
    } finally {
      _fallbackReinitInFlight = false;
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
        debugPrint('DepthProviderFactory: HardwareDepthProvider');
        return HardwareDepthProvider();

      case DepthTier.ncnnVulkan:
      case DepthTier.ncnnCpu:
        debugPrint(
          'DepthProviderFactory: NCNN tier requested via legacy create(); '
          'use createAndInit() instead. Returning FocalLength placeholder.',
        );
        return FocalLengthDepthProvider();

      case DepthTier.focalLength:
        debugPrint('DepthProviderFactory: FocalLengthDepthProvider');
        return FocalLengthDepthProvider();
    }
  }

  static DepthProvider createWithTier(DepthTier tier) {
    switch (tier) {
      case DepthTier.hardware:
        return HardwareDepthProvider();
      case DepthTier.focalLength:
        return FocalLengthDepthProvider();
      case DepthTier.ncnnVulkan:
      case DepthTier.ncnnCpu:
        debugPrint(
          'DepthProviderFactory: createWithTier called with NCNN tier; '
          'NCNN must be created via NcnnDepthProvider.tryCreate(). '
          'Returning FocalLength placeholder.',
        );
        return FocalLengthDepthProvider();
    }
  }

  static Future<DepthProvider> createAndInit(
    DeviceCapabilities caps, {
    int threads = 2,
  }) async {
    if (caps.bestDepthTier == DepthTier.hardware) {
      final hw = HardwareDepthProvider();
      try {
        if (await hw.init(threads: threads)) {
          debugPrint('DepthProviderFactory: activated Hardware (NCNN fallback inside)');
          return hw;
        }
        debugPrint('DepthProviderFactory: Hardware init failed, trying NCNN');
      } catch (e) {
        debugPrint('DepthProviderFactory: Hardware threw $e, trying NCNN');
      }
      try {
        hw.dispose();
      } catch (_) {}
    }

    final ncnn = await NcnnDepthProvider.tryCreate();
    if (ncnn != null) {
      try {
        if (await ncnn.init(threads: threads)) {
          debugPrint(
            'DepthProviderFactory: activated NCNN (vulkan=${ncnn.tier == DepthTier.ncnnVulkan})',
          );
          return ncnn;
        }
        debugPrint('DepthProviderFactory: NCNN init failed, falling back to focal');
      } catch (e) {
        debugPrint('DepthProviderFactory: NCNN threw $e, falling back to focal');
      }
      try {
        ncnn.dispose();
      } catch (_) {}
    }

    debugPrint('DepthProviderFactory: using FocalLengthDepthProvider');
    final focal = FocalLengthDepthProvider();
    await focal.init(threads: threads);
    return focal;
  }
}
