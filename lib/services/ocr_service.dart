import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';



class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  bool _busy = false;

  static const int _kStableFrames = 2;
  final List<String> _stabilizeBuffer = [];

  Future<String?> recognizeFromFrame(
    CameraImage image, {
    bool stabilize = false,
  }) async {
    if (_busy) return null;
    _busy = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return null;

      final recognized = await _recognizer.processImage(inputImage);

      final lines = recognized.blocks
          .map((b) => b.text.trim())
          .where((t) => t.length >= 2)
          .toList();

      if (lines.isEmpty) {
        _stabilizeBuffer.clear();
        return null;
      }

      final result = lines.take(3).join('. ');

      if (!stabilize) {
        _stabilizeBuffer.clear();
        return result;
      }

      _stabilizeBuffer.add(result);
      if (_stabilizeBuffer.length > _kStableFrames) {
        _stabilizeBuffer.removeAt(0);
      }

      if (_stabilizeBuffer.length < _kStableFrames) return null;

      final allSame = _stabilizeBuffer
          .every((r) => r == _stabilizeBuffer.first);

      if (!allSame) return null;

      _stabilizeBuffer.clear();
      return result;

    } catch (e) {
      debugPrint('OcrService error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  void resetStabilizer() => _stabilizeBuffer.clear();

  void dispose() {
    try { _recognizer.close(); } catch (_) {}
  }

  InputImage? _buildInputImage(CameraImage image) {
    try {
      final WriteBuffer buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final bytes = buffer.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size:        Size(image.width.toDouble(), image.height.toDouble()),
        rotation:    InputImageRotation.rotation0deg,
        format:      InputImageFormat.yuv420,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }
}
