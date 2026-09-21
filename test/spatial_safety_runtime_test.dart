import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/alerts/alert_arbiter.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

ObservationHeader _header(
  DateTime now, {
  int session = 7,
  int frame = 1,
  Duration age = const Duration(milliseconds: 20),
}) {
  final producedAt = now.subtract(age).microsecondsSinceEpoch;
  return ObservationHeader(
    providerId: 'ncnn-depth',
    modelId: 'midas-small-ncnn',
    modelHash: 'test-model-hash',
    preprocessId: 'test-preprocess',
    sessionGeneration: session,
    frameId: frame,
    sourceTimestampUs: producedAt - 1000,
    producedAtUs: producedAt,
    transformId: 'test-transform',
    confidence: 0.95,
    health: ObservationHealth.healthy,
  );
}

GenericObstacleObservation _observation() => const GenericObstacleObservation(
  geometry: ObstacleGeometry.broadSurface,
  zone: HazardZone.center,
  normalizedBounds: Rect.fromLTWH(0.30, 0.20, 0.40, 0.70),
  corridorOverlap: 0.90,
  confidence: 0.95,
  relativeProximity: 0.92,
  source: DepthProviderKind.ncnnRelative,
  pixelCount: 500,
);

GenericObstacleTrack _confirmedTrack() {
  final observation = _observation().copyWith(trackId: 3);
  return GenericObstacleTrack(
    id: 3,
    last: observation,
    hits: 3,
    misses: 0,
    age: 3,
    proximityHist: <double>[0.70, 0.82, 0.92],
    metricHist: <double?>[null, null, null],
    timestampUsHist: <int>[1, 2, 3],
    confirmed: true,
  );
}

GenericObstacleDetectResult _detection() => GenericObstacleDetectResult(
  observations: <GenericObstacleObservation>[_observation()],
  rejectReason: ObstacleRejectReason.none,
  detectorQuality: 0.95,
  groundConfidence: 0.85,
);

SpatialSafetyRuntime _runtime({int maxTraceEntries = 128}) {
  final runtime = SpatialSafetyRuntime(
    healthCoordinator: CoreHealthCoordinator(),
    maxTraceEntries: maxTraceEntries,
  );
  runtime.beginSession(7, now: DateTime.utc(2026, 9, 20, 10));
  return runtime;
}

