import 'dart:convert';
import 'dart:typed_data';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/camera_visible_passage_fixture.dart';

DepthFrame _frame(Float32List values, int time, {bool aligned = true}) =>
    DepthFrame(
      values: values,
      confidence01: Float32List.fromList(List.filled(values.length, 1)),
      width: 256,
      height: 256,
      timestampUs: time,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: 'midas-small-ncnn',
      modelHash: 'relative-model',
      preprocessId: 'relative-preprocessing',
      cropTopFraction: 0,
      frameQuality: 1,
      alignedToImage: aligned,
    );

// Includes the actual support, not just bounding rectangles or mean proximity.
String _signature(GenericObstacleDetectResult result) => jsonEncode({
  'reject': result.rejectReason.name,
  'ground': result.groundConfidence,
  'quality': result.detectorQuality,
  'disagreement': result.groundDisagreementPixels,
  'unknown': result.unknownReasons.map((r) => r.name).toList(),
  'observations': [
    for (final o in result.observations)
      {
        'geometry': o.geometry.name,
        'zone': o.zone.name,
        'bounds': [
          o.normalizedBounds.left,
          o.normalizedBounds.top,
          o.normalizedBounds.right,
          o.normalizedBounds.bottom,
        ],
        'proximity': o.relativeProximity,
        'confidence': o.confidence,
        'support': o.cameraSupport?.indices,
      },
  ],
});

Float32List _approaching(double proximity) {
  final values = Float32List(256 * 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      values[y * 256 + x] = 0.12 + 0.22 * y / 255;
      if (x >= 124 && x <= 132 && y >= 50 && y < 240) {
        values[y * 256 + x] = proximity;
      }
    }
  }
  return values;
}

void main() {
  late Float32List known;
  setUpAll(() {
    final fixture = VisibleFixture(
      root: 'test/fixtures/spatial_safety/camera-track-passage-v1',
    );
    final layout = (fixture.manifest['layouts'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((x) => x['id'] == 'test-association-wide-08');
    known = DepthMapOps.normalizeRelativeProximity(
      Float32List.fromList(fixture.raw(layout, 1)),
    );
  });

  test(
    'known regression: stateful RANSAC creates approach on unchanged map',
    () {
      final detector = GenericObstacleDetector(collectCameraSupport: true);
      final tracker = GenericObstacleTracker();
      for (var i = 0; i < 2; i++) {
        final t = 1000000 + i * 200000;
        final result = detector.detect(
          frame: _frame(known, t),
          pitchDeg: 3,
          rollDeg: 0,
          motion: MotionState.stationary,
        );
        tracker.update(
          observations: result.observations,
          timestampUs: t,
          relative: true,
        );
      }
      expect(tracker.tracks.any((t) => t.approachTrend() > 0), isTrue);
    },
  );

  test(
    'same current input is stable after repetitions and an unrelated frame',
    () {
      final detector = FrameStableGenericObstacleDetector(
        collectCameraSupport: true,
        collectOpeningDiagnostics: true,
      );
      final tracker = GenericObstacleTracker();
      String? expected;
      for (var i = 0; i < 8; i++) {
        final t = 1000000 + i * 200000;
        final result = detector.detect(
          frame: _frame(known, t),
          pitchDeg: 3,
          rollDeg: 0,
          motion: MotionState.stationary,
        );
        expected ??= _signature(result);
        expect(_signature(result), expected);
        final tracks = tracker.update(
          observations: result.observations,
          timestampUs: t,
          relative: true,
        );
        expect(tracks.every((t) => t.approachTrend() == 0), isTrue);
        detector.detect(
          frame: _frame(_approaching(.94), t + 100000),
          pitchDeg: 15,
          rollDeg: 4,
          motion: MotionState.walking,
        );
      }
      expect(tracker.tracks.every((t) => t.hits == 8), isTrue);
    },
  );

  test('first-frame segmentation matches unchanged legacy algorithm', () {
    final frame = _frame(known, 1000000);
    final legacy = GenericObstacleDetector(collectCameraSupport: true).detect(
      frame: frame,
      pitchDeg: 3,
      rollDeg: 0,
      motion: MotionState.walking,
    );
    final stable =
        FrameStableGenericObstacleDetector(collectCameraSupport: true).detect(
          frame: frame,
          pitchDeg: 3,
          rollDeg: 0,
          motion: MotionState.walking,
        );
    expect(_signature(stable), _signature(legacy));
  });

  test(
    'changed depth is recomputed and actual approach history is retained',
    () {
      final detector = FrameStableGenericObstacleDetector(
        collectCameraSupport: true,
      );
      final tracker = GenericObstacleTracker();
      for (var i = 0; i < 3; i++) {
        final t = 1000000 + i * 200000;
        final result = detector.detect(
          frame: _frame(_approaching(.70 + i * .10), t),
          pitchDeg: 15,
          rollDeg: 0,
          motion: MotionState.stationary,
        );
        tracker.update(
          observations: result.observations,
          timestampUs: t,
          relative: true,
        );
      }
      final pole = tracker.tracks.singleWhere(
        (t) => t.last.geometry == ObstacleGeometry.thinVertical,
      );
      expect(pole.hits, 3);
      expect(pole.confirmed, isTrue);
      expect(pole.proximityHist.length, 3);
      expect(pole.approachTrend(), closeTo(.20, .001));
      expect(pole.timestampUsHist, [1000000, 1200000, 1400000]);
    },
  );

  test('recomputed unknown, null, stale and invalid inputs keep rejection', () {
    final detector = FrameStableGenericObstacleDetector();
    GenericObstacleDetectResult detect(
      DepthFrame? f, {
      int? rgbTime,
      double roll = 0,
    }) => detector.detect(
      frame: f,
      pitchDeg: 15,
      rollDeg: roll,
      motion: MotionState.stationary,
      imageTimestampUs: rgbTime,
    );
    expect(detect(null).rejectReason, ObstacleRejectReason.noFrame);
    expect(
      detect(_frame(known, 1, aligned: false)).rejectReason,
      ObstacleRejectReason.unaligned,
    );
    expect(
      detect(_frame(known, 1), rgbTime: 1000000).rejectReason,
      ObstacleRejectReason.stale,
    );
    expect(
      detect(_frame(known, 1), roll: double.nan).rejectReason,
      ObstacleRejectReason.unaligned,
    );
    final unavailable = detect(
      _frame(Float32List.fromList(List.filled(256 * 256, double.nan)), 1),
    );
    expect(unavailable.observations, isEmpty);
    expect(unavailable.detectorQuality, 0);
  });
}
