import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

final _start = DateTime.utc(2026, 10, 4);
SpatialSafetyRuntime _runtime() => ConfidenceAuthoritySpatialRuntime(
  healthCoordinator: CoreHealthCoordinator(),
)..beginSession(1, now: _start.subtract(const Duration(milliseconds: 1)));

GenericObstacleObservation _component({
  double confidence = .15,
  double proximity = .51,
}) => GenericObstacleObservation(
  geometry: ObstacleGeometry.broadSurface,
  zone: HazardZone.center,
  normalizedBounds: const Rect.fromLTRB(.29, .18, .71, .64),
  corridorOverlap: .55,
  confidence: confidence,
  relativeProximity: proximity,
  source: DepthProviderKind.ncnnRelative,
  pixelCount: 8196,
);

SpatialRuntimeResult _ingest(
  SpatialSafetyRuntime runtime,
  GenericObstacleTracker tracker,
  int index, {
  GenericObstacleObservation? component,
  bool moving = false,
  int session = 1,
  int ageMs = 2,
  ObstacleRejectReason reason = ObstacleRejectReason.none,
}) {
  final captured = _start.add(Duration(milliseconds: index * 200));
  final observations = component == null
      ? <GenericObstacleObservation>[]
      : [component];
  final tracks = tracker.update(
    observations: observations,
    timestampUs: captured.microsecondsSinceEpoch,
    relative: true,
  );
  return runtime.ingestGenericGeometry(
    header: ObservationHeader(
      providerId: 'authority-fixture',
      modelId: 'fixture',
      modelHash: 'fixture-hash',
      preprocessId: 'relative-fixture',
      sessionGeneration: session,
      frameId: index + 1,
      sourceTimestampUs: captured.microsecondsSinceEpoch,
      producedAtUs: captured.microsecondsSinceEpoch + 1000,
      transformId: 'fixture',
      confidence: 1,
      health: ObservationHealth.healthy,
    ),
    detection: GenericObstacleDetectResult(
      observations: observations,
      rejectReason: reason,
      detectorQuality: 1,
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
    ),
    tracks: tracks,
    now: captured.add(Duration(milliseconds: ageMs)),
    orientationValid: true,
    userMoving: moving,
    poseQuality: 1,
  );
}

