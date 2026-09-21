import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';

SpatialEvidence _evidence({
  required DateTime at,
  required String sourceId,
  SpatialEvidenceSource source = SpatialEvidenceSource.geometry,
  double observed = 0.9,
  double confidence = 0.9,
  double? occupancy,
  double? traversability,
  double? drop,
  double? unknown,
  Duration ttl = const Duration(seconds: 1),
}) => SpatialEvidence(
  elementId: 'forward',
  coordinateMode: SceneCoordinateMode.relative,
  sourceId: sourceId,
  source: source,
  observedAt: at,
  validUntil: at.add(ttl),
  observedFraction: observed,
  confidence: confidence,
  occupancyProbability: occupancy,
  traversabilityProbability: traversability,
  dropProbability: drop,
  unknownProbability: unknown,
);

void main() {
  const policy = SceneFusionPolicy();

  test('low-risk semantic evidence cannot cancel geometry threat', () {
    final at = DateTime.utc(2026, 9, 19);
    final geometry = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: null,
      evidence: <SpatialEvidence>[
        _evidence(at: at, sourceId: 'geometry', occupancy: 0.9),
      ],
      now: at,
    );
    final fused = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: geometry,
      evidence: <SpatialEvidence>[
        _evidence(
          at: at.add(const Duration(milliseconds: 100)),
          sourceId: 'semantic:yolo',
          source: SpatialEvidenceSource.semantic,
          occupancy: 0.05,
          confidence: 0.99,
        ),
      ],
      now: at.add(const Duration(milliseconds: 100)),
    )!;

    expect(fused.element.occupancyProbability, 0.9);
    expect(
      fused.element.sourceMask,
      containsAll(<String>['geometry', 'semantic:yolo']),
    );
  });

  test('reliable source conflict raises unknown instead of averaging', () {
    final at = DateTime.utc(2026, 9, 19);
    final fused = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: null,
      evidence: <SpatialEvidence>[
        _evidence(at: at, sourceId: 'geometry', occupancy: 0.9),
        _evidence(
          at: at,
          sourceId: 'traversability',
          source: SpatialEvidenceSource.traversability,
          occupancy: 0.1,
          traversability: 0.95,
        ),
      ],
      now: at,
    )!;

    expect(fused.element.occupancyProbability, 0.9);
    expect(fused.element.unknownProbability, greaterThanOrEqualTo(0.65));
  });

  test('independent confirmations boost confidence and retain sources', () {
    final at = DateTime.utc(2026, 9, 19);
    final fused = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: null,
      evidence: <SpatialEvidence>[
        _evidence(
          at: at,
          sourceId: 'geometry',
          occupancy: 0.8,
          confidence: 0.7,
        ),
        _evidence(
          at: at,
          sourceId: 'depth',
          source: SpatialEvidenceSource.depth,
          occupancy: 0.75,
          confidence: 0.7,
        ),
      ],
      now: at,
    )!;

    expect(fused.element.confidence, closeTo(0.78, 1e-9));
    expect(fused.element.sourceMask, <String>{'geometry', 'depth'});
  });

  test('stale source is ignored and cannot create an empty free cell', () {
    final at = DateTime.utc(2026, 9, 19);
    final fused = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: null,
      evidence: <SpatialEvidence>[
        _evidence(
          at: at,
          sourceId: 'depth',
          occupancy: 0,
          traversability: 1,
          ttl: const Duration(milliseconds: 100),
        ),
      ],
      now: at.add(const Duration(milliseconds: 101)),
    );

    expect(fused, isNull);
  });

  test('time decay removes free authority and grows unknown', () {
    final at = DateTime.utc(2026, 9, 19);
    final fresh = policy.fuse(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      previous: null,
      evidence: <SpatialEvidence>[
        _evidence(
          at: at,
          sourceId: 'traversability',
          source: SpatialEvidenceSource.traversability,
          traversability: 0.95,
          unknown: 0.05,
        ),
      ],
      now: at,
    )!;
    final decayed = policy.decay(
      fresh,
      at.add(const Duration(milliseconds: 1400)),
    )!;
    final expired = policy.decay(fresh, at.add(const Duration(seconds: 3)));

    expect(
      decayed.element.traversabilityProbability,
      lessThan(fresh.element.traversabilityProbability),
    );
    expect(
      decayed.element.unknownProbability,
      greaterThan(fresh.element.unknownProbability),
    );
    expect(expired, isNull);
  });
}
