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
  bool _permanentlyDisabled = false;
  final List<DateTime> _recentFailures = [];

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
  double get lastConfidenceScore => 0;

  @override
  double get lastPreprocessMs => _lastPreprocessMs;

  @override
  double get lastInferenceMs => _lastInferenceMs;

  @override
  double get lastAnalyzeMs => _lastAnalyzeMs;

  @override
  bool get lastUsedNativeBridge => true;

  @override
  void setNativeBridgeEnabled(bool enabled) {
    
  }

  @override
  Future<bool> init({int threads = 2}) async {
    if (Settings.instance.isReady && Settings.instance.ncnnDisabled) {
      _permanentlyDisabled = true;
      debugPrint('NcnnDepthProvider: skipped — ncnnDisabled flag set');
      return false;
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
      if (_isOutputDegenerate(flat)) {
        debugPrint(
            'NcnnDepthProvider: degenerate output — recording failure');
        _recordFailure();
        return const [];
      }
      return _analyzer.analyze(
        flat,
        lumaMap: _lumaBuffer,
        userStationary: userStationary,
        weatherDegraded: weatherDegraded,
      );
    } catch (e) {
      debugPrint('NcnnDepthProvider: analyze failed ($e)');
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
        _lumaBuffer[outIdx++] = yBytes[rowStart + sx];
      }
    }
  }

  bool _isOutputDegenerate(Float32List flat) {
    if (flat.isEmpty) return true;
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
    if (badCount > flat.length ~/ 20) return true;
    if (!minV.isFinite || !maxV.isFinite) return true;
    if ((maxV - minV).abs() < 1e-3) return true;
    return false;
  }

  void _recordFailure() {
    final now = DateTime.now();
    _recentFailures.removeWhere((t) => now.difference(t) > _kFailureWindow);
    _recentFailures.add(now);
    if (_recentFailures.length >= _kMaxFailuresInWindow) {
      _markPermanentlyDisabled();
    }
  }

  void _markPermanentlyDisabled() {
    if (_permanentlyDisabled) return;
    _permanentlyDisabled = true;
    debugPrint(
      'NcnnDepthProvider: $_kMaxFailuresInWindow failures in '
      '${_kFailureWindow.inMinutes}m — disabling for this and future sessions',
    );
    if (Settings.instance.isReady) {
      Settings.instance.setNcnnDisabled(true).ignore();
    }
  }

  @override
  void dispose() {
    _ready = false;
    _bridge.dispose();
  }

  @visibleForTesting
  bool get debugIsPermanentlyDisabled => _permanentlyDisabled;
}
