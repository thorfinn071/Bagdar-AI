import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _surface = CorridorSurfaceEvidence(
  observedFraction: 1,
  continuity: 1,
  confidence: 1,
);

// Adapter/runtime fixtures isolate component confidence from sensing support.
// They are neither depth-model inference nor physical clearance measurements.
List<SpatialRuntimeResult> _sequence({
  double confidence = 0.008,
  List<double> proximities = const [0.023, 0.023, 0.023, 0.023, 0.023],
  double upperCoverage = 1,
  List<double>? upperCoverages,
  double lowerCoverage = 1,
  double detectorQuality = 1,
  double unknownFloor = 0,
  ObstacleRejectReason rejectReason = ObstacleRejectReason.none,
  CorridorSurfaceEvidence surface = _surface,
}) {
  final start = DateTime.utc(2026, 10, 1);
  final tracker = GenericObstacleTracker();
  final runtime = SpatialSafetyRuntime(
    healthCoordinator: CoreHealthCoordinator(),
  )..beginSession(1, now: start.subtract(const Duration(milliseconds: 1)));
  final results = <SpatialRuntimeResult>[];
  for (final (index, proximity) in proximities.indexed) {
    final at = start.add(Duration(milliseconds: index * 300));
    final timestampUs = at.microsecondsSinceEpoch;
    final observation = GenericObstacleObservation(
      geometry: ObstacleGeometry.broadSurface,
      zone: HazardZone.center,
      normalizedBounds: const Rect.fromLTRB(0.29, 0.18, 0.71, 0.44),
      corridorOverlap: 0.8,
      confidence: confidence,
      relativeProximity: proximity,
      source: DepthProviderKind.ncnnRelative,
      pixelCount: 6276,
    );
    final detection = GenericObstacleDetectResult(
      observations: [observation],
      rejectReason: rejectReason,
      detectorQuality: detectorQuality,
      groundConfidence: surface.confidence,
      surfaceEvidence: surface,
      corridorCoverage: CorridorDepthCoverage(
        upperObservedFraction: upperCoverages?[index] ?? upperCoverage,
        lowerObservedFraction: lowerCoverage,
      ),
      unknownProbabilityFloor: unknownFloor,
    );
    final tracks = tracker.update(
      observations: detection.observations,
      timestampUs: timestampUs,
      relative: true,
    );
    if (index >= 2) expect(tracks.single.confirmed, isTrue);
    final result = runtime.ingestGenericGeometry(
      header: ObservationHeader(
        providerId: 'component-confidence-fixture',
        modelId: 'relative-fixture',
        modelHash: _hash,
        preprocessId: 'relative-fixture-v1',
        sessionGeneration: 1,
        frameId: index + 1,
        sourceTimestampUs: timestampUs,
        producedAtUs: timestampUs + 1000,
        transformId: 'upright-fixture',
        confidence: detectorQuality,
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
    results.add(result);
  }
  return results;
}

void main() {
  for (final confidence in [0.008, 0.05, 0.20]) {
    test(
      'distant component confidence $confidence does not hide the sector',
      () {
        final results = _sequence(confidence: confidence);
        for (final result in results) {
          expect(
            result.decision!.action.kind,
            SafetyActionKind.continueForward,
          );
          final forward = result.snapshot.polarSectors.singleWhere(
            (sector) => sector.id == 'forward',
          );
          expect(forward.unknownProbability, 0);
        }
        // The confirmed component still contributes occupancy and hazard state.
        final forward = results.last.snapshot.polarSectors.singleWhere(
          (sector) => sector.id == 'forward',
        );
        expect(forward.occupancyProbability, greaterThanOrEqualTo(0.023));
        expect(results.last.snapshot.hazardTracks, hasLength(1));
      },
    );
  }

  test('confirmed close component stops despite very low confidence', () {
    final results = _sequence(proximities: List.filled(5, 0.98));
    for (final result in results.skip(2)) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      final forward = result.snapshot.polarSectors.singleWhere(
        (sector) => sector.id == 'forward',
      );
      expect(forward.occupancyProbability, greaterThanOrEqualTo(0.98));
    }
  });

  test(
    'confirmed approaching component retains moving threat at low confidence',
    () {
      final results = _sequence(proximities: [0.023, 0.16, 0.30]);
      expect(results.last.decision!.action.kind, SafetyActionKind.stopNow);
      expect(results.last.snapshot.movingThreats, isNotEmpty);
    },
  );

  for (final missingUpper in [true, false]) {
    test('${missingUpper ? 'upper' : 'lower'} dropout remains unknown', () {
      final results = _sequence(
        upperCoverage: missingUpper ? 0.1 : 1,
        lowerCoverage: missingUpper ? 1 : 0.1,
      );
      for (final result in results) {
        expect(result.decision!.action.kind, SafetyActionKind.stopNow);
        final forward = result.snapshot.polarSectors.singleWhere(
          (sector) => sector.id == 'forward',
        );
        expect(forward.unknownProbability, greaterThanOrEqualTo(0.9));
      }
    });
  }

  test('upper dropout after positive evidence still stops a moving user', () {
    final results = _sequence(upperCoverages: [1, 1, 1, 0.1, 0.1]);
    for (final result in results.take(3)) {
      expect(result.decision!.action.kind, SafetyActionKind.continueForward);
    }
    for (final result in results.skip(3)) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
  });

  test('detector uncertainty floor survives distant track confirmation', () {
    for (final result in _sequence(unknownFloor: 0.65)) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      final forward = result.snapshot.polarSectors.singleWhere(
        (sector) => sector.id == 'forward',
      );
      expect(forward.unknownProbability, greaterThanOrEqualTo(0.65));
    }
  });

  test('distant tracks cannot create missing positive surface evidence', () {
    for (final result in _sequence(
      surface: CorridorSurfaceEvidence.unavailable,
    )) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
  });

  test('poor sensing quality cannot inherit confidence from the surface', () {
    for (final result in _sequence(detectorQuality: 0.2)) {
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
    }
  });

  for (final reason in [
    ObstacleRejectReason.stale,
    ObstacleRejectReason.unaligned,
    ObstacleRejectReason.noFrame,
    ObstacleRejectReason.lowConfidence,
  ]) {
    test(
      'rejected sensing ${reason.name} still stops with a distant track',
      () {
        for (final result in _sequence(rejectReason: reason)) {
          expect(result.decision!.action.kind, SafetyActionKind.stopNow);
        }
      },
    );
  }
}
