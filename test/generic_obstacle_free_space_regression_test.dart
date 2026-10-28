import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

// Procedural relative-depth fixtures, not recordings or metric clearance.
// The forward region is fully observed; near side walls lie outside it.
DepthFrame _passage({
  required int size,
  required double rise,
  required int timestampUs,
  bool missingUpper = false,
  bool missingLower = false,
  bool blocked = false,
  bool lowObstacle = false,
  bool aligned = true,
  double quality = 1,
}) {
  final values = Float32List(size * size);
  final confidence = Float32List(size * size);
  final x0 = (size * 0.29).floor();
  final x1 = (size * 0.71).ceil();
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      final central = x >= x0 && x < x1;
      values[i] = central ? 0.12 + rise * y / (size - 1) : 0.92;
      confidence[i] = 1;
      if (central &&
          ((missingUpper && y < size * 0.60) ||
              (missingLower && y >= size * 0.60))) {
        values[i] = double.nan;
        confidence[i] = 0;
      }
      if (central && blocked) values[i] = 1;
      if (lowObstacle &&
          x >= size * 0.40 &&
          x < size * 0.60 &&
          y >= size * 0.74 &&
          y < size * 0.96) {
        values[i] = 1;
      }
    }
  }
  return DepthFrame(
    values: values,
    confidence01: confidence,
    width: size,
    height: size,
    timestampUs: timestampUs,
    provider: DepthProviderKind.ncnnRelative,
    semantics: DepthValueSemantics.relativeProximity,
    modelId: 'procedural-observed-passage',
    modelHash: _hash,
    preprocessId: 'relative-fixture-v1',
    cropTopFraction: 0,
    frameQuality: quality,
    alignedToImage: aligned,
  );
}

List<SpatialRuntimeResult> _sequence(
  DepthFrame Function(int timestampUs) frameFor, {
  int imageSkewUs = 0,
}) {
  final start = DateTime.utc(2026, 10, 1);
  final detector = GenericObstacleDetector();
  final tracker = GenericObstacleTracker();
  final runtime = SpatialSafetyRuntime(
    healthCoordinator: CoreHealthCoordinator(),
  )..beginSession(1, now: start.subtract(const Duration(milliseconds: 1)));
  return List.generate(3, (index) {
    final at = start.add(Duration(milliseconds: index * 300));
    final timestampUs = at.microsecondsSinceEpoch;
    final frame = frameFor(timestampUs);
    final detection = detector.detect(
      frame: frame,
      pitchDeg: 45,
      rollDeg: 0,
      motion: MotionState.walking,
      imageTimestampUs: timestampUs + imageSkewUs,
    );
    final tracks = tracker.update(
      observations: detection.observations,
      timestampUs: timestampUs,
      relative: true,
    );
    final result = runtime.ingestGenericGeometry(
      header: ObservationHeader(
        providerId: 'procedural-relative-depth',
        modelId: frame.modelId,
        modelHash: frame.modelHash,
        preprocessId: frame.preprocessId,
        sessionGeneration: 1,
        frameId: index + 1,
        sourceTimestampUs: timestampUs,
        producedAtUs: timestampUs + 1000,
        transformId: 'upright-fixture',
        confidence: detection.detectorQuality,
        health: ObservationHealth.healthy,
      ),
      detection: detection,
      tracks: tracks,
      now: at.add(const Duration(milliseconds: 2)),
      orientationValid: true,
      userMoving: true,
      poseQuality: 1,
    );
    expect(result.accepted, isTrue);
    expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
    expect(runtime.arbiter.active, isNull);
    return result;
  });
}

void main() {
  test(
    'fully observed passages retain positive forward evidence beside walls',
    () {
      final failures = <String>[];
      var frames = 0;
      for (final size in [128, 256]) {
        for (final rise in [0.22, 0.38, 0.50]) {
          final results = _sequence(
            (timestampUs) =>
                _passage(size: size, rise: rise, timestampUs: timestampUs),
          );
          for (final (index, result) in results.indexed) {
            frames++;
            if (result.decision!.action.kind !=
                SafetyActionKind.continueForward) {
              failures.add('$size/$rise/$index: ${result.trace.plannedRuleId}');
            }
          }
        }
      }
      expect(frames, 18);
      expect(
        failures,
        isEmpty,
        reason: 'false stops on observed passages: $failures',
      );
    },
  );

  for (final condition in [
    'upper dropout',
    'lower dropout',
    'wall',
    'unaligned',
    'low quality',
    'timestamp skew',
  ]) {
    test('$condition never becomes positive forward guidance', () {
      final results = _sequence(
        (timestampUs) => _passage(
          size: 256,
          rise: 0.22,
          timestampUs: timestampUs,
          missingUpper: condition == 'upper dropout',
          missingLower: condition == 'lower dropout',
          blocked: condition == 'wall',
          aligned: condition != 'unaligned',
          quality: condition == 'low quality' ? 0.2 : 1,
        ),
        imageSkewUs: condition == 'timestamp skew' ? 100000 : 0,
      );
      for (final result in results) {
        expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      }
    });
  }

  test('a low central obstacle never releases a moving user', () {
    final results = _sequence(
      (timestampUs) => _passage(
        size: 256,
        rise: 0.22,
        timestampUs: timestampUs,
        lowObstacle: true,
      ),
    );
    for (final result in results) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
    expect(results.last.snapshot.hazardTracks, isNotEmpty);
  });
}
