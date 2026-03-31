import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'depth_hazard.dart';
import 'ground_plane_analyzer.dart';



class MidasService {
  static const String _modelPath = 'assets/midas_v21_small.tflite';
  static const int    _inputSize = 256;

  Interpreter? _interpreter;
  bool _ready  = false;
  bool _busy   = false;
  List<Object>? _inputTensor;
  Map<int, Object>? _outputTensor;

  final GroundPlaneAnalyzer _analyzer = GroundPlaneAnalyzer();

  late final Float32List _inputBuffer =
      Float32List(_inputSize * _inputSize * 3);
  late final Float32List _outputBuffer =
      Float32List(_inputSize * _inputSize);

  Future<bool> init({int threads = 2, bool useNnApi = false}) async {
    try {
      try { _interpreter?.close(); } catch (_) {}
      _interpreter = null;
      _inputTensor = null;
      _outputTensor = null;
      _ready = false;

      final options = InterpreterOptions()
        ..threads = (threads < 1 ? 1 : threads > 4 ? 4 : threads)
        ..useNnApiForAndroid = useNnApi;

      _interpreter = await Interpreter.fromAsset(
        _modelPath,
        options: options,
      );
      _inputTensor = [_inputBuffer.reshape([1, _inputSize, _inputSize, 3])];
      _outputTensor = {0: _outputBuffer.reshape([1, _inputSize, _inputSize])};
      _ready = true;
      return true;
    } catch (e) {
      _ready = false;
      return false;
    }
  }

  bool get isReady => _ready;

  Future<List<DepthHazard>> analyze(CameraImage image) async {
    if (!_ready || _busy || _interpreter == null) return const [];
    final inputTensor = _inputTensor;
    final outputTensor = _outputTensor;
    if (inputTensor == null || outputTensor == null) return const [];
    _busy = true;

    try {
      _preprocessYuv(image);
      _interpreter!.runForMultipleInputs(inputTensor, outputTensor);
      final hazards = _analyzer.analyze(_outputBuffer);
      return hazards;
    } catch (e) {
      return const [];
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    try { _interpreter?.close(); } catch (_) {}
    _interpreter = null;
    _inputTensor = null;
    _outputTensor = null;
    _ready = false;
  }

  void _preprocessYuv(CameraImage image) {
    final yPlane    = image.planes[0];
    final srcWidth  = image.width;
    final srcHeight = image.height;
    final rowStride = yPlane.bytesPerRow;
    final src       = yPlane.bytes;

    final scaleX = srcWidth  / _inputSize;

    int outIdx = 0;
    for (int dy = 0; dy < _inputSize; dy++) {
      final srcY = (srcHeight * 0.40 + dy * srcHeight * 0.60 / _inputSize)
          .toInt()
          .clamp(0, srcHeight - 1);

      for (int dx = 0; dx < _inputSize; dx++) {
        final srcX = (dx * scaleX).toInt().clamp(0, srcWidth - 1);
        final yVal = src[srcY * rowStride + srcX] & 0xFF;
        final norm = yVal / 255.0;
        _inputBuffer[outIdx++] = norm;
        _inputBuffer[outIdx++] = norm;
        _inputBuffer[outIdx++] = norm;
      }
    }
  }
}



class FusionEngine {
  static const double kWeightMidas = 1.0;
  static const double kWeightYolo  = 0.0;
  static const double kWarningThreshold  = 0.35;
  static const double kCriticalThreshold = 0.58;
  static const int kTemporalFrames = 2;

  final Map<int, List<double>> _history = {};

  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration kAlertCooldown = Duration(seconds: 3);

  FusionResult? evaluate({
    required DepthHazard hazard,
    double yoloHazardConf = 0.0,
    required DateTime now,
  }) {
    final zoneIdx = hazard.zone.index;

    final fusionScore = (kWeightMidas * hazard.midasScore +
        kWeightYolo  * yoloHazardConf.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);

    final hist = _history.putIfAbsent(zoneIdx, () => []);
    hist.add(fusionScore);
    if (hist.length > kTemporalFrames) hist.removeAt(0);

    _history.removeWhere((k, _) => k != zoneIdx);

    if (now.difference(_lastAlertAt) < kAlertCooldown) return null;

    if (fusionScore >= kCriticalThreshold &&
        hist.length >= kTemporalFrames &&
        hist.every((s) => s >= kCriticalThreshold)) {
      _lastAlertAt = now;
      return FusionResult(
        level:        AlertLevel.critical,
        fusionScore:  fusionScore,
        hazard:       hazard,
        stableFrames: hist.length,
      );
    }

    if (fusionScore >= kWarningThreshold) {
      _lastAlertAt = now;
      return FusionResult(
        level:        AlertLevel.warning,
        fusionScore:  fusionScore,
        hazard:       hazard,
        stableFrames: hist.length,
      );
    }

    return null;
  }

  void reset() => _history.clear();
}

enum AlertLevel { warning, critical }

class FusionResult {
  final AlertLevel  level;
  final double      fusionScore;
  final DepthHazard hazard;
  final int         stableFrames;

  const FusionResult({
    required this.level,
    required this.fusionScore,
    required this.hazard,
    required this.stableFrames,
  });
}
