import 'dart:convert';
import 'dart:ui';

import 'package:bagdar/camera/inspection_scene_status.dart';
import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:flutter_test/flutter_test.dart';

final inspectionStamp = DateTime.utc(2026, 10, 19);

GenericObstacleDetectResult inspectionDetection({
  bool possible = false,
  ObstacleRejectReason reject = ObstacleRejectReason.none,
  double quality = 1,
}) => GenericObstacleDetectResult(
  observations: [
    if (possible)
      const GenericObstacleObservation(
        geometry: ObstacleGeometry.broadSurface,
        zone: HazardZone.center,
        normalizedBounds: Rect.fromLTRB(.35, .3, .65, .6),
        corridorOverlap: .8,
        confidence: .9,
        relativeProximity: .8,
        source: DepthProviderKind.ncnnRelative,
      ),
  ],
  rejectReason: reject,
  detectorQuality: quality,
  groundConfidence: 1,
  surfaceEvidence: const CorridorSurfaceEvidence(
    observedFraction: 1,
    continuity: 1,
    confidence: 1,
  ),
  corridorCoverage: const CorridorDepthCoverage(
    upperObservedFraction: 1,
    lowerObservedFraction: 1,
  ),
);

ObservationHeader inspectionHeader({
  int generation = 1,
  int frame = 1,
  ObservationHealth health = ObservationHealth.healthy,
}) => ObservationHeader(
  providerId: 'status-test',
  modelId: 'relative-test',
  modelHash: 'test-hash',
  preprocessId: 'test',
  sessionGeneration: generation,
  frameId: frame,
  sourceTimestampUs: inspectionStamp.microsecondsSinceEpoch,
  producedAtUs: inspectionStamp.microsecondsSinceEpoch + 1000,
  transformId: 'status-test',
  confidence: 1,
  health: health,
);

SpatialRuntimeResult admitInspection(
  SpatialSafetyRuntime runtime,
  ObservationHeader header,
  GenericObstacleDetectResult detection,
) => runtime.ingestGenericGeometry(
  header: header,
  detection: detection,
  tracks: const [],
  now: inspectionStamp.add(const Duration(microseconds: 2000)),
  orientationValid: true,
  userMoving: true,
  poseQuality: 1,
);

