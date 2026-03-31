import 'dart:collection';
import 'dart:math' as math;
import '../models/constants.dart';
import '../services/tts_service.dart';
import '../utils/distance_utils.dart' show smoothDistM;
import 'raw_det.dart';
import 'track.dart';

bool isVehicle(String label) =>
    const {'car', 'bus', 'truck', 'motorcycle', 'bicycle'}.contains(label);

bool isPedestrian(String label) =>
    const {'person', 'dog', 'cat'}.contains(label);

class Tracker {
  int _nextId = 1;
  final Map<int, Track> _tracks = {};

  TtsService? ttsService;

  List<Track> update(
      List<RawDet> dets, int imgW, int imgH, DateTime now) {
    for (final t in _tracks.values) {
      t.age++;
      t.kalman.predict();
    }

    final unmatched    = <RawDet>[];
    final usedTrackIds = <int>{};

    for (final det in dets) {
      int    bestId  = -1;
      double bestIou = kIoUMatchThreshold;

      final detArea = (det.x2 - det.x1) * (det.y2 - det.y1);

      for (final t in _tracks.values) {
        if (t.label != det.label) continue;
        if (usedTrackIds.contains(t.id)) continue;

        final pBox = t.kalman.getPredictedBox();
        final pArea = (pBox[2] - pBox[0]) * (pBox[3] - pBox[1]);

        final ix1 = math.max(det.x1, pBox[0]);
        final iy1 = math.max(det.y1, pBox[1]);
        final ix2 = math.min(det.x2, pBox[2]);
        final iy2 = math.min(det.y2, pBox[3]);

        if (ix2 > ix1 && iy2 > iy1) {
          final iArea = (ix2 - ix1) * (iy2 - iy1);
          final iou = iArea / (detArea + pArea - iArea);
          if (iou > bestIou) {
            bestIou = iou;
            bestId  = t.id;
          }
        }
      }

      if (bestId >= 0) {
        usedTrackIds.add(bestId);
        final t = _tracks[bestId]!;
        t.kalman.update(det);
        t.age       = 0;
        t.seenCount = math.min(9999, t.seenCount + 1);
        t.cx = det.cx; t.cy = det.cy;
        t.x1 = det.x1; t.y1 = det.y1; t.x2 = det.x2; t.y2 = det.y2;
        t.avgConf = t.avgConf == 0.0
            ? det.conf
            : t.avgConf * (1.0 - kConfEmaAlpha) + det.conf * kConfEmaAlpha;

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

          t.areaHist.add((now, ar));
          t.heightHist.add((now, bh / imgH));
          if (t.areaHist.length > kApproachHistLen)   t.areaHist.removeAt(0);
          if (t.heightHist.length > kApproachHistLen) t.heightHist.removeAt(0);

          t.approaching = false;
          if (t.areaHist.length >= 2) {
            final dt = t.areaHist.last.$1
                    .difference(t.areaHist.first.$1)
                    .inMilliseconds /
                1000.0;
            if (dt >= kApproachMinDtSec) {
              final ar0 = t.areaHist.first.$2;
              final ar1 = t.areaHist.last.$2;
              final h0  = t.heightHist.first.$2;
              final h1  = t.heightHist.last.$2;
              final areaRate   = (ar1 - ar0) / dt;
              final heightRate = (h1  - h0)  / dt;

              if (isVehicle(t.label)) {
                if (areaRate   >= kVehApproachAreaRateT ||
                    heightRate >= kVehApproachHeightRateT) {
                  t.approaching = true;
                }
              } else if (isPedestrian(t.label)) {
                if (areaRate   >= kPedApproachAreaRateT ||
                    heightRate >= kPedApproachHeightRateT) {
                  t.approaching = true;
                }
              }
            }
          }
        }
      } else {
        unmatched.add(det);
      }
    }

    for (final det in unmatched) {
      final t = Track(
        id:          _nextId++,
        label:       det.label,
        cx: det.cx,  cy: det.cy,
        x1: det.x1,  y1: det.y1,  x2: det.x2,  y2: det.y2,
        dist:        det.dist,
        distM:       det.distM,
        initialConf: det.conf,
      );
      t.distHist.addLast(det.dist);
      _tracks[t.id] = t;
    }

    _tracks.forEach((id, t) {
      if (t.age > kTrackMaxAge) ttsService?.evictTrack(id);
    });
    _tracks.removeWhere((_, t) => t.age > kTrackMaxAge);

    return _tracks.values
        .where((t) => t.age == 0 && t.seenCount >= kTrackConfirmFrames)
        .toList();
  }

  void clear() => _tracks.clear();

  static String _majorityDist(ListQueue<String> q) {
    final counts = <String, int>{};
    for (final s in q) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }
}
