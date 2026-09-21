import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/safety/world/local_scene_snapshot.dart';

SceneSpatialElement _element(String id, DateTime at) => SceneSpatialElement(
  id: id,
  occupancyProbability: 0.2,
  traversabilityProbability: 0.7,
  dropProbability: 0.1,
  unknownProbability: 0.15,
  confidence: 0.8,
  sourceMask: <String>{'depth'},
  lastObservedAt: at,
);

void main() {
  test('metric and relative scene representations cannot be mixed', () {
    final at = DateTime.utc(2026, 9, 19);
    expect(
      () => LocalSceneSnapshot(
        revision: 1,
        at: at,
        validUntil: at.add(const Duration(milliseconds: 500)),
        coordinateMode: SceneCoordinateMode.metric,
        spatialReferenceId: 'metric-test-v1',
        poseQuality: 0.8,
        observedField: const ObservedFieldSnapshot(
          observedFraction: 0.8,
          unknownFraction: 0.2,
        ),
        metricCells: <SceneSpatialElement>[_element('cell-1', at)],
        polarSectors: <SceneSpatialElement>[_element('sector-1', at)],
        hazardTracks: const <HazardTrackSnapshot>[],
        movingThreats: const <MovingThreatSnapshot>[],
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          'depth': SceneSensorState.healthy,
        }),
      ),
      throwsAssertionError,
    );
  });

  test('scene collections and source masks are immutable', () {
    final at = DateTime.utc(2026, 9, 19);
    final sources = <String>{'depth'};
    final sectors = <SceneSpatialElement>[_element('forward', at)];
    final snapshot = LocalSceneSnapshot(
      revision: 2,
      at: at,
      validUntil: at.add(const Duration(milliseconds: 500)),
      coordinateMode: SceneCoordinateMode.relative,
      spatialReferenceId: 'relative-test-v1',
      poseQuality: 0.5,
      observedField: const ObservedFieldSnapshot(
        observedFraction: 0.7,
        unknownFraction: 0.3,
      ),
      metricCells: const <SceneSpatialElement>[],
      polarSectors: sectors,
      hazardTracks: const <HazardTrackSnapshot>[],
      movingThreats: const <MovingThreatSnapshot>[],
      sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
        'depth': SceneSensorState.degraded,
      }),
    );
    final element = SceneSpatialElement(
      id: 'left',
      occupancyProbability: 0.2,
      traversabilityProbability: 0.7,
      dropProbability: 0.1,
      unknownProbability: 0.15,
      confidence: 0.8,
      sourceMask: sources,
      lastObservedAt: at,
    );
    sources.add('semantic');
    sectors.add(element);

    expect(snapshot.polarSectors, hasLength(1));
    expect(element.sourceMask, <String>{'depth'});
    expect(snapshot.toDiagnosticMap().keys, isNot(contains('coordinates')));
  });
}
