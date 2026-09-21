import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bagdar/models/plane_fit_quality.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = GroundPlaneAnalyzer.kMapSize;

Float32List _map(double Function(int x, int y) valueAt) {
  final values = Float32List(_size * _size);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      values[y * _size + x] = valueAt(x, y);
    }
  }
  return values;
}

Float32List _flat([double value = 0.5]) => _map((_, __) => value);

void main() {
  group('PlaneFitQuality admission matrix', () {
    test('flat and sloped planes are accepted with spatial coverage', () {
      final analyzer = GroundPlaneAnalyzer();
      analyzer.analyze(_flat());
      expect(analyzer.lastPlaneFitQuality.accepted, isTrue);
      expect(analyzer.lastPlaneFitQuality.inlierRowCoverage, 1);
      expect(analyzer.lastPlaneFitQuality.inlierColumnCoverage, 1);

      analyzer.analyze(_map((x, y) => 0.30 + x * 0.00035 + y * 0.00055));
      expect(analyzer.lastPlaneFitQuality.accepted, isTrue);
      expect(analyzer.lastPlaneFitQuality.temporalConsistencyScore, isNotNull);
    });

    test('curb and partial occlusion preserve a trustworthy base plane', () {
      final analyzer = GroundPlaneAnalyzer();
      final curb = _flat();
      for (var y = 220; y < _size; y++) {
        for (var x = 108; x < 148; x++) {
          curb[y * _size + x] = 0.68;
        }
      }
      analyzer.analyze(curb, userStationary: true);
      expect(analyzer.lastPlaneFitQuality.accepted, isTrue);

      final occluded = _flat();
      for (var y = 128; y < 180; y++) {
        for (var x = 0; x < 72; x++) {
          occluded[y * _size + x] = 0;
        }
      }
      analyzer.analyze(occluded);
      expect(analyzer.lastPlaneFitQuality.accepted, isTrue);
    });

    test('NaN and zero holes fail closed when coverage is too small', () {
      final analyzer = GroundPlaneAnalyzer();
      final holes = Float32List(_size * _size);
      holes.fillRange(0, holes.length, double.nan);
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          final y = GroundPlaneAnalyzer.kZoneStartRow + row * 4;
          holes[y * _size + col * 4] = 0.5;
        }
      }
      analyzer.analyze(holes);
      expect(analyzer.lastPlaneFitOk, isFalse);
      expect(
        analyzer.lastPlaneFitQuality.rejectionReason,
        PlaneFitRejectionReason.insufficientValidPoints,
      );
    });

    test('uniform and structured noise are rejected deterministically', () {
      final random = math.Random(42);
      final uniformNoise = _map((_, __) => 0.1 + random.nextDouble() * 0.8);
      final structuredNoise = _map(
        (x, y) => ((x ~/ 8 + y ~/ 8).isEven) ? 0.18 : 0.86,
      );

      for (final values in <Float32List>[uniformNoise, structuredNoise]) {
        final analyzer = GroundPlaneAnalyzer();
        analyzer.analyze(values, weatherDegraded: true);
        expect(analyzer.lastPlaneFitOk, isFalse);
        expect(
          analyzer.lastPlaneFitQuality.rejectionReason,
          isNot(PlaneFitRejectionReason.none),
        );
      }
    });

    test('early return cannot inherit an accepted prior frame', () {
      final analyzer = GroundPlaneAnalyzer();
      analyzer.analyze(_flat());
      expect(analyzer.lastPlaneFitOk, isTrue);

      final sparse = Float32List(_size * _size);
      for (var i = 0; i < 9; i++) {
        final y = GroundPlaneAnalyzer.kZoneStartRow + (i ~/ 3) * 4;
        final x = (i % 3) * 4;
        sparse[y * _size + x] = 0.5;
      }
      analyzer.analyze(sparse);

      expect(analyzer.lastPlaneFitOk, isFalse);
      expect(
        analyzer.lastPlaneFitQuality.rejectionReason,
        PlaneFitRejectionReason.insufficientValidPoints,
      );
    });
  });
}
