import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

final _start = DateTime.utc(2026, 10, 16);

// Fully observed synthetic relative-depth evidence isolates admission from
// model inference. It provides no metric clearance or device evidence.
GenericObstacleDetectResult _openScene() => const GenericObstacleDetectResult(
  observations: [],
  rejectReason: ObstacleRejectReason.none,
  detectorQuality: 1,
  groundConfidence: 1,
  surfaceEvidence: CorridorSurfaceEvidence(
    observedFraction: 1,
    continuity: 1,
    confidence: 1,
  ),
  corridorCoverage: CorridorDepthCoverage(
    upperObservedFraction: 1,
    lowerObservedFraction: 1,
  ),
);

SpatialSafetyRuntime _runtime() =>
    SpatialSafetyRuntime(healthCoordinator: CoreHealthCoordinator())
      ..beginSession(1, now: _start);

SpatialRuntimeResult _ingest(
  SpatialSafetyRuntime runtime, {
  required DateTime now,
  required int frame,
  ObservationHealth health = ObservationHealth.healthy,
  bool moving = true,
  Duration sourceAge = const Duration(milliseconds: 2),
  Duration producedAge = const Duration(milliseconds: 1),
}) => runtime.ingestGenericGeometry(
  header: ObservationHeader(
    providerId: 'admission-fixture',
    modelId: 'relative-fixture',
    modelHash: 'admission-model-hash',
    preprocessId: 'admission-v1',
    sessionGeneration: 1,
    frameId: frame,
    sourceTimestampUs: now.subtract(sourceAge).microsecondsSinceEpoch,
    producedAtUs: now.subtract(producedAge).microsecondsSinceEpoch,
    transformId: 'upright-fixture',
    confidence: 1,
    health: health,
  ),
  detection: _openScene(),
  tracks: const <GenericObstacleTrack>[],
  now: now,
  orientationValid: true,
  userMoving: moving,
  poseQuality: 1,
);

