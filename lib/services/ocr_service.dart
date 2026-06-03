import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/strings.dart';
import '../utils/performance_throttler.dart' show MemoryPressureLevel;
import 'field_logger.dart';
import 'kk_dictionary.dart';
import 'memory_monitor.dart';
import 'paddle_ocr_bridge.dart';
import 'settings_service.dart';

/// OCR pipeline used by the camera screen's "read text" flow.
///
/// Phase 3 of the Kazakh language stack rework introduces a tiered
/// recognizer:
///
///   1. **PaddleOCR via [PaddleOcrBridge]** — primary path when
///      `Settings.enableKazakhStackV2` is on AND the native side
///      reports the PaddleLite runtime + the four model artifacts as
///      available. Correctly handles Latin, Cyrillic, and the Kazakh
///      extra letters (Ә Ғ Қ Ң Ө Ұ Ү Һ І).
///   2. **ML Kit (legacy)** — fallback for every other case. Latin
///      works fine; ru/kk fall back to the same broken Cyrillic
///      behavior as before Phase 3, which is no worse than the status
///      quo. The fallback exists so Phase 3 can ship its code without
///      gating on the PaddleLite `.aar` + model assets.
///
/// Public API is preserved exactly so `camera_screen.dart` and
/// `CameraViewModel.ocr` do not need to change.
class OcrService {
  /// [memoryMonitor] is optional so the existing zero-arg constructor
  /// pattern in `CameraViewModel` keeps working. When supplied,
  /// `recognizeFromFrame` refuses to start a new session while the
  /// monitor reports `MemoryPressureLevel.critical`.
  OcrService({MemoryMonitor? memoryMonitor}) : _memoryMonitor = memoryMonitor;

  
  int sensorOrientationDeg = 90;

