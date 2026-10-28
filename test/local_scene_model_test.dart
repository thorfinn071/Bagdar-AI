import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/world/generic_geometry_scene_adapter.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/metric_occupancy_grid.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

ObservationHeader _header() => const ObservationHeader(
  providerId: 'generic-depth',
  modelId: 'midas-control',
  modelHash: _hash,
  preprocessId: 'relative-v1',
  sessionGeneration: 1,
  frameId: 1,
  sourceTimestampUs: 0,
  producedAtUs: 10,
  transformId: 'upright-v1',
  confidence: 0.9,
  health: ObservationHealth.healthy,
);

GenericObstacleObservation _observation({SemanticMatch? semantic}) =>
    GenericObstacleObservation(
      trackId: 7,
      geometry: ObstacleGeometry.broadSurface,
      zone: HazardZone.center,
      normalizedBounds: const Rect.fromLTWH(0.4, 0.3, 0.2, 0.4),
      corridorOverlap: 0.8,
      confidence: 0.9,
      relativeProximity: 0.8,
      source: DepthProviderKind.ncnnRelative,
      semantic: semantic,
      pixelCount: 120,
    );

GenericObstacleTrack _track({
  bool confirmed = true,
  List<double> proximity = const <double>[0.4, 0.8],
  SemanticMatch? semantic,
}) => GenericObstacleTrack(
  id: 7,
  last: _observation(semantic: semantic),
  hits: proximity.length,
  misses: 0,
  age: proximity.length,
  proximityHist: List<double>.from(proximity),
  metricHist: List<double?>.filled(proximity.length, null),
  timestampUsHist: List<int>.generate(
    proximity.length,
    (index) => index * 100000,
  ),
  confirmed: confirmed,
  hitWindow: List<bool>.filled(proximity.length, true),
);

GenericObstacleDetectResult _detection() => GenericObstacleDetectResult(
  observations: <GenericObstacleObservation>[_observation()],
  rejectReason: ObstacleRejectReason.none,
  detectorQuality: 0.9,
  groundConfidence: 0.8,
);

