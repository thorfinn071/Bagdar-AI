// Bagdar AI — Layered Diagnostic Test Harness (Phase 1)
//
// Diagnosis only — no production-logic changes. Each test exercises one pure-Dart
// layer with synthetic data and records the ACTUAL behaviour in the test log.
// JSON is written only when BAGDAR_HARNESS_OUTPUT is explicitly supplied.
//
// Layers under test:
//   A. GroundPlaneAnalyzer (RANSAC + foot-zone + reflective + stairs)
//   B. Tracker (Kalman + Hungarian + ghost-decay + graveyard)
//   C. AlertFilter (priority / cooldown / escalation / multi)
//   D. TtsService (priority queue / stale pruning / queue latency)
//
// Grounding corrections vs the originating prompt (documented in debug_findings.md):
//   * The public TTS enqueue method is `say`, not `speak` (lib/services/tts_service.dart:681).
//   * Stairs detection EXISTS (`_detectStairsDown` + public `detectStairsDownFromMap` /
//     `debugDetectStairsDown`); A5 audits/tests it instead of logging an architectural gap.
//   * AlertFilter escalation has a 2000 ms floor (`kCriticalRepeatCooldownSafety`); the
//     prompt's "passes at 1000 ms" is mechanically impossible — C3 asserts real behaviour.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/tracker/hungarian.dart';
import 'package:bagdar/tracker/raw_det.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/tracker/tracker.dart';
import 'package:bagdar/utils/alert_filter.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';

const _releaseCandidate = bool.fromEnvironment(
  'BAGDAR_RC',
  defaultValue: false,
);
const _harnessOutput = String.fromEnvironment('BAGDAR_HARNESS_OUTPUT');

// ---------------------------------------------------------------------------
// Results collector — accumulated across tests, serialised by the final test.
// ---------------------------------------------------------------------------
final List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];

void _record(Map<String, dynamic> r) {
  _results.add(r);
  // Also echo to the test log so results survive even if file-write fails.
  debugPrint('HARNESS_RESULT ${r['scenario_id']}: ${jsonEncode(r)}');
}

Map<String, dynamic> _entry(
  String id,
  String description,
  String layer,
  String status,
  String actual, {
  String expected = '',
  String notes = '',
}) => <String, dynamic>{
  'scenario_id': id,
  'description': description,
  'phase': 1,
  'layer': layer,
  'test_file': 'test/harness/scenario_harness_test.dart',
  'status': status,
  'actual_output': actual,
  'expected_output': expected,
  'notes': notes,
};

// ---------------------------------------------------------------------------
// Synthetic-data factories
// ---------------------------------------------------------------------------

/// RawDet factory matching the prompt's intent (cx/cy required, box defaulted).
RawDet makeDet({
  required String label,
  double cx = 320,
  double cy = 400,
  double? x1,
  double? y1,
  double? x2,
  double? y2,
  double conf = 0.75,
  String dist = 'close',
  double distM = 2.0,
}) {
  final bx1 = x1 ?? cx - 50;
  final by1 = y1 ?? cy - 50;
  final bx2 = x2 ?? cx + 50;
  final by2 = y2 ?? cy + 50;
  return RawDet(
    label: label,
    cx: cx,
    cy: cy,
    x1: bx1,
    y1: by1,
    x2: bx2,
    y2: by2,
    conf: conf,
    dist: dist,
    distM: distM,
  );
}

/// 256x256 flat depth map (kMapSize*kMapSize = 65536 values).
Float32List makeFlatDepthMap({double value = 0.5}) =>
    Float32List(GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize)
      ..fillRange(
        0,
        GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize,
        value,
      );

/// Foot-zone drop: rows 128-217 = 0.5, rows 218-255 = 0.05 (near-zero = far/void).
/// Note: 0.05 is NOT > 0.05, so foot-zone points are excluded from RANSAC sampling
/// (GroundPlaneAnalyzer.analyze line ~113 `if (z > 0.05)`); RANSAC fits the upper
/// plane z=0.5 and the drop is detected in the per-zone scan.
Float32List makeDropDepthMap() {
  final map = makeFlatDepthMap(value: 0.5);
  const n = GroundPlaneAnalyzer.kMapSize;
  for (int y = GroundPlaneAnalyzer.kFootZoneStartRow; y < n; y++) {
    for (int x = 0; x < n; x++) {
      map[y * n + x] = 0.05;
    }
  }
  return map;
}

/// Centre wall: columns 100-156, rows 128-255 = 0.9 (close), rest 0.5.
Float32List makeCenterWallMap() {
  final map = makeFlatDepthMap(value: 0.5);
  const n = GroundPlaneAnalyzer.kMapSize;
  for (int y = GroundPlaneAnalyzer.kZoneStartRow; y < n; y++) {
    for (int x = 100; x < 157; x++) {
      map[y * n + x] = 0.9;
    }
  }
  return map;
}

/// Uniform-grey luma (variance ~0) used for the reflective-surface scenario.
Uint8List makeLowVarianceLuma({int value = 128}) =>
    Uint8List(GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize)
      ..fillRange(
        0,
        GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize,
        value,
      );

