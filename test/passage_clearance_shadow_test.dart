import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

import 'fixtures/passage_clearance_contract/blender_oracle.dart';

final _origin = DateTime.utc(2026, 10, 2);
final _stamp = _origin.microsecondsSinceEpoch;

GenericObstacleDetectResult _detection({
  double unknown = 0.65,
  ObstacleRejectReason reject = ObstacleRejectReason.none,
  bool aperture = true,
}) => GenericObstacleDetectResult(
  observations: const [],
  rejectReason: reject,
  detectorQuality: 1,
  groundConfidence: 1,
  surfaceEvidence: const CorridorSurfaceEvidence(
    observedFraction: 1,
    continuity: 1,
    confidence: 1,
  ),
  unknownProbabilityFloor: unknown,
  unknownReasons: aperture
      ? const [
          ObstacleUnknownReason.unverifiedAperture,
          ObstacleUnknownReason.groundModelDisagreement,
        ]
      : const [],
);

ObservationHeader _header({
  int frame = 1,
  int? stamp,
  ObservationHealth health = ObservationHealth.healthy,
}) => ObservationHeader(
  providerId: 'procedural-relative-geometry',
  modelId: 'procedural',
  modelHash: 'procedural-hash',
  preprocessId: 'fixture',
  sessionGeneration: 1,
  frameId: frame,
  sourceTimestampUs: stamp ?? _stamp,
  producedAtUs: (stamp ?? _stamp) + 1000,
  transformId: 'synthetic-rig-v1',
  confidence: 1,
  health: health,
);

SpatialSafetyRuntime _runtime({bool enabled = true}) => SpatialSafetyRuntime(
  healthCoordinator: CoreHealthCoordinator(),
  shadowPassage: enabled ? oracleConfiguration() : null,
)..beginSession(1, now: _origin.subtract(const Duration(milliseconds: 1)));

Map<String, dynamic> _geometry() {
  final root = loadOracleGeometry();
  final frame = (root['frames'] as List).firstWhere(
    (item) => item['sceneId'] == 'context-doorway' && item['frameIndex'] == 0,
  );
  return jsonDecode(jsonEncode(frame['geometry'])) as Map<String, dynamic>;
}

PassageClearanceObservation _observation({
  Map<String, dynamic>? geometry,
  int frame = 1,
  int? stamp,
}) =>
    oracleSource(
      geometry: geometry ?? _geometry(),
      configuration: oracleConfiguration(),
      capturedAtUs: stamp ?? _stamp,
      frameId: frame,
    ).observationFor(
      PassageEvaluationContext(
        nowUs: (stamp ?? _stamp) + 2000,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: 1,
        frameId: frame,
        rgbTimestampUs: stamp ?? _stamp,
        transformId: 'synthetic-rig-v1',
      ),
    );

PassageClearanceObservation _fault(
  PassageClearanceObservation original,
  String fault,
) => PassageClearanceObservation(
  providerId: original.providerId,
  modelId: original.modelId,
  modelHash: fault == 'model' ? 'different-model' : original.modelHash,
  preprocessId: original.preprocessId,
  calibrationId: fault == 'calibration'
      ? 'different-calibration'
      : original.calibrationId,
  referenceFrameId: fault == 'reference'
      ? 'other-frame'
      : original.referenceFrameId,
  rgbTransformId: original.rgbTransformId,
  depthTransformId: fault == 'transform'
      ? 'misaligned'
      : original.depthTransformId,
  timestampDomain: fault == 'clock'
      ? PassageTimestampDomain.elapsedRealtimeMicroseconds
      : original.timestampDomain,
  units: fault == 'relative' ? PassageUnits.relativeProximity : original.units,
  sessionGeneration: fault == 'session' ? 0 : original.sessionGeneration,
  frameId: fault == 'frame' ? 7 : original.frameId,
  rgbTimestampUs: original.rgbTimestampUs,
  depthTimestampUs: fault == 'skew'
      ? original.depthTimestampUs - 60000
      : original.depthTimestampUs,
  producedAtUs: fault == 'future'
      ? original.producedAtUs + 10000
      : original.producedAtUs,
  providerHealthy: fault != 'provider',
  sections: fault == 'body' || fault == 'floor'
      ? [
          for (final section in original.sections)
            PassageSection(
              forwardStartM: section.forwardStartM,
              forwardEndM: section.forwardEndM,
              state: section.state,
              bodyObservedFraction: fault == 'body'
                  ? 0.99
                  : section.bodyObservedFraction,
              floorObservedFraction: fault == 'floor'
                  ? 0.99
                  : section.floorObservedFraction,
              confidence: section.confidence,
              leftBoundaryUpperM: section.leftBoundaryUpperM,
              rightBoundaryLowerM: section.rightBoundaryLowerM,
              headroomLowerBoundM: section.headroomLowerBoundM,
              floorRiseUpperBoundM: section.floorRiseUpperBoundM,
              floorDropUpperBoundM: section.floorDropUpperBoundM,
            ),
        ]
      : original.sections,
);

