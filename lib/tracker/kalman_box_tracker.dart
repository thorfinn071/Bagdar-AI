import 'dart:math' as math;
import '../models/constants.dart';
import 'raw_det.dart';

class KalmanBoxTracker {
  late List<double> x;
  late List<List<double>> P;

  KalmanBoxTracker(RawDet det) {
    final stats = _boxStats(det.x1, det.y1, det.x2, det.y2);

    
    
    x = [det.cx, det.cy, stats.area, stats.aspect, 0, 0, 0];
    P = List.generate(7, (i) => List.filled(7, 0.0));
    for (int i = 0; i < 4; i++) {
      P[i][i] = 10.0;
    }
    for (int i = 4; i < 7; i++) {
      P[i][i] = 1000.0;
    }
    _normalizeState();
  }

  void predict() {
    x[0]=_finiteOr(x[0],0.0)+_finiteOr(x[4],0.0);
    x[1]=_finiteOr(x[1],0.0)+_finiteOr(x[5],0.0);
    x[2]=math.max(1.0,_finiteOr(x[2],1.0)+_finiteOr(x[6],0.0));
    x[4] = _clampFinite(_finiteOr(x[4], 0.0) * 0.92, -3000.0, 3000.0);
    x[5] = _clampFinite(_finiteOr(x[5], 0.0) * 0.92, -3000.0, 3000.0);
    
    x[6] = _clampFinite(_finiteOr(x[6], 0.0) * 0.85, -4000.0, 4000.0);
    _normalizeState();
    for (int i = 0; i < 7; i++) {
      P[i][i] *= 1.1;
    }
  }

  void update(RawDet det) {
    final stats = _boxStats(det.x1, det.y1, det.x2, det.y2);
    final confidence = det.conf.isFinite
        ? det.conf.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final alpha = 0.35 + confidence * 0.45;
    final beta = 0.20 + confidence * 0.30;

    final currentCx = _finiteOr(x[0], det.cx);
    final currentCy = _finiteOr(x[1], det.cy);
    final currentArea = _finiteOr(x[2], stats.area);
    final dx = det.cx - currentCx;
    final dy = det.cy - currentCy;
    final dArea = stats.area - currentArea;

    x[4] = _clampFinite(
      (1 - beta) * _finiteOr(x[4], 0.0) + beta * dx,
      -3000.0,
      3000.0,
    );
    x[5] = _clampFinite(
      (1 - beta) * _finiteOr(x[5], 0.0) + beta * dy,
      -3000.0,
      3000.0,
    );
    x[6] = _clampFinite(
      (1 - beta) * _finiteOr(x[6], 0.0) + beta * dArea,
      -4000.0,
      4000.0,
    );

    x[0] = currentCx + dx * alpha;
    x[1] = currentCy + dy * alpha;
    x[2] = math.max(1.0, currentArea + dArea * alpha);
    x[3] = math.max(
      0.1,
      _finiteOr(x[3], stats.aspect) * (1 - alpha) + stats.aspect * alpha,
    );
    _normalizeState();
    for (int i = 0; i < 7; i++) {
      P[i][i] *= 0.5;
    }
  }

  List<double> getPredictedBox() {
    final cx = _finiteOr(x[0], 0.0);
    final cy = _finiteOr(x[1], 0.0);
    final area = math.max(1.0, _finiteOr(x[2], 1.0));
    final aspect = math.max(0.1, _finiteOr(x[3], 1.0));
    final h = math.sqrt(area / aspect);
    final w = area / h;

    return [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2];
  }

  double matchScore(RawDet det) {
    final cx = _finiteOr(x[0], 0.0);
    final cy = _finiteOr(x[1], 0.0);
    final area = math.max(1.0, _finiteOr(x[2], 1.0));
    final aspect = math.max(0.1, _finiteOr(x[3], 1.0));
    final h = math.sqrt(area / aspect);
    final w = area / h;

    final px1 = cx - w / 2;
    final py1 = cy - h / 2;
    final px2 = cx + w / 2;
    final py2 = cy + h / 2;

    final detArea = math.max(
      1.0,
      (det.x2 - det.x1).abs() * (det.y2 - det.y1).abs(),
    );
    final ix1 = math.max(det.x1, px1);
    final iy1 = math.max(det.y1, py1);
    final ix2 = math.min(det.x2, px2);
    final iy2 = math.min(det.y2, py2);

    double iou = 0.0;
    if (ix2 > ix1 && iy2 > iy1) {
      final iArea = (ix2 - ix1) * (iy2 - iy1);
      final union = detArea + area - iArea;
      if (union > 0) {
        iou = iArea / union;
      }
    }

    final dx = det.cx - cx;
    final dy = det.cy - cy;
    final centerDist = math.sqrt(dx * dx + dy * dy);
    if (centerDist > kTrackMatchDist) {
      return iou;
    }

    final sizeScore = math.min(detArea, area) / math.max(detArea, area);
    final distanceScore = 1.0 - (centerDist / kTrackMatchDist);
    final fallbackScore = distanceScore * 0.65 + sizeScore * 0.35;
    
    return math.max(iou, fallbackScore);
  }

  void _normalizeState() {
    x[0] = _finiteOr(x[0], 0.0);
    x[1] = _finiteOr(x[1], 0.0);
    x[2] = math.max(1.0, _finiteOr(x[2], 1.0));
    x[3] = math.max(0.1, _finiteOr(x[3], 1.0));
    x[4] = _finiteOr(x[4], 0.0);
    x[5] = _finiteOr(x[5], 0.0);
    x[6] = _finiteOr(x[6], 0.0);
  }

  static double _finiteOr(double value, double fallback) {
    return value.isFinite ? value : fallback;
  }

  static double _clampFinite(double value, double min, double max) {
    
    if (!value.isFinite) return min;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static ({double area, double aspect}) _boxStats(
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final w = (x2 - x1).abs();
    final h = (y2 - y1).abs();
    final area = math.max(1.0, w * h);
    final aspect = h > 0 ? math.max(0.1, w / h) : 1.0;
    return (area: area, aspect: aspect);
  }
}
