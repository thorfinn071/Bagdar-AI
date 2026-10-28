import 'dart:math' as math;

import 'passage_clearance.dart';

/// A camera-only first-return map. Bounds cover entire pixel footprints;
/// centre depths alone MUST NOT be substituted for these bounds. Axis bounds
/// are in camera forward-Z; [rangeM] is Euclidean range. Rotation maps camera
/// right/down/forward to walking lateral/forward/height. No labels or meshes.
class CameraVisibleDepthFrame {
  final int width, height, frameId, capturedAtUs, sessionGeneration;
  final double fx, fy, cx, cy, errorM, poseQuality;
  final String cameraId, modelHash, transformId, referenceFrameId;
  final PassageUnits units;
  final bool providerHealthy;
  final List<double> rotation, originM, rangeM, freeZLowerM, surfaceZUpperM;
  final List<bool> valid;

  CameraVisibleDepthFrame({
    required this.width,
    required this.height,
    required this.frameId,
    required this.capturedAtUs,
    required this.sessionGeneration,
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required this.errorM,
    required this.poseQuality,
    required this.cameraId,
    required this.modelHash,
    required this.transformId,
    required this.referenceFrameId,
    required this.units,
    required this.providerHealthy,
    required List<double> rotation,
    required List<double> originM,
    required List<double> rangeM,
    required List<double> freeZLowerM,
    required List<double> surfaceZUpperM,
    required List<bool> valid,
  }) : rotation = List.unmodifiable(rotation),
       originM = List.unmodifiable(originM),
       rangeM = List.unmodifiable(rangeM),
       freeZLowerM = List.unmodifiable(freeZLowerM),
       surfaceZUpperM = List.unmodifiable(surfaceZUpperM),
       valid = List.unmodifiable(valid);

  bool get structurallyValid {
    final n = width * height;
    if (width <= 0 ||
        height <= 0 ||
        n > 1048576 ||
        frameId <= 0 ||
        capturedAtUs < 0 ||
        sessionGeneration < 0 ||
        !fx.isFinite ||
        !fy.isFinite ||
        fx <= 0 ||
        fy <= 0 ||
        !cx.isFinite ||
        !cy.isFinite ||
        cx < 0 ||
        cx > width ||
        cy < 0 ||
        cy > height ||
        !errorM.isFinite ||
        errorM < 0 ||
        !poseQuality.isFinite ||
        poseQuality < .9 ||
        poseQuality > 1 ||
        !providerHealthy ||
        units != PassageUnits.metricMeters ||
        [
          cameraId,
          modelHash,
          transformId,
          referenceFrameId,
        ].any((s) => s.isEmpty) ||
        rotation.length != 9 ||
        originM.length != 3 ||
        rotation.any((x) => !x.isFinite) ||
        originM.any((x) => !x.isFinite) ||
        [
          rangeM.length,
          freeZLowerM.length,
          surfaceZUpperM.length,
          valid.length,
        ].any((x) => x != n)) {
      return false;
    }
    // Reject distorted/reflected pose matrices, not only missing pose values.
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var dot = 0.0;
        for (var k = 0; k < 3; k++) {
          dot += rotation[k * 3 + i] * rotation[k * 3 + j];
        }
        if ((dot - (i == j ? 1 : 0)).abs() > 1e-5) return false;
      }
    }
    final r = rotation;
    final det =
        r[0] * (r[4] * r[8] - r[5] * r[7]) -
        r[1] * (r[3] * r[8] - r[5] * r[6]) +
        r[2] * (r[3] * r[7] - r[4] * r[6]);
    return (det - 1).abs() < 1e-5;
  }

  List<double> worldPoint(int x, int y, double axisZ) {
    final a = (x + .5 - cx) / fx * axisZ;
    final b = (y + .5 - cy) / fy * axisZ;
    return [
      for (var row = 0; row < 3; row++)
        originM[row] +
            rotation[row * 3] * a +
            rotation[row * 3 + 1] * b +
            rotation[row * 3 + 2] * axisZ,
    ];
  }

  List<double> cameraPoint(List<double> p) => [
    for (var col = 0; col < 3; col++)
      rotation[col] * (p[0] - originM[0]) +
          rotation[3 + col] * (p[1] - originM[1]) +
          rotation[6 + col] * (p[2] - originM[2]),
  ];
}

class _Box {
  final double x0, x1, y0, y1, z0, z1;
  const _Box(this.x0, this.x1, this.y0, this.y1, this.z0, this.z1);
  List<List<double>> get corners => [
    for (final x in [x0, x1])
      for (final y in [y0, y1])
        for (final z in [z0, z1]) [x, y, z],
  ];
}