SpatialRuntimeResult _ingest(
  SpatialSafetyRuntime runtime, {
  PassageClearanceObservation? observation,
  GenericObstacleDetectResult? detection,
  ObservationHeader? header,
  DateTime? now,
  double pose = 1,
  bool orientation = true,
  List<GenericObstacleTrack> tracks = const [],
  bool moving = true,
}) {
  final result = runtime.ingestGenericGeometry(
    header: header ?? _header(),
    detection: detection ?? _detection(),
    tracks: tracks,
    now: now ?? _origin.add(const Duration(milliseconds: 2)),
    orientationValid: orientation,
    userMoving: moving,
    poseQuality: pose,
    passageObservation: observation,
  );
  expect(result.accepted, isTrue);
  expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
  expect(runtime.arbiter.active, isNull);
  return result;
}

void _stops(SpatialRuntimeResult result) =>
    expect(result.decision!.action.kind, SafetyActionKind.stopNow);

GenericObstacleTrack _track({
  bool confirmed = true,
  double proximity = 1,
  double confidence = 0.9,
  double approach = 0,
}) => GenericObstacleTrack(
  id: 1,
  hits: confirmed ? 3 : 1,
  misses: 0,
  age: 3,
  proximityHist: [proximity - approach, proximity],
  metricHist: [null, null],
  timestampUsHist: [_stamp - 300000, _stamp],
  confirmed: confirmed,
  last: GenericObstacleObservation(
    geometry: ObstacleGeometry.lowObstacle,
    zone: HazardZone.center,
    normalizedBounds: const Rect.fromLTWH(0.4, 0.6, 0.2, 0.3),
    corridorOverlap: 1,
    confidence: confidence,
    relativeProximity: proximity,
    source: DepthProviderKind.ncnnRelative,
  ),
);

