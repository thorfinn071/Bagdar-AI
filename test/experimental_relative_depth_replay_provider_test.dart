import 'dart:typed_data';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/services/experimental_relative_depth_replay_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = ExperimentalRelativeDepthReplayProvider(
    modelId: 'dav2-small-experiment',
    modelHash: 'sha256:checkpoint:fixture',
    preprocessId: 'RGB-ImageNet-short280-multiple14',
    width: 4,
    height: 4,
  );
  final rgbHash = sha256.convert(Uint8List.fromList([1, 2, 3])).toString();

  Uint8List encode(List<double> values) {
    final bytes = Uint8List(values.length * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], Endian.little);
    }
    return bytes;
  }

  DepthFrame replay(
    Uint8List bytes, {
    String? digest,
    String? sourceRgb,
    int now = 1002,
  }) => provider.frameForReplay(
    bytes: bytes,
    mapSha256: digest ?? sha256.convert(bytes).toString(),
    sourceRgbSha256: sourceRgb ?? rgbHash,
    expectedRgbSha256: rgbHash,
    sourceTimestampUs: 1000,
    evaluatedAtUs: now,
    diagnosticFrameQuality: 0.8,
  );

  test('relative output preserves larger nearer and owns its buffers', () {
    final bytes = encode(List.generate(16, (i) => i.toDouble()));
    final frame = replay(bytes);
    bytes.fillRange(0, bytes.length, 0);
    expect(frame.values.first, 0);
    expect(frame.values.last, 1);
    expect(frame.semantics, DepthValueSemantics.relativeProximity);
    expect(frame.intrinsics, isNull);
    expect(frame.modelId, provider.modelId);
    expect(provider.promotionAllowed, isFalse);
    expect(provider.isLiveInferenceProvider, isFalse);
  });

  test('wrong map digest or RGB association is rejected', () {
    final bytes = encode(List.generate(16, (i) => i.toDouble()));
    expect(() => replay(bytes, digest: rgbHash), throwsFormatException);
    expect(
      () => replay(bytes, sourceRgb: sha256.convert([4]).toString()),
      throwsFormatException,
    );
  });

  test('malformed shape, NaN and constant outputs are unavailable', () {
    expect(() => replay(Uint8List(60)), throwsFormatException);
    expect(() => replay(encode(List.filled(16, 1))), throwsFormatException);
    final invalid = List.generate(16, (i) => i.toDouble())..[4] = double.nan;
    expect(() => replay(encode(invalid)), throwsFormatException);
  });

  test('future and stale outputs are rejected without extending TTL', () {
    final bytes = encode(List.generate(16, (i) => i.toDouble()));
    expect(() => replay(bytes, now: 999), throwsFormatException);
    expect(() => replay(bytes, now: 2001001), throwsFormatException);
  });
}
