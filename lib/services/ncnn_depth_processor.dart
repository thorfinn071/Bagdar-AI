import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/depth_frame.dart';
import '../models/ncnn_depth_contract.dart';
import '../utils/depth_map_ops.dart';
import '../utils/depth_hazard.dart';
import '../utils/ground_plane_analyzer.dart';
import '../utils/ncnn_depth_debug_dump.dart';
import '../utils/ncnn_depth_preprocess.dart';
import 'ncnn_depth_worker_types.dart';

/// The unchanged NCNN normalization/ground analysis, owned by one worker.
class NcnnDepthProcessor {
  static const int _inputSize = NcnnDepthContract.mapSize;
  final NcnnDepthBackend _backend;
  final GroundPlaneAnalyzer _analyzer = GroundPlaneAnalyzer();
  final Uint8List _lumaBuffer = Uint8List(_inputSize * _inputSize);
  final Float32List _frameValues = Float32List(_inputSize * _inputSize);
  final Float32List _frameRelative = Float32List(_inputSize * _inputSize);
  final Float32List _frameConf = Float32List(_inputSize * _inputSize);
  double _prevMean = double.nan;
  double _lastPreprocessMs = 0;
  double _lastInferenceMs = 0;

  NcnnDepthProcessor(this._backend);

  NcnnDepthReply process(NcnnDepthInput input) {
    final timer = Stopwatch()..start();
    _lastPreprocessMs = 0;
    _lastInferenceMs = 0;
    DepthAnalysisResult result;
    try {
      input.validate();
      result = _analyze(input);
    } catch (e) {
      debugPrint('NcnnDepthProcessor: analyze failed ($e)');
      result = NcnnDepthReply.unavailable('exception').result;
    }
    return NcnnDepthReply(
      result: result,
      preprocessMs: _lastPreprocessMs,
      inferenceMs: _lastInferenceMs,
      totalMs: timer.elapsedMicroseconds / 1000,
      planeFitOk: _analyzer.lastPlaneFitOk,
    );
  }

  DepthAnalysisResult _analyze(NcnnDepthInput input) {
    final cropTopFrac = input.cropTopFrac;
    final rotationDegrees = input.rotationDegrees;
    final mirrored = input.mirrored;
    final sourceTimestampUs = input.sourceTimestampUs;
    final userStationary = input.userStationary;
    final weatherDegraded = input.weatherDegraded;
    final winterMode = input.winterMode;
    NcnnDepthDebugDump.consentGranted = input.debugDumpDirectory != null;
    NcnnDepthDebugDump.outputDir = input.debugDumpDirectory;
    if (input.planes.length < 3) {
      debugPrint('NcnnDepthProvider: YUV420 requires 3 planes');
      return DepthAnalysisResult(
        frame: null,
        legacyHazards: const <DepthHazard>[],
        health: DepthHealth.unavailable(
          provider: DepthProviderKind.ncnnRelative,
          reason: 'yuv_planes_missing',
        ),
      );
    }
    final yPlane = input.planes[0];
    final clampedCrop = cropTopFrac.clamp(0.0, 0.9);

    final preSw = Stopwatch()..start();
    _lumaBuffer.setAll(
      0,
      NcnnDepthPreprocess.alignedLuma(
        y: yPlane,
        width: input.width,
        height: input.height,
        rowStride: input.rowStrides[0],
        pixelStride: input.pixelStrides[0],
        rotationDegrees: rotationDegrees,
        mirrored: mirrored,
        cropTopFrac: clampedCrop,
      ),
    );
    preSw.stop();
    _lastPreprocessMs = preSw.elapsedMicroseconds / 1000.0;

    final infSw = Stopwatch()..start();
    final flat = _backend.infer(input);
    infSw.stop();
    _lastInferenceMs = infSw.elapsedMicroseconds / 1000.0;

    if (flat == null || flat.length != _frameValues.length) {
      return DepthAnalysisResult(
        frame: null,
        legacyHazards: const <DepthHazard>[],
        health: DepthHealth.unavailable(
          provider: DepthProviderKind.ncnnRelative,
          reason: 'infer_failed',
        ),
      );
    }

    _frameValues.setAll(0, flat);
    DepthMapOps.sanitizeInPlace(_frameValues);

    final outputClass = _classifyOutput(_frameValues);
    if (outputClass == _OutputClass.invalid) {
      debugPrint(
        'NcnnDepthProvider: invalid output (NaN/Inf) — recording failure',
      );
      return DepthAnalysisResult(
        frame: null,
        legacyHazards: const <DepthHazard>[],
        health: DepthHealth.unavailable(
          provider: DepthProviderKind.ncnnRelative,
          reason: 'nan_inf',
        ),
      );
    }
    if (outputClass == _OutputClass.degenerate) {
      return DepthAnalysisResult(
        frame: null,
        legacyHazards: const <DepthHazard>[],
        health: DepthHealth.unavailable(
          provider: DepthProviderKind.ncnnRelative,
          reason: 'degenerate',
        ),
      );
    }

    final relative = DepthMapOps.normalizeRelativeProximity(_frameValues);
    _frameRelative.setAll(0, relative);
    final valid = DepthMapOps.countValid(_frameRelative);
    final coverage = valid / _frameRelative.length;
    for (int i = 0; i < _frameConf.length; i++) {
      _frameConf[i] = DepthMapOps.isValid(_frameRelative[i]) ? 1.0 : 0.0;
    }
    final minV = DepthMapOps.minValid(_frameValues);
    final maxV = DepthMapOps.maxValid(_frameValues);
    final rawRange = (minV != null && maxV != null) ? (maxV - minV) : 0.0;
    final rangeQuality = (rawRange / 0.5).clamp(0.0, 1.0);
    var mean = 0.0;
    var meanN = 0;
    for (final v in _frameRelative) {
      if (DepthMapOps.isValid(v)) {
        mean += v;
        meanN++;
      }
    }
    if (meanN > 0) mean /= meanN;
    final temporal = (!_prevMean.isFinite || meanN == 0)
        ? 0.5
        : (1.0 - (mean - _prevMean).abs()).clamp(0.0, 1.0);
    _prevMean = mean;

    final components = DepthHealthComponents(
      validCoverage: coverage.clamp(0.0, 1.0),
      dynamicRange: rangeQuality,
      temporalStability: temporal,
      blurLightGate: _computeOutputConfidence(_frameValues),
      providerState: 1.0,
    );
    final ts = sourceTimestampUs > 0
        ? sourceTimestampUs
        : DateTime.now().microsecondsSinceEpoch;
    final normalizedRotation = NcnnDepthPreprocess.normalizeRotation(
      rotationDegrees,
    );
    final frame = DepthFrame(
      values: Float32List.fromList(_frameRelative),
      confidence01: Float32List.fromList(_frameConf),
      width: NcnnDepthContract.mapSize,
      height: NcnnDepthContract.mapSize,
      timestampUs: ts,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: NcnnDepthContract.modelId,
      modelHash: NcnnDepthContract.modelHash,
      preprocessId: NcnnDepthContract.preprocessId,
      cropTopFraction: clampedCrop,
      frameQuality: components.combined,
      alignedToImage: true,
      rotationDegrees: normalizedRotation,
      mirrored: mirrored,
      nativeOutputWidth: _backend.outputWidth,
      nativeOutputHeight: _backend.outputHeight,
    );
    NcnnDepthDebugDump.dump(
      depth: _frameValues,
      width: frame.width,
      height: frame.height,
      provider: 'ncnnRelative',
      timestampUs: ts,
      nativeOutW: frame.nativeOutputWidth,
      nativeOutH: frame.nativeOutputHeight,
      frameQuality: frame.frameQuality,
    );
    final hazards = _analyzer.analyze(
      _frameValues,
      lumaMap: _lumaBuffer,
      userStationary: userStationary,
      weatherDegraded: weatherDegraded,
      winterMode: winterMode,
    );
    final planeFitQuality = _analyzer.lastPlaneFitQuality;
    final healthy =
        components.combined >=
            GenericObstacleConfig.engineeringDefaults.minHealthyFrameQuality &&
        planeFitQuality.accepted;
    return DepthAnalysisResult(
      frame: frame,
      alignedLuma: Uint8List.fromList(_lumaBuffer),
      legacyHazards: hazards,
      planeFitQuality: planeFitQuality,
      health: DepthHealth(
        capability: healthy
            ? DepthCapability.healthyRelative
            : DepthCapability.temporarilyLowConfidence,
        components: components,
        genericObstacleAvailable: healthy,
        provider: DepthProviderKind.ncnnRelative,
        rejectionReason: healthy
            ? null
            : !planeFitQuality.accepted
            ? 'plane_unreliable:${planeFitQuality.rejectionReason.name}'
            : 'ncnn_frame_quality',
      ),
    );
  }