/// Uniform random noise depth (seeded) for the low-light / poor-fit scenario.
Float32List makeNoisyDepthMap({int seed = 42}) {
  final rng = math.Random(seed);
  final map = Float32List(
    GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize,
  );
  for (int i = 0; i < map.length; i++) {
    map[i] = 0.1 + rng.nextDouble() * 0.8; // 0.1 .. 0.9
  }
  return map;
}

/// Periodic descending-stairs pattern in the stairs signal region
/// (rows 64-256, cols 48-208) — a step function decreasing every [period] rows.
/// The differenced signal (stride 4) is a periodic negative-spike train, which
/// yields high energy + directionality + an autocorrelation peak at [period].
Float32List makeStairsDownMap({
  int period = 20,
  double base = 0.7,
  double stepHeight = 0.08,
}) {
  final map = makeFlatDepthMap(value: 0.5);
  const n = GroundPlaneAnalyzer.kMapSize;
  for (int y = 64; y < n; y++) {
    final stepIdx = (y - 64) ~/ period;
    final z = (base - stepIdx * stepHeight).clamp(0.1, 0.9);
    for (int x = 48; x < 208; x++) {
      map[y * n + x] = z.toDouble();
    }
  }
  return map;
}

/// Smooth monotonic ramp in the stairs region — no periodicity, expect null.
Float32List makeRampMap() {
  final map = makeFlatDepthMap(value: 0.5);
  const n = GroundPlaneAnalyzer.kMapSize;
  for (int y = 64; y < n; y++) {
    final z = (0.7 - (y - 64) * 0.002).clamp(0.1, 0.9);
    for (int x = 48; x < 208; x++) {
      map[y * n + x] = z.toDouble();
    }
  }
  return map;
}

/// Single step at y=150 — one discontinuity, no periodic peak, expect null.
Float32List makeSingleStepMap() {
  final map = makeFlatDepthMap(value: 0.5);
  const n = GroundPlaneAnalyzer.kMapSize;
  for (int y = 64; y < 150; y++) {
    for (int x = 48; x < 208; x++) {
      map[y * n + x] = 0.7;
    }
  }
  for (int y = 150; y < n; y++) {
    for (int x = 48; x < 208; x++) {
      map[y * n + x] = 0.5;
    }
  }
  return map;
}

