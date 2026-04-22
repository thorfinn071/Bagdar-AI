import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';







void main() {
  const size = GroundPlaneAnalyzer.kMapSize;
  const bottomStart = GroundPlaneAnalyzer.kFootZoneStartRow;

  
  
  
  Float32List makeScene({
    double topZ = 0.30,
    double bottomZ = 0.40,
  }) {
    final map = Float32List(size * size);
    for (int y = 0; y < size; y++) {
      final z = y >= bottomStart ? bottomZ : topZ;
      for (int x = 0; x < size; x++) {
        map[y * size + x] = z;
      }
    }
    return map;
  }

  group('GroundPlaneAnalyzer.debugDetectNearFieldIntrusion', () {
    test(
      'during warm-up (first _kNearFieldBaselineMin frames) no hazard '
      'is emitted even if the band is occupied',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final scene = makeScene(bottomZ: 0.80);
        for (int i = 0; i < 4; i++) {
          expect(
            analyzer.debugDetectNearFieldIntrusion(
              scene,
              userStationary: false,
            ),
            isNull,
            reason: 'warm-up frame $i should not emit',
          );
        }
      },
    );

    test(
      'stable scene past warm-up never emits — baseline tracks current '
      'depth so delta stays near zero',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final scene = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 12; i++) {
          expect(
            analyzer.debugDetectNearFieldIntrusion(
              scene,
              userStationary: false,
            ),
            isNull,
            reason: 'stable frame $i should not emit',
          );
        }
      },
    );

    test(
      'sudden intrusion after stable baseline fires hazard only after '
      '_kNearFieldConfirmFrames consecutive drifting frames',
      () {
        final analyzer = GroundPlaneAnalyzer();
        
        final calm = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        
        
        final intrusion = makeScene(bottomZ: 0.70);
        final firstSpike = analyzer.debugDetectNearFieldIntrusion(
          intrusion,
          userStationary: false,
        );
        expect(firstSpike, isNull);

        
        final secondSpike = analyzer.debugDetectNearFieldIntrusion(
          intrusion,
          userStationary: false,
        );
        expect(secondSpike, isNotNull);
        expect(secondSpike!.type, DepthHazardType.nearFieldIntrusion);
        expect(secondSpike.zone, HazardZone.center);
        
        expect(secondSpike.midasScore, lessThanOrEqualTo(0.85));
        
        expect(secondSpike.coverage, greaterThan(0.0));
        expect(secondSpike.coverage, lessThanOrEqualTo(1.0));
      },
    );

    test(
      'stationary user never gets an intrusion hazard even when the '
      'band would otherwise trigger — motion gate short-circuits',
      () {
        final analyzer = GroundPlaneAnalyzer();
        
        final calm = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        final intrusion = makeScene(bottomZ: 0.80);
        for (int i = 0; i < 4; i++) {
          expect(
            analyzer.debugDetectNearFieldIntrusion(
              intrusion,
              userStationary: true,
            ),
            isNull,
            reason: 'stationary frame $i should never emit',
          );
        }
      },
    );

    test(
      'streak resets when the intrusion clears — baseline resumes '
      'tracking and a later intrusion must re-confirm',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final calm = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        
        expect(
          analyzer.debugDetectNearFieldIntrusion(
            makeScene(bottomZ: 0.70),
            userStationary: false,
          ),
          isNull,
        );

        
        expect(
          analyzer.debugDetectNearFieldIntrusion(
            calm,
            userStationary: false,
          ),
          isNull,
        );

        
        expect(
          analyzer.debugDetectNearFieldIntrusion(
            makeScene(bottomZ: 0.70),
            userStationary: false,
          ),
          isNull,
        );
      },
    );

    test(
      'resetTemporalFilter dumps the baseline buffer — the next '
      'intrusion frame re-enters warm-up rather than firing immediately',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final calm = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        analyzer.resetTemporalFilter();

        
        
        
        final afterReset = analyzer.debugDetectNearFieldIntrusion(
          makeScene(bottomZ: 0.70),
          userStationary: false,
        );
        expect(afterReset, isNull);
      },
    );

    test(
      'slow drift below the jump threshold never triggers — the median '
      'baseline tracks gradual scene changes',
      () {
        final analyzer = GroundPlaneAnalyzer();
        
        
        
        
        for (int i = 0; i < 15; i++) {
          final z = 0.40 + 0.01 * i;
          expect(
            analyzer.debugDetectNearFieldIntrusion(
              makeScene(bottomZ: z),
              userStationary: false,
            ),
            isNull,
            reason: 'gentle drift frame $i (z=$z) should not emit',
          );
        }
      },
    );

    test(
      'mostly-invalid depth map (z ≤ 0.05 everywhere) returns null '
      'without corrupting the baseline',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final calm = makeScene(bottomZ: 0.40);
        for (int i = 0; i < 6; i++) {
          analyzer.debugDetectNearFieldIntrusion(calm, userStationary: false);
        }

        
        
        final blank = Float32List(size * size);
        expect(
          analyzer.debugDetectNearFieldIntrusion(
            blank,
            userStationary: false,
          ),
          isNull,
        );

        
        
        
        final intrusion = makeScene(bottomZ: 0.70);
        expect(
          analyzer.debugDetectNearFieldIntrusion(
            intrusion,
            userStationary: false,
          ),
          isNull,
        );
        final confirmed = analyzer.debugDetectNearFieldIntrusion(
          intrusion,
          userStationary: false,
        );
        expect(confirmed, isNotNull);
        expect(confirmed!.type, DepthHazardType.nearFieldIntrusion);
      },
    );
  });
}
