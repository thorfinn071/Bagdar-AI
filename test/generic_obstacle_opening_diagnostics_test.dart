import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

// Procedural relative maps isolate the opening from its posts and lintel.
// Their filled values are not measured physical body/head clearance.
DepthFrame _doorway({
  int timestampUs = 1,
  double cropTop = 0,
  String condition = 'observed',
}) {
  const size = 256;
  final values = Float32List(size * size);
  final confidence = Float32List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      values[i] = 0.12 + 0.22 * y / 255;
      if ((y >= 45 &&
              y < 180 &&
              ((x >= 60 && x < 96) || (x >= 160 && x < 196))) ||
          (y >= 45 && y < 76 && x >= 60 && x < 196)) {
        values[i] = 0.92;
      }
      final inside = x >= 96 && x < 160;
      if (inside &&
          ((condition == 'upper dropout' && y >= 76 && y < 160) ||
              (condition == 'lower dropout' && y >= 185))) {
        values[i] = double.nan;
      }
      if (condition == 'low obstacle' &&
          x >= 106 &&
          x < 150 &&
          y >= 186 &&
          y < 250) {
        values[i] = 1;
      }
      if (condition == 'overhead' && inside && y >= 76 && y < 102) {
        values[i] = 1;
      }
      if (condition == 'narrow opening' &&
          y >= 45 &&
          y < 180 &&
          x >= 70 &&
          x < 186 &&
          (x < 123 || x >= 133)) {
        values[i] = 0.92;
      }
      if (condition == 'wall dropout' &&
          y >= 60 &&
          y < 256 &&
          x >= 70 &&
          x < 186) {
        values[i] = x >= 102 && x < 154 && y < 190 ? double.nan : 0.92;
      }
      confidence[i] = values[i].isFinite ? 1 : 0;
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
    modelId: 'procedural-opening',
    modelHash: 'procedural-opening-hash',
    preprocessId: 'relative-fixture-v1',
    cropTopFraction: cropTop,
    frameQuality: 1,
    alignedToImage: true,
  );
}

GenericObstacleDetectResult _detect(
  GenericObstacleDetector detector,
  DepthFrame frame,
) => detector.detect(
  frame: frame,
  pitchDeg: 45,
  rollDeg: 0,
  motion: MotionState.walking,
  imageTimestampUs: frame.timestampUs,
);

// Compare every decision input, not just the chosen action: an optional
// diagnostic fit must not consume either authoritative fit's random stream.
Map<String, Object?> _decisionInputs(GenericObstacleDetectResult result) => {
  'reject': result.rejectReason,
  'quality': result.detectorQuality,
  'ground': result.groundConfidence,
  'surface': [
    result.surfaceEvidence.observedFraction,
    result.surfaceEvidence.continuity,
    result.surfaceEvidence.confidence,
  ],
  'coverage': [
    result.corridorCoverage?.upperObservedFraction,
    result.corridorCoverage?.lowerObservedFraction,
  ],
  'unknown': result.unknownProbabilityFloor,
  'reasons': result.unknownReasons,
  'disagreement': result.groundDisagreementPixels,
  'observations': [
    for (final item in result.observations)
      [
        item.geometry,
        item.zone,
        item.normalizedBounds,
        item.corridorOverlap,
        item.confidence,
        item.relativeProximity,
        item.nearestDistanceM,
        item.pixelCount,
        item.edgeOnly,
      ],
  ],
};

List<SpatialRuntimeResult> _runtimeSequence(String condition) {
  final start = DateTime.utc(2026, 10, 1);
  final detector = GenericObstacleDetector(collectOpeningDiagnostics: true);
  final tracker = GenericObstacleTracker();
  final runtime = SpatialSafetyRuntime(
    healthCoordinator: CoreHealthCoordinator(),
  )..beginSession(1, now: start.subtract(const Duration(milliseconds: 1)));
  return List.generate(3, (index) {
    final at = start.add(Duration(milliseconds: 300 * index));
    final frame = _doorway(
      timestampUs: at.microsecondsSinceEpoch,
      condition: condition,
    );
    final detection = _detect(detector, frame);
    final tracks = tracker.update(
      observations: detection.observations,
      timestampUs: frame.timestampUs,
      relative: true,
    );
    final result = runtime.ingestGenericGeometry(
      header: ObservationHeader(
        providerId: 'procedural-opening',
        modelId: frame.modelId,
        modelHash: frame.modelHash,
        preprocessId: frame.preprocessId,
        sessionGeneration: 1,
        frameId: index + 1,
        sourceTimestampUs: frame.timestampUs,
        producedAtUs: frame.timestampUs + 1000,
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
  test('opening fit excludes posts without claiming physical clearance', () {
    final result = _detect(
      GenericObstacleDetector(collectOpeningDiagnostics: true),
      _doorway(),
    );
    final opening = result.openingDiagnostics!;
    expect(opening.normalizedBounds.width, closeTo(0.25, 0.01));
    expect(opening.depthCoverage.minimumObservedFraction, 1);
    expect(opening.surface.continuity, 1);
    expect(opening.surface.confidence, 1);
    expect(opening.toDiagnosticMap()['widthM'], isNull);
    expect(
      result.unknownReasons,
      contains(ObstacleUnknownReason.unverifiedAperture),
    );
    for (final result in _runtimeSequence('observed')) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
  });

  test('visible floor cannot hide missing upper opening support', () {
    final result = _detect(
      GenericObstacleDetector(collectOpeningDiagnostics: true),
      _doorway(condition: 'upper dropout'),
    );
    final opening = result.openingDiagnostics!;
    expect(opening.depthCoverage.upperObservedFraction, lessThan(0.85));
    expect(opening.depthCoverage.lowerObservedFraction, 1);
    expect(opening.surface.continuity, 1);
    for (final result in _runtimeSequence('upper dropout')) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
  });

  for (final condition in [
    'lower dropout',
    'low obstacle',
    'overhead',
    'narrow opening',
    'wall dropout',
  ]) {
    test(
      '$condition does not become positive guidance from opening diagnostics',
      () {
        for (final result in _runtimeSequence(condition)) {
          expect(result.decision!.action.kind, SafetyActionKind.stopNow);
        }
      },
    );
  }

  test(
    'diagnostics leave decision inputs identical across changing frames',
    () {
      final ordinary = GenericObstacleDetector();
      final diagnostic = GenericObstacleDetector(
        collectOpeningDiagnostics: true,
      );
      for (final (index, condition) in [
        'observed',
        'low obstacle',
        'upper dropout',
        'observed',
        'overhead',
        'wall dropout',
        'observed',
      ].indexed) {
        final frame = _doorway(
          timestampUs: 1 + index * 300000,
          condition: condition,
        );
        final left = _detect(ordinary, frame);
        final right = _detect(diagnostic, frame);
        expect(left.openingDiagnostics, isNull);
        expect(_decisionInputs(right), _decisionInputs(left));
      }
    },
  );

  test('opening bounds retain full upright crop coordinates', () {
    final result = _detect(
      GenericObstacleDetector(collectOpeningDiagnostics: true),
      _doorway(cropTop: 0.4),
    );
    expect(result.openingDiagnostics!.normalizedBounds.top, 0.4);
    expect(result.openingDiagnostics!.normalizedBounds.bottom, 1);
  });
}
