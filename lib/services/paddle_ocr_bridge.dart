import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'field_logger.dart';

/// One recognized text line returned by PaddleOCR. Mirrors the native
/// payload shape (`{box, text, confidence}`) from
/// `bagdar/paddle_ocr.recognize`.
@immutable
class OcrTextLine {
  /// Recognized text, post-CTC-decoded by the native side. Whitespace is
  /// preserved as it appears in the source frame.
  final String text;

  /// Confidence in `[0, 1]`. Tuning threshold lives in [OcrService].
  final double confidence;

  /// Axis-aligned bounding box `[x, y, w, h]` in source-image pixel
  /// space. Empty list when the native side did not provide it.
  final List<int> box;

  const OcrTextLine({
    required this.text,
    required this.confidence,
    this.box = const [],
  });

  factory OcrTextLine.fromMap(Map<dynamic, dynamic> map) {
    final rawBox = map['box'];
    return OcrTextLine(
      text: map['text']?.toString() ?? '',
      confidence: (map['confidence'] is num)
          ? (map['confidence'] as num).toDouble()
          : 0.0,
      box: rawBox is List
          ? rawBox.map((e) => e is num ? e.toInt() : 0).toList(growable: false)
          : const [],
    );
  }

  @override
  String toString() =>
      'OcrTextLine(text="$text", conf=${confidence.toStringAsFixed(2)})';
}

/// Capability descriptor for the PaddleOCR engine, mirroring the
/// `EngineCapability` pattern from Phase 2. Reports whether the native
/// side has the PaddleLite library + all four model artifacts (`det`,
/// `rec`, `cls`, `keys.txt`) available.
@immutable
class PaddleOcrCapability {
  final bool available;
  final String version;
  final String unavailableReason;

  const PaddleOcrCapability({
    required this.available,
    this.version = '',
    this.unavailableReason = '',
  });

  static const PaddleOcrCapability unknown = PaddleOcrCapability(
    available: false,
    unavailableReason: 'not_probed',
  );

  factory PaddleOcrCapability.fromMap(Map<dynamic, dynamic> map) =>
      PaddleOcrCapability(
        available: map['available'] == true,
        version: map['version']?.toString() ?? '',
        unavailableReason: map['unavailableReason']?.toString() ?? '',
      );
}

/// Dart-side bridge to the `bagdar/paddle_ocr` Kotlin plugin
/// (`PaddleOcrPlugin` + `PaddleOcrEngine`).
///
/// Phase 3 of the Kazakh language stack — replaces the ML Kit Latin
/// recognizer (which is broken for Cyrillic) with PaddleOCR's
/// multilingual PP-OCRv4 mobile model. The bridge is intentionally
/// tolerant of a missing native side: when the PaddleLite `.aar` and
/// the four model artifacts have not yet shipped, [probe] reports
/// `available = false` and `OcrService` transparently keeps using the
/// legacy ML Kit path.
///
/// The bridge owns ZERO domain logic: confidence filtering, dedup,
/// stabilization, and Kazakh post-correction all live in [OcrService] /
/// [KkDictionary]. This keeps the Phase 3 surface easy to unit-test
/// without an actual PaddleLite predictor.
class PaddleOcrBridge {
  PaddleOcrBridge._({MethodChannel? methodChannel})
      : _method = methodChannel ?? const MethodChannel(_methodChannelName);

  static const String _methodChannelName = 'bagdar/paddle_ocr';

  static PaddleOcrBridge _instance = PaddleOcrBridge._();

  static PaddleOcrBridge get instance => _instance;

  @visibleForTesting
  static void debugReplaceInstance(PaddleOcrBridge bridge) {
    _instance = bridge;
  }

  @visibleForTesting
  static void debugResetInstance() {
    _instance = PaddleOcrBridge._();
  }

  @visibleForTesting
  factory PaddleOcrBridge.forTesting({required MethodChannel methodChannel}) =>
      PaddleOcrBridge._(methodChannel: methodChannel);

  final MethodChannel _method;

  bool _initStarted = false;
  bool _initialized = false;
  PaddleOcrCapability _capability = PaddleOcrCapability.unknown;

  bool get isInitialized => _initialized;
  PaddleOcrCapability get capability => _capability;
  bool get isAvailable => _capability.available;

  /// Probe whether the native side can run PaddleOCR. Idempotent — the
  /// cached capability is reused on subsequent calls. Use [refresh] to
  /// force a re-probe after dropping models onto disk during development.
  Future<void> init() async {
    if (_initialized || _initStarted) return;
    _initStarted = true;
    try {
      await _probe();
      _initialized = true;
    } catch (e, st) {
      debugPrint('PaddleOcrBridge.init failed: $e\n$st');
      _capability = const PaddleOcrCapability(
        available: false,
        unavailableReason: 'init_exception',
      );
    } finally {
      _initStarted = false;
    }
  }

  Future<void> refresh() async {
    await _probe();
  }

  /// Run detection + classification + recognition on a single
  /// camera-image frame. The native side handles YUV→RGB conversion,
  /// resizes to 960 px max edge, and returns ordered text lines.
  ///
  /// Returns an empty list if the engine reports unavailable, the
  /// channel errors, or no text is detected.
  Future<List<OcrTextLine>> recognize({
    required Uint8List yuvBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDeg,
    String languagePref = 'auto',
  }) async {
    if (!_capability.available) return const [];
    if (yuvBytes.isEmpty || width <= 0 || height <= 0) return const [];
    try {
      final raw = await _method.invokeMethod<dynamic>('recognize', {
        'yuvBytes': yuvBytes,
        'width': width,
        'height': height,
        'bytesPerRow': bytesPerRow,
        'rotationDeg': rotationDeg,
        'languagePref': languagePref,
      });
      if (raw is! List) return const [];
      final out = <OcrTextLine>[];
      for (final entry in raw) {
        if (entry is Map) {
          out.add(OcrTextLine.fromMap(entry));
        }
      }
      return out;
    } on PlatformException catch (e) {
      debugPrint('PaddleOcrBridge.recognize platform error: $e');
      FieldLogger.instance.log('paddle_ocr_recognize_error', {
        'code': e.code,
        'message': e.message ?? '',
      });
      return const [];
    } catch (e) {
      debugPrint('PaddleOcrBridge.recognize failed: $e');
      return const [];
    }
  }

  /// Release the native predictors. Called by `OcrService.dispose()` and
  /// by `OcrService` itself when memory pressure goes critical.
  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _method.invokeMethod<void>('dispose');
    } catch (e) {
      debugPrint('PaddleOcrBridge.dispose failed: $e');
    }
  }

  Future<void> _probe() async {
    try {
      final raw = await _method.invokeMethod<dynamic>('availableEngine');
      if (raw is Map) {
        _capability = PaddleOcrCapability.fromMap(raw);
      } else {
        _capability = const PaddleOcrCapability(
          available: false,
          unavailableReason: 'unexpected_probe_payload',
        );
      }
    } on MissingPluginException {
      _capability = const PaddleOcrCapability(
        available: false,
        unavailableReason: 'plugin_missing',
      );
    } on PlatformException catch (e) {
      _capability = PaddleOcrCapability(
        available: false,
        unavailableReason: 'platform_${e.code}',
      );
    } catch (e) {
      debugPrint('PaddleOcrBridge._probe failed: $e');
      _capability = const PaddleOcrCapability(
        available: false,
        unavailableReason: 'probe_exception',
      );
    }
  }

  // -- Test hooks ------------------------------------------------------------

  @visibleForTesting
  void debugSetCapability(PaddleOcrCapability cap) {
    _capability = cap;
    _initialized = true;
  }
}
