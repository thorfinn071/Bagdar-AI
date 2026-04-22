import 'dart:typed_data';

class BlurDetector {
  BlurDetector._();

  static double sharpnessScore(
    Uint8List yBytes, {
    required int width,
    required int height,
    required int rowStride,
    int stride = 8,
  }) {
    if (width < 4 || height < 4) return 0.0;
    if (rowStride < width) return 0.0;
    if (yBytes.length < rowStride * height) return 0.0;
    if (stride < 1) stride = 1;

    final xEnd = width - 1;
    final yEnd = height - 1;
    double sumL = 0.0;
    double sumL2 = 0.0;
    int n = 0;

    for (int y = 1; y < yEnd; y += stride) {
      final rowPrev = (y - 1) * rowStride;
      final row = y * rowStride;
      final rowNext = (y + 1) * rowStride;
      for (int x = 1; x < xEnd; x += stride) {
        final c = yBytes[row + x];
        final l = yBytes[row + x - 1];
        final r = yBytes[row + x + 1];
        final u = yBytes[rowPrev + x];
        final d = yBytes[rowNext + x];
        final lap = (c << 2) - l - r - u - d;
        sumL += lap;
        sumL2 += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0.0;
    final mean = sumL / n;
    final v = (sumL2 / n) - mean * mean;
    return v < 0 ? 0.0 : v;
  }

  static const double kBlurThreshold = 60.0;

  static bool isBlurry(double score) => score < kBlurThreshold;
}
