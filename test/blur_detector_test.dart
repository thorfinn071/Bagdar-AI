import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/utils/blur_detector.dart';

void main() {
  group('BlurDetector.sharpnessScore', () {
    test('uniform gray frame scores ~0 and is treated as blurry', () {
      const w = 64;
      const h = 48;
      final buf = Uint8List(w * h)..fillRange(0, w * h, 128);
      final score = BlurDetector.sharpnessScore(
        buf,
        width: w,
        height: h,
        rowStride: w,
        stride: 4,
      );
      expect(score, closeTo(0.0, 1e-9));
      expect(BlurDetector.isBlurry(score), isTrue);
    });

    test('sharp random noise scores strictly higher than its 3x3 box-'
        'blurred version', () {
      
      
      
      const w = 128;
      const h = 96;
      final rng = math.Random(11);
      final sharp = Uint8List(w * h);
      for (int i = 0; i < sharp.length; i++) {
        sharp[i] = rng.nextInt(256);
      }
      final blurred = Uint8List(w * h);
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          int s = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              s += sharp[(y + dy) * w + (x + dx)];
            }
          }
          blurred[y * w + x] = (s ~/ 9);
        }
      }
      final sharpScore = BlurDetector.sharpnessScore(
        sharp, width: w, height: h, rowStride: w, stride: 2);
      final blurredScore = BlurDetector.sharpnessScore(
        blurred, width: w, height: h, rowStride: w, stride: 2);
      expect(sharpScore, greaterThan(blurredScore * 2));
      expect(BlurDetector.isBlurry(sharpScore), isFalse);
    });

    test('random high-contrast noise scores above the blur threshold', () {
      const w = 128;
      const h = 96;
      final rng = math.Random(42);
      final buf = Uint8List(w * h);
      for (int i = 0; i < buf.length; i++) {
        buf[i] = rng.nextInt(256);
      }
      final score = BlurDetector.sharpnessScore(
        buf, width: w, height: h, rowStride: w, stride: 4);
      expect(score, greaterThan(BlurDetector.kBlurThreshold));
      expect(BlurDetector.isBlurry(score), isFalse);
    });

    test('tiny frame returns 0 without crashing', () {
      final buf = Uint8List(3 * 3)..fillRange(0, 9, 128);
      final score = BlurDetector.sharpnessScore(
        buf, width: 3, height: 3, rowStride: 3);
      expect(score, 0.0);
    });

    test('buffer shorter than rowStride*height returns 0 defensively', () {
      final buf = Uint8List(10);
      final score = BlurDetector.sharpnessScore(
        buf, width: 64, height: 48, rowStride: 64);
      expect(score, 0.0);
    });

    test('rowStride smaller than width is rejected', () {
      final buf = Uint8List(64 * 48)..fillRange(0, 64 * 48, 128);
      final score = BlurDetector.sharpnessScore(
        buf, width: 64, height: 48, rowStride: 32);
      expect(score, 0.0);
    });

    test('stride < 1 is clamped internally and does not infinite-loop', () {
      const w = 16;
      const h = 12;
      final buf = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          buf[y * w + x] = ((x + y) & 1) == 0 ? 0 : 255;
        }
      }
      final score = BlurDetector.sharpnessScore(
        buf, width: w, height: h, rowStride: w, stride: 0);
      expect(score, greaterThan(0));
    });
  });
}
