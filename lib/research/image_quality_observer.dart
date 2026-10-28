import 'dart:math' as math;
import 'dart:typed_data';

/// Optical evidence only. No state grants frame admission or movement authority.
enum ImageQualityEvidence {
  noiseDominated,
  insufficientStructure,
  blurSuspected,
  structured,
  unknown,
}

class ImageQualityObservation {
  final ImageQualityEvidence evidence;
  final String reason;
  final double? residualProxy,
      structureFraction,
      edgeConcentration,
      clippedFraction;
  final int supportedPixels;

  const ImageQualityObservation({
    required this.evidence,
    required this.reason,
    this.residualProxy,
    this.structureFraction,
    this.edgeConcentration,
    this.clippedFraction,
    this.supportedPixels = 0,
  });

  Map<String, Object?> toJson() => {
    'evidence': evidence.name,
    'reason': reason,
    'residualProxy': residualProxy,
    'structureFraction': structureFraction,
    'edgeConcentration': edgeConcentration,
    'clippedFraction': clippedFraction,
    'supportedPixels': supportedPixels,
    'promotionAllowed': false,
  };
}

/// Frozen v1 engineering hypotheses, not a calibrated camera-quality estimator.
/// The API deliberately accepts pixels/layout only, never generator parameters.
/// This file is used by research tooling; production admission does not import it.
class ImageQualityObserver {
  const ImageQualityObserver();

  static const version = 'mixed-residual-edge-concentration-v1';
  static const noiseResidualLimit = 2.5;
  static const minimumStructureFraction = 0.001;
  static const blurConcentrationLimit = 0.30;
  static const sharpConcentrationLimit = 0.55;

  ImageQualityObservation observe(
    Uint8List luma, {
    required int width,
    required int height,
    required int rowStride,
  }) {
    if (width < 24 ||
        height < 24 ||
        width > 2048 ||
        height > 2048 ||
        rowStride < width ||
        rowStride > 8192 ||
        luma.length < rowStride * height) {
      return const ImageQualityObservation(
        evidence: ImageQualityEvidence.unknown,
        reason: 'invalid_input',
      );
    }
    final histogram = Uint32List(511);
    var residualCount = 0, clipped = 0;
    for (var y = 0; y < height; y++) {
      final row = y * rowStride;
      for (var x = 0; x < width; x++) {
        final value = luma[row + x];
        if (value <= 2 || value >= 253) clipped++;
        if (x + 1 < width && y + 1 < height) {
          final mixed =
              (value -
                      luma[row + x + 1] -
                      luma[row + rowStride + x] +
                      luma[row + rowStride + x + 1])
                  .abs();
          histogram[mixed]++;
          residualCount++;
        }
      }
    }
    var cumulative = 0, median = 0;
    for (var i = 0; i < histogram.length; i++) {
      cumulative += histogram[i];
      if (cumulative * 2 >= residualCount) {
        median = i;
        break;
      }
    }
    // A robust high-frequency proxy, deliberately not labelled noise sigma.
    final residual = median / 2.0;
    final smooth = Uint8List(width * height);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        var sum = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final p = (y + dy) * rowStride + x;
          sum += luma[p - 1] + luma[p] + luma[p + 1];
        }
        smooth[y * width + x] = (sum + 4) ~/ 9;
      }
    }
    final concentrations = Uint32List(201);
    var support = 0;
    final spanFloor = math.max(8.0, residual * 6);
    for (var y = 7; y < height - 7; y++) {
      for (var x = 7; x < width - 7; x++) {
        final p = y * width + x;
        final gx = (smooth[p + 1] - smooth[p - 1]).abs();
        final gy = (smooth[p + width] - smooth[p - width]).abs();
        final horizontal = gx >= gy;
        final span = horizontal
            ? (smooth[p + 6] - smooth[p - 6]).abs()
            : (smooth[p + 6 * width] - smooth[p - 6 * width]).abs();
        final gradient = horizontal ? gx : gy;
        if (span < spanFloor || gradient < math.max(2, residual)) continue;
        final step = horizontal ? 1 : width;
        final before = (smooth[p] - smooth[p - 2 * step]).abs();
        final after = (smooth[p + 2 * step] - smooth[p]).abs();
        if (gradient < before || gradient < after) continue;
        final raw = y * rowStride + x;
        final fine = horizontal
            ? (luma[raw + 1] - luma[raw - 1]).abs()
            : (luma[raw + rowStride] - luma[raw - rowStride]).abs();
        concentrations[(100 * fine / span).round().clamp(0, 200)]++;
        support++;
      }
    }
    double? concentration;
    cumulative = 0;
    for (var i = 0; i < concentrations.length && support > 0; i++) {
      cumulative += concentrations[i];
      if (cumulative * 2 >= support) {
        concentration = i / 100;
        break;
      }
    }
    final fraction = support / ((width - 14) * (height - 14));
    final clipFraction = clipped / (width * height);
    ImageQualityEvidence evidence;
    String reason;
    if (clipFraction > 0.25) {
      evidence = ImageQualityEvidence.unknown;
      reason = 'substantial_clipping';
    } else if (residual >= noiseResidualLimit) {
      evidence = ImageQualityEvidence.noiseDominated;
      reason = 'large_mixed_residual_texture_can_confound';
    } else if (fraction < minimumStructureFraction || support < 24) {
      evidence = ImageQualityEvidence.insufficientStructure;
      reason = 'too_few_supported_edges';
    } else if (concentration! <= blurConcentrationLimit) {
      evidence = ImageQualityEvidence.blurSuspected;
      reason = 'broad_supported_edges';
    } else if (concentration >= sharpConcentrationLimit) {
      evidence = ImageQualityEvidence.structured;
      reason = 'concentrated_supported_edges_not_navigation_quality';
    } else {
      evidence = ImageQualityEvidence.unknown;
      reason = 'ambiguous_edge_concentration';
    }
    return ImageQualityObservation(
      evidence: evidence,
      reason: reason,
      residualProxy: residual,
      structureFraction: fraction,
      edgeConcentration: concentration,
      clippedFraction: clipFraction,
      supportedPixels: support,
    );
  }
}
