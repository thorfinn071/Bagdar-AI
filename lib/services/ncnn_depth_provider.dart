import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../utils/depth_hazard.dart';
import '../utils/ground_plane_analyzer.dart';
import 'depth_provider.dart';
import 'device_capability.dart';
import 'ncnn_depth_bridge.dart';
import 'settings_service.dart';

class NcnnDepthProvider implements DepthProvider {
  static const int _inputSize = NcnnDepthBridge.inputSize;
  static const String _paramAsset = 'assets/midas_small.ncnn.param';
  static const String _binAsset = 'assets/midas_small.ncnn.bin';

  
  static const int _kMaxFailuresInWindow = 3;
  static const Duration _kFailureWindow = Duration(minutes: 5);

  final NcnnDepthBridge _bridge;
  final GroundPlaneAnalyzer _analyzer = GroundPlaneAnalyzer();

  bool _ready = false;
  bool _busy = false;
  double _lastOutputConfidence = 0;
  bool _permanentlyDisabled = false;
  final List<DateTime> _recentFailures = [];

  
  void Function()? onSessionDisabled;

  late final Uint8List _lumaBuffer = Uint8List(_inputSize * _inputSize);

  double _lastPreprocessMs = 0;
  double _lastInferenceMs = 0;
  double _lastAnalyzeMs = 0;

  NcnnDepthProvider({required NcnnDepthBridge bridge}) : _bridge = bridge;

  static Future<NcnnDepthProvider?> tryCreate() async {
    final bridge = NcnnDepthBridge.tryCreate();
    if (bridge == null) return null;
    return NcnnDepthProvider(bridge: bridge);
  }

  @override
  DepthTier get tier =>
      _bridge.isVulkan ? DepthTier.ncnnVulkan : DepthTier.ncnnCpu;

  @override
  bool get isReady => _ready && !_permanentlyDisabled;

  @override
  bool get nativeBridgeEnabled => true;

  @override
  bool get nativeBridgeAvailable => true;

  @override
  bool get lowConfidenceFallbackActive => false;

  @override
  double get lastConfidenceScore => _lastOutputConfidence;

  @override
  double get lastPreprocessMs => _lastPreprocessMs;

  @override
  double get lastInferenceMs => _lastInferenceMs;

  @override
  double get lastAnalyzeMs => _lastAnalyzeMs;

  @override
  bool get lastUsedNativeBridge => true;

  
  @override
  bool get lastPlaneFitOk => _analyzer.lastPlaneFitOk;

  @override
  void setNativeBridgeEnabled(bool enabled) {
    
  }

  @override
  Future<bool> init({int threads = 2}) async {
    
    
    if (Settings.instance.isReady && Settings.instance.ncnnDisabled) {
      debugPrint(
        'NcnnDepthProvider: ncnnDisabled flag present in prefs — '
        'clearing (transient failures from a previous session are not '
        'persisted; only structural load failures should persist).',
      );
      
      Settings.instance.setNcnnDisabled(false).ignore();
    }
    final paths = await _extractAssets();
    if (paths == null) {
      debugPrint('NcnnDepthProvider: NCNN assets missing — provider unavailable');
      
      
      return false;
    }
    final ok = _bridge.init(
      paramPath: paths.$1,
      binPath: paths.$2,
      useVulkan: true,
      numThreads: threads.clamp(1, 4),
    );
    _ready = ok;
    if (!ok) {
      debugPrint('NcnnDepthProvider: bridge init failed');
      
      
    }
    return ok;
  }

  static Future<(String, String)?> _extractAssets() async {
    try {
      final docs = await getApplicationSupportDirectory();
      final paramPath = '${docs.path}/midas_small.ncnn.param';
      final binPath = '${docs.path}/midas_small.ncnn.bin';

      final paramData = await rootBundle.load(_paramAsset);
      final binData = await rootBundle.load(_binAsset);

      final paramFile = File(paramPath);
      final binFile = File(binPath);

      if (!await paramFile.exists() ||
          (await paramFile.length()) != paramData.lengthInBytes) {
        await paramFile.writeAsBytes(
          paramData.buffer.asUint8List(
            paramData.offsetInBytes,
            paramData.lengthInBytes,
          ),
          flush: true,
        );
      }
      if (!await binFile.exists() ||
          (await binFile.length()) != binData.lengthInBytes) {
        await binFile.writeAsBytes(
          binData.buffer.asUint8List(
            binData.offsetInBytes,
            binData.lengthInBytes,
          ),
          flush: true,
        );
      }
      return (paramPath, binPath);
    } catch (e) {
      debugPrint('NcnnDepthProvider: asset extraction failed ($e)');
      return null;
    }
  }

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async {
    if (_permanentlyDisabled || !_ready || _busy) return const [];
    _busy = true;
    final totalSw = Stopwatch()..start();
    _lastPreprocessMs = 0;
    _lastInferenceMs = 0;
    _lastAnalyzeMs = 0;
    try {
      final yPlane = image.planes[0];
      final clampedCrop = cropTopFrac.clamp(0.0, 0.9);

      final preSw = Stopwatch()..start();
      _extractLuma(
        yBytes: yPlane.bytes,
        srcWidth: image.width,
        srcHeight: image.height,
        rowStride: yPlane.bytesPerRow,
        cropTopFrac: clampedCrop,
      );
      preSw.stop();
      _lastPreprocessMs = preSw.elapsedMicroseconds / 1000.0;

      final infSw = Stopwatch()..start();
      final flat = _bridge.inferYuv(
        yBytes: yPlane.bytes,
        srcWidth: image.width,
        srcHeight: image.height,
        rowStride: yPlane.bytesPerRow,
        cropTopFrac: clampedCrop,
      );
      infSw.stop();
      _lastInferenceMs = infSw.elapsedMicroseconds / 1000.0;

      if (flat == null) {
        _recordFailure();
        return const [];
      }
      
      
      final outputClass = _classifyOutput(flat);
      if (outputClass == _OutputClass.invalid) {
        debugPrint(
            'NcnnDepthProvider: invalid output (NaN/Inf) — recording failure');
        _lastOutputConfidence = 0;
        _recordFailure();
        return const [];
      }
      if (outputClass == _OutputClass.degenerate) {
        _lastOutputConfidence = 0;
        // Safety audit 2026-06 fix A-4: degenerate counts toward session-disable
        _recordFailure();
        return const [];
      }
      _lastOutputConfidence = _computeOutputConfidence(flat);
      return _analyzer.analyze(
        flat,
        lumaMap: _lumaBuffer,
        userStationary: userStationary,
        weatherDegraded: weatherDegraded,
        winterMode: winterMode,
      );
    } catch (e) {
      debugPrint('NcnnDepthProvider: analyze failed ($e)');
      // Safety audit 2026-06 fix A-4: exception counts toward session-disable
      _recordFailure();
      return const [];
    } finally {
      totalSw.stop();
      _lastAnalyzeMs = totalSw.elapsedMicroseconds / 1000.0;
      _busy = false;
    }
  }