/// Experimental, synthetic-only source. A box is free only if its ENTIRE
/// projected footprint precedes conservative first-return bounds. Subdivision
/// covers view seams, never fills depth holes. Floor support is independently
/// bounded from whole-pixel surface depth. No sparse-sample coverage claims.
class CameraPassageClearanceSource implements PassageClearanceEvidenceSource {
  final PassageCalibration calibration;
  final PassageClearanceRequest request;
  final List<CameraVisibleDepthFrame> frames;
  final bool allowStaticSyntheticScan;
  final int producedAtUs;
  final double cellSizeM;
  final int refinementDepth;
  late final bool _healthy;
  late final List<PassageSection> _sections;
  final List<String> diagnostics = [];
  int certifiedBodyBoxes = 0, unknownBodyBoxes = 0;
  final List<List<double>> unobservedBodyCellCenters = [];

  CameraPassageClearanceSource({
    required this.calibration,
    required this.request,
    required List<CameraVisibleDepthFrame> frames,
    required this.producedAtUs,
    this.allowStaticSyntheticScan = false,
    this.cellSizeM = .15,
    this.refinementDepth = 4,
  }) : frames = List.unmodifiable(frames) {
    _healthy = _validate();
    _sections = _healthy ? _measure() : const [];
  }

  @override
  String get providerId => calibration.providerId;

  bool _validate() {
    if (frames.isEmpty ||
        frames.length > 12 ||
        (!allowStaticSyntheticScan && frames.length != 1) ||
        !cellSizeM.isFinite ||
        cellSizeM < .02 ||
        cellSizeM > .2 ||
        refinementDepth < 0 ||
        refinementDepth > 4 ||
        producedAtUs < 0) {
      diagnostics.add('invalid_scan_configuration');
      return false;
    }
    final first = frames.first;
    var previous = -1;
    final ids = <int>{};
    for (final f in frames) {
      if (!f.structurallyValid ||
          f.cameraId != first.cameraId ||
          f.modelHash != calibration.modelHash ||
          f.referenceFrameId != calibration.referenceFrameId ||
          f.transformId != calibration.transformId ||
          f.sessionGeneration != first.sessionGeneration ||
          f.capturedAtUs <= previous ||
          !ids.add(f.frameId) ||
          f.capturedAtUs > producedAtUs ||
          List.generate(
            3,
            (i) => (f.originM[i] - first.originM[i]).abs(),
          ).any((x) => x > 1e-6)) {
        diagnostics.add('incompatible_provider_pose_identity_or_time');
        return false;
      }
      previous = f.capturedAtUs;
    }
    if (frames.last.capturedAtUs - first.capturedAtUs > 3000000) {
      diagnostics.add('scan_window_exceeded');
      return false;
    }
    return true;
  }

  @override
  PassageClearanceObservation? observationFor(
    PassageEvaluationContext context,
  ) {
    if (frames.isEmpty) return null;
    final last = frames.last;
    return PassageClearanceObservation(
      providerId: providerId,
      modelId: calibration.modelId,
      modelHash: calibration.modelHash,
      preprocessId: calibration.preprocessId,
      calibrationId: calibration.id,
      referenceFrameId: calibration.referenceFrameId,
      rgbTransformId: last.transformId,
      depthTransformId: last.transformId,
      timestampDomain: calibration.timestampDomain,
      units: last.units,
      sessionGeneration: last.sessionGeneration,
      frameId: last.frameId,
      rgbTimestampUs: last.capturedAtUs,
      depthTimestampUs: last.capturedAtUs,
      oldestEvidenceTimestampUs: frames.first.capturedAtUs,
      producedAtUs: producedAtUs,
      providerHealthy: _healthy,
      sections: _sections,
    );
  }

  /// Pixel rectangle containing the whole perspective projection of a box.
  /// Requiring every pixel avoids claiming the space between centre rays.
  List<num>? _project(CameraVisibleDepthFrame f, _Box box) {
    var u0 = double.infinity,
        v0 = double.infinity,
        u1 = -double.infinity,
        v1 = -double.infinity,
        maxZ = 0.0;
    for (final corner in box.corners) {
      final p = f.cameraPoint(corner);
      if (p[2] <= .01) return null;
      final u = f.fx * p[0] / p[2] + f.cx, v = f.fy * p[1] / p[2] + f.cy;
      u0 = math.min(u0, u);
      u1 = math.max(u1, u);
      v0 = math.min(v0, v);
      v1 = math.max(v1, v);
      maxZ = math.max(maxZ, p[2]);
    }
    if (u0 < 0 || v0 < 0 || u1 >= f.width || v1 >= f.height) return null;
    return [u0.floor(), u1.floor(), v0.floor(), v1.floor(), maxZ];
  }