InspectionSceneStatus readInspection(
  SpatialSafetyRuntime runtime,
  ObservationHeader? header,
  GenericObstacleDetectResult? detection, {
  DateTime? now,
  bool ready = true,
  bool orientation = true,
}) => InspectionSceneStatus.fromCamera(
  runtime: runtime,
  header: header,
  detection: detection,
  now: now ?? inspectionStamp.add(const Duration(microseconds: 2000)),
  cameraReady: ready,
  orientationValid: orientation,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ConfidenceAuthoritySpatialRuntime runtime;
  setUp(() {
    AppStrings.setLanguage(AppLanguage.en);
    runtime =
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
        )..beginSession(
          1,
          now: inspectionStamp.subtract(const Duration(milliseconds: 1)),
        );
  });
  tearDown(() => AppStrings.setLanguage(AppLanguage.ru));

  test(
    'camera observation stays separate from STOP and walking permission',
    () {
      final header = inspectionHeader(), detection = inspectionDetection();
      final result = admitInspection(runtime, header, detection);
      expect(result.accepted, true);
      expect(result.decision!.action.kind.name, 'stopNow');
      final snapshotBefore = jsonEncode(
        runtime.snapshotAt(inspectionStamp).toDiagnosticMap(),
      );
      final traces = runtime.traces.length, state = runtime.planner.state;
      final status = readInspection(runtime, header, detection);
      expect(status.observation, InspectionObservationState.noObstacleReported);
      expect(status.clearance, InspectionClearanceCapability.notAvailable);
      expect(status.mayAuthorizeMovement, false);
      expect(runtime.traces.length, traces);
      expect(runtime.planner.state, state);
      expect(runtime.arbiter.active, isNull);
      expect(
        jsonEncode(runtime.snapshotAt(inspectionStamp).toDiagnosticMap()),
        snapshotBefore,
      );
    },
  );

  test(
    'current detector shapes are possible obstacles, not confirmed clearance',
    () {
      final header = inspectionHeader(),
          detection = inspectionDetection(possible: true);
      admitInspection(runtime, header, detection);
      final status = readInspection(runtime, header, detection);
      expect(status.observation, InspectionObservationState.possibleObstacle);
      expect(status.mayAuthorizeMovement, false);
    },
  );

  for (final rejection in ObstacleRejectReason.values.where(
    (r) =>
        r != ObstacleRejectReason.none &&
        r != ObstacleRejectReason.emptyCorridor,
  )) {
    test(
      'rejected ${rejection.name} is unavailable rather than no obstacles',
      () {
        final header = inspectionHeader(),
            detection = inspectionDetection(reject: rejection);
        admitInspection(runtime, header, detection);
        expect(
          readInspection(runtime, header, detection).observation,
          InspectionObservationState.unavailable,
        );
      },
    );
  }

  for (final health in ObservationHealth.values.where(
    (h) => h != ObservationHealth.healthy,
  )) {
    test('${health.name} provider cannot supply an observation claim', () {
      final header = inspectionHeader(health: health),
          detection = inspectionDetection();
      admitInspection(runtime, header, detection);
      expect(
        readInspection(runtime, header, detection).observation,
        InspectionObservationState.unavailable,
      );
    });
  }

  test('age is measured from capture and cadence cannot refresh it', () {
    final header = inspectionHeader(), detection = inspectionDetection();
    admitInspection(runtime, header, detection);
    final expiry = inspectionStamp.add(runtime.observationTtl);
    expect(
      readInspection(runtime, header, detection, now: expiry).observation,
      InspectionObservationState.noObstacleReported,
    );
    runtime.tick(
      now: expiry.add(const Duration(microseconds: 1)),
      userMoving: true,
      orientationValid: true,
    );
    expect(
      readInspection(
        runtime,
        header,
        detection,
        now: expiry.add(const Duration(microseconds: 1)),
      ).observation,
      InspectionObservationState.stale,
    );
  });

  test('new and ended sessions cannot reuse a previous observation', () {
    final header = inspectionHeader(), detection = inspectionDetection();
    admitInspection(runtime, header, detection);
    runtime.endSession(
      now: inspectionStamp.add(const Duration(milliseconds: 3)),
    );
    expect(
      readInspection(runtime, header, detection).observation,
      InspectionObservationState.unavailable,
    );
    runtime.beginSession(
      2,
      now: inspectionStamp.add(const Duration(milliseconds: 4)),
    );
    expect(
      readInspection(runtime, header, detection).observation,
      InspectionObservationState.unavailable,
    );
    expect(
      readInspection(runtime, null, null).observation,
      InspectionObservationState.notChecked,
    );
  });

  test(
    'a pipeline frame not admitted by runtime cannot replace observations',
    () {
      final first = inspectionHeader(), second = inspectionHeader(frame: 2);
      final detection = inspectionDetection();
      admitInspection(runtime, first, detection);
      expect(
        readInspection(runtime, second, detection).observation,
        InspectionObservationState.unavailable,
      );
      admitInspection(runtime, second, detection);
      expect(
        readInspection(runtime, first, detection).observation,
        InspectionObservationState.unavailable,
      );
    },
  );

  test(
    'camera loss, missing results, invalid orientation and future clocks',
    () {
      final header = inspectionHeader(), detection = inspectionDetection();
      admitInspection(runtime, header, detection);
      expect(
        readInspection(runtime, header, detection, ready: false).observation,
        InspectionObservationState.unavailable,
      );
      expect(
        readInspection(runtime, header, null).observation,
        InspectionObservationState.unavailable,
      );
      expect(
        readInspection(
          runtime,
          header,
          detection,
          orientation: false,
        ).observation,
        InspectionObservationState.adjustPhone,
      );
      expect(
        readInspection(
          runtime,
          header,
          detection,
          now: inspectionStamp,
        ).observation,
        InspectionObservationState.unavailable,
      );
      runtime.noteMissingObservation(
        providerId: header.providerId,
        providerState: SceneSensorState.unavailable,
        reason: 'test-loss',
        now: inspectionStamp.add(const Duration(milliseconds: 4)),
        orientationValid: true,
        userMoving: false,
      );
      expect(
        readInspection(
          runtime,
          header,
          detection,
          now: inspectionStamp.add(const Duration(milliseconds: 5)),
        ).observation,
        InspectionObservationState.unavailable,
      );
    },
  );

  test('a positive shadow action never becomes movement permission', () {
    final base =
        SpatialSafetyRuntime(healthCoordinator: CoreHealthCoordinator())
          ..beginSession(
            1,
            now: inspectionStamp.subtract(const Duration(milliseconds: 1)),
          );
    final header = inspectionHeader(), detection = inspectionDetection();
    final result = admitInspection(base, header, detection);
    expect(result.decision!.action.kind.name, 'continueForward');
    expect(result.submittedAction!.delivery.name, 'shadow');
    expect(readInspection(base, header, detection).mayAuthorizeMovement, false);
    expect(base.arbiter.active, isNull);
  });

  test(
    'an experiment configuration is not proof of a usable clearance source',
    () {
      final experiment = ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        shadowPassage: const PassageClearanceShadowConfiguration(
          policy: PassageClearancePolicy(
            maximumAgeUs: 100000,
            maximumPairSkewUs: 50000,
            maximumProcessingLatencyUs: 100000,
            minimumConfidence: .99,
          ),
          calibration: PassageCalibration(
            id: 'unvalidated',
            providerId: 'unvalidated',
            modelId: 'unvalidated',
            modelHash: 'unvalidated',
            preprocessId: 'unvalidated',
            referenceFrameId: 'test',
            transformId: 'test',
            timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
            metricScaleValidated: false,
            alignmentValidated: false,
            floorReferenceValidated: false,
          ),
          request: PassageClearanceRequest(
            referenceFrameId: 'test',
            lateralCenterM: 0,
            widthM: .9,
            headroomM: 1.85,
            forwardStartM: .2,
            forwardEndM: 3.5,
            maximumFloorRiseM: .05,
            maximumFloorDropM: .05,
          ),
        ),
      )..beginSession(1, now: inspectionStamp);
      final status = readInspection(experiment, null, null);
      expect(status.clearance, InspectionClearanceCapability.experimentalOnly);
      expect(status.mayAuthorizeMovement, false);
    },
  );

  for (final language in AppLanguage.values) {
    test(
      '${language.name} spoken status includes observations and movement limit',
      () {
        AppStrings.setLanguage(language);
        final health = CoreHealthCoordinator();
        for (final component in CoreComponent.values) {
          health.note(
            component: component,
            state: ComponentState.available,
            reasonCode: 'constructed-healthy',
            now: inspectionStamp,
            announce: false,
          );
        }
        final header = inspectionHeader(), detection = inspectionDetection();
        admitInspection(runtime, header, detection);
        final value = InspectionSystemStatus.fromHealth(
          health.snapshot(inspectionStamp),
          cameraReady: true,
          permissionDenied: false,
          scene: readInspection(runtime, header, detection),
        );
        expect(value.summary, S.get('inspection_run_operational'));
        expect(value.spokenText, contains(value.observationText));
        expect(value.spokenText, contains(value.clearanceText));
        expect(value.spokenText, contains(value.movementText));
        expect(value.spokenText, isNot(contains('inspection_')));
        expect(value.scene.mayAuthorizeMovement, false);
        final denied = InspectionSystemStatus.fromHealth(
          health.snapshot(inspectionStamp),
          cameraReady: true,
          permissionDenied: true,
          scene: value.scene,
        );
        expect(
          denied.scene.observation,
          InspectionObservationState.unavailable,
        );
      },
    );
  }
}
