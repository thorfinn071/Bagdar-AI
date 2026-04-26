import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/constants.dart';
import '../services/native_depth_bridge.dart';
import 'depth_hazard.dart';
import 'ground_plane_analyzer.dart';

typedef _PreprocessArgs = ({
  Uint8List yBytes,
  int srcWidth,
  int srcHeight,
  int rowStride,
  double cropTopFrac,
});

void _doPreprocess(_PreprocessArgs args, Float32List result) {
  const inputSize = 256;
  final scaleX = args.srcWidth / inputSize;
  final cropFrac = 1.0 - args.cropTopFrac;
  int outIdx = 0;
  for (int dy = 0; dy < inputSize; dy++) {
    final srcY =
        (args.srcHeight * args.cropTopFrac +
                dy * args.srcHeight * cropFrac / inputSize)
            .toInt()
            .clamp(0, args.srcHeight - 1);
    for (int dx = 0; dx < inputSize; dx++) {
      final srcX = (dx * scaleX).toInt().clamp(0, args.srcWidth - 1);
      final yVal = args.yBytes[srcY * args.rowStride + srcX] & 0xFF;
      final norm = yVal / 255.0;
      result[outIdx++] = norm;
      result[outIdx++] = norm;
      result[outIdx++] = norm;
    }
  }
}

void _extractLuma(_PreprocessArgs args, Uint8List result) {
  const inputSize = 256;
  final scaleX = args.srcWidth / inputSize;
  final cropFrac = 1.0 - args.cropTopFrac;
  int outIdx = 0;
  for (int dy = 0; dy < inputSize; dy++) {
    final srcY =
        (args.srcHeight * args.cropTopFrac +
                dy * args.srcHeight * cropFrac / inputSize)
            .toInt()
            .clamp(0, args.srcHeight - 1);
    for (int dx = 0; dx < inputSize; dx++) {
      final srcX = (dx * scaleX).toInt().clamp(0, args.srcWidth - 1);
      result[outIdx++] = args.yBytes[srcY * args.rowStride + srcX];
    }
  }
}

class MidasService {
  static const String _modelPath = 'assets/midas_small_int8.tflite';
  static const int _inputSize = 256;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  bool _ready = false;
  bool _busy = false;
  bool _nativeBridgeEnabled = true;

  
  
  
  
  int? _busyStartMs;
  bool _recovering = false;
  int _lastInitThreads = 2;
  bool _lastInitUseNnApi = false;

  final GroundPlaneAnalyzer _analyzer = GroundPlaneAnalyzer();
  NativeDepthBridge? _nativeBridge;

  late final Pointer<Float> _inputPtr = ffi.calloc<Float>(
    _inputSize * _inputSize * 3,
  );
  late final Float32List _inputBuffer = _inputPtr.asTypedList(
    _inputSize * _inputSize * 3,
  );
  late final Object _inputTensor = _inputBuffer.reshape([
    1,
    _inputSize,
    _inputSize,
    3,
  ]);
  late final Float32List _outputBuffer = Float32List(_inputSize * _inputSize);
  late final Uint8List _lumaBuffer = Uint8List(_inputSize * _inputSize);
  late final Map<int, Object> _outHolder = {
    0: _outputBuffer.reshape([1, _inputSize, _inputSize]),
  };

  double _lastPreprocessMs = 0;
  double _lastInferenceMs = 0;
  double _lastAnalyzeMs = 0;
  bool _lastUsedNativeBridge = false;

  Future<bool> init({int threads = 2, bool useNnApi = false}) async {
    try {
      try {
        _isolateInterpreter?.close().ignore();
        _interpreter?.close();
      } catch (_) {}
      _interpreter = null;
      _isolateInterpreter = null;
      _ready = false;

      final clampedThreads = threads < 1
          ? 1
          : threads > 4
          ? 4
          : threads;
      _lastInitThreads = clampedThreads;
      _lastInitUseNnApi = useNnApi;

      Future<Interpreter?> attemptLoad({
        required bool withCoreMl,
        required bool withNnApi,
      }) async {
        try {
          final options = InterpreterOptions()
            ..threads = clampedThreads
            ..useNnApiForAndroid = withNnApi;
          if (withCoreMl && Platform.isIOS) {
            try {
              options.addDelegate(CoreMlDelegate());
              debugPrint('MidasService: CoreML delegate attached');
            } catch (e) {
              debugPrint('MidasService: CoreML delegate init failed ($e)');
              return null;
            }
          }
          return await Interpreter.fromAsset(_modelPath, options: options);
        } catch (e) {
          debugPrint(
            'MidasService: interpreter load failed '
            '(coreml=$withCoreMl, nnapi=$withNnApi) — $e',
          );
          return null;
        }
      }

      Interpreter? interp;
      if (Platform.isIOS) {
        interp = await attemptLoad(withCoreMl: true, withNnApi: false);
      }
      interp ??= await attemptLoad(withCoreMl: false, withNnApi: useNnApi);
      if (interp == null && useNnApi) {
        interp = await attemptLoad(withCoreMl: false, withNnApi: false);
      }
      if (interp == null) {
        _ready = false;
        return false;
      }

      _interpreter = interp;
      _isolateInterpreter = await IsolateInterpreter.create(
        address: interp.address,
      );
      _nativeBridge = NativeDepthBridge.tryCreate();
      if (_nativeBridge != null) {
        debugPrint('MidasService: native depth bridge ready');
      } else {
        debugPrint(
          'MidasService: native depth bridge unavailable, using Dart preprocessing',
        );
      }
      _ready = true;
      return true;
    } catch (e) {
      _ready = false;
      return false;
    }
  }

