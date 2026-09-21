import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/ncnn_depth_contract.dart';
import 'package:bagdar/utils/ncnn_depth_preprocess.dart';

void main() {
  group('NCNN preprocess contract', () {
    test('in-graph mean/std are ImageNet RGB and must not be re-applied', () {
      expect(NcnnDepthContract.inGraphMeanRgb, [0.485, 0.456, 0.406]);
      expect(NcnnDepthContract.inGraphStdRgb, [0.229, 0.224, 0.225]);
    });

    test('solid red I420 round-trips to RGB with R dominant', () {
      const w = 16;
      const h = 16;
      final yuv = NcnnDepthPreprocess.rgbToYuv(255, 0, 0);
      final y = Uint8List(w * h);
      final u = Uint8List((w ~/ 2) * (h ~/ 2));
      final v = Uint8List((w ~/ 2) * (h ~/ 2));
      y.fillRange(0, y.length, yuv[0]);
      u.fillRange(0, u.length, yuv[1]);
      v.fillRange(0, v.length, yuv[2]);
      final chw = NcnnDepthPreprocess.yuv420ToChw(
        y: y,
        u: u,
        v: v,
        width: w,
        height: h,
        yRowStride: w,
        uRowStride: w ~/ 2,
        vRowStride: w ~/ 2,
        cropTopFrac: 0,
      );
      expect(chw.length, 3 * 256 * 256);
      const plane = 256 * 256;
      var r = 0.0, g = 0.0, b = 0.0;
      for (int i = 0; i < plane; i++) {
        r += chw[i];
        g += chw[plane + i];
        b += chw[2 * plane + i];
      }
      r /= plane;
      g /= plane;
      b /= plane;
      expect(r, greaterThan(0.85));
      expect(g, lessThan(0.15));
      expect(b, lessThan(0.15));
    });

    test('cropTopFrac drops the top of the frame', () {
      const w = 8;
      const h = 8;
      final y = Uint8List(w * h);
      final u = Uint8List(4 * 4);
      final v = Uint8List(4 * 4);
      // Top half black, bottom half white.
      for (int row = 0; row < h; row++) {
        final val = row < 4 ? 0 : 255;
        for (int x = 0; x < w; x++) {
          y[row * w + x] = val;
        }
      }
      u.fillRange(0, u.length, 128);
      v.fillRange(0, v.length, 128);
      final cropped = NcnnDepthPreprocess.yuv420ToChw(
        y: y,
        u: u,
        v: v,
        width: w,
        height: h,
        yRowStride: w,
        uRowStride: 4,
        vRowStride: 4,
        cropTopFrac: 0.5,
      );
      const plane = 256 * 256;
      var mean = 0.0;
      for (int i = 0; i < plane; i++) {
        mean += cropped[i];
      }
      mean /= plane;
      expect(mean, greaterThan(0.9));
    });

    test('chroma pixel stride 2 is sampled, not treated as planar', () {
      const w = 8;
      const h = 8;
      final y = Uint8List(w * h)..fillRange(0, w * h, 128);
      // NV12-style: U at even bytes, dummy at odd.
      final u = Uint8List(w * (h ~/ 2));
      final v = Uint8List(w * (h ~/ 2));
      for (int i = 0; i < u.length; i += 2) {
        u[i] = 128;
        u[i + 1] = 0;
        v[i] = 255; // strong V → red
        v[i + 1] = 0;
      }
      final chw = NcnnDepthPreprocess.yuv420ToChw(
        y: y,
        u: u,
        v: v,
        width: w,
        height: h,
        yRowStride: w,
        uRowStride: w,
        vRowStride: w,
        uPixelStride: 2,
        vPixelStride: 2,
        cropTopFrac: 0,
      );
      const plane = 256 * 256;
      var r = 0.0;
      for (int i = 0; i < plane; i++) {
        r += chw[i];
      }
      r /= plane;
      expect(r, greaterThan(0.6));
    });

    test('rotation and mirror are applied before crop/resize', () {
      final y = Uint8List.fromList(<int>[10, 20, 30, 40, 50, 60]);
      final rotated = NcnnDepthPreprocess.alignedLuma(
        y: y,
        width: 2,
        height: 3,
        rowStride: 2,
        rotationDegrees: 90,
        cropTopFrac: 0,
      );
      expect(rotated.first, 50);
      expect(rotated.last, 20);

      final mirrored = NcnnDepthPreprocess.alignedLuma(
        y: y,
        width: 2,
        height: 3,
        rowStride: 2,
        rotationDegrees: 90,
        mirrored: true,
        cropTopFrac: 0,
      );
      expect(mirrored.first, 10);
      expect(mirrored.last, 60);
    });
  });
}