void main() {
  test(
    'independent full-volume proof resolves the aperture before monotonic fusion',
    () {
      _stops(_ingest(_runtime(enabled: false), observation: _observation()));
      final result = _ingest(_runtime(), observation: _observation());
      expect(result.passageClearanceApplied, isTrue);
      expect(result.decision!.action.kind, SafetyActionKind.continueForward);
      expect(
        result.snapshot.validUntil.microsecondsSinceEpoch,
        _stamp + 400000,
      );
    },
  );
  test('missing metric producer cannot use the visible floor as clearance', () {
    final result = _ingest(_runtime());
    _stops(result);
    expect(result.passageClearanceApplied, isFalse);
    expect(
      result.passageClearance!.reasons,
      contains(PassageClearanceReason.missingObservation),
    );
  });
  final geometry = loadOracleGeometry();
  for (final contrast in geometry['contrasts'] as List) {
    test('actual mesh contrast ${contrast['id']} stays blocked in shadow', () {
      final result = _ingest(
        _runtime(),
        observation: _observation(
          geometry: contrast['geometry'] as Map<String, dynamic>,
        ),
      );
      _stops(result);
      expect(result.passageClearanceApplied, isFalse);
      expect(
        result.passageClearance!.status,
        contrast['id'] == 'missing-floor-face'
            ? PassageClearanceStatus.unavailable
            : PassageClearanceStatus.blocked,
      );
    });
  }
  for (final fault in [
    'model',
    'calibration',
    'reference',
    'transform',
    'clock',
    'relative',
    'session',
    'frame',
    'skew',
    'future',
    'provider',
    'body',
    'floor',
  ]) {
    test('$fault fault never grants passage clearance', () {
      final result = _ingest(
        _runtime(),
        observation: _fault(_observation(), fault),
      );
      _stops(result);
      expect(result.passageClearanceApplied, isFalse);
      expect(
        result.passageClearance!.status,
        PassageClearanceStatus.unavailable,
      );
    });
  }
  test(
    'stale measurements fail while the ordinary geometry header is fresh',
    () {
      final now = _origin.add(const Duration(milliseconds: 500));
      final stamp = now.microsecondsSinceEpoch - 2000;
      final result = _ingest(
        _runtime(),
        header: _header(stamp: stamp),
        now: now,
        observation: _observation(stamp: _stamp),
      );
      _stops(result);
      expect(result.passageClearanceApplied, isFalse);
    },
  );
  test('floor dropout in measured geometry stays unavailable', () {
    final geometry = _geometry()..['floorBounds'] = <Object>[];
    final result = _ingest(
      _runtime(),
      observation: _observation(geometry: geometry),
    );
    _stops(result);
    expect(
      result.passageClearance!.reasons,
      contains(PassageClearanceReason.unobservedFloor),
    );
  });
  test('known geometry outside the forward coverage leaves a coverage gap', () {
    final geometry = _geometry();
    (geometry['domain'] as Map<String, dynamic>)['endM'] = 3.0;
    final result = _ingest(
      _runtime(),
      observation: _observation(geometry: geometry),
    );
    _stops(result);
    expect(
      result.passageClearance!.reasons,
      contains(PassageClearanceReason.coverageGap),
    );
  });
  for (final mode in [
    'pose',
    'orientation',
    'health',
    'degraded',
    'extra-unknown',
  ]) {
    test('$mode loss cannot be cleared by a geometric oracle', () {
      final result = _ingest(
        _runtime(),
        observation: _observation(),
        pose: mode == 'pose' ? 0.3 : 1,
        orientation: mode != 'orientation',
        header: _header(
          health: mode == 'health'
              ? ObservationHealth.unavailable
              : ObservationHealth.healthy,
        ),
        detection: _detection(
          reject: mode == 'degraded'
              ? ObstacleRejectReason.lowCoverage
              : ObstacleRejectReason.none,
          unknown: mode == 'extra-unknown' ? 0.9 : 0.65,
        ),
      );
      _stops(result);
      expect(result.passageClearanceApplied, isFalse);
    });
  }
  for (final mode in ['confirmed', 'imminent', 'unresolved', 'approaching']) {
    test('clear passage cannot erase a $mode geometry threat', () {
      final track = _track(
        confirmed: mode == 'confirmed' || mode == 'approaching',
        proximity: mode == 'approaching' ? 0.4 : 1,
        confidence: mode == 'unresolved'
            ? 0.3
            : mode == 'approaching'
            ? 0.4
            : 0.9,
        approach: mode == 'approaching' ? 0.3 : 0,
      );
      final result = _ingest(
        _runtime(),
        observation: _observation(),
        tracks: [track],
      );
      _stops(result);
      if (mode == 'unresolved') expect(result.passageClearanceApplied, isFalse);
      if (mode == 'confirmed') expect(result.snapshot.hazardTracks, isNotEmpty);
    });
  }
  test(
    'provider loss after a clear frame invalidates the scene immediately',
    () {
      final runtime = _runtime();
      _ingest(runtime, observation: _observation());
      _stops(
        runtime.noteMissingObservation(
          providerId: 'geometry',
          providerState: SceneSensorState.unavailable,
          reason: 'test-loss',
          now: _origin.add(const Duration(milliseconds: 100)),
          orientationValid: true,
          userMoving: true,
        ),
      );
    },
  );
  test('expiry tick honors the shorter metric deadline', () {
    final runtime = _runtime();
    _ingest(runtime, observation: _observation());
    final before = runtime.tick(
      now: _origin.add(const Duration(milliseconds: 200)),
      userMoving: true,
      orientationValid: true,
    );
    expect(before.decision!.action.kind, SafetyActionKind.continueForward);
    _stops(
      runtime.tick(
        now: _origin.add(const Duration(milliseconds: 401)),
        userMoving: true,
        orientationValid: true,
      ),
    );
  });
  test('a new RGB frame cannot reuse the previous frame geometry', () {
    final runtime = _runtime();
    final original = _observation();
    _ingest(runtime, observation: original);
    final stamp = _stamp + 300000;
    final result = _ingest(
      runtime,
      observation: original,
      header: _header(frame: 2, stamp: stamp),
      now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
    );
    _stops(result);
    expect(result.passageClearanceApplied, isFalse);
  });
  test(
    'new clearance neither resets a moving stop nor subtracts historical unknown',
    () {
      final runtime = _runtime();
      _stops(_ingest(runtime));
      final stamp = _stamp + 300000;
      final result = _ingest(
        runtime,
        observation: _observation(frame: 2, stamp: stamp),
        header: _header(frame: 2, stamp: stamp),
        now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
      );
      _stops(result);
      expect(
        result.snapshot.polarSectors
            .firstWhere((item) => item.id == 'forward')
            .unknownProbability,
        greaterThanOrEqualTo(0.65),
      );
    },
  );
  test('producer refuses depth samples disguised as a full-scene oracle', () {
    final geometry = _geometry()..['scope'] = 'camera_depth_samples';
    expect(() => _observation(geometry: geometry), throwsFormatException);
  });
  test(
    'measured sections stay independent of labels added to input geometry',
    () {
      final input = _geometry()
        ..['groundTruthAction'] = 'stopNow'
        ..['state'] = 'blocked';
      expect(
        _observation(geometry: input).sections.map((item) => item.state),
        _observation().sections.map((item) => item.state),
      );
    },
  );
  test(
    'a very thin internal obstacle between scan positions remains blocked',
    () {
      final geometry = _geometry();
      (geometry['occupiedBounds'] as List).add({
        'leftM': -0.002,
        'rightM': 0.002,
        'startM': 1.234001,
        'endM': 1.234002,
        'bottomM': 0,
        'topM': 1.2,
      });
      _stops(
        _ingest(_runtime(), observation: _observation(geometry: geometry)),
      );
    },
  );
  test(
    'a clearance request for a different lateral lane cannot clear forward',
    () {
      final original = oracleConfiguration();
      final runtime =
          SpatialSafetyRuntime(
            healthCoordinator: CoreHealthCoordinator(),
            shadowPassage: PassageClearanceShadowConfiguration(
              calibration: original.calibration,
              policy: original.policy,
              request: PassageClearanceRequest(
                referenceFrameId: oracleRequest.referenceFrameId,
                lateralCenterM: 0.1,
                widthM: 0.9,
                headroomM: 1.8,
                forwardStartM: 0.2,
                forwardEndM: 3.5,
                maximumFloorRiseM: 0.05,
                maximumFloorDropM: 0.05,
              ),
            ),
          )..beginSession(
            1,
            now: _origin.subtract(const Duration(milliseconds: 1)),
          );
      final result = _ingest(runtime, observation: _observation());
      _stops(result);
      expect(result.passageClearanceApplied, isFalse);
    },
  );
  test('headroom is measured above the actual floor, not world zero', () {
    final geometry = <String, dynamic>{
      'scope': 'complete_scene_geometry_oracle',
      'measurementErrorM': 0.001,
      'domain': {
        'leftM': -2,
        'rightM': 2,
        'startM': 0.15,
        'endM': 4,
        'topM': 3,
      },
      'occupiedBounds': [
        {
          'leftM': -2,
          'rightM': 2,
          'startM': 0,
          'endM': 4,
          'bottomM': 1.9,
          'topM': 2.1,
        },
      ],
      'floorBounds': [
        {
          'leftM': -3,
          'rightM': 3,
          'startM': 0,
          'endM': 7,
          'bottomM': 0,
          'topM': 0.1,
        },
      ],
    };
    final result = _ingest(
      _runtime(),
      observation: _observation(geometry: geometry),
    );
    _stops(result);
    expect(
      result.passageClearance!.reasons,
      contains(PassageClearanceReason.insufficientHeadroom),
    );
    expect(result.passageClearance!.minimumHeadroomLowerBoundM, lessThan(1.8));
  });
}
