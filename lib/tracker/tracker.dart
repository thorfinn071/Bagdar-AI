import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/constants.dart';
import '../services/tts_service.dart';
import '../utils/distance_utils.dart' show smoothDistM;
import 'appearance.dart';
import 'hungarian.dart';
import 'raw_det.dart';
import 'track.dart';

bool isVehicle(String label) =>
    const {'car', 'bus', 'truck', 'motorcycle', 'bicycle'}.contains(label);

bool isPedestrian(String label) =>
    const {'person', 'dog', 'cat'}.contains(label);

class Tracker {
  
  
  
  
  
  static const double _kIouWeight = 0.6;
  
  
  
  static const double _kAppearanceBlend = 0.3;

  int _nextId = 1;
  final Map<int, Track> _tracks = {};
  int _predictTick = 0;

  TtsService? ttsService;

  
  
  
  
  
  
  bool weatherDegraded = false;
  static const double _kPedWeatherBoost = 1.3;

  List<Track> update(List<RawDet> dets, int imgW, int imgH, DateTime now) {
    _predictTick = 0;
    for (final t in _tracks.values) {
      t.age++;
      t.kalman.predict();
    }

    final unmatched = <RawDet>[];
    final trackList = _tracks.values.toList(growable: false);

    if (trackList.isEmpty || dets.isEmpty) {
      unmatched.addAll(dets);
    } else {
      
      
      
      
      
      final cost = List<List<double>>.generate(
        dets.length,
        (_) => List<double>.filled(trackList.length, Hungarian.kForbidden),
        growable: false,
      );
      for (int i = 0; i < dets.length; i++) {
        final det = dets[i];
        for (int j = 0; j < trackList.length; j++) {
          final t = trackList[j];
          if (t.label != det.label) continue;
          final score = _combinedScore(t, det);
          if (score <= 0.0) continue;
          cost[i][j] = 1.0 - score;
        }
      }

      final assignment = Hungarian.solveMinCost(
        cost,
        maxAssignableCost: 1.0 - kIoUMatchThreshold,
      );

      for (int i = 0; i < dets.length; i++) {
        final j = assignment[i];
        if (j < 0) {
          unmatched.add(dets[i]);
          continue;
        }
        _applyMatch(trackList[j], dets[i], imgW, imgH, now);
      }
    }

    for (final det in unmatched) {
      final t = Track(
        id: _nextId++,
        label: det.label,
        cx: det.cx,
        cy: det.cy,
        x1: det.x1,
        y1: det.y1,
        x2: det.x2,
        y2: det.y2,
        dist: det.dist,
        distM: det.distM,
        initialConf: det.conf,
      );
      t.distHist.addLast(det.dist);
      
      
      
      
      
      t.centerHist.addLast((now, det.cx, det.cy));
      if (det.appearance != null) {
        t.appearance = Float32List.fromList(det.appearance!);
      }
      if (_shouldFastTrack(det)) {
        t.fastTrack = true;
        t.nearFrameCount = 1;
        if (det.conf >= kMinAlertConf) t.reliableFrames = 1;
      }
      _tracks[t.id] = t;
    }

    _tracks.forEach((id, t) {
      if (t.age > kTrackMaxAge) ttsService?.evictTrack(id);
    });
    _tracks.removeWhere((_, t) => t.age > kTrackMaxAge);

    return _tracks.values
        .where(
          (t) =>
              t.age == 0 && (t.seenCount >= kTrackConfirmFrames || t.fastTrack),
        )
        .toList();
  }

  
  
  
  double _combinedScore(Track t, RawDet det) {
    final iou = t.kalman.matchScore(det);
    final tHist = t.appearance;
    final dHist = det.appearance;
    if (tHist == null || dHist == null) return iou;
    final sim = Appearance.similarity(tHist, dHist);
    return iou * _kIouWeight + sim * (1.0 - _kIouWeight);
  }