  bool get isReady => _ready;

  bool get nativeBridgeEnabled => _nativeBridgeEnabled;

  bool get nativeBridgeAvailable => _nativeBridge != null;

  double get lastPreprocessMs => _lastPreprocessMs;

  double get lastInferenceMs => _lastInferenceMs;

  double get lastAnalyzeMs => _lastAnalyzeMs;

  bool get lastUsedNativeBridge => _lastUsedNativeBridge;

  void setNativeBridgeEnabled(bool enabled) {
    _nativeBridgeEnabled = enabled;
  }

  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) async {
    if (!_ready) return const [];
    if (_busy) {
      
      
      
      _maybeTriggerRecovery();
      return const [];
    }
    if (_isolateInterpreter == null) return const [];
    _busy = true;
    _busyStartMs = DateTime.now().millisecondsSinceEpoch;
    final totalSw = Stopwatch()..start();
    _lastPreprocessMs = 0;
    _lastInferenceMs = 0;
    _lastAnalyzeMs = 0;
    _lastUsedNativeBridge = false;
    try {
      final yPlane = image.planes[0];
      final preprocessSw = Stopwatch()..start();
      final useNativeBridge = _nativeBridgeEnabled && _nativeBridge != null;
      final clampedCropTopFrac = cropTopFrac.clamp(0.0, 0.9);
      final preprocessInput = (
        yBytes: yPlane.bytes,
        srcWidth: image.width,
        srcHeight: image.height,
        rowStride: yPlane.bytesPerRow,
        cropTopFrac: clampedCropTopFrac,
      );
      if (useNativeBridge) {
        _lastUsedNativeBridge = _nativeBridge!.preprocess(
          yBytes: preprocessInput.yBytes,
          srcWidth: preprocessInput.srcWidth,
          srcHeight: preprocessInput.srcHeight,
          rowStride: preprocessInput.rowStride,
          cropTopFrac: preprocessInput.cropTopFrac,
          outBuffer: _inputPtr,
          outLength: _inputBuffer.length,
        );
        if (!_lastUsedNativeBridge) {
          _doPreprocess(preprocessInput, _inputBuffer);
        }
      } else {
        _doPreprocess(preprocessInput, _inputBuffer);
      }
      _extractLuma(preprocessInput, _lumaBuffer);
      preprocessSw.stop();
      _lastPreprocessMs = preprocessSw.elapsedMicroseconds / 1000.0;

      final inferenceSw = Stopwatch()..start();
      await _isolateInterpreter!.runForMultipleInputs([
        _inputTensor,
      ], _outHolder);
      inferenceSw.stop();
      _lastInferenceMs = inferenceSw.elapsedMicroseconds / 1000.0;

      final flat = _flattenOutput(_outHolder[0]!);
      if (flat.length != _inputSize * _inputSize) {
        return const [];
      }
      final result = _analyzer.analyze(
        flat,
        lumaMap: _lumaBuffer,
        userStationary: userStationary,
        weatherDegraded: weatherDegraded,
      );
      return result;
    } catch (e) {
      debugPrint('MidasService: analyze failed ($e)');
      return const [];
    } finally {
      totalSw.stop();
      _lastAnalyzeMs = totalSw.elapsedMicroseconds / 1000.0;
      _busy = false;
      _busyStartMs = null;
    }
  }

  
  
  bool _maybeTriggerRecovery() {
    if (_recovering) return false;
    final at = _busyStartMs;
    if (at == null) return false;
    final ageMs = DateTime.now().millisecondsSinceEpoch - at;
    if (ageMs <= kMidasStuckTimeoutMs) return false;
    _recovering = true;
    debugPrint(
      'MidasService: isolate stuck for ${ageMs}ms — tearing down + reinit',
    );
    unawaited(_recoverFromStuck());
    return true;
  }

  Future<void> _recoverFromStuck() async {
    try {
      _isolateInterpreter?.close().ignore();
    } catch (_) {}
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _isolateInterpreter = null;
    _ready = false;
    _busy = false;
    _busyStartMs = null;
    try {
      await init(threads: _lastInitThreads, useNnApi: _lastInitUseNnApi);
    } catch (e) {
      debugPrint('MidasService: stuck-recovery reinit failed ($e)');
    } finally {
      _recovering = false;
    }
  }

  @visibleForTesting
  bool get debugIsRecovering => _recovering;

  @visibleForTesting
  bool get debugIsBusy => _busy;

  @visibleForTesting
  void debugMarkStuck({Duration? age}) {
    final ageMs = (age ?? const Duration(milliseconds: 3500)).inMilliseconds;
    _busy = true;
    _busyStartMs = DateTime.now().millisecondsSinceEpoch - ageMs;
  }

  @visibleForTesting
  bool debugTriggerRecoveryCheck() => _maybeTriggerRecovery();

  static bool _warnedFlattenFallback = false;

  static Float32List _flattenOutput(Object raw) {
    if (raw is Float32List) return raw;
    if (!_warnedFlattenFallback) {
      _warnedFlattenFallback = true;
      debugPrint(
        'MidasService: output tensor is not Float32List (runtime=${raw.runtimeType}); '
        'skipping hazards this frame to avoid per-frame heap churn.',
      );
    }
    return Float32List(0);
  }

  void dispose() {
    try {
      _isolateInterpreter?.close().ignore();
    } catch (_) {}
    try {
      _interpreter?.close();
    } catch (_) {}
    try {
      _nativeBridge?.dispose();
    } catch (_) {}
    try {
      ffi.calloc.free(_inputPtr);
    } catch (_) {}
    _interpreter = null;
    _isolateInterpreter = null;
    _nativeBridge = null;
    _ready = false;
  }
}

