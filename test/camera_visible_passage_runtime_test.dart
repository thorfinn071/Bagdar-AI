import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/passage_clearance_contract/scenarios.dart';

void main() {
  for (final state in [
    PassageSectionState.blocked,
    PassageSectionState.unknown,
    null,
  ]) {
    test(
      'negative camera $state is admitted when detector misses aperture',
      () {
        final runtime = SpatialSafetyRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          shadowPassage: PassageClearanceShadowConfiguration(
            calibration: fixtureCalibration(),
            request: contractRequest,
            policy: contractPolicy,
            requireCameraEvidence: true,
          ),
        )..beginSession(1, now: DateTime.fromMicrosecondsSinceEpoch(999999));
        final result = runtime.ingestGenericGeometry(
          header: const ObservationHeader(
            providerId: 'relative-detector',
            modelId: 'relative',
            modelHash: 'hash',
            preprocessId: 'fixture',
            sessionGeneration: 1,
            frameId: 1,
            sourceTimestampUs: 1000000,
            producedAtUs: 1010000,
            transformId: 'upright-fixture-v1',
            confidence: 1,
            health: ObservationHealth.healthy,
          ),
          detection: const GenericObstacleDetectResult(
            observations: [],
            rejectReason: ObstacleRejectReason.none,
            detectorQuality: 1,
            groundConfidence: 1,
            surfaceEvidence: CorridorSurfaceEvidence(
              observedFraction: 1,
              continuity: 1,
              confidence: 1,
            ),
            unknownProbabilityFloor: .01,
            unknownReasons: [],
          ),
          tracks: [],
          now: DateTime.fromMicrosecondsSinceEpoch(1020000),
          orientationValid: true,
          userMoving: true,
          poseQuality: 1,
          passageObservation: state == null
              ? null
              : fixtureObservation(
                  sections: [
                    fixtureSection(
                      state: state,
                      body: state == PassageSectionState.unknown ? 0 : 1,
                    ),
                  ],
                ),
        );
        expect(result.accepted, true);
        expect(result.decision!.action.kind, SafetyActionKind.stopNow);
        expect(result.passageClearance, isNotNull);
        expect(result.passageClearanceApplied, false);
        expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
        expect(runtime.arbiter.active, isNull);
      },
    );
  }
}
