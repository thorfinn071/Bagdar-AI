import 'dart:typed_data';

import '../models/ncnn_depth_contract.dart';

/// Deterministic YUV_420_888 → RGB CHW preprocess matching
/// `bagdar_depth_ncnn.cpp`. Kept in Dart so the contract is unit-tested
/// without a device.
class NcnnDepthPreprocess {
  NcnnDepthPreprocess._();

  static const int mapSize = NcnnDepthContract.mapSize;

  /// Packs a 3 x 256 x 256 CHW float32 buffer in `[0, 1]`.
  ///
  /// [yPixelStride]/[uPixelStride]/[vPixelStride] default to 1. Android
  /// YUV_420_888 often uses chroma pixel stride 2 (NV12/NV21-style planes).
  static Float32List yuv420ToChw({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    int yPixelStride = 1,
    int uPixelStride = 1,
    int vPixelStride = 1,
    int rotationDegrees = 0,
    bool mirrored = false,
    double cropTopFrac = 0.40,
  }) {
    if (width <= 0 || height <= 1) {
      throw ArgumentError('invalid YUV size ${width}x$height');
    }
    final rotation = normalizeRotation(rotationDegrees);
    final swapAxes = rotation == 90 || rotation == 270;
    final orientedW = swapAxes ? height : width;
    final orientedH = swapAxes ? width : height;
    final crop = cropTopFrac.clamp(0.0, 0.9);
    final cropTop = (orientedH * crop).toInt().clamp(0, orientedH - 1);
    final cropH = (orientedH - cropTop).clamp(1, orientedH);
    final chromaW = (width + 1) >> 1;
    final chromaH = (height + 1) >> 1;
    const plane = mapSize * mapSize;
    final out = Float32List(plane * NcnnDepthContract.channels);
    final yPix = yPixelStride <= 0 ? 1 : yPixelStride;
    final uPix = uPixelStride <= 0 ? 1 : uPixelStride;
    final vPix = vPixelStride <= 0 ? 1 : vPixelStride;

    for (int dy = 0; dy < mapSize; dy++) {
      final oy = cropTop + (dy * cropH) ~/ mapSize;
      for (int dx = 0; dx < mapSize; dx++) {
        var ox = (dx * orientedW) ~/ mapSize;
        if (mirrored) ox = orientedW - 1 - ox;
        final source = orientedToSource(
          ox,
          oy,
          width: width,
          height: height,
          rotationDegrees: rotation,
        );
        final sx = source.$1;
        final sy = source.$2;
        final yv = _sample(y, sx, sy, width, height, yRowStride, yPix);
        final uvx = sx >> 1;
        final uvy = sy >> 1;
        final uVal = _sample(u, uvx, uvy, chromaW, chromaH, uRowStride, uPix);
        final vVal = _sample(v, uvx, uvy, chromaW, chromaH, vRowStride, vPix);
        final rgb = yuvToRgb01(yv, uVal, vVal);
        final idx = dy * mapSize + dx;
        out[idx] = rgb[0];
        out[plane + idx] = rgb[1];
        out[2 * plane + idx] = rgb[2];
      }
    }
    return out;
  }

  /// Extracts the luma plane with the exact transform used by
  /// [yuv420ToChw]. The generic detector must never compare a depth component
  /// with an untransformed camera plane.
  static Uint8List alignedLuma({
    required Uint8List y,
    required int width,
    required int height,
    required int rowStride,
    int pixelStride = 1,
    int rotationDegrees = 0,
    bool mirrored = false,
    double cropTopFrac = 0.40,
  }) {
    final rotation = normalizeRotation(rotationDegrees);
    final swapAxes = rotation == 90 || rotation == 270;
    final orientedW = swapAxes ? height : width;
    final orientedH = swapAxes ? width : height;
    final crop = cropTopFrac.clamp(0.0, 0.9);
    final cropTop = (orientedH * crop).toInt().clamp(0, orientedH - 1);
    final cropH = (orientedH - cropTop).clamp(1, orientedH);
    final out = Uint8List(mapSize * mapSize);
    final pix = pixelStride <= 0 ? 1 : pixelStride;
    for (int dy = 0; dy < mapSize; dy++) {
      final oy = cropTop + (dy * cropH) ~/ mapSize;
      for (int dx = 0; dx < mapSize; dx++) {
        var ox = (dx * orientedW) ~/ mapSize;
        if (mirrored) ox = orientedW - 1 - ox;
        final source = orientedToSource(
          ox,
          oy,
          width: width,
          height: height,
          rotationDegrees: rotation,
        );
        out[dy * mapSize + dx] = _sample(
          y,
          source.$1,
          source.$2,
          width,
          height,
          rowStride,
          pix,
        );
      }
    }
    return out;
  }

  static int normalizeRotation(int degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    return switch (normalized) {
      90 || 180 || 270 => normalized,
      _ => 0,
    };
  }

  /// Maps a coordinate in the upright, optionally rotated image back into the
  /// source sensor buffer. Mirroring is applied by the caller in upright
  /// coordinates before this inverse rotation.
  static (int, int) orientedToSource(
    int x,
    int y, {
    required int width,
    required int height,
    required int rotationDegrees,
  }) => switch (normalizeRotation(rotationDegrees)) {
    90 => (y, height - 1 - x),
    180 => (width - 1 - x, height - 1 - y),
    270 => (width - 1 - y, x),
    _ => (x, y),
  };

  static List<double> yuvToRgb01(int y, int u, int v) {
    final yf = y.toDouble();
    final uf = u - 128.0;
    final vf = v - 128.0;
    final r = (yf + NcnnDepthContract.kr * vf).clamp(0.0, 255.0) / 255.0;
    final g =
        (yf - NcnnDepthContract.kgU * uf - NcnnDepthContract.kgV * vf).clamp(
          0.0,
          255.0,
        ) /
        255.0;
    final b = (yf + NcnnDepthContract.kb * uf).clamp(0.0, 255.0) / 255.0;
    return <double>[r, g, b];
  }

  /// Inverse of [yuvToRgb01] (JPEG full-range) for building fixtures.
  static List<int> rgbToYuv(int r, int g, int b) {
    final y = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    final u = (128 - 0.168736 * r - 0.331264 * g + 0.5 * b).round().clamp(
      0,
      255,
    );
    final v = (128 + 0.5 * r - 0.418688 * g - 0.081312 * b).round().clamp(
      0,
      255,
    );
    return <int>[y, u, v];
  }

  static int _sample(
    Uint8List plane,
    int x,
    int y,
    int w,
    int h,
    int rowStride,
    int pixelStride,
  ) {
    if (plane.isEmpty || w <= 0 || h <= 0) return 0;
    final cx = x.clamp(0, w - 1);
    final cy = y.clamp(0, h - 1);
    final idx = cy * rowStride + cx * pixelStride;
    if (idx < 0 || idx >= plane.length) return 0;
    return plane[idx];
  }
}