  bool _freeIn(CameraVisibleDepthFrame f, _Box box) {
    final p = _project(f, box);
    if (p == null) return false;
    for (var y = p[2].toInt(); y <= p[3]; y++) {
      for (var x = p[0].toInt(); x <= p[1]; x++) {
        final i = y * f.width + x, lower = f.freeZLowerM[i];
        if (!f.valid[i] ||
            !f.rangeM[i].isFinite ||
            f.rangeM[i] <= 0 ||
            !lower.isFinite ||
            lower < 0 ||
            !_pixelBoundsCompatible(f, x, y) ||
            lower - f.errorM <= p[4]) {
          return false;
        }
      }
    }
    return true;
  }

  bool _pixelBoundsCompatible(CameraVisibleDepthFrame f, int x, int y) {
    final i = y * f.width + x;
    final norm = math.sqrt(
      1 +
          math.pow((x + .5 - f.cx) / f.fx, 2) +
          math.pow((y + .5 - f.cy) / f.fy, 2),
    );
    final centreZ = f.rangeM[i] / norm, upper = f.surfaceZUpperM[i];
    // NaN upper bounds mean no certified surface patch, but free bounds still
    // cannot extend behind the measured centre return. Allow float32 rounding.
    return f.freeZLowerM[i] <= centreZ + f.errorM + 1e-5 &&
        (upper.isNaN || upper.isFinite && upper >= centreZ - f.errorM - 1e-5);
  }

