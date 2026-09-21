import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';

DepthFrame _relative(
  Float32List values, {
  bool aligned = true,
  double quality = 0.8,
  double cropTop = 0.2,
  int timestampUs = 1,
}) {
  final conf = Float32List(values.length);
  for (int i = 0; i < values.length; i++) {
    conf[i] = values[i].isFinite ? 1.0 : 0.0;
  }
  return DepthFrame(
    values: values,
    confidence01: conf,
    width: 256,
    height: 256,
    timestampUs: timestampUs,
    provider: DepthProviderKind.ncnnRelative,
    semantics: DepthValueSemantics.relativeProximity,
    modelId: 'test-depth',
    modelHash: 'test-hash',
    preprocessId: 'test-preprocess',
    cropTopFraction: cropTop,
    frameQuality: quality,
    alignedToImage: aligned,
  );
}

Float32List _openCorridor() {
  final m = Float32List(256 * 256);
  for (int y = 0; y < 256; y++) {
    final g = 0.12 + 0.22 * (y / 255.0);
    for (int x = 0; x < 256; x++) {
      m[y * 256 + x] = g;
    }
  }
  return m;
}

Float32List _wall() {
  final m = _openCorridor();
  for (int y = 60; y < 256; y++) {
    for (int x = 70; x < 186; x++) {
      m[y * 256 + x] = 0.92;
    }
  }
  return m;
}

Float32List _pole() {
  final m = _openCorridor();
  for (int y = 50; y < 240; y++) {
    for (int x = 124; x <= 132; x++) {
      m[y * 256 + x] = 0.93;
    }
  }
  return m;
}

Float32List _box() {
  final m = _openCorridor();
  for (int y = 190; y < 250; y++) {
    for (int x = 100; x < 156; x++) {
      m[y * 256 + x] = 0.88;
    }
  }
  return m;
}

Float32List _overhead() {
  final m = _openCorridor();
  for (int y = 0; y < 70; y++) {
    for (int x = 80; x < 176; x++) {
      m[y * 256 + x] = 0.9;
    }
  }
  return m;
}

Float32List _planarWall() {
  final m = Float32List(256 * 256);
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      m[y * 256 + x] = 0.75 + 0.04 * (x / 255.0);
    }
  }
  return m;
}

void main() {
  final det = GenericObstacleDetector();

  GenericObstacleDetectResult run(Float32List map, {bool aligned = true}) =>
      det.detect(
        frame: _relative(map, aligned: aligned),
        pitchDeg: 45,
        rollDeg: 0,
        motion: MotionState.walking,
      );

  test('flat open corridor produces no warning observation', () {
    final r = run(_openCorridor());
    expect(
      r.observations.where(
        (o) => o.relativeProximity >= 0.6 && o.corridorOverlap >= 0.2,
      ),
      isEmpty,
    );
  });

  test('wide wall is a broad surface without YOLO', () {
    final r = run(_wall());
    expect(r.observations, isNotEmpty);
    expect(
      r.observations.any((o) => o.geometry == ObstacleGeometry.broadSurface),
      isTrue,
    );
  });

  test('center pole is thinVertical and does not use wall coverage', () {
    final r = run(_pole());
    expect(
      r.observations.any((o) => o.geometry == ObstacleGeometry.thinVertical),
      isTrue,
    );
    expect(
      r.observations
          .where((o) => o.geometry == ObstacleGeometry.thinVertical)
          .every((o) => o.edgeOnly),
      isTrue,
      reason: 'missing luma must not count as positive edge evidence',
    );
  });

  test(
    'aligned luma edge promotes a depth-backed pole beyond monitor-only',
    () {
      final luma = Uint8List(256 * 256);
      for (int y = 0; y < 256; y++) {
        for (int x = 128; x < 256; x++) {
          luma[y * 256 + x] = 255;
        }
      }
      final r = det.detect(
        frame: _relative(_pole()),
        pitchDeg: 45,
        rollDeg: 0,
        motion: MotionState.walking,
        lumaMap: luma,
      );
      final pole = r.observations.firstWhere(
        (o) => o.geometry == ObstacleGeometry.thinVertical,
      );
      expect(pole.edgeOnly, isFalse);
    },
  );

  test('low box/chair is a lowObstacle or unknown near the feet', () {
    final r = run(_box());
    expect(r.observations, isNotEmpty);
    expect(
      r.observations.any(
        (o) =>
            o.geometry == ObstacleGeometry.lowObstacle ||
            o.geometry == ObstacleGeometry.unknown ||
            o.geometry == ObstacleGeometry.broadSurface,
      ),
      isTrue,
    );
  });

  test('overhead component is classified overhead', () {
    final r = run(_overhead());
    expect(
      r.observations.any((o) => o.geometry == ObstacleGeometry.overhead),
      isTrue,
    );
  });

  test(
    'coherent planar near wall is detected without residual discontinuity',
    () {
      final r = run(_planarWall());
      expect(
        r.observations.any((o) => o.geometry == ObstacleGeometry.broadSurface),
        isTrue,
      );
    },
  );

  test('crop metadata remaps component bounds into the full upright frame', () {
    final r = det.detect(
      frame: _relative(_box(), cropTop: 0.4),
      pitchDeg: 45,
      rollDeg: 0,
      motion: MotionState.walking,
    );
    expect(r.observations, isNotEmpty);
    expect(r.observations.first.normalizedBounds.top, greaterThan(0.4));
  });

  test('stale image/depth timestamp pairs reject fail-closed', () {
    final r = det.detect(
      frame: _relative(_wall(), timestampUs: 1),
      pitchDeg: 45,
      rollDeg: 0,
      motion: MotionState.walking,
      imageTimestampUs: 100002,
    );
    expect(r.rejectReason, ObstacleRejectReason.stale);
    expect(r.observations, isEmpty);
  });

  test('low-quality and excessive-roll frames reject fail-closed', () {
    final low = det.detect(
      frame: _relative(_wall(), quality: 0.2),
      pitchDeg: 45,
      rollDeg: 0,
      motion: MotionState.walking,
    );
    final rolled = det.detect(
      frame: _relative(_wall()),
      pitchDeg: 45,
      rollDeg: 40,
      motion: MotionState.walking,
    );
    expect(low.rejectReason, ObstacleRejectReason.lowConfidence);
    expect(rolled.rejectReason, ObstacleRejectReason.unaligned);
  });

  test('unaligned frames are rejected, not a healthy empty scene', () {
    final r = run(_wall(), aligned: false);
    expect(r.rejectReason, ObstacleRejectReason.unaligned);
    expect(r.observations, isEmpty);
  });

  test('all-NaN map is low coverage, not path-clear', () {
    final m = Float32List(256 * 256);
    for (int i = 0; i < m.length; i++) {
      m[i] = double.nan;
    }
    final r = run(m);
    expect(r.rejectReason, ObstacleRejectReason.lowCoverage);
    expect(r.observations, isEmpty);
  });
}