void main() {
  for (final drop in [true, false]) {
    test(
      'independent ${drop ? 'drop' : 'moving threat'} retains emergency precedence',
      () {
        final sector = RelativePolarSector(
          observedFraction: .35,
          occupancyProbability: 0,
          traversabilityProbability: 0,
          dropProbability: drop ? .4 : 0,
          movingThreatRisk: drop ? 0 : .8,
          unknownProbability: .65,
          confidence: .95,
          sourceMask: {'independent-risk'},
          hazardIds: ['independent-risk'],
          lastObservedAt: _start,
        );
        final grid = RelativePolarGrid(
          revision: 1,
          at: _start,
          validUntil: _start.add(const Duration(milliseconds: 100)),
          orientationValid: true,
          sensingHealthy: true,
          userMoving: false,
          sectors: {
            for (final direction in RelativeSectorDirection.values)
              direction: sector,
          },
        );
        final decision = ConfidenceAuthorityGuidance().evaluate(
          grid,
          now: _start,
        );
        expect(decision.action.ruleId, 'SPATIAL-P0-IMMINENT');
        expect(decision.action.kind, SafetyActionKind.stopNow);
      },
    );
  }
  test(
    'first weak central hypothesis cannot grant movement over a perfect floor',
    () {
      final runtime = _runtime();
      final result = _ingest(
        runtime,
        GenericObstacleTracker(),
        0,
        component: _component(),
      );
      expect(result.decision!.action.kind, SafetyActionKind.stopNow);
      expect(
        result.decision!.action.ruleId,
        'SPATIAL-P1-UNVERIFIED-OBSTRUCTION',
      );
      final forward = result.snapshot.polarSectors.singleWhere(
        (s) => s.id == 'forward',
      );
      expect(forward.occupancyProbability, 0);
      expect(forward.unknownProbability, greaterThanOrEqualTo(.65));
      expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
      expect(runtime.arbiter.active, isNull);
    },
  );
  test(
    'confirmed rank-one weak component remains blocking without false imminent',
    () {
      final runtime = _runtime(), tracker = GenericObstacleTracker();
      late SpatialRuntimeResult result;
      for (var i = 0; i < 4; i++) {
        result = _ingest(
          runtime,
          tracker,
          i,
          component: _component(confidence: .53, proximity: 1),
          moving: true,
        );
        expect(result.decision!.action.kind, SafetyActionKind.stopNow);
        expect(result.decision!.action.ruleId, isNot('SPATIAL-P0-IMMINENT'));
      }
      expect(tracker.tracks.single.confirmed, true);
      expect(
        result.snapshot.hazardTracks
            .where((t) => t.id == 'geometry:1')
            .single
            .risk,
        .53,
      );
      expect(
        result.snapshot.polarSectors
            .singleWhere((s) => s.id == 'forward')
            .occupancyProbability,
        .53,
      );
    },
  );
  test('strong first-sighting obstacle keeps emergency precedence', () {
    final result = _ingest(
      _runtime(),
      GenericObstacleTracker(),
      0,
      component: _component(confidence: .95, proximity: 1),
    );
    expect(result.decision!.action.ruleId, 'SPATIAL-P0-IMMINENT');
    expect(result.decision!.action.kind, SafetyActionKind.stopNow);
  });
  test('missed strong component retains its previous emergency risk', () {
    final runtime = _runtime(), tracker = GenericObstacleTracker();
    _ingest(
      runtime,
      tracker,
      0,
      component: _component(confidence: .95, proximity: 1),
    );
    final result = _ingest(runtime, tracker, 1);
    expect(result.decision!.action.ruleId, 'SPATIAL-P0-IMMINENT');
  });
  test(
    'perfect floor and depth coverage without body proof only allow stationary scan',
    () {
      final result = _ingest(_runtime(), GenericObstacleTracker(), 0);
      expect(result.decision!.action.kind, SafetyActionKind.holdAndScan);
      expect(
        result.decision!.candidates
            .singleWhere((c) => c.direction.name == 'forward')
            .positiveEvidencePassed,
        false,
      );
    },
  );
  test('moving with a perfect floor and no body proof remains stopped', () {
    final result = _ingest(
      _runtime(),
      GenericObstacleTracker(),
      0,
      moving: true,
    );
    expect(result.decision!.action.kind, SafetyActionKind.stopNow);
  });
  test('missing depth cannot reuse perfect surface metadata', () {
    final result = _ingest(
      _runtime(),
      GenericObstacleTracker(),
      0,
      moving: true,
      reason: ObstacleRejectReason.noFrame,
    );
    expect(result.decision!.action.kind, SafetyActionKind.stopNow);
  });
  test('correction does not bypass stale or session admission', () {
    final runtime = _runtime();
    expect(
      _ingest(
        runtime,
        GenericObstacleTracker(),
        0,
        component: _component(),
        ageMs: 2000,
      ).status,
      SpatialRuntimeIngestStatus.rejectedStale,
    );
    expect(
      _ingest(
        runtime,
        GenericObstacleTracker(),
        1,
        component: _component(),
        session: 2,
      ).status,
      SpatialRuntimeIngestStatus.rejectedSession,
    );
    expect(
      _ingest(runtime, GenericObstacleTracker(), 2).decision!.action.kind,
      SafetyActionKind.holdAndScan,
    );
  });
  test('custom planner must use the same authority policy', () {
    expect(
      () => ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        planner: GuidanceStateMachine(),
      ),
      throwsArgumentError,
    );
  });
  test(
    'uncertain stop cannot release while moving or on duplicate positive revisions',
    () {
      RelativePolarGrid grid(
        int revision, {
        bool moving = false,
        bool hypothesis = false,
      }) {
        final sector = RelativePolarSector(
          observedFraction: hypothesis ? .35 : 1,
          occupancyProbability: 0,
          traversabilityProbability: 1,
          dropProbability: 0,
          movingThreatRisk: 0,
          unknownProbability: hypothesis ? .65 : 0,
          confidence: 1,
          sourceMask: {'independent-current-corridor'},
          hazardIds: hypothesis ? ['candidate'] : [],
          lastObservedAt: _start,
        );
        return RelativePolarGrid(
          revision: revision,
          at: _start,
          validUntil: _start.add(const Duration(milliseconds: 100)),
          orientationValid: true,
          sensingHealthy: true,
          userMoving: moving,
          sectors: {for (final d in RelativeSectorDirection.values) d: sector},
        );
      }

      final planner = ConfidenceAuthorityGuidance();
      expect(
        planner.evaluate(grid(1, hypothesis: true), now: _start).action.kind,
        SafetyActionKind.stopNow,
      );
      final movingStop = planner
          .evaluate(grid(2, moving: true), now: _start)
          .action;
      expect(movingStop.kind, SafetyActionKind.stopNow);
      expect(movingStop.priority, SafetyPriority.p0Emergency);
      expect(
        planner.evaluate(grid(3), now: _start).action.kind,
        SafetyActionKind.holdAndScan,
      );
      expect(
        planner.evaluate(grid(3), now: _start).action.kind,
        SafetyActionKind.holdAndScan,
      );
      expect(
        planner.evaluate(grid(4), now: _start).action.kind,
        SafetyActionKind.continueForward,
      );
    },
  );
}