  _OutputClass _classifyOutput(Float32List flat) {
    if (flat.isEmpty) return _OutputClass.invalid;
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    int badCount = 0;
    for (int i = 0; i < flat.length; i++) {
      final v = flat[i];
      if (v.isNaN || v.isInfinite) {
        badCount++;
        continue;
      }
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }

    if (badCount > flat.length ~/ 20) return _OutputClass.invalid;
    if (!minV.isFinite || !maxV.isFinite) return _OutputClass.invalid;

    if ((maxV - minV).abs() < 1e-3) return _OutputClass.degenerate;
    return _OutputClass.ok;
  }

  /// Compute a pseudo-confidence score [0..1] from depth map statistics.
  /// Low range, many near-zero pixels, or low variance indicate poor output.
  double _computeOutputConfidence(Float32List flat) {
    if (flat.isEmpty) return 0;
    final n = flat.length;
    double sum = 0;
    double sqSum = 0;
    int nearZeroCount = 0;
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    for (int i = 0; i < n; i++) {
      final v = flat[i];
      if (!v.isFinite) continue;
      sum += v;
      sqSum += v * v;
      if (v < 0.02) nearZeroCount++;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (!minV.isFinite || !maxV.isFinite) return 0;

    final range = maxV - minV;
    final mean = sum / n;
    final variance = (sqSum / n) - mean * mean;
    final nearZeroRatio = nearZeroCount / n;

    // Score components:
    // 1. Range should be > 0.1 for good depth maps (max 0.3 contribution)
    final rangeScore = (range / 0.5).clamp(0.0, 1.0) * 0.3;
    // 2. Low near-zero ratio (max 0.4 contribution)
    final validScore = (1.0 - nearZeroRatio * 2).clamp(0.0, 1.0) * 0.4;
    // 3. Reasonable variance (max 0.3 contribution)
    final varScore = (variance / 0.01).clamp(0.0, 1.0) * 0.3;

    return (rangeScore + validScore + varScore).clamp(0.0, 1.0);
  }
}

enum _OutputClass { ok, degenerate, invalid }