  void _applyMatch(
    Track t,
    RawDet det,
    int imgW,
    int imgH,
    DateTime now,
  ) {
    t.kalman.update(det);
    t.age = 0;
    t.seenCount = math.min(9999, t.seenCount + 1);
    if (t.seenCount >= kTrackConfirmFrames) t.fastTrack = false;
    t.cx = det.cx;
    t.cy = det.cy;
    t.x1 = det.x1;
    t.y1 = det.y1;
    t.x2 = det.x2;
    t.y2 = det.y2;
    t.avgConf = t.avgConf == 0.0
        ? det.conf
        : t.avgConf * (1.0 - kConfEmaAlpha) + det.conf * kConfEmaAlpha;

    
    
    
    
    
    t.centerHist.addLast((now, det.cx, det.cy));
    while (t.centerHist.length > kVehTurnMinCenterHist) {
      t.centerHist.removeFirst();
    }
    final turnState = _computeTurnState(t.centerHist);
    t.lastAngularVelocity = turnState.angularVelocity;
    t.turning = turnState.turning;

    
    
    
    if (det.appearance != null) {
      final existing = t.appearance;
      if (existing == null) {
        t.appearance = Float32List.fromList(det.appearance!);
      } else {
        t.appearance = Appearance.blend(
          existing,
          det.appearance!,
          alpha: _kAppearanceBlend,
        );
      }
    }

    if (det.conf >= kMinAlertConf) {
      t.reliableFrames = math.min(999, t.reliableFrames + 1);
    } else {
      t.reliableFrames = 0;
    }

    t.distM = smoothDistM(t.distM, det.distM);
    t.distHist.addLast(det.dist);
    if (t.distHist.length > 5) t.distHist.removeFirst();
    t.dist = _majorityDist(t.distHist);
    final rawDist = det.dist;
    
    if (rawDist == 'very close' || rawDist == 'close') {
      if (t.nearFrameCount == 0) {
        t.lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
      }
      t.nearFrameCount = math.min(999, t.nearFrameCount + 1);
    } else {
      if (t.nearFrameCount > 0) {
        ttsService?.evictTrack(t.id);
      }
      t.nearFrameCount = 0;
    }

    final frameArea = imgW * imgH;
    if (frameArea > 0) {
      final bw = det.x2 - det.x1;
      final bh = det.y2 - det.y1;
      final ar = (bw * bh) / frameArea;

      t.areaHist.addLast((now, ar));
      t.heightHist.addLast((now, bh / imgH));
      if (t.areaHist.length > kApproachHistLen) t.areaHist.removeFirst();
      if (t.heightHist.length > kApproachHistLen) t.heightHist.removeFirst();

      t.approaching = false;
      t.dynamicThreat = false;
      if (t.areaHist.length >= 2) {
        final dt =
            t.areaHist.last.$1.difference(t.areaHist.first.$1).inMilliseconds /
                1000.0;
        if (dt >= kApproachMinDtSec) {
          final ar0 = t.areaHist.first.$2;
          final ar1 = t.areaHist.last.$2;
          final h0 = t.heightHist.first.$2;
          final h1 = t.heightHist.last.$2;
          final areaRate = (ar1 - ar0) / dt;
          final heightRate = (h1 - h0) / dt;

          if (isVehicle(t.label)) {
            
            
            
            
            final closeRange = t.distM > 0 && t.distM <= 4.0;
            
            
            
            
            
            
            
            final turningNear = t.turning &&
                t.distM > 0 &&
                t.distM <= kVehTurnDistThreshold;
            double areaT = kVehApproachAreaRateT;
            double heightT = kVehApproachHeightRateT;
            if (turningNear) {
              areaT = math.min(areaT, kPedApproachAreaRateT);
              heightT = math.min(heightT, kPedApproachHeightRateT);
            }
            if (closeRange) {
              areaT *= 0.6;
              heightT *= 0.6;
            }
            if (areaRate >= areaT || heightRate >= heightT) {
              t.approaching = true;
            }
          } else if (isPedestrian(t.label)) {
            
            
            
            
            
            final areaT = weatherDegraded
                ? kPedApproachAreaRateT * _kPedWeatherBoost
                : kPedApproachAreaRateT;
            final heightT = weatherDegraded
                ? kPedApproachHeightRateT * _kPedWeatherBoost
                : kPedApproachHeightRateT;
            if (areaRate >= areaT || heightRate >= heightT) {
              t.approaching = true;
            }
          }

          if (areaRate >= kPedApproachAreaRateT ||
              heightRate >= kPedApproachHeightRateT) {
            t.dynamicThreat = true;
          }
        }
      }
    }
  }

