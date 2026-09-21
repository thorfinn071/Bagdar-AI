import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:bagdar/utils/ncnn_depth_debug_dump.dart';

void main() {
  group('depth map ops', () {
    test('resize is spatial, not zero-padded flatten', () {
      final src = Float32List.fromList([1, 2, 3, 4]);
      final dst = DepthMapOps.resizeBilinear(src, 2, 2, 4, 4);
      expect(dst.length, 16);
      expect(dst[0], closeTo(1, 0.35));
      expect(dst[15], closeTo(4, 0.35));
      // A zero-pad flatten would put 1,2,3,4 in the first four slots
      // and zeros everywhere else — that must not happen.
      expect(dst[5], isNot(0));
    });

    test('NaN and Inf become NaN and do not look like empty scene zeros', () {
      final src = Float32List.fromList([0.2, double.nan, double.infinity, 0.8]);
      DepthMapOps.sanitizeInPlace(src);
      expect(src[0], closeTo(0.2, 1e-6));
      expect(src[1].isNaN, isTrue);
      expect(src[2].isNaN, isTrue);
      expect(src[3], closeTo(0.8, 1e-6));
    });

    test('constant map normalizes to all-NaN (degenerate)', () {
      final src = Float32List(64)..fillRange(0, 64, 0.42);
      final n = DepthMapOps.normalizeRelativeProximity(src);
      expect(n.every((v) => v.isNaN), isTrue);
    });

    test('relative normalize keeps larger = nearer', () {
      final src = Float32List.fromList([
        for (int i = 0; i < 32; i++) i < 16 ? 1.0 : 10.0,
      ]);
      final n = DepthMapOps.normalizeRelativeProximity(src);
      final near = n[20];
      final far = n[2];
      expect(near, greaterThan(far));
    });

    test(
      'metric conversion is inverse-depth, not an arbitrary metre scale',
      () {
        final meters = Float32List.fromList([
          for (int i = 0; i < 32; i++) i < 16 ? 8.0 : 0.5,
        ]);
        final rel = DepthMapOps.metricToRelativeProximity(meters);
        expect(rel[20], greaterThan(rel[2]));
      },
    );

    test('inferSquareLayout rejects non-square lengths', () {
      expect(DepthMapOps.inferSquareLayout(4096), (64, 64));
      expect(DepthMapOps.inferSquareLayout(1000), isNull);
    });

    test('debug dump is off without explicit consent', () {
      NcnnDepthDebugDump.consentGranted = false;
      NcnnDepthDebugDump.outputDir = '/tmp/should-not-write';
      expect(NcnnDepthDebugDump.enabled, isFalse);
    });
  });
}
