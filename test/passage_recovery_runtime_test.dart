import 'dart:ui';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/passage_clearance_contract/scenarios.dart';

final _start = DateTime.utc(2026, 10, 2).microsecondsSinceEpoch;
const _calibration = PassageCalibration(
  id: 'synthetic-calibration-v1',
  providerId: 'synthetic-conservative-bounds',
  modelId: 'bounds-fixture-v1',
  modelHash: 'synthetic-bounds-hash-v1',
  preprocessId: 'bounds-fixture-preprocess-v1',
  referenceFrameId: 'walking-frame-fixture-v1',
  transformId: 'upright-fixture-v1',
  timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
  metricScaleValidated: true,
  alignmentValidated: true,
  floorReferenceValidated: true,
);
const _request = PassageClearanceRequest(
  referenceFrameId: 'walking-frame-fixture-v1',
  lateralCenterM: 0,
  widthM: .9,
  headroomM: 1.8,
  forwardStartM: .2,
  forwardEndM: 3.5,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);

SpatialSafetyRuntime _runtime({PassageClearanceRequest request = _request}) =>
    SpatialSafetyRuntime(
      healthCoordinator: CoreHealthCoordinator(),
      shadowPassage: PassageClearanceShadowConfiguration(
        calibration: _calibration,
        request: request,
        policy: contractPolicy,
        requireCameraEvidence: true,
      ),
    )..beginSession(1, now: DateTime.fromMicrosecondsSinceEpoch(_start - 1));

SpatialRuntimeResult _ingest(
  SpatialSafetyRuntime runtime,
  int frame, {
  bool moving = false,
  String? fault,
  bool aperture = true,
  List<GenericObstacleTrack> tracks = const [],
}) {
  final stamp = _start + (frame - 1) * 200000;
  return runtime.ingestGenericGeometry(
    header: ObservationHeader(
      providerId: 'relative-detector',
      modelId: 'relative-model',
      modelHash: 'hash',
      preprocessId: 'fixture',
      sessionGeneration: 1,
      frameId: frame,
      sourceTimestampUs: stamp,
      producedAtUs: stamp + 1000,
      transformId: 'upright-fixture-v1',
      confidence: 1,
      health: ObservationHealth.healthy,
    ),
    detection: GenericObstacleDetectResult(
      observations: const [],
      rejectReason: ObstacleRejectReason.none,
      detectorQuality: 1,
      groundConfidence: 1,
      surfaceEvidence: const CorridorSurfaceEvidence(
        observedFraction: 1,
        continuity: 1,
        confidence: 1,
      ),
      unknownProbabilityFloor: fault == 'unclassified' ? .8 : .65,
      unknownReasons: aperture
          ? const [ObstacleUnknownReason.unverifiedAperture]
          : const [],
    ),
    tracks: tracks,
    now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
    orientationValid: fault != 'orientation',
    userMoving: moving,
    poseQuality: fault == 'pose' ? .2 : 1,
    passageObservation: fault == 'missing'
        ? null
        : fixtureObservation(
            domain: PassageTimestampDomain.utcEpochMicroseconds,
            frame: fault == 'frame' ? frame - 1 : frame,
            session: fault == 'session' ? 2 : 1,
            modelHash: fault == 'model' ? 'wrong' : 'synthetic-bounds-hash-v1',
            calibrationId: fault == 'calibration'
                ? 'wrong'
                : 'synthetic-calibration-v1',
            depthTransform: fault == 'transform'
                ? 'wrong'
                : 'upright-fixture-v1',
            rgbUs: stamp,
            depthUs: fault == 'expired' ? stamp - 500000 : stamp,
            producedUs: stamp + 1000,
            healthy: fault != 'provider',
            sections: [
              fixtureSection(
                start: .2,
                end: 3.5,
                state: fault == 'partial'
                    ? PassageSectionState.unknown
                    : fault == 'conflict'
                    ? PassageSectionState.conflicting
                    : fault == 'obstacle'
                    ? PassageSectionState.blocked
                    : PassageSectionState.measured,
                body: fault == 'partial' ? 0 : 1,
                floor: fault == 'partial' ? 0 : 1,
              ),
            ],
          ),
  );
}

void _shadow(SpatialRuntimeResult result) {
  expect(result.submittedAction?.delivery, SafetyActionDelivery.shadow);
}