  static bool _shouldFastTrack(RawDet det) {
    if (det.conf < 0.60) return false;
    if (det.dist != 'very close' && det.dist != 'close') return false;
    if (det.distM <= 0) return false;
    
    
    
    
    
    final isLightVehicle =
        det.label == 'bicycle' || det.label == 'motorcycle';
    if (det.dist == 'close' && !isLightVehicle) return false;
    final maxDist = isLightVehicle ? 5.0 : 1.5;
    if (det.distM > maxDist) return false;
    return true;
  }

  List<Track> predict() {
    _predictTick++;
    final shouldAge = _predictTick >= 4;
    if (shouldAge) _predictTick = 0;

    for (final t in _tracks.values) {
      if (shouldAge) t.age++;
      t.kalman.predict();
      final pBox = t.kalman.getPredictedBox();
      t.cx = (pBox[0] + pBox[2]) / 2;
      t.cy = (pBox[1] + pBox[3]) / 2;
      t.x1 = pBox[0];
      t.y1 = pBox[1];
      t.x2 = pBox[2];
      t.y2 = pBox[3];
    }

    _tracks.forEach((id, t) {
      if (t.age > kTrackMaxAge) ttsService?.evictTrack(id);
    });
    _tracks.removeWhere((_, t) => t.age > kTrackMaxAge);

    return _tracks.values.toList();
  }

  void clear() {
    _tracks.clear();
    _predictTick = 0;
  }

  
  
  
  
  
  static ({bool turning, double angularVelocity}) _computeTurnState(
    ListQueue<(DateTime, double, double)> hist,
  ) {
    if (hist.length < kVehTurnMinCenterHist) {
      return (turning: false, angularVelocity: 0.0);
    }
    final p0 = hist.elementAt(0);
    final p1 = hist.elementAt(1);
    final p2 = hist.elementAt(2);

    final v1x = p1.$2 - p0.$2;
    final v1y = p1.$3 - p0.$3;
    final v2x = p2.$2 - p1.$2;
    final v2y = p2.$3 - p1.$3;

    final d1 = math.sqrt(v1x * v1x + v1y * v1y);
    final d2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (d1 < kVehTurnMinDisplacementPx || d2 < kVehTurnMinDisplacementPx) {
      return (turning: false, angularVelocity: 0.0);
    }

    
    
    
    final dtSec = p2.$1.difference(p1.$1).inMicroseconds / 1e6;
    if (dtSec <= 0.05 || dtSec >= 1.0) {
      return (turning: false, angularVelocity: 0.0);
    }

    
    
    final a1 = math.atan2(v1y, v1x);
    final a2 = math.atan2(v2y, v2x);
    var dA = a2 - a1;
    while (dA > math.pi) {
      dA -= 2 * math.pi;
    }
    while (dA <= -math.pi) {
      dA += 2 * math.pi;
    }
    final angVel = dA / dtSec;

    
    
    
    final cross = v1x * v2y - v1y * v2x;
    final d1cubed = d1 * d1 * d1;
    final curvature = cross.abs() / d1cubed;

    final turning = angVel.abs() > kVehTurnAngVelThreshold &&
        curvature > kVehTurnCurvatureThreshold;
    return (turning: turning, angularVelocity: angVel);
  }

  static String _majorityDist(ListQueue<String> q) {
    if (q.isEmpty) return 'far';
    final counts = <String, int>{};
    for (final s in q) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
