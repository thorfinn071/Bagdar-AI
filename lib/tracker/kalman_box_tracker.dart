import 'dart:math' as math;
import 'raw_det.dart';

class KalmanBoxTracker {
  late List<double> x;
  late List<List<double>> P;

  KalmanBoxTracker(RawDet det) {
    final w = det.x2 - det.x1;
    final h = det.y2 - det.y1;
    final area = w * h;
    final aspect = h > 0 ? w / h : 1.0;

    x = [det.cx, det.cy, area, aspect, 0, 0, 0];
    P = List.generate(7, (i) => List.filled(7, 0.0));
    for (int i = 0; i < 4; i++) {
      P[i][i] = 10.0;
    }
    for (int i = 4; i < 7; i++) {
      P[i][i] = 1000.0;
    }
  }

  void predict() {
    x[0] += x[4];
    x[1] += x[5];
    x[2] += x[6];
    
    if (x[2] < 1) x[2] = 1;
    for (int i = 0; i < 7; i++) {
      P[i][i] *= 1.1;
    }
  }

  void update(RawDet det) {
    final w = det.x2 - det.x1;
    final h = det.y2 - det.y1;
    final area = w * h;
    final aspect = h > 0 ? w / h : 1.0;

    final z = [det.cx, det.cy, area, aspect];
    const alpha = 0.6;
    
    x[4] = alpha * (z[0] - x[0]) + (1 - alpha) * x[4];
    x[5] = alpha * (z[1] - x[1]) + (1 - alpha) * x[5];
    x[6] = alpha * (z[2] - x[2]) + (1 - alpha) * x[6];
    
    x[0] = alpha * z[0] + (1 - alpha) * x[0];
    x[1] = alpha * z[1] + (1 - alpha) * x[1];
    x[2] = alpha * z[2] + (1 - alpha) * x[2];
    x[3] = alpha * z[3] + (1 - alpha) * x[3];
    for (int i = 0; i < 7; i++) {
      P[i][i] *= 0.5;
    }
  }

  List<double> getPredictedBox() {
    final cx = x[0];
    final cy = x[1];
    final area = math.max(1.0, x[2]);
    final aspect = math.max(0.1, x[3]);
    final h = math.sqrt(area / aspect);
    final w = area / h;
    
    return [
      cx - w / 2,
      cy - h / 2,
      cx + w / 2,
      cy + h / 2,
    ];
  }
}