  void _extractLuma({
    required Uint8List yBytes,
    required int srcWidth,
    required int srcHeight,
    required int rowStride,
    required double cropTopFrac,
  }) {
    final cropTop = (srcHeight * cropTopFrac).toInt().clamp(0, srcHeight - 1);
    final cropH = (srcHeight - cropTop).clamp(1, srcHeight);
    int outIdx = 0;
    for (int dy = 0; dy < _inputSize; dy++) {
      final sy = ((dy * cropH) ~/ _inputSize).clamp(0, cropH - 1) + cropTop;
      final rowStart = sy * rowStride;
      for (int dx = 0; dx < _inputSize; dx++) {
        final sx = ((dx * srcWidth) ~/ _inputSize).clamp(0, srcWidth - 1);
        // Safety audit 2026-06 fix A-3: bounds check before array access
        if (rowStart + sx >= yBytes.length) continue;
        _lumaBuffer[outIdx++] = yBytes[rowStart + sx];
      }
    }
  }

  
  _OutputClass _classifyOutput(Float32List flat) {
    if (flat.isEmpty) return _OutputClass.invalid;
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    int badCount = 0;
    for (int i = 0; i < flat.length; i++) {
      final v = flat[i];
      if (v.isNaN || v.isInfinite) {
        badCount++;
        continue;
      }
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    
    if (badCount > flat.length ~/ 20) return _OutputClass.invalid;
    if (!minV.isFinite || !maxV.isFinite) return _OutputClass.invalid;
    
    
    if ((maxV - minV).abs() < 1e-3) return _OutputClass.degenerate;
    return _OutputClass.ok;
  }

  /// Compute a pseudo-confidence score [0..1] from depth map statistics.
  /// Low range, many near-zero pixels, or low variance indicate poor output.
  double _computeOutputConfidence(Float32List flat) {
    if (flat.isEmpty) return 0;
    final n = flat.length;
    double sum = 0;
    double sqSum = 0;
    int nearZeroCount = 0;
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    for (int i = 0; i < n; i++) {
      final v = flat[i];
      if (!v.isFinite) continue;
      sum += v;
      sqSum += v * v;
      if (v < 0.02) nearZeroCount++;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (!minV.isFinite || !maxV.isFinite) return 0;

    final range = maxV - minV;
    final mean = sum / n;
    final variance = (sqSum / n) - mean * mean;
    final nearZeroRatio = nearZeroCount / n;

    // Score components:
    // 1. Range should be > 0.1 for good depth maps (max 0.3 contribution)
    final rangeScore = (range / 0.5).clamp(0.0, 1.0) * 0.3;
    // 2. Low near-zero ratio (max 0.4 contribution)
    final validScore = (1.0 - nearZeroRatio * 2).clamp(0.0, 1.0) * 0.4;
    // 3. Reasonable variance (max 0.3 contribution)
    final varScore = (variance / 0.01).clamp(0.0, 1.0) * 0.3;

    return (rangeScore + validScore + varScore).clamp(0.0, 1.0);
  }

  void _recordFailure() {
    final now = DateTime.now();
    _recentFailures.removeWhere((t) => now.difference(t) > _kFailureWindow);
    _recentFailures.add(now);
    if (_recentFailures.length >= _kMaxFailuresInWindow) {
      _markSessionDisabled();
    }
  }

  
  void _markSessionDisabled() {
    if (_permanentlyDisabled) return;
    _permanentlyDisabled = true;
    debugPrint(
      'NcnnDepthProvider: $_kMaxFailuresInWindow invalid-output failures in '
      '${_kFailureWindow.inMinutes}m — disabling for THIS session only. '
      'A restart will re-enable NCNN depth.',
    );
    
    
    onSessionDisabled?.call();
  }

  @override
  void dispose() {
    _ready = false;
    _bridge.dispose();
  }

  @visibleForTesting
  bool get debugIsPermanentlyDisabled => _permanentlyDisabled;
}


enum _OutputClass {
  
  ok,
  
  
  degenerate,
  
  
  invalid,
}