void main() {
  group('spatial observation admission', () {
    for (final health in [
      ObservationHealth.degraded,
      ObservationHealth.unavailable,
      ObservationHealth.rejected,
    ]) {
      for (final moving in [false, true]) {
        test(
          '${health.name} header invalidates an open scene, moving=$moving',
          () {
            final runtime = _runtime();
            final at = _start.add(const Duration(seconds: 1));
            final open = _ingest(runtime, now: at, frame: 1, moving: moving);
            expect(
              open.decision!.action.kind,
              SafetyActionKind.continueForward,
            );

            final now = at.add(const Duration(milliseconds: 20));
            final lost = _ingest(
              runtime,
              now: now,
              frame: 2,
              health: health,
              moving: moving,
            );
            final expectedState = health == ObservationHealth.degraded
                ? SceneSensorState.degraded
                : SceneSensorState.unavailable;
            expect(lost.accepted, isTrue);
            expect(
              lost.snapshot.sensorHealth.providers['admission-fixture'],
              expectedState,
            );
            expect(lost.snapshot.sensorHealth.hasUsableProvider, isFalse);
            expect(lost.snapshot.observedField.unknownFraction, 1);
            expect(
              lost.decision!.action.kind,
              moving ? SafetyActionKind.stopNow : SafetyActionKind.holdAndScan,
            );
            final component = runtime.healthCoordinator
                .snapshot(now)
                .components[CoreComponent.genericGeometry]!;
            expect(
              component.state,
              health == ObservationHealth.degraded
                  ? ComponentState.degraded
                  : ComponentState.unavailable,
            );
            expect(lost.submittedAction!.isShadowOnly, isTrue);
            expect(runtime.arbiter.active, isNull);
          },
        );
      }
    }

    test(
      'recovery after a bad header still requires stopping and fresh scenes',
      () {
        final runtime = _runtime();
        final at = _start.add(const Duration(seconds: 1));
        _ingest(runtime, now: at, frame: 1);
        final lost = _ingest(
          runtime,
          now: at.add(const Duration(milliseconds: 20)),
          frame: 2,
          health: ObservationHealth.unavailable,
        );
        expect(lost.decision!.action.kind, SafetyActionKind.stopNow);

        final movingRecovery = _ingest(
          runtime,
          now: at.add(const Duration(seconds: 3)),
          frame: 3,
        );
        expect(movingRecovery.decision!.action.kind, SafetyActionKind.stopNow);
        final stopped = _ingest(
          runtime,
          now: at.add(const Duration(milliseconds: 3020)),
          frame: 4,
          moving: false,
        );
        expect(stopped.decision!.action.kind, SafetyActionKind.holdAndScan);
        final reconfirmed = _ingest(
          runtime,
          now: at.add(const Duration(milliseconds: 3040)),
          frame: 5,
          moving: false,
        );
        expect(
          reconfirmed.decision!.action.kind,
          SafetyActionKind.continueForward,
        );
        expect(reconfirmed.submittedAction!.isShadowOnly, isTrue);
        expect(runtime.arbiter.active, isNull);
      },
    );

    test(
      'a scene rejection cannot consume a frame or hide provider recovery',
      () {
        final runtime = _runtime();
        final at = _start.add(const Duration(seconds: 1));
        _ingest(runtime, now: at, frame: 1);
        final lostAt = at.add(const Duration(milliseconds: 100));
        final lost = runtime.noteMissingObservation(
          providerId: 'admission-fixture',
          providerState: SceneSensorState.unavailable,
          reason: 'fixture_provider_loss',
          now: lostAt,
          orientationValid: true,
          userMoving: true,
        );

        // Its inference finished before the explicit provider-loss transition.
        // A large frame ID must not poison admission of subsequent valid frames.
        final rejected = _ingest(
          runtime,
          now: lostAt,
          frame: 100,
          sourceAge: const Duration(milliseconds: 30),
          producedAge: const Duration(milliseconds: 20),
        );
        expect(rejected.status, SpatialRuntimeIngestStatus.rejectedScene);
        expect(rejected.reason, 'update_precedes_current_scene');
        expect(runtime.lastFrameId, 1);
        expect(runtime.snapshotAt(lostAt).revision, lost.snapshot.revision);

        final waiting = runtime.tick(
          now: lostAt.add(const Duration(milliseconds: 1)),
          userMoving: true,
          orientationValid: true,
        );
        expect(waiting.reason, 'provider_loss');
        expect(waiting.decision!.action.kind, SafetyActionKind.stopNow);

        final recovered = _ingest(
          runtime,
          now: lostAt.add(const Duration(milliseconds: 20)),
          frame: 2,
        );
        expect(recovered.accepted, isTrue);
        expect(recovered.reason, 'recovery');
        expect(runtime.lastFrameId, 2);
        expect(recovered.decision!.action.kind, SafetyActionKind.stopNow);
      },
    );

    test('fresh inference cannot renew an expired capture timestamp', () {
      final runtime = _runtime();
      final now = _start.add(const Duration(seconds: 2));
      final expired = _ingest(
        runtime,
        now: now,
        frame: 100,
        sourceAge: const Duration(seconds: 1),
      );
      expect(expired.status, SpatialRuntimeIngestStatus.rejectedStale);
      expect(expired.decision, isNull);
      expect(runtime.lastFrameId, 0);
      expect(runtime.snapshotAt(now).sensorHealth.hasUsableProvider, isFalse);

      final fresh = _ingest(runtime, now: now, frame: 1);
      expect(fresh.accepted, isTrue);
      expect(fresh.reason, 'recovery');
    });

    test('scene deadline retains capture age after delayed inference', () {
      final runtime = _runtime();
      final now = _start.add(const Duration(seconds: 2));
      final sourceAge =
          runtime.observationTtl - const Duration(milliseconds: 10);
      final delayed = _ingest(
        runtime,
        now: now,
        frame: 1,
        sourceAge: sourceAge,
        producedAge: Duration.zero,
      );
      expect(delayed.accepted, isTrue);
      expect(
        delayed.snapshot.validUntil.microsecondsSinceEpoch,
        now.add(const Duration(milliseconds: 10)).microsecondsSinceEpoch,
      );

      final expired = runtime.tick(
        now: now.add(const Duration(milliseconds: 11)),
        userMoving: true,
        orientationValid: true,
      );
      expect(expired.reason, 'expiry_tick');
      expect(expired.snapshot.sensorHealth.hasUsableProvider, isFalse);
      expect(expired.decision!.action.kind, SafetyActionKind.stopNow);
      expect(expired.submittedAction!.isShadowOnly, isTrue);
      expect(runtime.arbiter.active, isNull);
    });
  });
}
