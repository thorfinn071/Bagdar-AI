import 'dart:math' as math;

import '../models/constants.dart';
import '../models/strings.dart';
import '../services/settings_service.dart';
import '../../tracker/track.dart';



double _currentFocalLength = 1006.0;

double get currentFocalLength => _currentFocalLength;

void loadFocalLength() {
  final saved = Settings.instance.focalLength;
  if (saved > 0) _currentFocalLength = saved;
}

Future<void> calibrateFocalLength(
    String label, double x1, double y1, double x2, double y2,
    double actualDistanceMeters) async {
  final dim = kRealDims[label];
  if (dim == null) return;

  final pixelSize = dim.type == 'height'
      ? math.max(1.0, y2 - y1)
      : math.max(1.0, x2 - x1);

  final newFocal = (actualDistanceMeters * pixelSize) / dim.meters;
  _currentFocalLength = newFocal;

  await Settings.instance.setFocalLength(newFocal);
}

const double _kPersonShoulderWidth = 0.45;

double focalDistM(String label, double x1, double y1, double x2, double y2) {
  final bw = math.max(1.0, x2 - x1);
  final bh = math.max(1.0, y2 - y1);
  final fl  = _currentFocalLength;

  if (label == 'person') {
    final distByHeight = (1.70 * fl) / bh;
    final distByWidth  = (_kPersonShoulderWidth * fl) / bw;
    if (distByWidth > distByHeight * 3.0) return distByHeight;
    return math.min(distByHeight, distByWidth);
  }

  final dim = kRealDims[label];
  if (dim == null) return -1.0;
  final pixelSize = dim.type == 'height' ? bh : bw;
  return (dim.meters * fl) / pixelSize;
}

double smoothDistM(double prev, double raw, {double alpha = 0.25}) {
  if (raw <= 0) return prev;
  if (prev <= 0) return raw;
  return prev * (1.0 - alpha) + raw * alpha;
}

String distByBox(
    double areaRatio, double heightRatio, double bottomRatio) {
  if (areaRatio < kAbsFarArea && heightRatio < kAbsFarHeight) return 'far';
  if (areaRatio < kFarAreaMax && heightRatio < kFarHeightMax) return 'far';
  final score =
      areaRatio * 0.70 + heightRatio * 0.25 + bottomRatio * 0.05;
  if (score >= kDistVeryCloseT) return 'very close';
  if (score >= kDistCloseT)     return 'close';
  return 'far';
}

String distMToCategory(double distM, String fallback) {
  if (distM < 0) return fallback;
  if (distM <= 1.5) return 'very close';
  if (distM <= 3.5) return 'close';
  return 'far';
}



String posFromCx(double cx, double imgW) {
  if (imgW <= 0) return 'center';
  final n = cx / imgW;
  if (n < 0.35) return 'left';
  if (n > 0.65) return 'right';
  return 'center';
}

String clockDir(double x1, double x2, double imgW) {
  if (imgW <= 0) return S.dir('forward');
  final n = ((x1 + x2) / 2.0) / imgW;
  if (n < 0.10) return S.dir('9');
  if (n < 0.22) return S.dir('10');
  if (n < 0.38) return S.dir('11');
  if (n < 0.62) return S.dir('forward');
  if (n < 0.78) return S.dir('1');
  if (n < 0.90) return S.dir('2');
  return S.dir('3');
}



double threatScore(
    String label, String pos, String dist, double areaRatio) {
  final w            = kClassWeight[label] ?? 1.0;
  final distFactor   = dist == 'very close' ? 2.2 : dist == 'close' ? 1.5 : 1.0;
  final sizeFactor   = 0.7 + 2.2 * math.sqrt(areaRatio);
  final centerFactor = pos == 'center' ? 1.25 : 1.0;
  return w * distFactor * sizeFactor * centerFactor;
}



(String, double, double) bestDirectionHint(
    List<Track> tracks, double imgW, double imgH) {
  if (tracks.isEmpty) return ('forward', 0.0, 0.0);

  final frameArea  = imgW * imgH;
  final zoneThreat = List<double>.filled(kZoneCount, 0.0);

  for (final t in tracks) {
    final cxNorm = (t.cx / imgW).clamp(0.0, 0.9999);
    final zi     = (cxNorm * kZoneCount).floor();
    final bw     = t.x2 - t.x1;
    final bh     = t.y2 - t.y1;
    final ar     = frameArea > 0 ? (bw * bh) / frameArea : 0.0;
    final pos    = posFromCx(t.cx, imgW);
    zoneThreat[zi] += threatScore(t.label, pos, t.dist, ar);
  }

  final bestI =
      List.generate(kZoneCount, (i) => i)
          .reduce((a, b) => zoneThreat[a] <= zoneThreat[b] ? a : b);
  const midI   = kZoneCount ~/ 2;
  final bestTh = zoneThreat[bestI];
  final centTh = zoneThreat[midI];

  if (bestI == midI) return ('forward', centTh, bestTh);

  final String hint;
  if (bestI < midI) {
    hint = bestI == 0
        ? S.get('nav_left')
        : S.get('nav_slight_left');
  } else {
    hint = bestI == kZoneCount - 1
        ? S.get('nav_right')
        : S.get('nav_slight_right');
  }
  return (hint, centTh, bestTh);
}



double _getObstacleWeight(String label) {
  switch (label) {
    case 'person':     return 1.0;
    case 'car':
    case 'bus':
    case 'truck':      return 1.5;
    case 'bicycle':
    case 'motorcycle': return 1.2;
    default:           return 0.7;
  }
}

(double, String)? findFreeCorridor(
    List<Track> tracks, double imgW, double imgH) {
  if (imgW <= 0 || imgH <= 0) return null;

  final groundY = imgH * 0.75;
  final segments = <(double, double)>[];

  for (final t in tracks) {
    final isRelevant = t.y2 >= groundY || (t.distM > 0 && t.distM < 3.0);
    if (!isRelevant) continue;

    final weight = _getObstacleWeight(t.label);
    final expand = 20.0 * weight;
    final x1 = (t.x1 - expand).clamp(0.0, imgW);
    final x2 = (t.x2 + expand).clamp(0.0, imgW);
    segments.add((x1, x2));
  }

  if (segments.isEmpty) return null;

  segments.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(double, double)>[];
  for (final s in segments) {
    if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
      merged[merged.length - 1] =
          (merged.last.$1, math.max(merged.last.$2, s.$2));
    } else {
      merged.add(s);
    }
  }

  final gaps = <(double, double)>[];
  double prev = 0;
  for (final (a, b) in merged) {
    if (a > prev) gaps.add((prev, a));
    prev = b;
  }
  if (prev < imgW) gaps.add((prev, imgW));
  if (gaps.isEmpty) return null;

  double gapScore((double, double) gap) {
    final width = gap.$2 - gap.$1;
    final center = (gap.$1 + gap.$2) / 2.0;
    final distFromCenter = (center - imgW / 2.0).abs();
    return width - distFromCenter * 0.5;
  }

  final best = gaps.reduce((a, b) => gapScore(a) >= gapScore(b) ? a : b);
  final widthPx = best.$2 - best.$1;
  const scale = 4.0;
  final widthM = (widthPx / imgW) * scale;

  final centerNorm = (best.$1 + best.$2) / 2.0 / imgW;
  final pos = centerNorm < 0.35 ? 'left' : centerNorm > 0.65 ? 'right' : 'center';

  return (widthM, pos);
}