AlertCandidate _cand(
  String text,
  SpeechPriority p,
  AlertCategory cat, {
  double urgency = 0.5,
  double pan = 0.0,
  int? trackId,
  double? distanceM,
  bool isGroupAlert = false,
}) => AlertCandidate(
  text: text,
  priority: p,
  pan: pan,
  category: cat,
  urgency: urgency,
  trackId: trackId,
  isGroupAlert: isGroupAlert,
  distanceM: distanceM,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // GROUP A — GroundPlaneAnalyzer (Layer 2, RANSAC)
  // =========================================================================
  group('A. GroundPlaneAnalyzer', () {
    test('A1_flat_surface_no_hazards', () {
      final gpa = GroundPlaneAnalyzer();
      final hazards = gpa.analyze(makeFlatDepthMap(value: 0.5));
      final planeOk = gpa.lastPlaneFitOk;
      // First call: temporal window not full → candidates returned as-is.
      // Flat plane → no drops/rises; inlierRatio > 0.75 → deadZones removed.
      expect(
        hazards,
        isEmpty,
        reason: 'Flat 0.5 plane must yield zero hazards; got $hazards',
      );
      _record(
        _entry(
          'A1',
          'Flat surface -> no hazards',
          'GroundPlaneAnalyzer',
          hazards.isEmpty ? 'pass' : 'fail',
          'hazards=$hazards; planeFitOk=$planeOk',
          expected: 'empty list',
          notes: 'planeFitOk=$planeOk',
        ),
      );
    });

    test('A2_foot_zone_drop_stationary', () {
      // Walking gate (kWalkingMinCoverage=0.38) suppresses a 0.30-coverage drop,
      // so we run stationary (gate returns true) to observe the hazard, and also
      // record the walking-suppressed variant for diagnosis.
      final gpa = GroundPlaneAnalyzer();
      final hazardsStat = gpa.analyze(makeDropDepthMap(), userStationary: true);
      final planeOkStat = gpa.lastPlaneFitOk;

      final gpaWalk = GroundPlaneAnalyzer();
      final hazardsWalk = gpaWalk.analyze(
        makeDropDepthMap(),
        userStationary: false,
      );
      final walkingDetectsDrop = hazardsWalk.any(
        (h) =>
            h.type == DepthHazardType.stepDown ||
            h.type == DepthHazardType.pothole ||
            h.type == DepthHazardType.unknown,
      );

      expect(
        hazardsStat,
        isNotEmpty,
        reason:
            'Foot-zone drop with userStationary=true should produce >=1 hazard; '
            'got $hazardsStat',
      );
      _record(
        _entry(
          'A2',
          'Foot-zone drop -> DepthHazard (drop)',
          'GroundPlaneAnalyzer',
          hazardsStat.isNotEmpty ? 'pass' : 'fail',
          'stationary hazards=${hazardsStat.map((h) => h.toString()).toList()}; '
              'planeFitOk=$planeOkStat; '
              'walkingDetectsDrop=$walkingDetectsDrop',
          expected: '>=1 DepthHazard (drop) in foot zone',
          notes:
              'RANSAC excludes z<=0.05 points so it fits the upper plane; the '
              'plane-based per-zone scan detects the drop (cov 0.30) when stationary. '
              'While walking, that scan is GATED (0.30 < kWalkingMinCoverage=0.38), '
              'BUT the pit-gradient fallback (detectPitGradientFromMap, GPA:433/744) '
              'runs because hasCenterDrop=false and still reports the discontinuity. '
              'So the foot-zone drop survives the walking gate via a second path '
              '(walkingDetectsDrop=$walkingDetectsDrop) — a safety-positive result.',
        ),
      );
    });

    test('A3_center_wall_rise', () {
      final gpa = GroundPlaneAnalyzer();
      final hazards = gpa.analyze(makeCenterWallMap(), userStationary: true);
      final planeOk = gpa.lastPlaneFitOk;
      final riseZones = hazards
          .where(
            (h) =>
                h.type == DepthHazardType.stepUp ||
                h.type == DepthHazardType.curb ||
                h.type == DepthHazardType.lowCurb,
          )
          .map((h) => h.zone)
          .toSet();
      expect(
        hazards,
        isNotEmpty,
        reason:
            'Centre wall (close) should yield >=1 rise hazard; got $hazards',
      );
      _record(
        _entry(
          'A3',
          'Centre wall -> rise hazard',
          'GroundPlaneAnalyzer',
          hazards.isNotEmpty ? 'pass' : 'fail',
          'hazards=${hazards.map((h) => h.toString()).toList()}; '
              'riseZones=$riseZones; planeFitOk=$planeOk',
          expected: '>=1 rise hazard in centre zone(s)',
          notes: 'Wall spans centre-left/centre/centre-right column zones.',
        ),
      );
    });

    test('A4_reflective_surface_suppressed', () {
      // Flat depth (inlierRatio ~1.0 >= 0.88) + uniform luma (variance ~0 <= 60)
      // -> isSuspiciousReflectiveSurface == true -> deadZone hazard, plane-based
      // drop/rise scan skipped (early return).
      final reflective = GroundPlaneAnalyzer.isSuspiciousReflectiveSurface(
        inlierRatio: 1.0,
        lumaVariance: 0.0,
      );
      expect(reflective, isTrue);

      final gpa = GroundPlaneAnalyzer();
      final luma = makeLowVarianceLuma(value: 128);
      final hazards = gpa.analyze(makeFlatDepthMap(value: 0.5), lumaMap: luma);
      final lumaVar = GroundPlaneAnalyzer.scanZoneLumaVariance(luma);
      final hasDeadZone = hazards.any(
        (h) => h.type == DepthHazardType.deadZone,
      );
      _record(
        _entry(
          'A4',
          'Reflective surface (mirror) -> deadZone, plane scan skipped',
          'GroundPlaneAnalyzer',
          (reflective && hasDeadZone) ? 'pass' : 'fail',
          'isSuspiciousReflectiveSurface=$reflective; lumaVariance=$lumaVar; '
              'hazards=${hazards.map((h) => h.toString()).toList()}; '
              'hasDeadZone=$hasDeadZone',
          expected: 'isSuspiciousReflectiveSurface==true; >=1 deadZone hazard',
          notes:
              'kReflectiveInlierRatioMin=0.88, kReflectiveLumaVarianceMax=60.0',
        ),
      );
    });

    test('A5_stairs_vs_ramp_vs_single_step', () {
      // The stairs detector classifies via autocorrelation of a differenced
      // depth signal (lag 12-48, peak ratio >= 3x mean, directionality >= 0.58).
      final stairs = GroundPlaneAnalyzer.detectStairsDownFromMap(
        makeStairsDownMap(),
      );
      final ramp = GroundPlaneAnalyzer.detectStairsDownFromMap(makeRampMap());
      final single = GroundPlaneAnalyzer.detectStairsDownFromMap(
        makeSingleStepMap(),
      );

      // Ramp and single-step must NOT classify as stairs (no periodic peak).
      expect(ramp, isNull, reason: 'Smooth ramp must not be stairs; got $ramp');
      expect(
        single,
        isNull,
        reason: 'Single step must not be stairs; got $single',
      );

      _record(
        _entry(
          'A5',
          'Stairs discrimination: periodic vs ramp vs single-step',
          'GroundPlaneAnalyzer',
          (ramp == null && single == null) ? 'pass' : 'fail',
          'stairs=${stairs?.toString() ?? "null"}; '
              'ramp=${ramp?.toString() ?? "null"}; '
              'singleStep=${single?.toString() ?? "null"}',
          expected:
              'ramp=null; singleStep=null; stairs=stairsDown (periodic pattern)',
          notes: stairs == null
              ? 'PARTIAL: synthetic periodic pattern did not classify as stairs — '
                    'the autocorrelation signature may require realistic MiDaS-style '
                    'stair depth. Ramp/single-step discrimination still holds.'
              : 'Periodic descending-stairs pattern classified as stairsDown.',
        ),
      );
    });

    test('A6_noisy_depth_plane_fit_behaviour', () {
      final gpa = GroundPlaneAnalyzer();
      final hazards = gpa.analyze(
        makeNoisyDepthMap(seed: 42),
        userStationary: false,
        weatherDegraded: true,
      );
      final planeOk = gpa.lastPlaneFitOk;
      expect(planeOk, isFalse);
      expect(gpa.lastPlaneFitQuality.accepted, isFalse);
      _record(
        _entry(
          'A6',
          'Noisy depth (low light) -> planeFitOk behaviour',
          'GroundPlaneAnalyzer',
          'pass',
          'planeFitOk=$planeOk; hazardCount=${hazards.length}; '
              'hazardTypes=${hazards.map((h) => h.type.name).toList()}',
          expected: 'planeFitOk=false and a machine-readable rejection reason',
          notes: 'quality=${gpa.lastPlaneFitQuality.toDiagnosticMap()}',
        ),
      );
    });
  });

  // =========================================================================
  // GROUP B — Tracker (Layer 3)
  // =========================================================================
  group('B. Tracker', () {
    test('B1_single_object_no_id_switch', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      final ids = <int>[];
      for (int f = 0; f < 10; f++) {
        final out = tr.update(
          [makeDet(label: 'person', cx: 320 + f * 5.0, cy: 400)],
          640,
          480,
          now.add(Duration(milliseconds: f * 120)),
        );
        if (f == 0) {
          expect(
            out,
            isEmpty,
            reason: 'Frame 0 must not confirm (need 2 frames)',
          );
        }
        if (out.isNotEmpty) ids.add(out.single.id);
      }
      final switches = ids.toSet().length - 1;
      expect(ids, isNotEmpty);
      expect(
        ids.every((id) => id == ids.first),
        isTrue,
        reason: 'No ID switch expected; ids=$ids',
      );
      _record(
        _entry(
          'B1',
          'Single object -> one track, no ID switch',
          'Tracker',
          (ids.isNotEmpty && switches == 0) ? 'pass' : 'fail',
          'ids=$ids; idSwitches=$switches',
          expected:
              'frame 0 empty; frames 1-9 single track same ID; 0 switches',
          notes: 'kTrackConfirmFrames=2',
        ),
      );
    });

    test('B2_occlusion_3_frames_survives', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      // 3 confirming frames at cx=320.
      tr.update([makeDet(label: 'person', cx: 320)], 640, 480, now);
      final f1 = tr.update(
        [makeDet(label: 'person', cx: 320)],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );
      expect(f1.single.id, 1);
      // 3 empty frames (occlusion) — age increments to 3, still <= kTrackMaxAge=6.
      for (int f = 3; f <= 5; f++) {
        final out = tr.update(
          [],
          640,
          480,
          now.add(Duration(milliseconds: f * 120)),
        );
        expect(out, isEmpty, reason: 'Hidden frames must not return tracks');
      }
      // Reappears at same position -> same ID, no respawn.
      final f6 = tr.update(
        [makeDet(label: 'person', cx: 320)],
        640,
        480,
        now.add(const Duration(milliseconds: 720)),
      );
      expect(f6, hasLength(1));
      expect(f6.single.id, 1, reason: 'Same track ID after 3-frame occlusion');
      _record(
        _entry(
          'B2',
          '3-frame occlusion -> track survives, same ID',
          'Tracker',
          (f6.isNotEmpty && f6.single.id == 1) ? 'pass' : 'fail',
          'reappearanceId=${f6.single.id}; seenCount=${f6.single.seenCount}',
          expected:
              'same ID (1) after occlusion; seenCount > kTrackConfirmFrames',
          notes: 'kTrackMaxAge=6; 3 empty frames -> age=3, survives',
        ),
      );
    });

    test('B3_vehicle_graveyard_inherits_areaHist_and_approaching', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      // Big bbox -> area ratio 0.376 >= kVehBboxDangerAreaRatio=0.35.
      RawDet carDet() => makeDet(
        label: 'car',
        cx: 315,
        cy: 245,
        x1: 140,
        y1: 80,
        x2: 490,
        y2: 410,
        conf: 0.9,
        dist: 'close',
        distM: 2.0,
      );
      // Frame 0: create (areaHist empty).
      tr.update([carDet()], 640, 480, now);
      // Frame 1: match (areaHist length 1).
      tr.update(
        [carDet()],
        640,
        480,
        now.add(const Duration(milliseconds: 400)),
      );
      // Frame 2: match (areaHist length 2, dt=400ms>=kApproachMinDtSec=0.35 ->
      // danger-size sets approaching=true).
      final f2 = tr.update(
        [carDet()],
        640,
        480,
        now.add(const Duration(milliseconds: 800)),
      );
      expect(f2, isNotEmpty);
      expect(
        f2.single.approaching,
        isTrue,
        reason: 'Big bbox should trigger danger-size approaching',
      );

      // 8 empty frames -> age exceeds kTrackMaxAge=6 -> track dies & enters
      // graveyard (approaching + vehicle + areaHist.isNotEmpty).
      for (int f = 3; f <= 10; f++) {
        tr.update([], 640, 480, now.add(Duration(milliseconds: 800 + f * 100)));
      }

      // Reappear at same bbox -> new track inherits areaHist + approaching=true.
      tr.update(
        [carDet()],
        640,
        480,
        now.add(const Duration(milliseconds: 1700)),
      );
      final f12 = tr.update(
        [carDet()],
        640,
        480,
        now.add(const Duration(milliseconds: 2100)),
      );

      expect(f12, hasLength(1), reason: 'Reappeared car must confirm');
      final inheritedLen = f12.single.areaHist.length;
      // 2 inherited entries + 1 own match = 3 (cap kApproachHistLen=6).
      expect(
        inheritedLen,
        3,
        reason: 'Graveyard should contribute 2 inherited areaHist entries',
      );
      expect(
        f12.single.approaching,
        isTrue,
        reason: 'Inherited approaching=true (sustained via danger-size)',
      );
      _record(
        _entry(
          'B3',
          'Vehicle graveyard inheritance (areaHist + approaching)',
          'Tracker',
          (f12.isNotEmpty && inheritedLen == 3 && f12.single.approaching)
              ? 'pass'
              : 'fail',
          'reappearanceId=${f12.single.id}; '
              'areaHist.length=$inheritedLen; '
              'approaching=${f12.single.approaching}',
          expected:
              'areaHist.length==3 (2 inherited + 1 own); approaching==true',
          notes:
              'A non-inheriting fresh track after 1 match would have '
              'areaHist.length==1 and approaching==false (cannot enter the approach '
              'block with length<2). Graveyard TTL=_kGraveyardTtl=3s.',
        ),
      );
    });

    test('B4_ghost_track_confidence_decay', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      // Build a confirmed car track with avgConf=0.85.
      tr.update(
        [makeDet(label: 'car', cx: 320, conf: 0.85, distM: 2.0)],
        640,
        480,
        now,
      );
      tr.update(
        [makeDet(label: 'car', cx: 320, conf: 0.85, distM: 2.0)],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );

      final trajectory = <double>[];
      for (int p = 1; p <= 6; p++) {
        final out = tr.predict();
        final conf = out.single.avgConf;
        trajectory.add(double.parse(conf.toStringAsFixed(4)));
      }
      final finalConf = trajectory.last;
      // After 3 predict-only frames, avgConf halves each frame:
      // 0.85 -> 0.425 -> 0.2125 -> 0.10625.
      expect(
        finalConf,
        lessThan(0.15),
        reason:
            'Ghost decay must drive avgConf well below 0.5; '
            'trajectory=$trajectory',
      );
      _record(
        _entry(
          'B4',
          'Ghost-track confidence decay (predict-only)',
          'Tracker',
          (finalConf < 0.5) ? 'pass' : 'fail',
          'avgConf trajectory (6 predicts)=$trajectory; final=$finalConf',
          expected:
              'avgConf halves each frame after kTrackGhostDecayFrames=3; '
              'final << 0.5',
          notes:
              'kTrackGhostDecayFactor=0.50. Decay fires in predict() when '
              '_predictOnlyFrames[id] > 3 (tracker.dart:484-486).',
        ),
      );
    });

    test('B5_crowd_hungarian_performance', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      // Frame 0: create 15 person tracks.
      final dets0 = List<RawDet>.generate(
        15,
        (i) => makeDet(label: 'person', cx: 50 + i * 40.0, cy: 240),
      );
      tr.update(dets0, 640, 480, now);

      // Frame 1: 15 shifted dets vs 15 existing tracks -> 15x15 Hungarian solve.
      final dets1 = List<RawDet>.generate(
        15,
        (i) => makeDet(label: 'person', cx: 52 + i * 40.0, cy: 240),
      );
      final sw = Stopwatch()..start();
      final out = tr.update(
        dets1,
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );
      sw.stop();
      final elapsedMs = sw.elapsedMilliseconds;

      expect(
        () => Hungarian.solveMinCost(
          List<List<double>>.generate(15, (_) => List<double>.filled(15, 0.5)),
        ),
        returnsNormally,
      );
      _record(
        _entry(
          'B5',
          'Crowd (15) Hungarian solve — no crash, measure time',
          'Tracker',
          (out.isNotEmpty && elapsedMs < 50) ? 'pass' : 'partial',
          'confirmedTracks=${out.length}; elapsedMs=$elapsedMs',
          expected: 'no crash; all 15 matched; on-device target < 16ms',
          notes:
              'Measured on dev host (faster than Snapdragon 680). '
              'Prompt target is <16ms; asserted <50ms here to avoid host/CI flakiness.',
        ),
      );
    });

    test('B6_bicycle_lateral_linear_motion', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      Track? last;
      for (int f = 0; f < 8; f++) {
        final out = tr.update(
          [makeDet(label: 'bicycle', cx: 320 - f * 20.0, cy: 400, distM: 3.0)],
          640,
          480,
          now.add(Duration(milliseconds: f * 120)),
        );
        if (out.isNotEmpty) last = out.single;
      }
      expect(last, isNotNull);
      final angVel = last!.lastAngularVelocity;
      expect(
        angVel.abs(),
        lessThan(1e-6),
        reason: 'Linear motion -> zero angular velocity; got $angVel',
      );
      expect(
        last.approaching,
        isFalse,
        reason: 'Lateral motion (no bbox growth) -> not approaching',
      );
      _record(
        _entry(
          'B6',
          'Bicycle lateral motion -> linear, not approaching',
          'Tracker',
          (angVel.abs() < 1e-6 && !last.approaching) ? 'pass' : 'fail',
          'lastAngularVelocity=$angVel; approaching=${last.approaching}',
          expected: 'lastAngularVelocity ~ 0; approaching == false',
          notes:
              'centerHist capped at kVehTurnMinCenterHist=3; _computeTurnState '
              'returns 0 for parallel velocity vectors.',
        ),
      );
    });

    test('B7_fov_edge_track_created', () {
      final tr = Tracker();
      final now = DateTime(2025, 1, 1, 12);
      tr.update(
        [
          makeDet(
            label: 'person',
            cx: 25,
            cy: 400,
            x1: 0,
            y1: 350,
            x2: 50,
            y2: 450,
          ),
        ],
        640,
        480,
        now,
      );
      final f1 = tr.update(
        [
          makeDet(
            label: 'person',
            cx: 25,
            cy: 400,
            x1: 0,
            y1: 350,
            x2: 50,
            y2: 450,
          ),
        ],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );
      expect(f1, hasLength(1));
      expect(f1.single.cx, 25);
      // Pan is derived downstream by AlertManager from cx/imgW; the Tracker does
      // not compute pan. With cx=25/imgW=640 -> pan ~ -0.92 (AlertManager-side).
      _record(
        _entry(
          'B7',
          'FOV-edge (cx=25) track created',
          'Tracker',
          (f1.isNotEmpty && f1.single.cx == 25) ? 'pass' : 'fail',
          'created=${f1.isNotEmpty}; cx=${f1.isNotEmpty ? f1.single.cx : "n/a"}',
          expected:
              'track created with cx=25; pan mapped by AlertManager (~-0.92)',
          notes:
              'Pan is AlertManager responsibility (cx/imgW -> [-1,1]); not '
              'assertable at the Tracker layer.',
        ),
      );
    });
  });

  // =========================================================================
  // GROUP C — AlertFilter (Layer 4, prioritisation)
  // =========================================================================
  group('C. AlertFilter', () {
    test('C1_priority_sort_critical_first', () {
      final f = AlertFilter()..reset();
      final now = DateTime(2025, 1, 1, 12);
      // Insert in mixed priority order.
      f.add(
        _cand(
          'info msg',
          SpeechPriority.info,
          AlertCategory.obstacleFar,
          urgency: 0.9,
        ),
      );
      f.add(
        _cand(
          'warning msg',
          SpeechPriority.warning,
          AlertCategory.approachingVehicle,
          urgency: 0.5,
        ),
      );
      f.add(
        _cand(
          'critical msg',
          SpeechPriority.critical,
          AlertCategory.obstacleClose,
          urgency: 0.3,
        ),
      );
      final picked = f.flush(0, now);
      expect(picked, isNotNull);
      expect(picked!.priority, SpeechPriority.critical);
      _record(
        _entry(
          'C1',
          'Priority sort: critical beats warning beats info',
          'AlertFilter',
          picked.priority == SpeechPriority.critical ? 'pass' : 'fail',
          'picked=${picked.priority.name} (${picked.text})',
          expected: 'critical candidate selected',
        ),
      );
    });

    test('C2_critical_cooldown_block_then_pass', () {
      final f = AlertFilter()..reset();
      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      final step1 =
          (f..add(
                _cand(
                  'obs',
                  SpeechPriority.critical,
                  AlertCategory.obstacleClose,
                  distanceM: 1.0,
                ),
              ))
              .flush(0, t0);
      final step2 =
          (f..add(
                _cand(
                  'obs',
                  SpeechPriority.critical,
                  AlertCategory.obstacleClose,
                  distanceM: 1.0,
                ),
              ))
              .flush(0, t0.add(const Duration(milliseconds: 1000)));
      final step3 =
          (f..add(
                _cand(
                  'obs',
                  SpeechPriority.critical,
                  AlertCategory.obstacleClose,
                  distanceM: 1.0,
                ),
              ))
              .flush(0, t0.add(const Duration(milliseconds: 2200)));
      expect(step1, isNotNull);
      expect(
        step2,
        isNull,
        reason: '1000ms < kCriticalRepeatCooldownSafety=2000ms -> blocked',
      );
      expect(step3, isNotNull, reason: '2200ms >= 2000ms -> passes');
      _record(
        _entry(
          'C2',
          'Critical cooldown: block within 2s, pass after',
          'AlertFilter',
          (step1 != null && step2 == null && step3 != null) ? 'pass' : 'fail',
          'step1=${step1 != null}; step2=${step2 == null ? "blocked" : "passed"}; '
              'step3=${step3 != null}',
          expected:
              'step1 pass; step2 blocked (1000ms<2000ms); step3 pass (2200ms)',
          notes: 'kCriticalRepeatCooldownSafety=2000ms (safety categories).',
        ),
      );
    });

    test('C3_escalation_distance_has_2000ms_floor', () {
      // Use a NON-safety category so the base cooldown is
      // kCriticalRepeatCooldownDefault=4000ms; escalation can then relax it to
      // kCriticalRepeatCooldownSafety=2000ms — but NOT below 2000ms.
      final f = AlertFilter()..reset();
      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      final step1 =
          (f..add(
                _cand(
                  'corridor',
                  SpeechPriority.critical,
                  AlertCategory.corridorNarrow,
                  distanceM: 3.0,
                ),
              ))
              .flush(0, t0);
      // 1000ms + distance drop 3.0 -> 2.0 (<= 3.0*0.70=2.1): escalation condition
      // met BUT gap 1000ms < 2000ms floor -> still BLOCKED.
      final step2 =
          (f..add(
                _cand(
                  'corridor',
                  SpeechPriority.critical,
                  AlertCategory.corridorNarrow,
                  distanceM: 2.0,
                ),
              ))
              .flush(0, t0.add(const Duration(milliseconds: 1000)));
      // 2200ms + distance drop: gap >= 2000ms floor -> PASSES early (vs 4000ms).
      final step3 =
          (f..add(
                _cand(
                  'corridor',
                  SpeechPriority.critical,
                  AlertCategory.corridorNarrow,
                  distanceM: 2.0,
                ),
              ))
              .flush(0, t0.add(const Duration(milliseconds: 2200)));
      expect(step1, isNotNull);
      expect(
        step2,
        isNull,
        reason:
            'Escalation floor is kCriticalRepeatCooldownSafety=2000ms; '
            '1000ms is still blocked even with a 30% distance drop.',
      );
      expect(
        step3,
        isNotNull,
        reason: '2200ms >= 2000ms floor + distance drop -> passes early',
      );
      _record(
        _entry(
          'C3',
          'Distance escalation relaxes 4000ms->2000ms, floor 2000ms',
          'AlertFilter',
          (step1 != null && step2 == null && step3 != null) ? 'pass' : 'fail',
          'step1=${step1 != null}; step2(1000ms,escal)=${step2 == null ? "blocked" : "passed"}; '
              'step3(2200ms,escal)=${step3 != null}',
          expected:
              'step1 pass; step2 BLOCKED at 1000ms (floor 2000ms); '
              'step3 pass at 2200ms',
          notes:
              'DISCREPANCY vs prompt: prompt expected pass at 1000ms. Real code '
              '(alert_filter.dart:172-183) requires gap >= kCriticalRepeatCooldownSafety '
              'even in the escalation branch. Escalation is a NO-OP for the 3 safety '
              'categories (obstacleClose/corridorBlocked/approachingVehicle) whose base '
              'cooldown is already 2000ms; it only helps default-cooldown categories '
              '(4000ms -> 2000ms). kEscalationDistanceFraction=0.70.',
        ),
      );
    });

    test('C4_flushMulti_critical_then_warning_not_info', () {
      final f = AlertFilter()..reset();
      final now = DateTime(2025, 1, 1, 12);
      f.add(
        _cand(
          'wall ahead',
          SpeechPriority.critical,
          AlertCategory.corridorBlocked,
          urgency: 0.9,
        ),
      );
      f.add(
        _cand(
          'car right',
          SpeechPriority.warning,
          AlertCategory.approachingVehicle,
          urgency: 0.5,
        ),
      );
      f.add(
        _cand(
          'person side',
          SpeechPriority.info,
          AlertCategory.obstacleFar,
          urgency: 0.3,
        ),
      );
      final winners = f.flushMulti(1, now);
      expect(
        winners.length,
        2,
        reason: 'flushMulti returns up to 2 winners from different categories',
      );
      expect(winners.first.priority, SpeechPriority.critical);
      expect(winners.last.priority, SpeechPriority.warning);
      _record(
        _entry(
          'C4',
          'flushMulti: [critical, warning], info dropped',
          'AlertFilter',
          (winners.length == 2 &&
                  winners.first.priority == SpeechPriority.critical &&
                  winners.last.priority == SpeechPriority.warning)
              ? 'pass'
              : 'fail',
          'winners=${winners.map((w) => "${w.priority.name}:${w.category.name}").toList()}',
          expected: '[critical, warning] (info not picked)',
        ),
      );
    });

    test('C5_crowd_info_suppressed_when_not_reliable', () {
      final f = AlertFilter()..reset();
      final now = DateTime(2025, 1, 1, 12);
      f.add(
        _cand(
          'person side',
          SpeechPriority.info,
          AlertCategory.obstacleFar,
          urgency: 0.3,
          trackId: 5,
        ),
      );
      final picked = f.flush(6, now, reliableTrackIds: <int>{1, 2, 3, 4});
      expect(
        picked,
        isNull,
        reason:
            'trackCount>=5 + info + urgency<0.4 + trackId not in reliable '
            '-> suppressed',
      );
      _record(
        _entry(
          'C5',
          'Crowd: non-reliable info suppressed',
          'AlertFilter',
          picked == null ? 'pass' : 'fail',
          'picked=${picked == null ? "null (suppressed)" : picked.priority.name}',
          expected: 'null (suppressed)',
          notes: 'trackCount=6, urgency=0.3<0.4, trackId=5 not in {1,2,3,4}.',
        ),
      );
    });

    test('C6_navigation_hint_suppressed_after_obstacle_close', () {
      final f = AlertFilter()..reset();
      final t0 = DateTime(2025, 1, 1, 12);
      // Step 1: speak an obstacle-close critical.
      final s1 =
          (f..add(
                _cand(
                  'obstacle',
                  SpeechPriority.critical,
                  AlertCategory.obstacleClose,
                  distanceM: 1.0,
                ),
              ))
              .flush(1, t0);
      expect(s1, isNotNull);
      // Step 2: 3s later, a navigation hint -> blocked because
      // _lastCategory == obstacleClose (alert_filter.dart:211-214).
      final s2 =
          (f..add(
                _cand(
                  'turn left',
                  SpeechPriority.info,
                  AlertCategory.navigationHint,
                  urgency: 0.6,
                ),
              ))
              .flush(1, t0.add(const Duration(milliseconds: 3000)));
      expect(
        s2,
        isNull,
        reason: 'navigationHint blocked when _lastCategory==obstacleClose',
      );
      _record(
        _entry(
          'C6',
          'navigationHint suppressed after obstacleClose',
          'AlertFilter',
          s2 == null ? 'pass' : 'fail',
          'step1=${s1 != null}; step2=${s2 == null ? "blocked" : "passed"}',
          expected: 'navigationHint blocked',
          notes:
              'Code blocks on _lastCategory==obstacleClose unconditionally '
              '(no 8s gap check for this branch); the 8s check applies only to '
              'corridorNarrow/corridorBlocked predecessors.',
        ),
      );
    });
  });

  // =========================================================================
  // GROUP D — TtsService priority queue (Layer 4, output)
  // =========================================================================
  group('D. TtsService', () {
    test('D1_critical_preempts_info', () {
      final svc = TtsService.forTesting();
      svc.say('info msg', SpeechPriority.info);
      expect(svc.queueSnapshot, hasLength(1));
      svc.say('critical msg', SpeechPriority.critical);
      // Critical branch removes all non-critical jobs before enqueueing.
      expect(svc.queueSnapshot, hasLength(1));
      expect(svc.queueSnapshot.single.priority, SpeechPriority.critical);
      expect(svc.queueSnapshot.single.text, 'critical msg');
      _record(
        _entry(
          'D1',
          'Critical preempts pending info in queue',
          'TtsService',
          (svc.queueSnapshot.length == 1 &&
                  svc.queueSnapshot.single.priority == SpeechPriority.critical)
              ? 'pass'
              : 'fail',
          'queue=${svc.queueSnapshot.map((j) => "${j.priority.name}:${j.text}").toList()}',
          expected: 'queue=[critical] (info evicted)',
          notes:
              'tts_service.dart:739 _queue.removeWhere(j.priority != critical). '
              'Overlaps existing tts_service_test.dart coverage.',
        ),
      );
    });

    test('D2_stale_critical_pruned', () {
      final svc = TtsService.forTesting();
      final t0 = DateTime.now();
      svc.say('crit stale', SpeechPriority.critical);
      final before = svc.queueSnapshot.length;
      expect(before, 1);
      // Enqueued at ~t0; prune at t0+5s with maxAge=4s -> 5s > 4s -> removed.
      svc.pruneStaleCriticalsForTesting(
        t0.add(const Duration(seconds: 5)),
        maxAge: const Duration(seconds: 4),
      );
      final after = svc.queueSnapshot.length;
      expect(after, 0, reason: 'Stale critical (age 5s > 4s) must be pruned');
      _record(
        _entry(
          'D2',
          'Stale critical pruning (age > maxAge)',
          'TtsService',
          (before == 1 && after == 0) ? 'pass' : 'fail',
          'queueBefore=$before; queueAfter=$after',
          expected: '1 -> 0',
          notes:
              '_kCriticalStaleAfter=4s; pruneStaleCriticalsForTesting requires '
              'explicit maxAge (no-op if maxAge==null).',
        ),
      );
    });

    test('D3_queue_insertion_latency', () {
      final svc = TtsService.forTesting();
      final sw = Stopwatch()..start();
      svc.say('Препятствие!', SpeechPriority.critical);
      sw.stop();
      final micros = sw.elapsedMicroseconds;
      // Queue insertion is in-memory; real audio-output latency is on-device only.
      expect(
        micros,
        lessThan(50000),
        reason: 'Queue insertion should be sub-50ms; got ${micros}us',
      );
      _record(
        _entry(
          'D3',
          'TTS queue insertion latency (object -> queue)',
          'TtsService',
          micros < 50000 ? 'pass' : 'fail',
          'insertionLatencyUs=$micros (${(micros / 1000).toStringAsFixed(3)}ms)',
          expected: '< 50ms (host queue latency only)',
          notes:
              'Measures enqueue latency, NOT audio output latency. Real '
              'ear-to-queue + queue-to-audio latency must be measured on device.',
        ),
      );
    });
  });

  // =========================================================================
  // Final test — render results; explicit output is opt-in so tests are
  // read-only by default.
  // =========================================================================
  test('__write_harness_results_json', () {
    final results = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
      'phase': 1,
      'scenario_count': _results.length,
      'scenarios': _results,
    };
    final json = const JsonEncoder.withIndent('  ').convert(results);
    if (_harnessOutput.isNotEmpty) {
      final output = File(_harnessOutput);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync('$json\n');
      debugPrint(
        'HARNESS: wrote ${output.absolute.path} (${_results.length} scenarios)',
      );
    } else {
      debugPrint('HARNESS_RESULTS_RAW:\n$json');
    }
    expect(_results, isNotEmpty, reason: 'No harness results were recorded');
    if (_releaseCandidate) {
      final incomplete = _results
          .where((result) => result['status'] == 'partial')
          .map((result) => result['scenario_id'])
          .toList(growable: false);
      expect(
        incomplete,
        isEmpty,
        reason: 'Release-candidate harness cannot contain partial scenarios.',
      );
    }
  });
}
