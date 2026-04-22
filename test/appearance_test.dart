import 'dart:typed_data';

import 'package:bagdar/tracker/appearance.dart';
import 'package:flutter_test/flutter_test.dart';


Uint8List _uniformY(int w, int h, int value) {
  final bytes = Uint8List(w * h);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = value;
  }
  return bytes;
}


Uint8List _checkerY(int w, int h, int lo, int hi, {int tile = 4}) {
  final bytes = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final on = (((x ~/ tile) + (y ~/ tile)) & 1) == 1;
      bytes[y * w + x] = on ? hi : lo;
    }
  }
  return bytes;
}

void main() {
  const w = 64;
  const h = 64;

  group('Appearance.extractFromYPlane', () {
    test('uniform gray frame produces a single-bin histogram', () {
      final y = _uniformY(w, h, 128);
      final hist = Appearance.extractFromYPlane(
        yPlane: y,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      expect(hist.length, Appearance.kBins);
      
      expect(hist[8], closeTo(1.0, 1e-6));
      for (int i = 0; i < Appearance.kBins; i++) {
        if (i != 8) expect(hist[i], closeTo(0.0, 1e-6));
      }
      
      final sum = hist.fold<double>(0.0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 1e-5));
    });

    test('degenerate bbox returns null', () {
      final y = _uniformY(w, h, 128);
      expect(
        Appearance.extractFromYPlane(
          yPlane: y,
          rowStride: w,
          imgW: w,
          imgH: h,
          x1: 10,
          y1: 10,
          x2: 10,
          y2: 10,
        ),
        isNull,
      );
    });

    test('bbox clipped to image bounds still produces a valid histogram', () {
      final y = _uniformY(w, h, 200);
      final hist = Appearance.extractFromYPlane(
        yPlane: y,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: -50,
        y1: -50,
        x2: w.toDouble() + 50,
        y2: h.toDouble() + 50,
      );
      expect(hist, isNotNull);
      final sum = hist!.fold<double>(0.0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 1e-5));
      
      expect(hist[12], greaterThan(0.9));
    });

    test('extreme value 255 does not overflow the bin array', () {
      final y = _uniformY(w, h, 255);
      final hist = Appearance.extractFromYPlane(
        yPlane: y,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      expect(hist[Appearance.kBins - 1], closeTo(1.0, 1e-6));
    });
  });

  group('Appearance.similarity', () {
    test('identical histograms have similarity 1.0', () {
      final y = _uniformY(w, h, 80);
      final hist = Appearance.extractFromYPlane(
        yPlane: y,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      expect(Appearance.similarity(hist, hist), closeTo(1.0, 1e-5));
    });

    test('fully disjoint histograms have similarity 0', () {
      final dark = _uniformY(w, h, 0);
      final bright = _uniformY(w, h, 255);
      final hA = Appearance.extractFromYPlane(
        yPlane: dark,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      final hB = Appearance.extractFromYPlane(
        yPlane: bright,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      expect(Appearance.similarity(hA, hB), closeTo(0.0, 1e-6));
    });

    test('checkerboard with same intensities yields identical histograms', () {
      final a = _checkerY(w, h, 40, 200);
      final b = _checkerY(w, h, 40, 200, tile: 8);
      final hA = Appearance.extractFromYPlane(
        yPlane: a,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      final hB = Appearance.extractFromYPlane(
        yPlane: b,
        rowStride: w,
        imgW: w,
        imgH: h,
        x1: 0,
        y1: 0,
        x2: w.toDouble() - 1,
        y2: h.toDouble() - 1,
      )!;
      
      expect(Appearance.similarity(hA, hB), greaterThan(0.95));
    });

    test('null or mismatched inputs yield 0 without throwing', () {
      final hist = Float32List(Appearance.kBins);
      hist[0] = 1.0;
      expect(Appearance.similarity(null, hist), 0.0);
      expect(Appearance.similarity(hist, null), 0.0);
      expect(Appearance.similarity(Float32List(4), hist), 0.0);
    });
  });

  group('Appearance.blend', () {
    test('alpha 0 returns a copy of current', () {
      final current = Float32List.fromList([0.5, 0.5, 0.0, 0.0]);
      final update = Float32List.fromList([0.0, 0.0, 1.0, 0.0]);
      final out = Appearance.blend(current, update, alpha: 0.0);
      expect(out, orderedEquals([0.5, 0.5, 0.0, 0.0]));
      
      expect(identical(out, current), isFalse);
    });

    test('alpha 1 returns a copy of update', () {
      final current = Float32List.fromList([0.5, 0.5, 0.0, 0.0]);
      final update = Float32List.fromList([0.0, 0.0, 1.0, 0.0]);
      final out = Appearance.blend(current, update, alpha: 1.0);
      expect(out, orderedEquals([0.0, 0.0, 1.0, 0.0]));
    });

    test('default alpha moves the histogram toward update', () {
      final current = Float32List.fromList([1.0, 0.0, 0.0, 0.0]);
      final update = Float32List.fromList([0.0, 0.0, 0.0, 1.0]);
      final out = Appearance.blend(current, update);
      expect(out[0], lessThan(1.0));
      expect(out[3], greaterThan(0.0));
      
      final sum = out.fold<double>(0.0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 1e-6));
    });
  });
}
