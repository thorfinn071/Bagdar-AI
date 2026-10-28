import 'dart:math';
import 'dart:typed_data';

import 'package:bagdar/research/image_quality_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const observer = ImageQualityObserver();
  const w = 96, h = 128;
  Uint8List edge({
    bool broad = false,
    int shift = 0,
    int padding = 0,
    bool noise = false,
  }) {
    final result = Uint8List((w + padding) * h);
    final rng = Random(217);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final value = broad
            ? 70 + 120 / (1 + exp(-(x - w / 2 - shift) / 6))
            : x < w / 2 + shift
            ? 70
            : 190;
        result[y * (w + padding) + x] =
            (value + (noise ? rng.nextInt(33) - 16 : 0)).round().clamp(0, 255);
      }
    }
    return result;
  }

  ImageQualityObservation observe(Uint8List b, {int stride = w}) =>
      observer.observe(b, width: w, height: h, rowStride: stride);

  test('invalid dimensions, short buffers and strides stay unknown', () {
    for (final args in [
      (0, h, w),
      (w, h, w - 1),
      (w, h, 9000),
      (3000, h, 3000),
    ]) {
      expect(
        observer
            .observe(
              Uint8List(0),
              width: args.$1,
              height: args.$2,
              rowStride: args.$3,
            )
            .evidence,
        ImageQualityEvidence.unknown,
      );
    }
    expect(observe(Uint8List(w * h - 1)).reason, 'invalid_input');
  });
  test('flat field has insufficient structure; clipping retains unknown', () {
    final flat = Uint8List(w * h)..fillRange(0, w * h, 128);
    expect(observe(flat).evidence, ImageQualityEvidence.insufficientStructure);
    expect(observe(Uint8List(w * h)).evidence, ImageQualityEvidence.unknown);
  });
  test('supported sharp and broad edges have distinct evidence', () {
    expect(observe(edge()).evidence, ImageQualityEvidence.structured);
    expect(
      observe(edge(broad: true)).evidence,
      ImageQualityEvidence.blurSuspected,
    );
  });
  test('noise never turns the paired broad edge into structured evidence', () {
    expect(
      observe(edge(broad: true, noise: true)).evidence,
      ImageQualityEvidence.noiseDominated,
    );
  });
  test('row padding is ignored and caller pixels stay immutable', () {
    final bytes = edge(padding: 17);
    final before = Uint8List.fromList(bytes);
    expect(observe(bytes, stride: w + 17).toJson(), observe(edge()).toJson());
    expect(bytes, before);
  });
  test('sparse edge stays structured across eight sampling phases', () {
    for (var shift = 0; shift < 8; shift++) {
      expect(
        observe(edge(shift: shift)).evidence,
        ImageQualityEvidence.structured,
      );
    }
  });
  test(
    'arbitrary images produce finite nullable diagnostics and no authority',
    () {
      final rng = Random(818);
      for (var i = 0; i < 8; i++) {
        final o = observe(
          Uint8List.fromList(List.generate(w * h, (_) => rng.nextInt(256))),
        );
        for (final v in [
          o.residualProxy,
          o.structureFraction,
          o.edgeConcentration,
          o.clippedFraction,
        ]) {
          expect(v == null || v.isFinite, true);
        }
        expect(o.toJson()['promotionAllowed'], false);
      }
    },
  );
}