void main() {
  test(
    'missed track uses its own capture clock, never the latest RGB clock',
    () {
      final runtime = _runtime();
      final track = GenericObstacleTrack(
        id: 1,
        last: const GenericObstacleObservation(
          geometry: ObstacleGeometry.broadSurface,
          zone: HazardZone.center,
          normalizedBounds: Rect.fromLTWH(.4, .2, .2, .6),
          corridorOverlap: .9,
          confidence: .9,
          relativeProximity: .9,
          source: DepthProviderKind.ncnnRelative,
        ),
        hits: 3,
        misses: 1,
        age: 4,
        proximityHist: [.9],
        metricHist: [null],
        timestampUsHist: [_start],
        confirmed: true,
      );
      expect(
        _ingest(
          runtime,
          1,
          moving: true,
          fault: 'partial',
          tracks: [track],
        ).decision!.action.kind,
        SafetyActionKind.stopNow,
      );
      final retained = _ingest(runtime, 2, tracks: [track]);
      expect(
        retained.snapshot.polarSectors
            .firstWhere((e) => e.id == 'forward')
            .occupancyProbability,
        .9,
      );
      final expired = _ingest(runtime, 16, tracks: [track]);
      expect(
        expired.snapshot.polarSectors
            .firstWhere((e) => e.id == 'forward')
            .occupancyProbability,
        0,
      );
      expect(
        _ingest(runtime, 17, tracks: [track]).decision!.action.kind,
        SafetyActionKind.continueForward,
      );
    },
  );
  test(
    'coverage recovery retains moving stop and requires two stationary checks',
    () {
      final runtime = _runtime();
      expect(
        _ingest(
          runtime,
          1,
          moving: true,
          fault: 'partial',
        ).decision!.action.kind,
        SafetyActionKind.stopNow,
      );
      final moving = _ingest(runtime, 2, moving: true);
      expect(moving.passageClearanceApplied, true);
      expect(moving.decision!.action.kind, SafetyActionKind.stopNow);
      final first = _ingest(runtime, 3);
      expect(first.decision!.action.kind, SafetyActionKind.holdAndScan);
      final second = _ingest(runtime, 4);
      expect(second.decision!.action.kind, SafetyActionKind.continueForward);
      expect(runtime.arbiter.active, isNull);
      _shadow(second);
    },
  );
  test(
    'full observed volume works independently of the aperture hypothesis',
    () {
      final runtime = _runtime();
      expect(
        _ingest(
          runtime,
          1,
          moving: true,
          fault: 'partial',
          aperture: false,
        ).decision!.action.kind,
        SafetyActionKind.stopNow,
      );
      expect(
        _ingest(runtime, 2, aperture: false).passageClearanceApplied,
        true,
      );
      final result = _ingest(runtime, 3, aperture: false);
      expect(result.decision!.action.kind, SafetyActionKind.continueForward);
      _shadow(result);
    },
  );
  for (final fault in [
    'partial',
    'missing',
    'expired',
    'frame',
    'session',
    'transform',
    'model',
    'calibration',
    'provider',
    'pose',
    'orientation',
    'conflict',
    'obstacle',
    'unclassified',
  ]) {
    test('new $fault after a recovered passage stops or holds', () {
      final runtime = _runtime();
      _ingest(runtime, 1, moving: true, fault: 'partial');
      _ingest(runtime, 2);
      expect(
        _ingest(runtime, 3).decision!.action.kind,
        SafetyActionKind.continueForward,
      );
      final result = _ingest(runtime, 4, moving: true, fault: fault);
      expect(
        result.decision!.action.kind,
        isNot(SafetyActionKind.continueForward),
      );
      expect(result.passageClearanceApplied, false);
      _shadow(result);
    });
  }
  test('a short contract never confirms the full forward volume', () {
    final runtime = _runtime(
      request: const PassageClearanceRequest(
        referenceFrameId: 'walking-frame-fixture-v1',
        lateralCenterM: 0,
        widthM: .9,
        headroomM: 1.8,
        forwardStartM: .2,
        forwardEndM: 1.5,
        maximumFloorRiseM: .05,
        maximumFloorDropM: .05,
      ),
    );
    final result = _ingest(runtime, 1, moving: true);
    expect(
      result.passageClearance!.status,
      PassageClearanceStatus.measuredClear,
    );
    expect(result.passageClearanceApplied, false);
    expect(result.decision!.action.kind, SafetyActionKind.stopNow);
  });
  test('expiry tick and provider loss revoke recovery', () {
    final runtime = _runtime();
    _ingest(runtime, 1, moving: true, fault: 'partial');
    _ingest(runtime, 2);
    _ingest(runtime, 3);
    final expired = runtime.tick(
      now: DateTime.fromMicrosecondsSinceEpoch(_start + 1000000),
      userMoving: true,
      orientationValid: true,
    );
    expect(
      expired.decision!.action.kind,
      isNot(SafetyActionKind.continueForward),
    );
    runtime.noteMissingObservation(
      providerId: 'relative-detector',
      providerState: SceneSensorState.unavailable,
      reason: 'recovery-test-loss',
      now: DateTime.fromMicrosecondsSinceEpoch(_start + 1100000),
      orientationValid: true,
      userMoving: true,
    );
    expect(
      runtime.sceneModel
          .snapshotAt(DateTime.fromMicrosecondsSinceEpoch(_start + 1100000))
          .observedField
          .unknownFraction,
      1,
    );
  });
}
