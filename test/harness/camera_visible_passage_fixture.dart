import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:crypto/crypto.dart';

const visibleRoot = 'test/fixtures/spatial_safety/camera-visible-passage-v1';
const visibleStamp = 1790899200000000;
const visibleRequest = PassageClearanceRequest(
  referenceFrameId: 'synthetic-walking-frame-v1',
  lateralCenterM: 0,
  widthM: .9,
  headroomM: 1.8,
  forwardStartM: .2,
  forwardEndM: 3.5,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);
const visibleScanPolicy = PassageClearancePolicy(
  maximumAgeUs: 3000000,
  maximumPairSkewUs: 50000,
  maximumProcessingLatencyUs: 100000,
  minimumConfidence: .99,
);
const visibleSinglePolicy = PassageClearancePolicy(
  maximumAgeUs: 400000,
  maximumPairSkewUs: 50000,
  maximumProcessingLatencyUs: 100000,
  minimumConfidence: .99,
);

Map<String, dynamic> visibleJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
String visibleSha(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

List<double> visibleFloats(String path) {
  final bytes = gzip.decode(File(path).readAsBytesSync());
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return List.generate(
    bytes.length ~/ 4,
    (i) => data.getFloat32(i * 4, Endian.little),
  );
}

class VisibleFixture {
  final String root;
  late final Map<String, dynamic> manifest = visibleJson('$root/manifest.json');
  late final Map<String, dynamic> ncnn = visibleJson(
    '$root/ncnn/manifest.json',
  );
  final _cache = <String, List<CameraVisibleDepthFrame>>{};
  late final String modelHash = visibleSha('$root/manifest.json');

  VisibleFixture({this.root = visibleRoot}) {
    if (ncnn['corpusManifestSha256'] != modelHash) {
      throw StateError('MiDaS corpus mismatch');
    }
    for (final path in [
      'assets/midas_small.ncnn.param',
      'assets/midas_small.ncnn.bin',
    ]) {
      final key = path.endsWith('param')
          ? 'modelParamSha256'
          : 'modelBinSha256';
      if (visibleSha(path) != ncnn[key]) {
        throw StateError('MiDaS model mismatch');
      }
    }
  }

  PassageCalibration calibration({bool metric = true}) => PassageCalibration(
    id: 'synthetic-visible-calibration-v1',
    providerId: 'synthetic-visible-camera',
    modelId: 'first-return-visible-v1',
    modelHash: modelHash,
    preprocessId: 'calibrated-whole-pixel-footprint-v1',
    referenceFrameId: visibleRequest.referenceFrameId,
    transformId: 'synthetic-optical-centre-fixed-v1',
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: metric,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  List<double> _asset(Map<String, dynamic> a) {
    final relative = a['path'] as String;
    if (relative.startsWith('/') ||
        relative.contains('..') ||
        relative.contains('\\')) {
      throw StateError('Unsafe asset path');
    }
    final path = '$root/$relative';
    if (visibleSha(path) != a['sha256']) {
      throw StateError('Visible asset hash mismatch $relative');
    }
    return visibleFloats(path);
  }

  List<CameraVisibleDepthFrame> frames(Map<String, dynamic> layout) {
    return _cache.putIfAbsent(
      layout['id'] as String,
      () => [
        for (final item in layout['frames'] as List)
          _frame(item as Map<String, dynamic>),
      ],
    );
  }

  CameraVisibleDepthFrame _frame(Map<String, dynamic> f) {
    final v = f['validity'] as Map<String, dynamic>;
    final path = '$root/${v['path']}';
    if (visibleSha(path) != v['sha256']) {
      throw StateError('Validity hash mismatch');
    }
    final rgb = f['rgb'] as Map<String, dynamic>;
    if (visibleSha('$root/${rgb['path']}') != rgb['sha256']) {
      throw StateError('RGB hash mismatch');
    }
    return CameraVisibleDepthFrame(
      width: f['width'] as int,
      height: f['height'] as int,
      frameId: f['frameId'] as int,
      capturedAtUs: visibleStamp + (f['capturedOffsetUs'] as int),
      sessionGeneration: 1,
      fx: (f['fx'] as num).toDouble(),
      fy: (f['fy'] as num).toDouble(),
      cx: (f['cx'] as num).toDouble(),
      cy: (f['cy'] as num).toDouble(),
      errorM: 0,
      poseQuality: (f['poseQuality'] as num).toDouble(),
      cameraId: 'one-synthetic-camera',
      modelHash: modelHash,
      transformId: 'synthetic-optical-centre-fixed-v1',
      referenceFrameId: visibleRequest.referenceFrameId,
      units: PassageUnits.metricMeters,
      providerHealthy: true,
      rotation: (f['cameraToWalkingRotation'] as List)
          .map((x) => (x as num).toDouble())
          .toList(),
      originM: (f['cameraOriginM'] as List)
          .map((x) => (x as num).toDouble())
          .toList(),
      rangeM: _asset(f['depth']),
      freeZLowerM: _asset(f['freeZLower']),
      surfaceZUpperM: _asset(f['surfaceZUpper']),
      valid: gzip
          .decode(File(path).readAsBytesSync())
          .map((v) => v == 1)
          .toList(),
    );
  }

  List<double> raw(
    Map<String, dynamic> layout,
    int frameId, {
    String variant = 'clean',
  }) {
    final record = (ncnn['frames'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (r) =>
              r['layoutId'] == layout['id'] &&
              r['frameId'] == frameId &&
              r['variant'] == variant,
        );
    final path = '$root/ncnn/${record['path']}';
    if (visibleSha(path) != record['sha256']) {
      throw StateError('NCNN output hash mismatch');
    }
    return visibleFloats(path);
  }
}

CameraVisibleDepthFrame copyVisibleFrame(
  CameraVisibleDepthFrame f, {
  List<double>? range,
  List<double>? lower,
  List<double>? upper,
  List<bool>? valid,
  List<double>? rotation,
  List<double>? origin,
  double? error,
  double? pose,
  int? frameId,
  int? timestamp,
  int? session,
  String? transform,
  String? modelHash,
  String? referenceFrame,
  String? cameraId,
  PassageUnits? units,
  bool? healthy,
}) => CameraVisibleDepthFrame(
  width: f.width,
  height: f.height,
  frameId: frameId ?? f.frameId,
  capturedAtUs: timestamp ?? f.capturedAtUs,
  sessionGeneration: session ?? f.sessionGeneration,
  fx: f.fx,
  fy: f.fy,
  cx: f.cx,
  cy: f.cy,
  errorM: error ?? f.errorM,
  poseQuality: pose ?? f.poseQuality,
  cameraId: cameraId ?? f.cameraId,
  modelHash: modelHash ?? f.modelHash,
  transformId: transform ?? f.transformId,
  referenceFrameId: referenceFrame ?? f.referenceFrameId,
  units: units ?? f.units,
  providerHealthy: healthy ?? f.providerHealthy,
  rotation: rotation ?? f.rotation,
  originM: origin ?? f.originM,
  rangeM: range ?? f.rangeM,
  freeZLowerM: lower ?? f.freeZLowerM,
  surfaceZUpperM: upper ?? f.surfaceZUpperM,
  valid: valid ?? f.valid,
);

CameraVisibleDepthFrame damagedVisibleFrame(
  CameraVisibleDepthFrame f,
  String condition,
) {
  final rng = math.Random(9000 + f.frameId),
      range = f.rangeM.toList(),
      lo = f.freeZLowerM.toList(),
      hi = f.surfaceZUpperM.toList(),
      valid = f.valid.toList();
  final sigma = condition == 'noise5'
      ? .005
      : condition == 'noise20'
      ? .02
      : 0.0;
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      final i = y * f.width + x;
      if (condition == 'drop10' && rng.nextDouble() < .1 ||
          condition == 'drop40' && rng.nextDouble() < .4 ||
          condition == 'strip' && x >= f.width * .45 && x <= f.width * .55) {
        valid[i] = false;
        range[i] = lo[i] = hi[i] = double.nan;
      }
      if (sigma > 0 && valid[i]) {
        final gaussian =
            math.sqrt(-2 * math.log(math.max(1e-12, rng.nextDouble()))) *
            math.cos(2 * math.pi * rng.nextDouble());
        final noise = gaussian.clamp(-3, 3) * sigma;
        range[i] += noise;
        lo[i] += noise;
        hi[i] += noise;
      }
    }
  }
  return copyVisibleFrame(
    f,
    range: range,
    lower: lo,
    upper: hi,
    valid: valid,
    error: 3 * sigma,
  );
}

CameraVisibleDepthFrame modelGridReference(CameraVisibleDepthFrame f) {
  const size = 256;
  final range = <double>[], lo = <double>[], hi = <double>[], valid = <bool>[];
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final sx = x * f.width ~/ size, sy = y * f.height ~/ size;
      range.add(f.rangeM[sy * f.width + sx]);
      var lower = double.infinity, upper = 0.0, ok = true, surface = true;
      final x1 = (((x + 1) * f.width / size).ceil() - 1).clamp(0, f.width - 1);
      final y1 = (((y + 1) * f.height / size).ceil() - 1).clamp(
        0,
        f.height - 1,
      );
      for (var yy = sy; yy <= y1; yy++) {
        for (var xx = sx; xx <= x1; xx++) {
          final i = yy * f.width + xx;
          ok &= f.valid[i] && f.freeZLowerM[i].isFinite;
          surface &= f.surfaceZUpperM[i].isFinite;
          lower = math.min(lower, f.freeZLowerM[i]);
          upper = math.max(upper, f.surfaceZUpperM[i]);
        }
      }
      lo.add(ok ? lower : double.nan);
      hi.add(surface ? upper : double.nan);
      valid.add(ok);
    }
  }
  return CameraVisibleDepthFrame(
    width: size,
    height: size,
    frameId: f.frameId,
    capturedAtUs: f.capturedAtUs,
    sessionGeneration: f.sessionGeneration,
    fx: f.fx * size / f.width,
    fy: f.fy * size / f.height,
    cx: f.cx * size / f.width,
    cy: f.cy * size / f.height,
    errorM: .02,
    poseQuality: f.poseQuality,
    cameraId: f.cameraId,
    modelHash: f.modelHash,
    transformId: f.transformId,
    referenceFrameId: f.referenceFrameId,
    units: f.units,
    providerHealthy: f.providerHealthy,
    rotation: f.rotation,
    originM: f.originM,
    rangeM: range,
    freeZLowerM: lo,
    surfaceZUpperM: hi,
    valid: valid,
  );
}

