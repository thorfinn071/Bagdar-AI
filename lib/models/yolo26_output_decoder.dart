import 'dart:math' as math;
import 'dart:typed_data';

class Yolo26Detection {
  final double left01;
  final double top01;
  final double right01;
  final double bottom01;
  final double score;
  final int classId;

  const Yolo26Detection({
    required this.left01,
    required this.top01,
    required this.right01,
    required this.bottom01,
    required this.score,
    required this.classId,
  });
}

/// Independent experiment decoder for the YOLO26 end-to-end `[1,300,6]`
/// tensor. It is deliberately not connected to [ModelService].
class Yolo26OutputDecoder {
  static const int maxDetections = 300;
  static const int fieldsPerDetection = 6;
  static const int cocoClassCount = 80;

  const Yolo26OutputDecoder();

  List<Yolo26Detection> decode(
    Float32List values, {
    required List<int> shape,
    required int inputWidth,
    required int inputHeight,
    double scoreThreshold = 0.25,
  }) {
    if (!_sameShape(shape, const <int>[1, maxDetections, fieldsPerDetection])) {
      throw ArgumentError.value(shape, 'shape', 'expected [1, 300, 6]');
    }
    if (values.length != maxDetections * fieldsPerDetection) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'expected ${maxDetections * fieldsPerDetection}',
      );
    }
    if (inputWidth <= 0 || inputHeight <= 0) {
      throw ArgumentError('input dimensions must be positive');
    }
    if (!scoreThreshold.isFinite || scoreThreshold < 0 || scoreThreshold > 1) {
      throw ArgumentError.value(scoreThreshold, 'scoreThreshold');
    }

    final detections = <Yolo26Detection>[];
    for (var row = 0; row < maxDetections; row++) {
      final offset = row * fieldsPerDetection;
      final x1 = values[offset];
      final y1 = values[offset + 1];
      final x2 = values[offset + 2];
      final y2 = values[offset + 3];
      final score = values[offset + 4];
      final classValue = values[offset + 5];
      if (![x1, y1, x2, y2, score, classValue].every((v) => v.isFinite)) {
        continue;
      }
      if (score < scoreThreshold || score > 1) continue;
      final classId = classValue.round();
      if ((classValue - classId).abs() > 1e-3 ||
          classId < 0 ||
          classId >= cocoClassCount) {
        continue;
      }

      final left = (math.min(x1, x2) / inputWidth).clamp(0.0, 1.0);
      final right = (math.max(x1, x2) / inputWidth).clamp(0.0, 1.0);
      final top = (math.min(y1, y2) / inputHeight).clamp(0.0, 1.0);
      final bottom = (math.max(y1, y2) / inputHeight).clamp(0.0, 1.0);
      if (right <= left || bottom <= top) continue;
      detections.add(
        Yolo26Detection(
          left01: left,
          top01: top,
          right01: right,
          bottom01: bottom,
          score: score,
          classId: classId,
        ),
      );
    }
    return List.unmodifiable(detections);
  }

  bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}
