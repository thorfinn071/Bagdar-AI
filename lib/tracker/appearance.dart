import 'dart:math' as math;
import 'dart:typed_data';












class Appearance {
  
  
  
  static const int kBins = 16;

  
  static const int kMaxSamplesPerAxis = 16;

  
  
  
  static Float32List? extractFromYPlane({
    required Uint8List yPlane,
    required int rowStride,
    required int imgW,
    required int imgH,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    if (imgW <= 0 || imgH <= 0 || rowStride <= 0) return null;
    if (yPlane.isEmpty) return null;

    final xLo = x1.clamp(0, imgW - 1).toInt();
    final yLo = y1.clamp(0, imgH - 1).toInt();
    final xHi = x2.clamp(0, imgW - 1).toInt();
    final yHi = y2.clamp(0, imgH - 1).toInt();
    if (xHi - xLo < 2 || yHi - yLo < 2) return null;

    
    
    
    final strideX = math
        .max(1, ((xHi - xLo) / kMaxSamplesPerAxis).ceil());
    final strideY = math
        .max(1, ((yHi - yLo) / kMaxSamplesPerAxis).ceil());

    final counts = List<int>.filled(kBins, 0);
    int total = 0;
    for (int y = yLo; y <= yHi; y += strideY) {
      final rowStart = y * rowStride;
      for (int x = xLo; x <= xHi; x += strideX) {
        final idx = rowStart + x;
        if (idx < 0 || idx >= yPlane.length) continue;
        final v = yPlane[idx];
        
        
        final bin = (v * kBins) >> 8;
        counts[bin >= kBins ? kBins - 1 : bin]++;
        total++;
      }
    }
    if (total == 0) return null;

    final hist = Float32List(kBins);
    final inv = 1.0 / total;
    for (int i = 0; i < kBins; i++) {
      hist[i] = counts[i] * inv;
    }
    return hist;
  }

  
  
  
  
  static double similarity(Float32List? a, Float32List? b) {
    if (a == null || b == null) return 0.0;
    if (a.isEmpty || a.length != b.length) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final prod = a[i] * b[i];
      if (prod > 0.0) sum += math.sqrt(prod);
    }
    
    if (sum < 0.0) return 0.0;
    if (sum > 1.0) return 1.0;
    return sum;
  }

  
  
  
  static Float32List blend(
    Float32List current,
    Float32List update, {
    double alpha = 0.3,
  }) {
    assert(current.length == update.length, 'histogram length mismatch');
    final a = alpha.clamp(0.0, 1.0);
    final out = Float32List(current.length);
    for (int i = 0; i < current.length; i++) {
      out[i] = current[i] * (1.0 - a) + update[i] * a;
    }
    return out;
  }
}
