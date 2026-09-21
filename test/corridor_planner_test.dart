import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/corridor_generator.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';

RelativePolarSector _sector(
  DateTime at, {
  double observed = 0.95,
  double occupancy = 0.05,
  double traversability = 0.90,
  double drop = 0.02,
  double movingThreat = 0.02,
  double unknown = 0.05,
  double confidence = 0.90,
  Set<String> sourceMask = const <String>{'geometry', 'depth'},
}) => RelativePolarSector(
  observedFraction: observed,
  occupancyProbability: occupancy,
  traversabilityProbability: traversability,
  dropProbability: drop,
  movingThreatRisk: movingThreat,
  unknownProbability: unknown,
  confidence: confidence,
  sourceMask: sourceMask,
  hazardIds: const <String>[],
  lastObservedAt: at,
);

RelativePolarGrid _grid(
  DateTime at, {
  RelativePolarSector? left,
  RelativePolarSector? forward,
  RelativePolarSector? right,
  bool orientationValid = true,
  bool sensingHealthy = true,
  DateTime? validUntil,
}) => RelativePolarGrid(
  revision: 1,
  at: at,
  validUntil: validUntil ?? at.add(const Duration(seconds: 1)),
  orientationValid: orientationValid,
  sensingHealthy: sensingHealthy,
  userMoving: false,
  sectors: <RelativeSectorDirection, RelativePolarSector>{
    RelativeSectorDirection.left: left ?? _sector(at),
    RelativeSectorDirection.forward: forward ?? _sector(at),
    RelativeSectorDirection.right: right ?? _sector(at),
  },
);

void main() {
  group('CorridorGenerator', () {
    test('always emits the bounded left, forward, right candidate set', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final candidates = const CorridorGenerator().generate(
        _grid(now),
        now: now,
      );

      expect(candidates, hasLength(3));
      expect(candidates.map((candidate) => candidate.direction), [
        CorridorDirection.left,
        CorridorDirection.forward,
        CorridorDirection.right,
      ]);
      expect(
        candidates.every((candidate) => candidate.hasPositiveEvidence),
        isTrue,
      );
      expect(
        candidates
            .singleWhere(
              (candidate) => candidate.direction == CorridorDirection.forward,
            )
            .softCost,
        lessThan(
          candidates
              .singleWhere(
                (candidate) => candidate.direction == CorridorDirection.left,
              )
              .softCost,
        ),
      );
    });

    test('hard reject cannot be compensated by favourable soft evidence', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final candidates = const CorridorGenerator().generate(
        _grid(
          now,
          forward: _sector(
            now,
            occupancy: 0.90,
            traversability: 1,
            unknown: 0,
            confidence: 1,
          ),
        ),
        now: now,
      );
      final forward = candidates.singleWhere(
        (candidate) => candidate.direction == CorridorDirection.forward,
      );

      expect(forward.isHardRejected, isTrue);
      expect(
        forward.rejectionReasons,
        contains(CorridorRejectionReason.confirmedObstacle),
      );
      expect(forward.hasPositiveEvidence, isFalse);
      expect(
        forward.softCosts.keys,
        contains(CorridorSoftCostKind.lowClearance),
      );
    });

    test(
      'unknown, stale, invalid orientation and unhealthy sensing reject',
      () {
        final now = DateTime.utc(2026, 9, 20, 10);
        final candidates = const CorridorGenerator().generate(
          _grid(
            now.subtract(const Duration(seconds: 2)),
            forward: _sector(
              now,
              observed: 0.30,
              traversability: 0.10,
              unknown: 0.90,
              confidence: 0.20,
            ),
            orientationValid: false,
            sensingHealthy: false,
            validUntil: now.subtract(const Duration(milliseconds: 1)),
          ),
          now: now,
        );
        final forward = candidates.singleWhere(
          (candidate) => candidate.direction == CorridorDirection.forward,
        );

        expect(
          forward.rejectionReasons,
          containsAll(<CorridorRejectionReason>[
            CorridorRejectionReason.staleScene,
            CorridorRejectionReason.invalidOrientation,
            CorridorRejectionReason.unhealthySensing,
            CorridorRejectionReason.insufficientObservedWidth,
            CorridorRejectionReason.unknownArea,
            CorridorRejectionReason.surfaceNotContinuous,
          ]),
        );
        expect(forward.hasPositiveEvidence, isFalse);
      },
    );

    test(
      'positive evidence requires an attributable source and confidence',
      () {
        final now = DateTime.utc(2026, 9, 20, 10);
        final candidates = const CorridorGenerator().generate(
          _grid(
            now,
            left: _sector(now, sourceMask: const <String>{}),
            right: _sector(now, confidence: 0.40),
          ),
          now: now,
        );

        expect(
          candidates
              .singleWhere(
                (candidate) => candidate.direction == CorridorDirection.left,
              )
              .hasPositiveEvidence,
          isFalse,
        );
        expect(
          candidates
              .singleWhere(
                (candidate) => candidate.direction == CorridorDirection.right,
              )
              .hasPositiveEvidence,
          isFalse,
        );
      },
    );

    test('moving threat intersection is a non-compensable hard reject', () {
      final now = DateTime.utc(2026, 9, 20, 10);
      final forward = const CorridorGenerator()
          .generate(
            _grid(now, forward: _sector(now, movingThreat: 0.80)),
            now: now,
          )
          .singleWhere(
            (candidate) => candidate.direction == CorridorDirection.forward,
          );

      expect(
        forward.rejectionReasons,
        contains(CorridorRejectionReason.movingThreatIntersection),
      );
      expect(forward.hasPositiveEvidence, isFalse);
    });
  });
}