/// Frozen affine fit; no reference depth, validity mask or test labels are
/// used. These are empirical diagnostic intervals, never device calibration.
CameraVisibleDepthFrame diagnosticMidasFrame(
  CameraVisibleDepthFrame f,
  List<double> raw,
  Map<String, dynamic> fit,
) {
  const size = 256;
  final a = (fit['a'] as num).toDouble(), b = (fit['b'] as num).toDouble();
  final error = (fit['validationAbsErrorMaxM'] as num).toDouble();
  final fx = f.fx * size / f.width,
      fy = f.fy * size / f.height,
      cx = f.cx * size / f.width,
      cy = f.cy * size / f.height;
  final axis = raw
      .map((p) => a * p + b > 0 ? 1 / (a * p + b) : double.nan)
      .toList();
  final range = <double>[],
      lower = <double>[],
      upper = <double>[],
      valid = <bool>[];
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x, z = axis[i];
      var lo = z, hi = z;
      for (var yy = math.max(0, y - 1); yy <= math.min(size - 1, y + 1); yy++) {
        for (
          var xx = math.max(0, x - 1);
          xx <= math.min(size - 1, x + 1);
          xx++
        ) {
          lo = math.min(lo, axis[yy * size + xx]);
          hi = math.max(hi, axis[yy * size + xx]);
        }
      }
      range.add(
        z *
            math.sqrt(
              1 +
                  math.pow((x + .5 - cx) / fx, 2) +
                  math.pow((y + .5 - cy) / fy, 2),
            ),
      );
      lower.add(math.max(0, lo - error));
      upper.add(hi + error);
      valid.add(z.isFinite && z > 0 && lo.isFinite && hi.isFinite);
    }
  }
  return CameraVisibleDepthFrame(
    width: size,
    height: size,
    frameId: f.frameId,
    capturedAtUs: f.capturedAtUs,
    sessionGeneration: f.sessionGeneration,
    fx: fx,
    fy: fy,
    cx: cx,
    cy: cy,
    errorM: 0,
    poseQuality: f.poseQuality,
    cameraId: f.cameraId,
    modelHash: f.modelHash,
    transformId: f.transformId,
    referenceFrameId: f.referenceFrameId,
    units: PassageUnits.metricMeters,
    providerHealthy: fit['accepted'] == true,
    rotation: f.rotation,
    originM: f.originM,
    rangeM: range,
    freeZLowerM: lower,
    surfaceZUpperM: upper,
    valid: valid,
  );
}