  Future<String?> recognizeFromFrame(
    CameraImage image, {
    bool stabilize = false,
  }) async {
    if (_busy) return null;
    _busy = true;

    try {
      if (_shouldRefuseForMemoryPressure()) {
        FieldLogger.instance.log('ocr_skipped_low_memory', {
          'level': _memoryMonitor?.level.name ?? 'unknown',
        });
        return null;
      }

      final paddleText = await _tryPaddleOcr(image);
      if (paddleText != null) {
        return _finalize(paddleText, stabilize: stabilize);
      }

      final mlkitText = await _runMlKit(image);
      if (mlkitText == null || mlkitText.isEmpty) {
        _stabilizeBuffer.clear();
        return null;
      }
      return _finalize(mlkitText, stabilize: stabilize);
    } catch (e) {
      debugPrint('OcrService error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  void resetStabilizer() => _stabilizeBuffer.clear();

  void dispose() {
    
    
    unawaited(_latinRecognizer.close().catchError((Object _) {}));
    unawaited(_defaultRecognizer.close().catchError((Object _) {}));
    unawaited(PaddleOcrBridge.instance.dispose());
  }

  
  final TextRecognizer _latinRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final TextRecognizer _defaultRecognizer = TextRecognizer();

  bool _busy = false;
  final MemoryMonitor? _memoryMonitor;

  /// Minimum native confidence (`[0, 1]`) for a Paddle text line to
  /// reach the final string. Lower threshold via
  /// [debugSetConfidenceThreshold] only from tests.
  static const double _kPaddleConfidenceThreshold = 0.6;

  /// Maximum number of text lines surfaced to TTS. Phase 0 also capped
  /// at 3 (`lines.take(3).join('. ')`).
  static const int _kMaxLines = 3;

  static const int _kStableFrames = 2;
  final ListQueue<String> _stabilizeBuffer = ListQueue<String>();

  double _confidenceThreshold = _kPaddleConfidenceThreshold;

  Future<String?> _tryPaddleOcr(CameraImage image) async {
    if (!_isKazakhStackV2Enabled()) return null;
    final bridge = PaddleOcrBridge.instance;
    if (!bridge.isInitialized) {
      try {
        await bridge.init();
      } catch (_) {
        return null;
      }
    }
    if (!bridge.isAvailable) return null;

    final concatenated = _concatenatePlanes(image);
    if (concatenated == null) return null;

    final stopwatch = Stopwatch()..start();
    final lines = await bridge.recognize(
      yuvBytes: concatenated,
      width: image.width,
      height: image.height,
      bytesPerRow:
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      rotationDeg: sensorOrientationDeg,
      languagePref: _languagePref(),
    );
    stopwatch.stop();

    if (lines.isEmpty) {
      FieldLogger.instance.log('paddle_ocr_session', {
        'latency_ms': stopwatch.elapsedMilliseconds,
        'language': AppStrings.current.name,
        'lines_returned': 0,
      });
      return null;
    }

    final filtered = <String>[];
    final seen = <String>{};
    for (final line in lines) {
      if (line.confidence < _confidenceThreshold) continue;
      final text = line.text.trim();
      if (text.length < 2) continue;
      if (!seen.add(text)) continue;
      filtered.add(text);
      if (filtered.length >= _kMaxLines) break;
    }
    if (filtered.isEmpty) {
      FieldLogger.instance.log('paddle_ocr_session', {
        'latency_ms': stopwatch.elapsedMilliseconds,
        'language': AppStrings.current.name,
        'lines_returned': 0,
        'filtered': true,
      });
      return null;
    }

    final joined = filtered.join('. ');
    final corrected = AppStrings.current == AppLanguage.kk
        ? _applyKkCorrection(joined)
        : joined;

    FieldLogger.instance.log('paddle_ocr_session', {
      'latency_ms': stopwatch.elapsedMilliseconds,
      'language': AppStrings.current.name,
      'lines_returned': filtered.length,
      'post_correction_count': corrected == joined ? 0 : 1,
    });

    return corrected;
  }

  /// Legacy ML Kit recognition. Kept verbatim from Phase 0 so the
  /// fallback path matches the pre-Phase-3 behavior bit-for-bit.
  Future<String?> _runMlKit(CameraImage image) async {
    final inputImage = _buildInputImage(image);
    if (inputImage == null) return null;

    final recognizers = switch (AppStrings.current) {
      AppLanguage.en => <TextRecognizer>[_latinRecognizer],
      AppLanguage.ru || AppLanguage.kk => <TextRecognizer>[
          _defaultRecognizer,
          _latinRecognizer,
        ],
    };

    final lines = <String>[];
    final seen = <String>{};
    for (final recognizer in recognizers) {
      final recognized = await recognizer.processImage(inputImage);
      for (final block in recognized.blocks) {
        final text = block.text.trim();
        if (text.length < 2) continue;
        if (!seen.add(text)) continue;
        lines.add(text);
      }
    }

    if (lines.isEmpty) return null;
    return lines.take(_kMaxLines).join('. ');
  }

  /// Returns `null` when stabilization is enabled but the buffer has not
  /// yet collected the required number of identical reads. Returns the
  /// recognized text otherwise. Mirrors the pre-Phase-3 contract.
  String? _finalize(String text, {required bool stabilize}) {
    if (!stabilize) {
      _stabilizeBuffer.clear();
      return text;
    }

    _stabilizeBuffer.add(text);
    if (_stabilizeBuffer.length > _kStableFrames) {
      _stabilizeBuffer.removeFirst();
    }

    if (_stabilizeBuffer.length < _kStableFrames) return null;

    final allSame =
        _stabilizeBuffer.every((r) => r == _stabilizeBuffer.first);
    if (!allSame) return null;

    _stabilizeBuffer.clear();
    return text;
  }

  String _applyKkCorrection(String text) {
    final dict = KkDictionary.instance;
    if (!dict.isLoaded) {
      
      
      unawaited(dict.load());
      return text;
    }
    return dict.correctSentence(text);
  }

  bool _shouldRefuseForMemoryPressure() {
    final monitor = _memoryMonitor;
    if (monitor == null) return false;
    try {
      return monitor.level == MemoryPressureLevel.critical;
    } catch (_) {
      return false;
    }
  }

  bool _isKazakhStackV2Enabled() {
    try {
      return Settings.instance.enableKazakhStackV2;
    } catch (_) {
      return false;
    }
  }

  String _languagePref() {
    switch (AppStrings.current) {
      case AppLanguage.kk:
        return 'kk';
      case AppLanguage.ru:
        return 'ru';
      case AppLanguage.en:
        return 'en';
    }
  }

  /// Flattens a YUV420 [CameraImage] into a single byte buffer that the
  /// native side can hand to libyuv for RGB conversion. Plane order is
  /// preserved (Y, U, V).
  Uint8List? _concatenatePlanes(CameraImage image) {
    try {
      var totalLen = 0;
      for (final plane in image.planes) {
        totalLen += plane.bytes.length;
      }
      final out = Uint8List(totalLen);
      var offset = 0;
      for (final plane in image.planes) {
        out.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    try {
      final WriteBuffer buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final bytes = buffer.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotationFromDegrees(sensorOrientationDeg),
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }

  static InputImageRotation _rotationFromDegrees(int deg) {
    final normalized = ((deg % 360) + 360) % 360;
    switch (normalized) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation90deg;
    }
  }

  
  /// Lower the confidence threshold from tests so canned mock lines
  /// reach the final string. Production code never calls this.
  @visibleForTesting
  void debugSetConfidenceThreshold(double value) {
    _confidenceThreshold = value.clamp(0.0, 1.0);
  }

  /// Run the Kazakh post-correction step in isolation. Tests use this
  /// to verify confusion-pair handling against a seeded dictionary.
  @visibleForTesting
  String debugApplyKkCorrection(String text) => _applyKkCorrection(text);

  /// Drive only the [_finalize] pipeline. Used by stabilization tests so
  /// they don't have to build a real [CameraImage].
  @visibleForTesting
  String? debugFinalizeForTesting(
    String text, {
    required bool stabilize,
  }) =>
      _finalize(text, stabilize: stabilize);

  @visibleForTesting
  int debugStabilizeBufferLength() => _stabilizeBuffer.length;
}
