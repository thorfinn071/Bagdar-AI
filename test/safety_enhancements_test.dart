import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/motion_prealert.dart';
import 'package:bagdar/services/orientation_service.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/distance_utils.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';

void main() {
  group('GroundPlaneAnalyzer.detectStairsDownFromMap', () {
    Float32List makeFlat(double value) {
      const size = GroundPlaneAnalyzer.kMapSize;
      return Float32List(size * size)..fillRange(0, size * size, value);
    }

    Float32List makeStaircase({
      double baseZ = 0.4,
      double treadStep = 0.08,
      int treadHeight = 20,
    }) {
      const size = GroundPlaneAnalyzer.kMapSize;
      final map = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final treadIndex = (y / treadHeight).floor();
        final z = baseZ + treadIndex * treadStep;
        for (int x = 0; x < size; x++) {
          map[y * size + x] = z;
        }
      }
      return map;
    }

    test('flat map does not trigger the stairs detector', () {
      final hazard = GroundPlaneAnalyzer.detectStairsDownFromMap(makeFlat(0.5));
      expect(hazard, isNull);
    });

    test('quasi-periodic staircase signal is detected as stairsDown', () {
      final hazard = GroundPlaneAnalyzer.detectStairsDownFromMap(makeStaircase());
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.stairsDown);
      expect(hazard.zone, HazardZone.center);
      expect(hazard.midasScore, greaterThanOrEqualTo(0.55));
    });

    test('smooth monotonic ramp without periodic jumps does not trigger', () {
      const size = GroundPlaneAnalyzer.kMapSize;
      final map = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final z = 0.3 + y * 0.0015;
        for (int x = 0; x < size; x++) {
          map[y * size + x] = z;
        }
      }
      expect(
        GroundPlaneAnalyzer.detectStairsDownFromMap(map),
        isNull,
      );
    });

    test('non-conformant map size returns null without crashing', () {
      final tiny = Float32List(10);
      expect(
        GroundPlaneAnalyzer.detectStairsDownFromMap(tiny),
        isNull,
      );
    });
  });

  group('GroundPlaneAnalyzer.isLikelyShadowArtifact', () {
    test('suppresses a uniform dark drop with low variance', () {
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 12.3, 
        dropLumaSum: 60.0 * 100,
        dropLumaCount: 100,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.38,
      );
      expect(suppress, isTrue);
    });

    test('keeps a high-variance drop (physical pit signature)', () {
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 22.0, 
        dropLumaSum: 60.0 * 100,
        dropLumaCount: 100,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.40,
      );
      expect(suppress, isFalse);
    });

    test('keeps a deep drop even when variance is low (deep hole signature)',
        () {
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 80.0,
        dropSqSum: 64.2, 
        dropLumaSum: 60.0 * 100,
        dropLumaCount: 100,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.80,
      );
      expect(suppress, isFalse);
    });

    test('keeps a drop that is not darker than surrounding flat', () {
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 12.3,
        dropLumaSum: 140.0 * 100,
        dropLumaCount: 100,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.38,
      );
      expect(suppress, isFalse);
    });

    test('ignores suppression when there are too few samples', () {
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 4,
        dropSum: 1.0,
        dropSqSum: 0.3,
        dropLumaSum: 2.0 * 4,
        dropLumaCount: 4,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.35,
      );
      expect(suppress, isFalse);
    });

    test(
        'OPT-04: suppresses a drop that is much BRIGHTER than surrounding '
        'flat (puddle reflecting sky)', () {
      
      
      
      
      
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 12.3, 
        dropLumaSum: 200.0 * 100, 
        dropLumaCount: 100,
        flatLumaSum: 40.0 * 200, 
        flatLumaCount: 200,
        maxDrop: 0.38,
      );
      expect(suppress, isTrue);
    });

    test(
        'OPT-04: suppresses a drop with matching mean luma but high intra-zone '
        'variance (patchy puddle)', () {
      
      
      
      
      
      
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 12.3,
        dropLumaSum: 150.0 * 100,
        dropLumaSqSum: (150.0 * 150.0 + 900.0) * 100,
        dropLumaCount: 100,
        flatLumaSum: 150.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.38,
      );
      expect(suppress, isTrue);
    });

    test(
        'OPT-04: keeps a uniformly dark real pothole even when sqSum is '
        'supplied (low intra-zone variance)', () {
      
      
      
      
      
      final suppress = GroundPlaneAnalyzer.isLikelyShadowArtifact(
        dropCount: 100,
        dropSum: 35.0,
        dropSqSum: 12.3,
        dropLumaSum: 60.0 * 100,
        dropLumaSqSum: (60.0 * 60.0 + 25.0) * 100,
        dropLumaCount: 100,
        flatLumaSum: 60.0 * 200,
        flatLumaCount: 200,
        maxDrop: 0.38,
      );
      expect(suppress, isFalse);
    });
  });

  group('GroundPlaneAnalyzer (OPT-04) temporal confirmation', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    Float32List makeFlat(double value) =>
        Float32List(size * size)..fillRange(0, size * size, value);

    
    
    
    Float32List makeStableHazardMap() {
      final map = Float32List(size * size)..fillRange(0, size * size, 0.5);
      for (int y = GroundPlaneAnalyzer.kFootZoneStartRow; y < size; y++) {
        for (int x = 0; x < size; x++) {
          if ((x + y) % 2 == 0) map[y * size + x] += 0.45;
        }
      }
      return map;
    }

    test(
        'single-frame hazard after warm-up is filtered out (4-of-5 '
        'confirmation required)', () {
      final analyzer = GroundPlaneAnalyzer();
      final flat = makeFlat(0.5);

      for (int i = 0; i < 5; i++) {
        analyzer.analyze(flat);
      }

      final flicker = analyzer.analyze(makeStableHazardMap());

      expect(flicker, isEmpty);
    });

    test(
        'a hazard that persists long enough survives the '
        '4-of-5 temporal filter', () {
      final analyzer = GroundPlaneAnalyzer();
      final flat = makeFlat(0.5);
      for (int i = 0; i < 5; i++) {
        analyzer.analyze(flat);
      }

      final map = makeStableHazardMap();
      for (int i = 0; i < 6; i++) {
        analyzer.analyze(map);
      }
      final out = analyzer.analyze(map);
      expect(
        out.any((h) =>
            h.zone == HazardZone.center &&
            h.type == DepthHazardType.deadZone),
        isTrue,
      );
    });

    test('cold-start emits unfiltered results until buffer is full', () {
      final analyzer = GroundPlaneAnalyzer();
      final map = makeStableHazardMap();

      analyzer.analyze(map);
      analyzer.analyze(map);
      final out = analyzer.analyze(map);

      expect(
        out.any((h) =>
            h.zone == HazardZone.center &&
            h.type == DepthHazardType.deadZone),
        isTrue,
      );
    });

    test('resetTemporalFilter restores cold-start behaviour', () {
      final analyzer = GroundPlaneAnalyzer();
      final flat = makeFlat(0.5);
      for (int i = 0; i < 5; i++) {
        analyzer.analyze(flat);
      }

      analyzer.resetTemporalFilter();
      final map = makeStableHazardMap();
      analyzer.analyze(map);
      analyzer.analyze(map);
      final out = analyzer.analyze(map);
      expect(
        out.any((h) =>
            h.zone == HazardZone.center &&
            h.type == DepthHazardType.deadZone),
        isTrue,
      );
    });
  });

  group('MotionPreAlert.analyzeLumaGrids', () {
    List<int> makeUniform(int gridW, int gridH, int value) =>
        List<int>.filled(gridW * gridH, value);

    List<int> injectLeftMotion(int gridW, int gridH, int baseValue) {
      final grid = makeUniform(gridW, gridH, baseValue);
      for (int y = 0; y < gridH; y++) {
        for (int x = 0; x < 8; x++) {
          grid[y * gridW + x] = (baseValue + 90).clamp(0, 255);
        }
      }
      return grid;
    }

    List<int> injectRightMotion(int gridW, int gridH, int baseValue) {
      final grid = makeUniform(gridW, gridH, baseValue);
      for (int y = 0; y < gridH; y++) {
        for (int x = gridW - 8; x < gridW; x++) {
          grid[y * gridW + x] = (baseValue + 90).clamp(0, 255);
        }
      }
      return grid;
    }

    test('no change between frames returns null', () {
      final now = DateTime(2025, 1, 1, 12);
      final event = MotionPreAlert.analyzeLumaGrids(
        prevGrid: makeUniform(32, 24, 128),
        curGrid: makeUniform(32, 24, 128),
        gridW: 32,
        gridH: 24,
        now: now,
      );
      expect(event, isNull);
    });

    test('strong left-sector brightness change fires a left-side event', () {
      final now = DateTime(2025, 1, 1, 12);
      final event = MotionPreAlert.analyzeLumaGrids(
        prevGrid: makeUniform(32, 24, 128),
        curGrid: injectLeftMotion(32, 24, 128),
        gridW: 32,
        gridH: 24,
        now: now,
      );
      expect(event, isNotNull);
      expect(event!.side, MotionIntrusionSide.left);
      expect(event.strength, greaterThan(0.0));
    });

    test('strong right-sector brightness change fires a right-side event', () {
      final now = DateTime(2025, 1, 1, 12);
      final event = MotionPreAlert.analyzeLumaGrids(
        prevGrid: makeUniform(32, 24, 128),
        curGrid: injectRightMotion(32, 24, 128),
        gridW: 32,
        gridH: 24,
        now: now,
      );
      expect(event, isNotNull);
      expect(event!.side, MotionIntrusionSide.right);
    });

    test('simultaneous left+right changes collapse to a center warning', () {
      final now = DateTime(2025, 1, 1, 12);
      final grid = injectLeftMotion(32, 24, 128);
      for (int y = 0; y < 24; y++) {
        for (int x = 32 - 8; x < 32; x++) {
          grid[y * 32 + x] = (128 + 90).clamp(0, 255);
        }
      }
      final event = MotionPreAlert.analyzeLumaGrids(
        prevGrid: makeUniform(32, 24, 128),
        curGrid: grid,
        gridW: 32,
        gridH: 24,
        now: now,
      );
      expect(event, isNotNull);
      expect(event!.side, MotionIntrusionSide.center);
    });

    test('high baseline suppresses noisy flicker below trigger multiplier',
        () {
      final now = DateTime(2025, 1, 1, 12);
      
      
      final cur = makeUniform(32, 24, 128);
      for (int y = 0; y < 24; y++) {
        for (int x = 0; x < 8; x++) {
          cur[y * 32 + x] = 140;
        }
      }
      final event = MotionPreAlert.analyzeLumaGrids(
        prevGrid: makeUniform(32, 24, 128),
        curGrid: cur,
        gridW: 32,
        gridH: 24,
        now: now,
        baselineLeft: 50.0,
        baselineRight: 50.0,
      );
      expect(event, isNull);
    });
  });

  group('GroundPlaneAnalyzer.detectOverheadFromMap', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    Float32List makeBackground(double near, double far) {
      final map = Float32List(size * size);
      
      for (int y = 0; y < size; y++) {
        final t = (size - 1 - y) / (size - 1);
        final z = far * (1.0 - t) + near * t;
        for (int x = 0; x < size; x++) {
          map[y * size + x] = z;
        }
      }
      return map;
    }

    test('flat-ramp background without obstacle returns null', () {
      final map = makeBackground(0.4, 1.8);
      final hazard = GroundPlaneAnalyzer.detectOverheadFromMap(
        map,
        planeA: 0.0,
        planeB: -0.005,
        planeC: 1.8,
      );
      expect(hazard, isNull);
    });

    test('narrow horizontal band at chest level is flagged overhead', () {
      final map = makeBackground(0.4, 1.8);
      
      
      for (int y = 80; y < 88; y++) {
        for (int x = 40; x < 220; x++) {
          map[y * size + x] = 0.4;
        }
      }
      final hazard = GroundPlaneAnalyzer.detectOverheadFromMap(
        map,
        planeA: 0.0,
        planeB: -0.005,
        planeC: 1.8,
      );
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.overhead);
    });

    test('tall vertical pillar does not trigger overhead (vertical spread '
        'gate filters walls)', () {
      final map = makeBackground(0.4, 1.8);
      
      for (int y = 55; y < 120; y++) {
        for (int x = 110; x < 135; x++) {
          map[y * size + x] = 0.4;
        }
      }
      final hazard = GroundPlaneAnalyzer.detectOverheadFromMap(
        map,
        planeA: 0.0,
        planeB: -0.005,
        planeC: 1.8,
      );
      expect(hazard, isNull);
    });
  });

  group('GroundPlaneAnalyzer.detectPitGradientFromMap', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    Float32List makeLinearFloor(double zBottom, double zTop) {
      final map = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final t = (size - 1 - y) / (size - 1);
        final z = zTop * (1.0 - t) + zBottom * t;
        for (int x = 0; x < size; x++) {
          map[y * size + x] = z;
        }
      }
      return map;
    }

    test('linear floor without a pit does not trigger', () {
      final map = makeLinearFloor(0.5, 1.4);
      final hazard = GroundPlaneAnalyzer.detectPitGradientFromMap(map);
      expect(hazard, isNull);
    });

    test('sustained depth jump extending the floor slope direction is '
        'caught as a pit', () {
      
      
      
      final map = makeLinearFloor(0.5, 1.4);
      for (int y = 120; y < 195; y += 2) {
        for (int x = 100; x < 156; x++) {
          map[y * size + x] = 0.2;
        }
      }
      final hazard = GroundPlaneAnalyzer.detectPitGradientFromMap(map);
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.pothole);
      expect(hazard.zone, HazardZone.center);
      expect(hazard.midasScore, greaterThanOrEqualTo(0.60));
    });

    test('wall ahead (deviation opposite to floor slope) is NOT flagged as '
        'a pit', () {
      final map = makeLinearFloor(0.5, 1.4);
      
      
      for (int y = 120; y < 195; y += 2) {
        for (int x = 100; x < 156; x++) {
          map[y * size + x] = 2.5;
        }
      }
      final hazard = GroundPlaneAnalyzer.detectPitGradientFromMap(map);
      expect(hazard, isNull);
    });

    test('empty depth below baseline (no data) returns null safely', () {
      final map = Float32List(size * size);
      final hazard = GroundPlaneAnalyzer.detectPitGradientFromMap(map);
      expect(hazard, isNull);
    });
  });

  group('GroundPlaneAnalyzer reflective-surface guard', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    test('scanZoneLumaVariance is ~0 on uniform luma', () {
      final luma = Uint8List(size * size)..fillRange(0, size * size, 128);
      expect(GroundPlaneAnalyzer.scanZoneLumaVariance(luma), closeTo(0.0, 1e-9));
    });

    test('scanZoneLumaVariance is large on high-contrast scan zone', () {
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          luma[y * size + x] = ((x ~/ 4) & 1) == 0 ? 0 : 255;
        }
      }
      final v = GroundPlaneAnalyzer.scanZoneLumaVariance(luma);
      expect(v, greaterThan(1000.0));
    });

    test('scanZoneLumaVariance returns 0 on wrong-sized buffer', () {
      final luma = Uint8List(16);
      expect(GroundPlaneAnalyzer.scanZoneLumaVariance(luma), 0.0);
    });

    test('isSuspiciousReflectiveSurface requires BOTH high inliers AND '
        'low variance', () {
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: 0.95, lumaVariance: 40.0),
        isTrue,
      );
      
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: 0.95, lumaVariance: 500.0),
        isFalse,
      );
      
      
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: 0.50, lumaVariance: 40.0),
        isFalse,
      );
    });

    test('isSuspiciousReflectiveSurface returns false when luma is null', () {
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: 0.95, lumaVariance: null),
        isFalse,
      );
    });

    test('isSuspiciousReflectiveSurface is defensive against NaN/Infinity', () {
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: double.nan, lumaVariance: 40.0),
        isFalse,
      );
      expect(
        GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
            inlierRatio: 0.95, lumaVariance: double.infinity),
        isFalse,
      );
    });

    test('analyze() on a perfect plane with uniform luma suppresses the '
        'plane-based zone classifier and emits a dead-zone caution', () {
      
      final depth = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final z = 0.5 + y * 0.002;
        for (int x = 0; x < size; x++) {
          depth[y * size + x] = z;
        }
      }
      final luma = Uint8List(size * size)..fillRange(0, size * size, 128);
      final analyzer = GroundPlaneAnalyzer();
      final hazards = analyzer.analyze(depth, lumaMap: luma);
      
      
      expect(hazards, isNotEmpty);
      expect(
        hazards.any((h) =>
            h.type == DepthHazardType.deadZone &&
            h.zone == HazardZone.center),
        isTrue,
      );
    });

    test('analyze() with textured luma over the same flat depth does NOT '
        'emit the reflective dead-zone caution (false alarm guard)', () {
      final depth = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        final z = 0.5 + y * 0.002;
        for (int x = 0; x < size; x++) {
          depth[y * size + x] = z;
        }
      }
      
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          luma[y * size + x] = ((x ~/ 2) & 1) == 0 ? 0 : 255;
        }
      }
      final analyzer = GroundPlaneAnalyzer();
      final hazards = analyzer.analyze(depth, lumaMap: luma);
      expect(
        hazards.any((h) =>
            h.type == DepthHazardType.deadZone &&
            h.zone == HazardZone.center &&
            h.midasScore == 0.60),
        isFalse,
      );
    });
  });

  group('OrientationService.cropTopFracForPitch', () {
    test('returns min crop when phone is nearly flat (looking at the floor)',
        () {
      expect(OrientationService.cropTopFracForPitch(10.0), closeTo(0.20, 1e-9));
      expect(OrientationService.cropTopFracForPitch(25.0), closeTo(0.20, 1e-9));
    });

    test('returns max crop when phone points at the horizon', () {
      expect(OrientationService.cropTopFracForPitch(75.0), closeTo(0.55, 1e-9));
      expect(OrientationService.cropTopFracForPitch(89.0), closeTo(0.55, 1e-9));
    });

    test('interpolates linearly between 30° and 60°', () {
      final at45 = OrientationService.cropTopFracForPitch(45.0);
      expect(at45, closeTo(0.375, 1e-9));
      final at30 = OrientationService.cropTopFracForPitch(30.0);
      expect(at30, closeTo(0.20, 1e-9));
      final at60 = OrientationService.cropTopFracForPitch(60.0);
      expect(at60, closeTo(0.55, 1e-9));
    });

    test('non-finite input falls back to mid crop without crashing', () {
      expect(
        OrientationService.cropTopFracForPitch(double.nan),
        closeTo(0.40, 1e-9),
      );
      expect(
        OrientationService.cropTopFracForPitch(double.infinity),
        closeTo(0.40, 1e-9),
      );
    });
  });

  group('OrientationService.computeRoll', () {
    test('upright phone (ax=0) returns 0 degrees', () {
      expect(OrientationService.computeRoll(0.0, 9.81), closeTo(0.0, 1e-9));
    });

    test('phone tilted fully to the right returns +90 degrees', () {
      expect(OrientationService.computeRoll(9.81, 0.0), closeTo(90.0, 1e-9));
    });

    test('phone tilted fully to the left returns -90 degrees', () {
      expect(OrientationService.computeRoll(-9.81, 0.0), closeTo(-90.0, 1e-9));
    });

    test('40 degree right tilt crosses the excessive enter threshold', () {
      final roll = OrientationService.computeRoll(
        9.81 * math.sin(40 * math.pi / 180),
        9.81 * math.cos(40 * math.pi / 180),
      );
      expect(roll, closeTo(40.0, 1e-6));
      expect(roll.abs() > OrientationService.kRollEnterThreshold, isTrue);
    });

    test('30 degree tilt stays below the excessive enter threshold', () {
      final roll = OrientationService.computeRoll(5.0, 5.0 * math.sqrt(3));
      expect(roll, closeTo(30.0, 1e-6));
      expect(roll.abs() > OrientationService.kRollEnterThreshold, isFalse);
    });

    test('exit threshold below enter threshold (hysteresis)', () {
      expect(
        OrientationService.kRollExitThreshold,
        lessThan(OrientationService.kRollEnterThreshold),
      );
    });
  });

  group('GroundPlaneAnalyzer.detectGlassDoorFromLuma', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    Uint8List makeUniform(int value) =>
        Uint8List(size * size)..fillRange(0, size * size, value);

    test('uniform mid-gray upper-half fires a glass-door hazard', () {
      final luma = makeUniform(128);
      final hazard = GroundPlaneAnalyzer.detectGlassDoorFromLuma(luma);
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.glassDoor);
      expect(hazard.zone, HazardZone.center);
    });

    test('bright-left / dark-right asymmetric pattern does not trigger', () {
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          luma[y * size + x] = x < size ~/ 2 ? 240 : 20;
        }
      }
      expect(GroundPlaneAnalyzer.detectGlassDoorFromLuma(luma), isNull);
    });

    test('high-contrast textured wall does not trigger', () {
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final base = ((x ~/ 8) + (y ~/ 8)) & 1;
          luma[y * size + x] = base == 0 ? 0 : 255;
        }
      }
      expect(GroundPlaneAnalyzer.detectGlassDoorFromLuma(luma), isNull);
    });

    test('non-conformant map size returns null without crashing', () {
      expect(
        GroundPlaneAnalyzer.detectGlassDoorFromLuma(Uint8List(16)),
        isNull,
      );
    });
  });

  group('GroundPlaneAnalyzer.detectSlipperyFromLuma', () {
    const size = GroundPlaneAnalyzer.kMapSize;

    test('horizontal banding in the bottom half is flagged as slippery', () {
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        final band = (y ~/ 4) & 1;
        final base = band == 0 ? 40 : 200;
        for (int x = 0; x < size; x++) {
          luma[y * size + x] = base + (x & 3);
        }
      }
      final hazard = GroundPlaneAnalyzer.detectSlipperyFromLuma(luma);
      expect(hazard, isNotNull);
      expect(hazard!.type, DepthHazardType.slippery);
      expect(hazard.zone, HazardZone.center);
    });

    test('vertical stripes in the bottom half do not trigger slippery', () {
      final luma = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final bright = (x ~/ 4) & 1;
          luma[y * size + x] = bright == 0 ? 0 : 255;
        }
      }
      expect(GroundPlaneAnalyzer.detectSlipperyFromLuma(luma), isNull);
    });

    test('uniform featureless surface does not trigger slippery', () {
      final luma = Uint8List(size * size)..fillRange(0, size * size, 128);
      expect(GroundPlaneAnalyzer.detectSlipperyFromLuma(luma), isNull);
    });

    test('non-conformant map size returns null without crashing', () {
      expect(
        GroundPlaneAnalyzer.detectSlipperyFromLuma(Uint8List(16)),
        isNull,
      );
    });
  });

  group('findFreeCorridor polar-metric mode', () {
    Track makeTrack({
      required int id,
      required double cx,
      required double cy,
      required double width,
      required double height,
      required double distM,
      String label = 'person',
    }) {
      final x1 = cx - width / 2;
      final x2 = cx + width / 2;
      final y1 = cy - height / 2;
      final y2 = cy + height / 2;
      return Track(
        id: id,
        label: label,
        cx: cx,
        cy: cy,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        dist: 'close',
        distM: distM,
      );
    }

    test('empty track list returns null', () {
      expect(findFreeCorridor(const [], 1600, 900), isNull);
    });

    test('single close obstacle centred ahead forces a side corridor', () {
      final tracks = [
        makeTrack(
          id: 1,
          cx: 800,
          cy: 600,
          width: 120,
          height: 400,
          distM: 1.0,
        ),
      ];
      final result = findFreeCorridor(tracks, 1600, 900);
      expect(result, isNotNull);
      expect(result!.$2, isNot('center'));
      expect(result.$1, greaterThan(0.0));
    });

    test('obstacles on both edges leave a centred corridor', () {
      final tracks = [
        makeTrack(
          id: 1,
          cx: 100,
          cy: 600,
          width: 120,
          height: 400,
          distM: 0.8,
        ),
        makeTrack(
          id: 2,
          cx: 1500,
          cy: 600,
          width: 120,
          height: 400,
          distM: 0.8,
        ),
      ];
      final result = findFreeCorridor(tracks, 1600, 900);
      expect(result, isNotNull);
      expect(result!.$2, 'center');
      expect(result.$1, greaterThan(0.5));
    });

    test('dense wall of close obstacles forces a side corridor', () {
      final tracks = <Track>[];
      for (int i = 0; i < 9; i++) {
        final cx = 100.0 + i * 180.0;
        tracks.add(makeTrack(
          id: i,
          cx: cx,
          cy: 600,
          width: 260,
          height: 400,
          distM: 0.8,
        ));
      }
      final result = findFreeCorridor(tracks, 1600, 900);
      expect(result, isNotNull);
      expect(result!.$2, isNot('center'));
    });

    test('far obstacles (distM >> 1.5m) leave the whole FOV passable', () {
      final tracks = [
        makeTrack(
          id: 1,
          cx: 800,
          cy: 600,
          width: 60,
          height: 200,
          distM: 10.0,
        ),
      ];
      final result = findFreeCorridor(tracks, 1600, 900);
      expect(result, isNotNull);
      expect(result!.$2, 'center');
      expect(result.$1, greaterThan(1.0));
    });
  });
}