  bool _free(_Box b, int depth) {
    if (frames.any((f) => _freeIn(f, b))) return true;
    if (depth == 0) return false;
    final xm = (b.x0 + b.x1) / 2,
        ym = (b.y0 + b.y1) / 2,
        zm = (b.z0 + b.z1) / 2;
    for (final x in [
      [b.x0, xm],
      [xm, b.x1],
    ]) {
      for (final y in [
        [b.y0, ym],
        [ym, b.y1],
      ]) {
        for (final z in [
          [b.z0, zm],
          [zm, b.z1],
        ]) {
          if (!_free(_Box(x[0], x[1], y[0], y[1], z[0], z[1]), depth - 1)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  bool _floorIn(CameraVisibleDepthFrame f, _Box patch) {
    final p = _project(f, patch);
    if (p == null) return false;
    for (var y = p[2].toInt(); y <= p[3]; y++) {
      for (var x = p[0].toInt(); x <= p[1]; x++) {
        final i = y * f.width + x,
            lo = f.freeZLowerM[i],
            hi = f.surfaceZUpperM[i];
        if (!f.valid[i] ||
            !f.rangeM[i].isFinite ||
            f.rangeM[i] <= 0 ||
            !lo.isFinite ||
            lo < 0 ||
            !hi.isFinite ||
            hi < lo ||
            !_pixelBoundsCompatible(f, x, y)) {
          return false;
        }
        // Bounds for every ray in the pixel and every possible surface depth.
        for (final u in [x.toDouble(), x + 1.0]) {
          for (final v in [y.toDouble(), y + 1.0]) {
            for (final z in [math.max(0, lo - f.errorM), hi + f.errorM]) {
              final a = (u - f.cx) / f.fx, b = (v - f.cy) / f.fy;
              final h =
                  f.originM[2] +
                  z * (f.rotation[6] * a + f.rotation[7] * b + f.rotation[8]);
              if (h > request.maximumFloorRiseM ||
                  h < -request.maximumFloorDropM) {
                return false;
              }
            }
          }
        }
      }
    }
    return true;
  }

  bool _floor(_Box b, int depth) {
    if (frames.any((f) => _floorIn(f, b))) return true;
    if (depth == 0) return false;
    final xm = (b.x0 + b.x1) / 2, ym = (b.y0 + b.y1) / 2;
    for (final x in [
      [b.x0, xm],
      [xm, b.x1],
    ]) {
      for (final y in [
        [b.y0, ym],
        [ym, b.y1],
      ]) {
        if (!_floor(_Box(x[0], x[1], y[0], y[1], 0, 0), depth - 1)) {
          return false;
        }
      }
    }
    return true;
  }

  List<PassageSection> _measure() {
    final left = request.lateralCenterM - request.widthM / 2,
        right = request.lateralCenterM + request.widthM / 2;
    if (!left.isFinite ||
        !right.isFinite ||
        request.widthM <= 0 ||
        !request.forwardStartM.isFinite ||
        !request.forwardEndM.isFinite ||
        request.forwardStartM < 0 ||
        request.forwardEndM <= request.forwardStartM ||
        !request.headroomM.isFinite ||
        request.headroomM <= .05 ||
        request.headroomM > 3 ||
        request.forwardEndM > 10 ||
        request.widthM > 3 ||
        !request.maximumFloorRiseM.isFinite ||
        !request.maximumFloorDropM.isFinite ||
        request.maximumFloorRiseM < 0 ||
        request.maximumFloorDropM < 0 ||
        request.maximumFloorRiseM > .5 ||
        request.maximumFloorDropM > .5) {
      diagnostics.add('invalid_or_oversized_request');
      return const [];
    }
    final ny = ((request.forwardEndM - request.forwardStartM) / cellSizeM)
        .ceil();
    if (ny > 128) {
      diagnostics.add('section_budget');
      return const [];
    }
    final bodyTop = request.headroomM + request.maximumFloorRiseM;
    final nx = (request.widthM / cellSizeM).ceil(),
        nz = ((bodyTop - .05) / cellSizeM).ceil();
    final blocked = List<bool>.filled(ny, false);
    var conflict = false;
    for (var fi = 0; fi < frames.length; fi++) {
      final f = frames[fi];
      for (var y = 0; y < f.height; y++) {
        for (var x = 0; x < f.width; x++) {
          final i = y * f.width + x, r = f.rangeM[i];
          if (!f.valid[i] || !r.isFinite || r <= 0) continue;
          final norm = math.sqrt(
            1 +
                math.pow((x + .5 - f.cx) / f.fx, 2) +
                math.pow((y + .5 - f.cy) / f.fy, 2),
          );
          final p = f.worldPoint(x, y, r / norm);
          if (p[0] + f.errorM < left ||
              p[0] - f.errorM > right ||
              p[1] + f.errorM < request.forwardStartM ||
              p[1] - f.errorM > request.forwardEndM) {
            continue;
          }
          final occupied =
              p[2] - f.errorM > request.maximumFloorRiseM &&
                  p[2] - f.errorM < bodyTop ||
              p[2] + f.errorM < -request.maximumFloorDropM;
          if (!occupied) continue;
          for (var s = 0; s < ny; s++) {
            final a =
                request.forwardStartM +
                (request.forwardEndM - request.forwardStartM) * s / ny;
            final b =
                request.forwardStartM +
                (request.forwardEndM - request.forwardStartM) * (s + 1) / ny;
            if (p[1] + f.errorM >= a && p[1] - f.errorM <= b) blocked[s] = true;
          }
          // Old occupied returns cannot be silently erased by newer free rays.
          final epsilon = math.max(.001, f.errorM);
          final pointBox = _Box(
            p[0] - epsilon,
            p[0] + epsilon,
            p[1] - epsilon,
            p[1] + epsilon,
            p[2] - epsilon,
            p[2] + epsilon,
          );
          if (frames.skip(fi + 1).any((next) => _freeIn(next, pointBox))) {
            conflict = true;
          }
        }
      }
    }
    if (conflict) diagnostics.add('temporal_surface_conflict');
    final sections = <PassageSection>[];
    for (var iy = 0; iy < ny; iy++) {
      final a =
          request.forwardStartM +
          (request.forwardEndM - request.forwardStartM) * iy / ny;
      final b =
          request.forwardStartM +
          (request.forwardEndM - request.forwardStartM) * (iy + 1) / ny;
      var bodyCount = 0, floorCount = 0;
      if (!blocked[iy] && !conflict) {
        for (var ix = 0; ix < nx; ix++) {
          final x0 = left + request.widthM * ix / nx,
              x1 = left + request.widthM * (ix + 1) / nx;
          if (_floor(_Box(x0, x1, a, b, 0, 0), refinementDepth)) floorCount++;
          for (var iz = 0; iz < nz; iz++) {
            final z0 = .05 + (bodyTop - .05) * iz / nz,
                z1 = .05 + (bodyTop - .05) * (iz + 1) / nz;
            if (_free(_Box(x0, x1, a, b, z0, z1), refinementDepth)) {
              bodyCount++;
              certifiedBodyBoxes++;
            } else {
              unknownBodyBoxes++;
              if (unobservedBodyCellCenters.length < 32) {
                unobservedBodyCellCenters.add([
                  (x0 + x1) / 2,
                  (a + b) / 2,
                  (z0 + z1) / 2,
                ]);
              }
            }
          }
        }
      }
      final body = bodyCount / (nx * nz), floor = floorCount / nx;
      final measured = body == 1 && floor == 1;
      sections.add(
        PassageSection(
          forwardStartM: a,
          forwardEndM: b,
          state: blocked[iy]
              ? PassageSectionState.blocked
              : conflict
              ? PassageSectionState.conflicting
              : measured
              ? PassageSectionState.measured
              : PassageSectionState.unknown,
          bodyObservedFraction: body,
          floorObservedFraction: floor,
          confidence: 1,
          leftBoundaryUpperM: measured ? left : null,
          rightBoundaryLowerM: measured ? right : null,
          headroomLowerBoundM: measured ? request.headroomM : null,
          floorRiseUpperBoundM: measured ? request.maximumFloorRiseM : null,
          floorDropUpperBoundM: measured ? request.maximumFloorDropM : null,
        ),
      );
    }
    return sections;
  }
}
