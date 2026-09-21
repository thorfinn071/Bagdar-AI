import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

GenericObstacleObservation _obs({
  required double nx,
  required double proximity,
  ObstacleGeometry geom = ObstacleGeometry.broadSurface,
}) => GenericObstacleObservation(
  geometry: geom,
  zone: HazardZone.center,
  normalizedBounds: Rect.fromLTWH(nx - 0.1, 0.3, 0.2, 0.4),
  corridorOverlap: 0.5,
  confidence: 0.8,
  relativeProximity: proximity,
  source: DepthProviderKind.ncnnRelative,
  pixelCount: 80,
);

void main() {
  test('N-of-M confirmation and stable IDs', () {
    final t = GenericObstacleTracker();
    var id1 = 0;
    for (int i = 0; i < 3; i++) {
      final tracks = t.update(
        observations: [_obs(nx: 0.5, proximity: 0.7 + i * 0.02)],
        timestampUs: i * 800000,
        relative: true,
      );
      id1 = tracks.single.id;
    }
    expect(t.tracks.single.confirmed, isTrue);
    expect(t.tracks.single.id, id1);
  });

  test('new hazard gets a new id (cooldown independence)', () {
    final t = GenericObstacleTracker();
    t.update(
      observations: [_obs(nx: 0.3, proximity: 0.8)],
      timestampUs: 0,
      relative: true,
    );
    t.update(
      observations: [
        _obs(nx: 0.3, proximity: 0.8),
        _obs(nx: 0.8, proximity: 0.85),
      ],
      timestampUs: 800000,
      relative: true,
    );
    expect(t.tracks.length, 2);
    expect(t.tracks.map((e) => e.id).toSet().length, 2);
  });

  test('short miss does not immediately expire; long miss does', () {
    final t = GenericObstacleTracker();
    t.update(
      observations: [_obs(nx: 0.5, proximity: 0.8)],
      timestampUs: 0,
      relative: true,
    );
    t.update(observations: const [], timestampUs: 800000, relative: true);
    expect(t.tracks, isNotEmpty);
    t.update(observations: const [], timestampUs: 1600000, relative: true);
    t.update(observations: const [], timestampUs: 2400000, relative: true);
    expect(t.tracks, isEmpty);
  });

  test('approach trend is positive when proximity increases', () {
    final t = GenericObstacleTracker();
    t.update(
      observations: [_obs(nx: 0.5, proximity: 0.5)],
      timestampUs: 0,
      relative: true,
    );
    t.update(
      observations: [_obs(nx: 0.5, proximity: 0.7)],
      timestampUs: 800000,
      relative: true,
    );
    expect(t.tracks.single.approachTrend(), greaterThan(0));
  });

  test('lifetime hits outside the rolling N-of-M window do not confirm', () {
    final t = GenericObstacleTracker();
    var ts = 0;
    for (final hasObservation in <bool>[
      true,
      false,
      false,
      true,
      false,
      false,
      true,
    ]) {
      t.update(
        observations: hasObservation
            ? <GenericObstacleObservation>[_obs(nx: 0.5, proximity: 0.8)]
            : const <GenericObstacleObservation>[],
        timestampUs: ts,
        relative: true,
      );
      ts += 100000;
    }
    expect(t.tracks.where((track) => track.confirmed), isEmpty);
  });

  test('zero-IoU replacement in the same coarse zone gets a new id', () {
    final t = GenericObstacleTracker();
    final first = t
        .update(
          observations: <GenericObstacleObservation>[
            _obs(nx: 0.25, proximity: 0.8),
          ],
          timestampUs: 0,
          relative: true,
        )
        .single
        .id;
    final tracks = t.update(
      observations: <GenericObstacleObservation>[
        _obs(nx: 0.75, proximity: 0.82),
      ],
      timestampUs: 100000,
      relative: true,
    );
    expect(tracks, hasLength(2));
    expect(
      tracks.any((track) => track.id != first && track.misses == 0),
      isTrue,
    );
  });
}