void main() {
  test('unobserved relative sectors start unknown, never free', () {
    final at = DateTime.utc(2026, 9, 19);
    final snapshot = LocalSceneModel.relative().snapshotAt(at);

    expect(snapshot.polarSectors, hasLength(3));
    for (final sector in snapshot.polarSectors) {
      expect(sector.unknownProbability, 1);
      expect(sector.traversabilityProbability, 0);
      expect(sector.confidence, 0);
      expect(sector.sourceMask, isEmpty);
    }
  });

  test('generic geometry survives complete YOLO absence', () {
    final at = DateTime.utc(2026, 9, 19);
    final model = LocalSceneModel.relative();
    final result = model.ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[_track()],
      at: at,
      validUntil: at.add(const Duration(milliseconds: 900)),
      poseQuality: 0.9,
    );
    final forward = result.snapshot.polarSectors.singleWhere(
      (element) => element.id == 'forward',
    );

    expect(result.accepted, isTrue);
    expect(forward.occupancyProbability, greaterThanOrEqualTo(0.8));
    expect(forward.sourceMask, contains('geometry:generic-depth'));
    expect(
      forward.sourceMask.where((source) => source.startsWith('semantic:')),
      isEmpty,
    );
    expect(result.snapshot.hazardTracks.single.id, 'geometry:7');
  });

  test(
    'ground surface evidence raises traversability without hiding unknown',
    () {
      final at = DateTime.utc(2026, 9, 19);
      final result = LocalSceneModel.relative().ingestGenericGeometry(
        header: _header(),
        detection: const GenericObstacleDetectResult(
          observations: <GenericObstacleObservation>[],
          rejectReason: ObstacleRejectReason.emptyCorridor,
          detectorQuality: 0.5,
          groundConfidence: 0.8,
          surfaceEvidence: CorridorSurfaceEvidence(
            observedFraction: 0.75,
            continuity: 1,
            confidence: 0.8,
          ),
          unknownProbabilityFloor: 0.65,
        ),
        tracks: const <GenericObstacleTrack>[],
        at: at,
        validUntil: at.add(const Duration(milliseconds: 900)),
        poseQuality: 0.9,
      );
      final forward = result.snapshot.polarSectors.singleWhere(
        (element) => element.id == 'forward',
      );

      expect(forward.traversabilityProbability, 0.8);
      expect(forward.unknownProbability, 0.65);
      expect(forward.sourceMask, contains('surface:generic-depth'));
    },
  );

  test('approaching confirmed track populates moving-threat state', () {
    final at = DateTime.utc(2026, 9, 19);
    final result = LocalSceneModel.relative().ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[_track()],
      at: at,
      validUntil: at.add(const Duration(milliseconds: 900)),
      poseQuality: 0.9,
    );
    final forward = result.snapshot.polarSectors.singleWhere(
      (element) => element.id == 'forward',
    );

    expect(forward.movingThreatRisk, greaterThanOrEqualTo(0.5));
    expect(result.snapshot.movingThreats.single.elementId, 'forward');
  });

  test('only imminent central evidence bypasses N-of-M confirmation', () {
    final at = DateTime.utc(2026, 9, 19);
    final ordinary = _track(confirmed: false, proximity: const <double>[0.8]);
    final imminent = _track(confirmed: false, proximity: const <double>[0.9]);
    imminent.last = imminent.last.copyWith(relativeProximity: 0.9);

    final ordinaryResult = LocalSceneModel.relative().ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[ordinary],
      at: at,
      validUntil: at.add(const Duration(milliseconds: 900)),
      poseQuality: 0.9,
    );
    final imminentResult = LocalSceneModel.relative().ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[imminent],
      at: at,
      validUntil: at.add(const Duration(milliseconds: 900)),
      poseQuality: 0.9,
    );

    expect(ordinaryResult.snapshot.hazardTracks, isEmpty);
    expect(imminentResult.snapshot.hazardTracks.single.id, 'geometry:7');
  });

  test('close central hazard survives first-frame track confirmation', () {
    final at = DateTime.utc(2026, 9, 23);
    final close = _track(confirmed: false, proximity: const <double>[0.99]);
    close.last = close.last.copyWith(relativeProximity: 0.99, confidence: 0.60);
    final weak = _track(confirmed: false, proximity: const <double>[0.99]);
    weak.last = weak.last.copyWith(relativeProximity: 0.99, confidence: 0.54);

    LocalSceneUpdateResult ingest(GenericObstacleTrack track) =>
        LocalSceneModel.relative().ingestGenericGeometry(
          header: _header(),
          detection: _detection(),
          tracks: <GenericObstacleTrack>[track],
          at: at,
          validUntil: at.add(const Duration(milliseconds: 900)),
          poseQuality: 0.9,
        );

    final admitted = ingest(close);
    final excluded = ingest(weak);
    expect(admitted.snapshot.hazardTracks, hasLength(1));
    expect(
      admitted.snapshot.polarSectors
          .singleWhere((sector) => sector.id == 'forward')
          .occupancyProbability,
      greaterThanOrEqualTo(0.95),
    );
    expect(excluded.snapshot.hazardTracks, isEmpty);
    expect(
      excluded.snapshot.polarSectors
          .singleWhere((sector) => sector.id == 'forward')
          .unknownProbability,
      0.65,
    );
  });

  test('unconfirmed close central evidence cannot make forward look clear', () {
    final at = DateTime.utc(2026, 9, 23);

    LocalSceneUpdateResult ingest({
      required double confidence,
      required double proximity,
      required double overlap,
      required HazardZone zone,
      int misses = 0,
    }) {
      final track = _track(confirmed: false, proximity: <double>[proximity]);
      track.last = GenericObstacleObservation(
        trackId: track.id,
        geometry: ObstacleGeometry.broadSurface,
        zone: zone,
        normalizedBounds: const Rect.fromLTWH(0.3, 0.1, 0.4, 0.8),
        corridorOverlap: overlap,
        confidence: confidence,
        relativeProximity: proximity,
        source: DepthProviderKind.ncnnRelative,
        pixelCount: 9000,
      );
      track.misses = misses;
      return LocalSceneModel.relative().ingestGenericGeometry(
        header: _header(),
        detection: const GenericObstacleDetectResult(
          observations: <GenericObstacleObservation>[],
          rejectReason: ObstacleRejectReason.none,
          detectorQuality: 0.98,
          groundConfidence: 0.95,
          surfaceEvidence: CorridorSurfaceEvidence(
            observedFraction: 1,
            continuity: 0.9,
            confidence: 0.95,
          ),
        ),
        tracks: <GenericObstacleTrack>[track],
        at: at,
        validUntil: at.add(const Duration(milliseconds: 900)),
        poseQuality: 1,
      );
    }

    double forwardUnknown(LocalSceneUpdateResult result) => result
        .snapshot
        .polarSectors
        .singleWhere((sector) => sector.id == 'forward')
        .unknownProbability;

    for (final confidence in <double>[0.30, 0.54]) {
      final unresolved = ingest(
        confidence: confidence,
        proximity: 1,
        overlap: 0.95,
        zone: HazardZone.center,
      );
      expect(unresolved.accepted, isTrue);
      expect(unresolved.snapshot.hazardTracks, isEmpty);
      expect(forwardUnknown(unresolved), 0.65);
      expect(
        unresolved.snapshot.polarSectors
            .singleWhere((sector) => sector.id == 'forward')
            .occupancyProbability,
        0,
      );
    }

    for (final negative
        in <
          ({
            double confidence,
            double proximity,
            double overlap,
            HazardZone zone,
            int misses,
          })
        >[
          (
            confidence: 0.20,
            proximity: 1,
            overlap: 0.95,
            zone: HazardZone.center,
            misses: 0,
          ),
          (
            confidence: 0.40,
            proximity: 0.8,
            overlap: 0.95,
            zone: HazardZone.center,
            misses: 0,
          ),
          (
            confidence: 0.40,
            proximity: 1,
            overlap: 0.2,
            zone: HazardZone.center,
            misses: 0,
          ),
          (
            confidence: 0.40,
            proximity: 1,
            overlap: 0.95,
            zone: HazardZone.right,
            misses: 0,
          ),
          (
            confidence: 0.40,
            proximity: 1,
            overlap: 0.95,
            zone: HazardZone.center,
            misses: 1,
          ),
        ]) {
      final result = ingest(
        confidence: negative.confidence,
        proximity: negative.proximity,
        overlap: negative.overlap,
        zone: negative.zone,
        misses: negative.misses,
      );
      expect(forwardUnknown(result), closeTo(0.02, 1e-9));
    }
  });

  test('stale cells lose authority and become unknown', () {
    final at = DateTime.utc(2026, 9, 19);
    final model = LocalSceneModel.relative();
    model.ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[_track()],
      at: at,
      validUntil: at.add(const Duration(milliseconds: 900)),
      poseQuality: 0.9,
    );
    final stale = model.snapshotAt(at.add(const Duration(seconds: 3)));
    final forward = stale.polarSectors.singleWhere(
      (element) => element.id == 'forward',
    );

    expect(forward.occupancyProbability, 0);
    expect(forward.traversabilityProbability, 0);
    expect(forward.unknownProbability, 1);
    expect(forward.sourceMask, isEmpty);
    expect(
      stale.sensorHealth.providers['generic-depth'],
      SceneSensorState.stale,
    );
  });

  test('out-of-order update cannot mutate current scene revision', () {
    final at = DateTime.utc(2026, 9, 19, 12);
    final model = LocalSceneModel.relative();
    final first = model.ingestGenericGeometry(
      header: _header(),
      detection: _detection(),
      tracks: <GenericObstacleTrack>[_track()],
      at: at,
      validUntil: at.add(const Duration(seconds: 1)),
      poseQuality: 0.9,
    );
    final revision = first.snapshot.revision;
    final late = model.update(
      LocalSceneUpdate(
        coordinateMode: SceneCoordinateMode.relative,
        at: at.subtract(const Duration(milliseconds: 1)),
        validUntil: at.add(const Duration(seconds: 1)),
        poseQuality: 0.9,
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          'depth': SceneSensorState.healthy,
        }),
        evidence: const <SpatialEvidence>[],
      ),
    );

    expect(late.status, LocalSceneUpdateStatus.rejectedOutOfOrder);
    expect(late.snapshot.revision, revision);
    expect(model.revision, revision);
  });

  test('metric mode requires calibrated cell IDs and never mixes modes', () {
    final at = DateTime.utc(2026, 9, 19);
    const calibration = MetricGridCalibration(
      calibrationId: 'reference-phone-lab-v1',
      lateralCellCount: 3,
      forwardCellCount: 4,
      cellSizeMeters: 0.25,
    );
    final model = LocalSceneModel.metric(calibration: calibration);
    final invalid = model.update(
      LocalSceneUpdate(
        coordinateMode: SceneCoordinateMode.metric,
        at: at,
        validUntil: at.add(const Duration(seconds: 1)),
        poseQuality: 0.9,
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          'metric-depth': SceneSensorState.healthy,
        }),
        evidence: <SpatialEvidence>[
          SpatialEvidence(
            elementId: 'forward',
            coordinateMode: SceneCoordinateMode.metric,
            sourceId: 'metric-depth',
            source: SpatialEvidenceSource.depth,
            observedAt: at,
            validUntil: at.add(const Duration(seconds: 1)),
            observedFraction: 1,
            confidence: 0.9,
            occupancyProbability: 0.8,
          ),
        ],
      ),
    );
    final accepted = model.update(
      LocalSceneUpdate(
        coordinateMode: SceneCoordinateMode.metric,
        at: at,
        validUntil: at.add(const Duration(seconds: 1)),
        poseQuality: 0.9,
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          'metric-depth': SceneSensorState.healthy,
        }),
        evidence: <SpatialEvidence>[
          SpatialEvidence(
            elementId: const MetricCellIndex(lateral: 1, forward: 2).elementId,
            coordinateMode: SceneCoordinateMode.metric,
            sourceId: 'metric-depth',
            source: SpatialEvidenceSource.depth,
            observedAt: at,
            validUntil: at.add(const Duration(seconds: 1)),
            observedFraction: 1,
            confidence: 0.9,
            occupancyProbability: 0.8,
          ),
        ],
      ),
    );

    expect(invalid.status, LocalSceneUpdateStatus.rejectedMetricCalibration);
    expect(accepted.accepted, isTrue);
    expect(accepted.snapshot.metricCells, hasLength(1));
    expect(accepted.snapshot.polarSectors, isEmpty);
    expect(
      () => RelativePolarGrid.fromSnapshot(
        accepted.snapshot,
        orientationValid: true,
        userMoving: false,
      ),
      throwsArgumentError,
    );
  });

  test('identical evidence produces deterministic snapshot diagnostics', () {
    final at = DateTime.utc(2026, 9, 19);
    LocalSceneSnapshot run() {
      final model = LocalSceneModel.relative();
      return model
          .ingestGenericGeometry(
            header: _header(),
            detection: _detection(),
            tracks: <GenericObstacleTrack>[_track()],
            at: at,
            validUntil: at.add(const Duration(milliseconds: 900)),
            poseQuality: 0.9,
          )
          .snapshot;
    }

    final first = run();
    final second = run();
    expect(second.toDiagnosticMap(), first.toDiagnosticMap());
    expect(
      second.polarSectors.map((element) => element.toDiagnosticMap()),
      first.polarSectors.map((element) => element.toDiagnosticMap()),
    );
  });
}