void main() {
  group('SpatialSafetyRuntime', () {
    test('runs scene -> planner -> arbiter while forcing shadow delivery', () {
      final now = DateTime.utc(2026, 9, 20, 10, 0, 1);
      final runtime = _runtime();

      final result = runtime.ingestGenericGeometry(
        header: _header(now),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: now,
        orientationValid: true,
        userMoving: true,
        poseQuality: 0.95,
      );

      expect(result.accepted, isTrue);
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
      expect(result.arbiterEvent!.type, AlertArbiterEventType.suppressed);
      expect(result.arbiterEvent!.reason, 'shadow_action_not_deliverable');
      expect(runtime.arbiter.active, isNull);
      expect(result.snapshot.hazardTracks.single.id, 'geometry:3');
      expect(
        result.trace.toDiagnosticMap(),
        containsPair('plannedRuleId', 'SPATIAL-P0-IMMINENT'),
      );
    });

    test('rejects cross-session and repeated frames before scene mutation', () {
      final now = DateTime.utc(2026, 9, 20, 10, 0, 1);
      final runtime = _runtime();

      final wrongSession = runtime.ingestGenericGeometry(
        header: _header(now, session: 6),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: now,
        orientationValid: true,
        userMoving: false,
        poseQuality: 1,
      );
      expect(wrongSession.status, SpatialRuntimeIngestStatus.rejectedSession);

      final accepted = runtime.ingestGenericGeometry(
        header: _header(now),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: now,
        orientationValid: true,
        userMoving: false,
        poseQuality: 1,
      );
      final repeated = runtime.ingestGenericGeometry(
        header: _header(now),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: now,
        orientationValid: true,
        userMoving: false,
        poseQuality: 1,
      );

      expect(accepted.accepted, isTrue);
      expect(repeated.status, SpatialRuntimeIngestStatus.rejectedOutOfOrder);
      expect(repeated.snapshot.revision, accepted.snapshot.revision);
    });

    test('rejects an observation older than its runtime TTL', () {
      final now = DateTime.utc(2026, 9, 20, 10, 0, 2);
      final runtime = _runtime();

      final result = runtime.ingestGenericGeometry(
        header: _header(now, age: const Duration(seconds: 2)),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: now,
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
      );

      expect(result.status, SpatialRuntimeIngestStatus.rejectedStale);
      expect(result.decision, isNull);
      expect(runtime.arbiter.active, isNull);
    });

    test('provider loss becomes unknown scene and never a free corridor', () {
      final now = DateTime.utc(2026, 9, 20, 10, 0, 2);
      final runtime = _runtime();

      final result = runtime.noteMissingObservation(
        providerId: 'ncnn-depth',
        providerState: SceneSensorState.unavailable,
        reason: 'provider_unavailable',
        now: now,
        orientationValid: true,
        userMoving: true,
      );

      expect(result.accepted, isTrue);
      expect(result.snapshot.observedField.unknownFraction, 1);
      expect(result.snapshot.sensorHealth.hasUsableProvider, isFalse);
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      expect(result.submittedAction!.isShadowOnly, isTrue);
      expect(result.arbiterEvent!.type, AlertArbiterEventType.suppressed);
    });

    test('trace storage is bounded and contains rejection reasons', () {
      final runtime = _runtime(maxTraceEntries: 3);
      final start = DateTime.utc(2026, 9, 20, 10, 0, 2);

      for (var i = 0; i < 5; i++) {
        runtime.noteMissingObservation(
          providerId: 'ncnn-depth',
          providerState: SceneSensorState.degraded,
          reason: 'missing_$i',
          now: start.add(Duration(milliseconds: i)),
          orientationValid: false,
          userMoving: false,
        );
      }

      expect(runtime.traces, hasLength(3));
      expect(runtime.traces.map((trace) => trace.reason), <String>[
        'provider_loss:missing_2',
        'provider_loss:missing_3',
        'provider_loss:missing_4',
      ]);
    });

    test('new camera session clears planner and arbiter temporal state', () {
      final runtime = _runtime();
      final now = DateTime.utc(2026, 9, 20, 10, 0, 2);
      runtime.noteMissingObservation(
        providerId: 'ncnn-depth',
        providerState: SceneSensorState.unavailable,
        reason: 'provider_unavailable',
        now: now,
        orientationValid: true,
        userMoving: true,
      );

      runtime.beginSession(8, now: now.add(const Duration(seconds: 1)));

      expect(runtime.activeSessionGeneration, 8);
      expect(runtime.lastFrameId, 0);
      expect(runtime.planner.state.name, 'observing');
      expect(runtime.arbiter.bufferedCount, 0);
      expect(runtime.traces.single.reason, 'session_started');
    });

    test('decision clock expires a silent provider to unknown and stop', () {
      final runtime = _runtime();
      final observedAt = DateTime.utc(2026, 9, 20, 10, 0, 1);
      runtime.ingestGenericGeometry(
        header: _header(observedAt),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: observedAt,
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
      );

      final expired = runtime.tick(
        now: observedAt.add(const Duration(seconds: 1)),
        userMoving: true,
        orientationValid: true,
      );

      expect(expired.reason, 'expiry_tick');
      expect(expired.snapshot.observedField.unknownFraction, 1);
      expect(expired.snapshot.sensorHealth.hasUsableProvider, isFalse);
      expect(expired.decision!.action.kind, SafetyActionKind.stopNow);
    });

    test(
      'stationary user holds after expiry and duplicate ticks are bounded',
      () {
        final runtime = _runtime();
        final observedAt = DateTime.utc(2026, 9, 20, 10, 0, 1);
        runtime.ingestGenericGeometry(
          header: _header(observedAt),
          detection: _detection(),
          tracks: <GenericObstacleTrack>[_confirmedTrack()],
          now: observedAt,
          orientationValid: true,
          userMoving: false,
          poseQuality: 1,
        );

        final first = runtime.tick(
          now: observedAt.add(const Duration(seconds: 1)),
          userMoving: false,
          orientationValid: true,
        );
        final repeated = runtime.tick(
          now: observedAt.add(const Duration(milliseconds: 1300)),
          userMoving: false,
          orientationValid: true,
        );

        expect(first.decision!.action.kind, SafetyActionKind.holdAndScan);
        expect(first.submittedAction, isNotNull);
        expect(repeated.reason, 'provider_loss');
        expect(repeated.decision!.action.kind, SafetyActionKind.holdAndScan);
        expect(repeated.submittedAction, isNull);
        expect(repeated.trace.arbiterReason, 'tick_duplicate_action_cooldown');
      },
    );

    test('orientation invalidation is evaluated without a new observation', () {
      final runtime = _runtime();
      final observedAt = DateTime.utc(2026, 9, 20, 10, 0, 1);
      runtime.sceneModel.update(
        LocalSceneUpdate(
          coordinateMode: SceneCoordinateMode.relative,
          at: observedAt,
          validUntil: observedAt.add(const Duration(milliseconds: 900)),
          poseQuality: 1,
          sensorHealth: SceneSensorHealth(const <String, SceneSensorState>{
            'test': SceneSensorState.healthy,
          }),
          evidence: <SpatialEvidence>[
            for (final id in const <String>['left', 'forward', 'right'])
              SpatialEvidence(
                elementId: id,
                coordinateMode: SceneCoordinateMode.relative,
                sourceId: 'test-traversability',
                source: SpatialEvidenceSource.traversability,
                observedAt: observedAt,
                validUntil: observedAt.add(const Duration(milliseconds: 900)),
                observedFraction: 1,
                confidence: 1,
                occupancyProbability: 0,
                traversabilityProbability: 1,
                unknownProbability: 0,
              ),
          ],
        ),
      );

      final result = runtime.tick(
        now: observedAt.add(const Duration(milliseconds: 300)),
        userMoving: false,
        orientationValid: false,
      );

      expect(result.reason, 'tick_no_state_change');
      expect(result.decision!.action.kind, SafetyActionKind.holdAndScan);
    });

    test('fresh observation after provider loss is marked recovery', () {
      final runtime = _runtime();
      final start = DateTime.utc(2026, 9, 20, 10, 0, 1);
      runtime.noteMissingObservation(
        providerId: 'ncnn-depth',
        providerState: SceneSensorState.unavailable,
        reason: 'thermal_throttling',
        now: start,
        orientationValid: true,
        userMoving: true,
      );

      final recoveredAt = start.add(const Duration(milliseconds: 300));
      final result = runtime.ingestGenericGeometry(
        header: _header(recoveredAt, frame: 2),
        detection: _detection(),
        tracks: <GenericObstacleTrack>[_confirmedTrack()],
        now: recoveredAt,
        orientationValid: true,
        userMoving: false,
        poseQuality: 1,
      );

      expect(result.reason, 'recovery');
    });

    test('stopping a session rejects ticks and clears owned state', () {
      final runtime = _runtime();
      final now = DateTime.utc(2026, 9, 20, 10, 0, 2);
      runtime.endSession(now: now);

      expect(runtime.activeSessionGeneration, -1);
      expect(runtime.arbiter.bufferedCount, 0);
      expect(
        () => runtime.tick(
          now: now.add(const Duration(milliseconds: 250)),
          userMoving: false,
          orientationValid: true,
        ),
        throwsStateError,
      );
    });
  });
}
