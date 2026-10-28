import 'dart:math' as math;
import 'dart:typed_data';

/// Spatial and semantic helpers for canonical depth maps.
///
/// Invalid depth is `NaN`. Zero is a real value (e.g. a metric reading at
/// the camera origin is still invalid and should already have been NaN'd).
class DepthMapOps {
  DepthMapOps._();

  static bool isValid(double v) => v.isFinite;

  /// Replaces Inf / non-finite values with NaN in place.
  static void sanitizeInPlace(Float32List map) {
    for (int i = 0; i < map.length; i++) {
      if (!map[i].isFinite) map[i] = double.nan;
    }
  }

  /// Bilinear resize. Non-finite source samples propagate as NaN.
  /// Never zero-pads a smaller flattened map into a larger one.
  static Float32List resizeBilinear(
    Float32List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0) {
      throw ArgumentError('invalid resize $srcW x $srcH -> $dstW x $dstH');
    }
    if (src.length < srcW * srcH) {
      throw ArgumentError('source length ${src.length} < $srcW*$srcH');
    }
    if (srcW == dstW && srcH == dstH) {
      return Float32List.fromList(src.sublist(0, srcW * srcH));
    }
    final dst = Float32List(dstW * dstH);
    for (int y = 0; y < dstH; y++) {
      final fy = srcH == 1 ? 0.0 : ((y + 0.5) * srcH / dstH) - 0.5;
      final y0 = fy.floor();
      final y1 = y0 + 1;
      final wy = fy - y0;
      final yy0 = y0.clamp(0, srcH - 1);
      final yy1 = y1.clamp(0, srcH - 1);
      for (int x = 0; x < dstW; x++) {
        final fx = srcW == 1 ? 0.0 : ((x + 0.5) * srcW / dstW) - 0.5;
        final x0 = fx.floor();
        final x1 = x0 + 1;
        final wx = fx - x0;
        final xx0 = x0.clamp(0, srcW - 1);
        final xx1 = x1.clamp(0, srcW - 1);
        final v00 = src[yy0 * srcW + xx0];
        final v10 = src[yy0 * srcW + xx1];
        final v01 = src[yy1 * srcW + xx0];
        final v11 = src[yy1 * srcW + xx1];
        if (![v00, v10, v01, v11].every(isValid)) {
          dst[y * dstW + x] = double.nan;
          continue;
        }
        final v0 = v00 * (1 - wx) + v10 * wx;
        final v1 = v01 * (1 - wx) + v11 * wx;
        dst[y * dstW + x] = v0 * (1 - wy) + v1 * wy;
      }
    }
    return dst;
  }

  /// If a 1-D buffer is a perfect square, recover (side, side). Otherwise
  /// null — callers must not invent a layout.
  static (int, int)? inferSquareLayout(int length) {
    if (length <= 0) return null;
    final side = math.sqrt(length).round();
    if (side * side == length) return (side, side);
    return null;
  }

  /// Percentile-normalize valid samples to `[0, 1]` **keeping larger=nearer**.
  /// Invalid samples stay NaN. Degenerate (near-constant) maps become all NaN.
  static Float32List normalizeRelativeProximity(
    Float32List raw, {
    double lowPercentile = 0.05,
    double highPercentile = 0.95,
    double minRange = 1e-3,
  }) {
    final valid = <double>[];
    for (final v in raw) {
      if (isValid(v)) valid.add(v);
    }
    final out = Float32List(raw.length);
    if (valid.length < 16) {
      out.fillRange(0, out.length, double.nan);
      return out;
    }
    valid.sort();
    final lo = _percentileSorted(valid, lowPercentile);
    final hi = _percentileSorted(valid, highPercentile);
    final range = hi - lo;
    if (!range.isFinite || range.abs() < minRange) {
      out.fillRange(0, out.length, double.nan);
      return out;
    }
    for (int i = 0; i < raw.length; i++) {
      final v = raw[i];
      if (!isValid(v)) {
        out[i] = double.nan;
      } else {
        out[i] = ((v - lo) / range).clamp(0.0, 1.0);
      }
    }
    return out;
  }

  /// Metric metres → relative proximity in `[0, 1]`, larger = nearer.
  /// Does not invent a scale: uses the frame's own valid range.
  static Float32List metricToRelativeProximity(
    Float32List meters, {
    double minM = 0.05,
    double maxM = 12.0,
  }) {
    final inv = Float32List(meters.length);
    for (int i = 0; i < meters.length; i++) {
      final z = meters[i];
      if (!isValid(z) || z < minM || z > maxM) {
        inv[i] = double.nan;
      } else {
        inv[i] = 1.0 / z;
      }
    }
    return normalizeRelativeProximity(inv);
  }

  static double _percentileSorted(List<double> sorted, double p) {
    if (sorted.isEmpty) return double.nan;
    final t = (p.clamp(0.0, 1.0) * (sorted.length - 1));
    final i = t.floor();
    final f = t - i;
    if (i >= sorted.length - 1) return sorted.last;
    return sorted[i] * (1 - f) + sorted[i + 1] * f;
  }

  static int countValid(Float32List map) {
    var n = 0;
    for (final v in map) {
      if (isValid(v)) n++;
    }
    return n;
  }

  static double? minValid(Float32List map) {
    var m = double.infinity;
    for (final v in map) {
      if (isValid(v) && v < m) m = v;
    }
    return m.isFinite ? m : null;
  }

  static double? maxValid(Float32List map) {
    var m = double.negativeInfinity;
    for (final v in map) {
      if (isValid(v) && v > m) m = v;
    }
    return m.isFinite ? m : null;
  }
}
