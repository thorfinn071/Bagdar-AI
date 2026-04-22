import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';






void main() {
  const size = GroundPlaneAnalyzer.kMapSize;

  
  
  
  
  
  Float32List makeStaircase({
    double baseZ = 0.4,
    double treadStep = 0.08,
    int treadHeight = 20,
    int rowShift = 0,
  }) {
    final map = Float32List(size * size);
    for (int y = 0; y < size; y++) {
      final treadIndex = ((y + rowShift) / treadHeight).floor();
      final z = baseZ + treadIndex * treadStep;
      for (int x = 0; x < size; x++) {
        map[y * size + x] = z;
      }
    }
    return map;
  }

  group('GroundPlaneAnalyzer.debugDetectStairsDown', () {
    test(
      'walking user on a staircase always sees the stairsDown critical',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final frame = makeStaircase();
        final hazard = analyzer.debugDetectStairsDown(
          frame,
          userStationary: false,
        );
        expect(hazard, isNotNull);
        expect(hazard!.type, DepthHazardType.stairsDown);
      },
    );

    test(
      'stationary user seeing a stable pattern keeps the stairsDown critical',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final frame = makeStaircase();

        
        
        final first = analyzer.debugDetectStairsDown(
          frame,
          userStationary: true,
        );
        expect(first, isNotNull);
        expect(first!.type, DepthHazardType.stairsDown);

        
        
        final second = analyzer.debugDetectStairsDown(
          frame,
          userStationary: true,
        );
        expect(second, isNotNull);
        expect(second!.type, DepthHazardType.stairsDown);
      },
    );

    test(
      'stationary user on a drifting pattern suppresses critical, then '
      'emits escalatorRiding after the confirmation streak',
      () {
        final analyzer = GroundPlaneAnalyzer();

        
        final baseFrame = makeStaircase();
        final prime = analyzer.debugDetectStairsDown(
          baseFrame,
          userStationary: true,
        );
        expect(prime, isNotNull);
        expect(prime!.type, DepthHazardType.stairsDown);

        
        
        
        final shifted1 = makeStaircase(rowShift: 6);
        final draft = analyzer.debugDetectStairsDown(
          shifted1,
          userStationary: true,
        );
        expect(draft, isNull);

        
        
        
        final shifted2 = makeStaircase(rowShift: 12);
        final escalator = analyzer.debugDetectStairsDown(
          shifted2,
          userStationary: true,
        );
        expect(escalator, isNotNull);
        expect(escalator!.type, DepthHazardType.escalatorRiding);
        expect(escalator.zone, HazardZone.center);
        
        
        expect(escalator.midasScore, lessThan(prime.midasScore));
      },
    );

    test(
      'walking user on a drifting pattern still gets the stairsDown '
      'critical — conservative parallax branch',
      () {
        final analyzer = GroundPlaneAnalyzer();

        
        
        
        analyzer.debugDetectStairsDown(makeStaircase(), userStationary: false);

        final drifted = makeStaircase(rowShift: 10);
        final hazard = analyzer.debugDetectStairsDown(
          drifted,
          userStationary: false,
        );
        expect(hazard, isNotNull);
        expect(hazard!.type, DepthHazardType.stairsDown);
      },
    );

    test(
      'resetTemporalFilter clears the phase-shift buffer so the next '
      'drifting frame re-enters the cold-start critical path',
      () {
        final analyzer = GroundPlaneAnalyzer();

        analyzer.debugDetectStairsDown(
          makeStaircase(),
          userStationary: true,
        );
        analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 6),
          userStationary: true,
        );

        analyzer.resetTemporalFilter();

        
        
        
        final afterReset = analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 6),
          userStationary: true,
        );
        expect(afterReset, isNotNull);
        expect(afterReset!.type, DepthHazardType.stairsDown);
      },
    );

    test(
      'flat depth map produces no hazard regardless of motion state',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final flat = Float32List(size * size)..fillRange(0, size * size, 0.5);

        expect(
          analyzer.debugDetectStairsDown(flat, userStationary: false),
          isNull,
        );
        expect(
          analyzer.debugDetectStairsDown(flat, userStationary: true),
          isNull,
        );
      },
    );

    test(
      'escalator streak resets when the periodic pattern disappears so a '
      'later drift must re-confirm before emitting the info hazard',
      () {
        final analyzer = GroundPlaneAnalyzer();

        
        analyzer.debugDetectStairsDown(
          makeStaircase(),
          userStationary: true,
        );
        analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 6),
          userStationary: true,
        );

        
        
        final flat = Float32List(size * size)..fillRange(0, size * size, 0.5);
        expect(
          analyzer.debugDetectStairsDown(flat, userStationary: true),
          isNull,
        );

        
        
        
        
        
        final revived = analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 8),
          userStationary: true,
        );
        expect(revived, isNotNull);
        expect(revived!.type, DepthHazardType.stairsDown);

        
        
        
        final followUp = analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 14),
          userStationary: true,
        );
        expect(followUp, isNull);
      },
    );

    test(
      'stationary → walking mid-sequence immediately falls back to the '
      'conservative stairsDown critical even if a drift is ongoing',
      () {
        final analyzer = GroundPlaneAnalyzer();

        analyzer.debugDetectStairsDown(
          makeStaircase(),
          userStationary: true,
        );
        final streakFrame = analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 6),
          userStationary: true,
        );
        expect(streakFrame, isNull);

        
        
        final walkingFrame = analyzer.debugDetectStairsDown(
          makeStaircase(rowShift: 12),
          userStationary: false,
        );
        expect(walkingFrame, isNotNull);
        expect(walkingFrame!.type, DepthHazardType.stairsDown);
      },
    );
  });

  group('GroundPlaneAnalyzer.detectStairsDownFromMap backward compat', () {
    test('still exposes the pure static detector for legacy callers', () {
      final flat = Float32List(size * size)..fillRange(0, size * size, 0.5);
      expect(GroundPlaneAnalyzer.detectStairsDownFromMap(flat), isNull);

      final staircase = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final treadIndex = (y / 20).floor();
        final z = 0.4 + treadIndex * 0.08;
        for (int x = 0; x < size; x++) {
          staircase[y * size + x] = z;
        }
      }
      final hazard = GroundPlaneAnalyzer.detectStairsDownFromMap(staircase);
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.stairsDown);
    });
  });
}
