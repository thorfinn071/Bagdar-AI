import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/depth_frame.dart';
import '../utils/depth_map_ops.dart';

/// Adapter for real, precomputed desktop NCNN outputs in a synthetic replay.
///
/// This does not implement camera inference and is never selected by
/// DepthProviderFactory. The caller explicitly supplies diagnostic frame
/// quality; model output coverage is not a physical visibility certificate.
class ExperimentalRelativeDepthReplayProvider {
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final int width;
  final int height;
  final Duration maximumAge;

  const ExperimentalRelativeDepthReplayProvider({
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    this.width = 256,
    this.height = 256,
    this.maximumAge = const Duration(seconds: 2),
  });

  bool get promotionAllowed => false;
  bool get isLiveInferenceProvider => false;

  DepthFrame frameForReplay({
    required Uint8List bytes,
    required String mapSha256,
    required String sourceRgbSha256,
    required String expectedRgbSha256,
    required int sourceTimestampUs,
    required int evaluatedAtUs,
    required double diagnosticFrameQuality,
  }) {
    final digestPattern = RegExp(r'^[a-f0-9]{64}$');
    if (modelId.isEmpty || modelHash.isEmpty || preprocessId.isEmpty) {
      throw const FormatException('missing experimental model identity');
    }
    if (!digestPattern.hasMatch(mapSha256) ||
        !digestPattern.hasMatch(sourceRgbSha256) ||
        sourceRgbSha256 != expectedRgbSha256 ||
        sha256.convert(bytes).toString() != mapSha256) {
      throw const FormatException('experimental depth/RGB identity mismatch');
    }
    if (width <= 0 ||
        height <= 0 ||
        width * height > 1024 * 1024 ||
        bytes.length != width * height * 4) {
      throw const FormatException('invalid experimental depth map dimensions');
    }
    if (sourceTimestampUs < 0 ||
        evaluatedAtUs < sourceTimestampUs ||
        maximumAge.inMicroseconds <= 0 ||
        evaluatedAtUs - sourceTimestampUs > maximumAge.inMicroseconds) {
      throw const FormatException('stale or future experimental depth frame');
    }
    if (!diagnosticFrameQuality.isFinite ||
        diagnosticFrameQuality < 0 ||
        diagnosticFrameQuality > 1) {
      throw const FormatException('invalid diagnostic frame quality');
    }
    final data = ByteData.sublistView(bytes);
    final raw = Float32List(width * height);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = data.getFloat32(i * 4, Endian.little);
      if (!raw[i].isFinite) {
        throw const FormatException('non-finite experimental relative depth');
      }
    }
    final relative = DepthMapOps.normalizeRelativeProximity(raw);
    if (DepthMapOps.countValid(relative) != raw.length) {
      throw const FormatException('degenerate experimental relative depth');
    }
    return DepthFrame(
      values: relative,
      confidence01: Float32List(raw.length)..fillRange(0, raw.length, 1),
      width: width,
      height: height,
      timestampUs: sourceTimestampUs,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: modelId,
      modelHash: modelHash,
      preprocessId: preprocessId,
      cropTopFraction: 0,
      frameQuality: diagnosticFrameQuality,
      alignedToImage: true,
    );
  }
}
