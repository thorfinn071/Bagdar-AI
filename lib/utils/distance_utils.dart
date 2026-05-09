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
  String label,
  double x1,
  double y1,
  double x2,
  double y2,
  double actualDistanceMeters,
) async {
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
  final fl = _currentFocalLength;

  if (label == 'person') {
    final distByHeight = (1.70 * fl) / bh;
    final distByWidth = (_kPersonShoulderWidth * fl) / bw;
    if(distByWidth>distByHeight*3.0) return distByHeight;
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

class DistanceCrossCheck {
  final double adjustedM;
  final bool disagreement;
  const DistanceCrossCheck(this.adjustedM, this.disagreement);
}

DistanceCrossCheck crossCheckDistance({
  required double bboxM,
  required double midasRelative,
  required bool isCalibrated,
  double trustWeight = 0.5,
}) {
  if (bboxM <= 0) return DistanceCrossCheck(bboxM, false);

  if (midasRelative <= 0) {
    return DistanceCrossCheck(bboxM, false);
  }

  if (!isCalibrated) {
    return DistanceCrossCheck(bboxM, false);
  }

  final midasMetric = midasRelative * _currentFocalLength / 500.0;
  if (midasMetric <= 0) return DistanceCrossCheck(bboxM, false);

  final relDiff = (bboxM - midasMetric).abs() / bboxM;
  if (relDiff > 0.5) {
    final blended = bboxM * (1.0 - trustWeight) + midasMetric * trustWeight;
    return DistanceCrossCheck(blended, true);
  }
  return DistanceCrossCheck(bboxM, false);
}

String distByBox(double areaRatio, double heightRatio, double bottomRatio) {
  if (areaRatio < kAbsFarArea && heightRatio < kAbsFarHeight) return 'far';
  if (areaRatio < kFarAreaMax && heightRatio < kFarHeightMax) return 'far';
  final score = areaRatio * 0.70 + heightRatio * 0.25 + bottomRatio * 0.05;
  if (score >= kDistVeryCloseT) return 'very close';
  if (score >= kDistCloseT) return 'close';
  return 'far';
}

String distMToCategory(double distM, String fallback) {
  if (distM < 0) return fallback;
  if (distM <= 1.5) return 'very close';
  if (distM <= 3.5) return 'close';
  return 'far';
}

double visibleXFraction(
  double cx,
  double imgW, {
  double? imgH,
  double? viewportAspect,
}) {
  if (imgW <= 0) return 0.5;
  final raw = ((cx / imgW).clamp(0.0, 0.9999)).toDouble();
  if (imgH == null ||
      imgH <= 0 ||
      viewportAspect == null ||
      viewportAspect <= 0) {
    return raw;
  }
  final sourceAspect = imgW / imgH;
  if (viewportAspect >= sourceAspect) return raw;
  final visibleWidth = imgH * viewportAspect;
  final cropX = (imgW - visibleWidth) / 2.0;
  return (((cx - cropX) / visibleWidth).clamp(0.0, 0.9999)).toDouble();
}

String posFromCx(
  double cx,
  double imgW, {
  double? imgH,
  double? viewportAspect,
}) {
  final n = visibleXFraction(
    cx,
    imgW,
    imgH: imgH,
    viewportAspect: viewportAspect,
  );
  if (n < 0.35) return 'left';
  if (n > 0.65) return 'right';
  return 'center';
}

int zoneIndexFromCx(
  double cx,
  double imgW, {
  double? imgH,
  double? viewportAspect,
}) {
  if (imgW <= 0) return kZoneCount ~/ 2;
  final normalized = visibleXFraction(
    cx,
    imgW,
    imgH: imgH,
    viewportAspect: viewportAspect,
  );
  return (normalized * kZoneCount).floor();
}

String clockDir(
  double x1,
  double x2,
  double imgW, {
  double? imgH,
  double? viewportAspect,
  bool forAlert = false,
}) {
  String d(String key) => forAlert ? S.alertDir(key) : S.dir(key);
  if (imgW <= 0) return d('forward');
  final n = visibleXFraction(
    (x1 + x2) / 2.0,
    imgW,
    imgH: imgH,
    viewportAspect: viewportAspect,
  );
  if (n < 0.10) return d('9');
  if (n < 0.22) return d('10');
  if (n < 0.38) return d('11');
  if (n < 0.62) return d('forward');
  if (n < 0.78) return d('1');
  if (n < 0.90) return d('2');
  return d('3');
}

double threatScore(String label, String pos, String dist, double areaRatio) {
  final w = kClassWeight[label] ?? 1.0;
  final distFactor = dist == 'very close'
      ? 2.2
      : dist == 'close'
      ? 1.5
      : 1.0;
  final sizeFactor = 0.7 + 2.2 * math.sqrt(areaRatio);
  final centerFactor = pos == 'center' ? 1.25 : 1.0;
  return w * distFactor * sizeFactor * centerFactor;
}

(String, double, double) bestDirectionHint(
  List<Track> tracks,
  double imgW,
  double imgH, {
  double? viewportAspect,
}) {
  if (tracks.isEmpty) return ('forward', 0.0, 0.0);

  final frameArea = imgW * imgH;
  final zoneThreat = List<double>.filled(kZoneCount, 0.0);

  for (final t in tracks) {
    final zi = zoneIndexFromCx(
      t.cx,
      imgW,
      imgH: imgH,
      viewportAspect: viewportAspect,
    );
    final bw = t.x2 - t.x1;
    final bh = t.y2 - t.y1;
    final ar = frameArea > 0 ? (bw * bh) / frameArea : 0.0;
    final pos = posFromCx(
      t.cx,
      imgW,
      imgH: imgH,
      viewportAspect: viewportAspect,
    );
    zoneThreat[zi] += threatScore(t.label, pos, t.dist, ar);
  }

  var bestI = 0;
  var bestTh = zoneThreat[0];
  for (var i = 1; i < kZoneCount; i++) {
    if (zoneThreat[i] >= bestTh) {
      bestTh = zoneThreat[i];
      bestI = i;
    }
  }
  const midI = kZoneCount ~/ 2;
  final centTh = zoneThreat[midI];

  if (bestI == midI) return ('forward', centTh, bestTh);

  final String hint;
  if (bestI < midI) {
    hint = bestI == 0 ? S.get('nav_left') : S.get('nav_slight_left');
  } else {
    hint = bestI == kZoneCount - 1
        ? S.get('nav_right')
        : S.get('nav_slight_right');
  }
  return (hint, centTh, bestTh);
}

double _getObstacleWeight(String label) {
  switch (label) {
    case 'person':
      return 1.0;
    case 'car':
    case 'bus':
    case 'truck':
      return 1.5; 
      
    case 'bicycle':
    case 'motorcycle':
      return 1.3;
    default:
      return 0.7;
  }
}

const int _kPolarBinCount = 21;

const double _kPolarBinWidth = 6.0 * math.pi / 180.0;

const double _kPolarClearMinM = 1.2;

const double _kPolarShoulderHalfM = 0.25;

(double, String)? findFreeCorridor(
  List<Track> tracks,
  double imgW,
  double imgH, {
  double? viewportAspect,
}) {
  if (imgW <= 0 || imgH <= 0) return null;

  final hasMetric = tracks.any((t) => t.distM > 0);
  if (hasMetric) {
    final result = _findFreeCorridorPolar(
      tracks,
      imgW,
      imgH,
      viewportAspect: viewportAspect,
    );
    if (result != null) return result;
  }

  return _findFreeCorridorPixel(
    tracks,
    imgW,
    imgH,
    viewportAspect: viewportAspect,
  );
}

(double, String)? _findFreeCorridorPolar(
  List<Track> tracks,
  double imgW,
  double imgH, {
  double? viewportAspect,
}) {
  final fl = currentFocalLength;
  if (fl <= 0) return null;

  final binDist = List<double>.filled(_kPolarBinCount, double.infinity);
  const int halfSpan = _kPolarBinCount ~/ 2;

  bool anyPopulated = false;
  for (final t in tracks) {
    if (t.distM <= 0) continue;

    final azimuth = math.atan2(t.cx - imgW / 2.0, fl);

    final binIdx = (azimuth / _kPolarBinWidth + halfSpan).round().clamp(
      0,
      _kPolarBinCount - 1,
    );

    final bw = math.max(1.0, t.x2 - t.x1);
    final halfAngle = math.atan2(bw / 2.0, fl);
    final binSpread = (halfAngle / _kPolarBinWidth).ceil();
    final bLo = (binIdx - binSpread).clamp(0, _kPolarBinCount - 1);
    final bHi = (binIdx + binSpread).clamp(0, _kPolarBinCount - 1);

    for (int b = bLo; b <= bHi; b++) {
      if (t.distM < binDist[b]) {
        binDist[b] = t.distM;
        anyPopulated = true;
      }
    }
  }

  if (!anyPopulated) return null;

  final clearDist = List<double>.filled(_kPolarBinCount, double.infinity);
  for (int i = 0; i < _kPolarBinCount; i++) {
    clearDist[i] = binDist[i].isFinite
        ? (binDist[i] - _kPolarShoulderHalfM).clamp(0.0, double.infinity)
        : double.infinity;
  }

  int bestStart = -1, bestLen = 0;
  int runStart = -1, runLen = 0;
  for (int i = 0; i < _kPolarBinCount; i++) {
    if (clearDist[i] >= _kPolarClearMinM) {
      if (runStart < 0) runStart = i;
      runLen++;
      if (runLen > bestLen) {
        bestLen = runLen;
        bestStart = runStart;
      }
    } else {
      runStart = -1;
      runLen = 0;
    }
  }

  if (bestLen == 0) {
    return (0.0, 'center');
  }

  double corridorMinDist = double.infinity;
  for (int i = bestStart; i < bestStart + bestLen; i++) {
    if (binDist[i] < corridorMinDist) corridorMinDist = binDist[i];
  }
  if (!corridorMinDist.isFinite) {
    corridorMinDist = 5.0;
  }
  final halfAngle = bestLen * _kPolarBinWidth / 2.0;
  final widthM = 2.0 * corridorMinDist * math.sin(halfAngle);

  final centreIdx = bestStart + bestLen / 2.0;
  final centreNorm = centreIdx / _kPolarBinCount;
  final pos = centreNorm < 0.35
      ? 'left'
      : centreNorm > 0.65
      ? 'right'
      : 'center';

  return (widthM, pos);
}

(double, String)? _findFreeCorridorPixel(
  List<Track> tracks,
  double imgW,
  double imgH, {
  double? viewportAspect,
}) {
  final groundY = imgH * 0.75;
  final segments = <(double, double)>[];

  double visibleX(double x) =>
      visibleXFraction(x, imgW, imgH: imgH, viewportAspect: viewportAspect) *
      imgW;

  for (final t in tracks) {
    final isRelevant = t.y2 >= groundY || (t.distM > 0 && t.distM < 3.0);
    if (!isRelevant) continue;

    final weight = _getObstacleWeight(t.label);
    final expand = 20.0 * weight;
    final x1 = visibleX((t.x1 - expand).clamp(0.0, imgW));
    final x2 = visibleX((t.x2 + expand).clamp(0.0, imgW));
    
    segments.add((x1, x2));
  }

  if (segments.isEmpty) return null;

  segments.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(double, double)>[];
  for (final s in segments) {
    if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
      merged[merged.length - 1] = (
        merged.last.$1,
        math.max(merged.last.$2, s.$2),
      );
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
  final pos = centerNorm < 0.35
      ? 'left'
      : centerNorm > 0.65
      ? 'right'
      : 'center';

  return (widthM, pos);
}