class FusionEngine {
  static const double kCriticalThreshold = kFusionCriticalScore;
  static const double kWarningThreshold = kFusionWarningScore;

  final Map<int, ListQueue<double>> _history = {};
  final Map<int, double> _emaScore = {};
  DateTime _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWarningAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDeadZoneAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastZoneIdx;

  FusionResult? evaluate({
    required DepthHazard hazard,
    double yoloHazardConf = 0.0,
    required DateTime now,
  }) {
    final zoneIdx = hazard.zone.index;

    if (_lastZoneIdx != null && _lastZoneIdx != zoneIdx) {
      _history.clear();
      _emaScore.clear();
    }
    _lastZoneIdx = zoneIdx;

    final fusionScore = (hazard.midasScore + yoloHazardConf.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    final previousEma = _emaScore[zoneIdx] ?? fusionScore;
    final emaScore =
        (kFusionEmaAlpha * fusionScore + (1.0 - kFusionEmaAlpha) * previousEma)
            .clamp(0.0, 1.0);
    _emaScore[zoneIdx] = emaScore;

    final hist = _history.putIfAbsent(zoneIdx, () => ListQueue<double>());
    hist.addLast(emaScore);
    if (hist.length > kFusionTemporalFrames) {
      hist.removeFirst();
    }

    final isDeadZone = hazard.type == DepthHazardType.deadZone;

    if (isDeadZone && emaScore >= kFusionWarningScore) {
      if (now.difference(_lastDeadZoneAt) < kHazardDeadZoneCooldown) {
        return null;
      }
      _lastDeadZoneAt = now;
      return FusionResult(
        level: emaScore >= kFusionCriticalScore
            ? AlertLevel.critical
            : AlertLevel.warning,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    if (emaScore >= kFusionCriticalScore &&
        hist.length >= kFusionTemporalFrames &&
        hist.every((s) => s >= kFusionCriticalScore)) {
      if (now.difference(_lastCriticalAt) < kHazardCriticalCooldown)
        return null;
      _lastCriticalAt = now;
      _lastWarningAt = now;
      return FusionResult(
        level: AlertLevel.critical,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    if (emaScore >= kFusionWarningScore) {
      if (now.difference(_lastWarningAt) < kHazardWarningCooldown) return null;
      _lastWarningAt = now;
      return FusionResult(
        level: AlertLevel.warning,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    return null;
  }

  void reset() {
    _history.clear();
    _emaScore.clear();
    _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastWarningAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastDeadZoneAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

enum AlertLevel { warning, critical }

class FusionResult {
  final AlertLevel level;
  final double fusionScore;
  final DepthHazard hazard;
  final int stableFrames;

  const FusionResult({
    required this.level,
    required this.fusionScore,
    required this.hazard,
    required this.stableFrames,
  });
}
