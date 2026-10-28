import 'dart:math' as math;
import 'dart:typed_data';

import 'camera_height_envelope_passage_source.dart';
import 'camera_passage_clearance_source.dart';
import 'passage_clearance.dart';

class _Box {
  final double x0, x1, y0, y1, z0, z1;
  const _Box(this.x0, this.x1, this.y0, this.y1, this.z0, this.z1);
}

/// Exact count of rejected pixels over a closed rectangle. No area averaging.
class _BadPixels {
  final int stride;
  final Int32List sums;

  _BadPixels(int width, int height, List<bool> bad)
    : stride = width + 1,
      sums = Int32List((width + 1) * (height + 1)) {
    for (var y = 0; y < height; y++) {
      var row = 0;
      for (var x = 0; x < width; x++) {
        if (bad[y * width + x]) row++;
        sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row;
      }
    }
  }

  int count(int x0, int x1, int y0, int y1) =>
      sums[(y1 + 1) * stride + x1 + 1] -
      sums[y0 * stride + x1 + 1] -
      sums[(y1 + 1) * stride + x0] +
      sums[y0 * stride + x0];
}

class _PixelIndex {
  static const tileSize = 8;
  final CameraVisibleDepthFrame frame;
  final Float64List centreZ, lower, tileMinimum;
  final int tileWidth;
  late final _BadPixels freeBad, floorBad;
  bool envelopeHealthy = true;

  _PixelIndex(CameraHeightEnvelopeFrame e, PassageClearanceRequest request)
    : frame = e.depth,
      centreZ = Float64List(e.depth.width * e.depth.height),
      lower = Float64List(e.depth.width * e.depth.height),
      tileWidth = (e.depth.width + tileSize - 1) ~/ tileSize,
      tileMinimum = Float64List(
        ((e.depth.width + tileSize - 1) ~/ tileSize) *
            ((e.depth.height + tileSize - 1) ~/ tileSize),
      ) {
    final f = frame, n = f.width * f.height;
    final freeRejected = List<bool>.filled(n, false);
    final floorRejected = List<bool>.filled(n, false);
    tileMinimum.fillRange(0, tileMinimum.length, double.infinity);
    for (var y = 0; y < f.height; y++) {
      for (var x = 0; x < f.width; x++) {
        final i = y * f.width + x;
        final norm = math.sqrt(
          1 +
              math.pow((x + .5 - f.cx) / f.fx, 2) +
              math.pow((y + .5 - f.cy) / f.fy, 2),
        );
        final z = centreZ[i] = f.rangeM[i] / norm;
        final firstZ = e.firstZLowerM[i];
        final heightLo = e.heightLowerM[i], heightHi = e.heightUpperM[i];
        // Same envelope admission predicates as the frozen producer, fused
        // with indexing so ray norms and heights are calculated only once.
        if (!firstZ.isNaN &&
            (!firstZ.isFinite ||
                firstZ < 0 ||
                !z.isFinite ||
                !f.valid[i] ||
                firstZ > z + f.errorM + 1e-5 ||
                firstZ < f.freeZLowerM[i] - f.errorM - 2e-5)) {
          envelopeHealthy = false;
        }
        if (!(heightLo.isNaN && heightHi.isNaN)) {
          final a = (x + .5 - f.cx) / f.fx * z;
          final b = (y + .5 - f.cy) / f.fy * z;
          final height =
              f.originM[2] +
              f.rotation[6] * a +
              f.rotation[7] * b +
              f.rotation[8] * z;
          if (firstZ.isNaN ||
              !heightLo.isFinite ||
              !heightHi.isFinite ||
              heightLo > heightHi ||
              !f.valid[i] ||
              !height.isFinite ||
              height < heightLo - f.errorM - 1e-5 ||
              height > heightHi + f.errorM + 1e-5) {
            envelopeHealthy = false;
          }
        }
        // Match the frozen body producer's independent first-Z substitution.
        final lo = lower[i] = e.firstZLowerM[i].isFinite
            ? e.firstZLowerM[i]
            : f.freeZLowerM[i];
        final hi = f.surfaceZUpperM[i];
        freeRejected[i] =
            !f.valid[i] ||
            !f.rangeM[i].isFinite ||
            f.rangeM[i] <= 0 ||
            !lo.isFinite ||
            lo < 0 ||
            !(lo <= z + f.errorM + 1e-5 &&
                (hi.isNaN || hi.isFinite && hi >= z - f.errorM - 1e-5));
        final tile = (y ~/ tileSize) * tileWidth + x ~/ tileSize;
        if (lo.isFinite) tileMinimum[tile] = math.min(tileMinimum[tile], lo);
        // The floor predicate uses original axis bounds and independent height.
        // Body free-Z does not repair a missing surface or height observation.
        final axisLo = f.freeZLowerM[i];
        floorRejected[i] =
            !f.valid[i] ||
            !f.rangeM[i].isFinite ||
            f.rangeM[i] <= 0 ||
            !axisLo.isFinite ||
            !hi.isFinite ||
            axisLo < 0 ||
            hi < axisLo ||
            !heightLo.isFinite ||
            !heightHi.isFinite ||
            heightLo > heightHi ||
            heightLo - f.errorM < -request.maximumFloorDropM ||
            heightHi + f.errorM > request.maximumFloorRiseM ||
            axisLo > z + f.errorM + 1e-5 ||
            hi < z - f.errorM - 1e-5;
      }
    }
    freeBad = _BadPixels(f.width, f.height, freeRejected);
    floorBad = _BadPixels(f.width, f.height, floorRejected);
  }

  /// Minimum over exactly the requested rectangle. Only fully contained tiles
  /// use a cached minimum; all boundary pixels are visited individually.
  double minimum(int x0, int x1, int y0, int y1) {
    var result = double.infinity;
    for (var ty = y0 ~/ tileSize; ty <= y1 ~/ tileSize; ty++) {
      final a = math.max(y0, ty * tileSize);
      final b = math.min(y1, (ty + 1) * tileSize - 1);
      for (var tx = x0 ~/ tileSize; tx <= x1 ~/ tileSize; tx++) {
        final c = math.max(x0, tx * tileSize);
        final d = math.min(x1, (tx + 1) * tileSize - 1);
        if (a == ty * tileSize &&
            b == (ty + 1) * tileSize - 1 &&
            c == tx * tileSize &&
            d == (tx + 1) * tileSize - 1) {
          result = math.min(result, tileMinimum[ty * tileWidth + tx]);
        } else {
          for (var y = a; y <= b; y++) {
            for (var x = c; x <= d; x++) {
              result = math.min(result, lower[y * frame.width + x]);
            }
          }
        }
      }
    }
    return result;
  }
}

/// Opt-in synthetic-only successor to the frozen complete-envelope source.
/// Pixel predicates are identical to that source. Rectangle indexes only
/// accelerate exhaustive whole-footprint checks; unknown pixels remain unknown.
/// Coverage is computed once for this immutable input/request, never retimestamped.
/// No normal-camera, model, planner, TTS or haptic wiring.
class CameraIndexedHeightEnvelopePassageSource
    implements PassageClearanceEvidenceSource {
  final PassageCalibration calibration;
  final PassageClearanceRequest request;
  final List<CameraVisibleDepthFrame> frames;
  final List<CameraHeightEnvelopeFrame> envelopes;
  final _indexes = <CameraVisibleDepthFrame, _PixelIndex>{};
  final stageComputeUs = <String, int>{};
  final int producedAtUs;
  final double cellSizeM;
  final int refinementDepth;
  late final bool _healthy;
  late final List<PassageSection> _sections;
  final List<String> diagnostics = [];
  int certifiedBodyBoxes = 0, unknownBodyBoxes = 0;
  final List<List<double>> unobservedBodyCellCenters = [];

  CameraIndexedHeightEnvelopePassageSource({
    required this.calibration,
    required this.request,
    required List<CameraHeightEnvelopeFrame> frames,
    required this.producedAtUs,
    this.cellSizeM = .15,
    this.refinementDepth = 4,
  }) : envelopes = List.unmodifiable(frames),
       frames = List.unmodifiable(frames.map((e) => e.depth)) {
    final watch = Stopwatch()..start();
    var healthy = _validate();
    stageComputeUs['validation'] = watch.elapsedMicroseconds;
    watch.reset();
    if (healthy) {
      for (final e in envelopes) {
        final index = _PixelIndex(e, request);
        _indexes[e.depth] = index;
        if (!index.envelopeHealthy) {
          healthy = false;
          break;
        }
      }
    }
    _healthy = healthy;
    stageComputeUs['pixelIndexAndEnvelopeValidation'] =
        watch.elapsedMicroseconds;
    watch.reset();
    _sections = _healthy ? _measure() : const [];
    stageComputeUs['coverage'] = watch.elapsedMicroseconds;
    watch.stop();
  }

  @override
  String get providerId => calibration.providerId;

  bool _validate() {
    if (frames.isEmpty ||
        frames.length > 12 ||
        !cellSizeM.isFinite ||
        cellSizeM < .02 ||
        cellSizeM > .2 ||
        refinementDepth < 0 ||
        refinementDepth > 4 ||
        producedAtUs < 0) {
      diagnostics.add('invalid_scan_configuration');
      return false;
    }
    if (envelopes.any(
      (e) =>
          e.heightLowerM.length != e.depth.width * e.depth.height ||
          e.heightUpperM.length != e.heightLowerM.length ||
          e.firstZLowerM.length != e.heightLowerM.length,
    )) {
      diagnostics.add('invalid_envelope_shape');
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
    final r = f.rotation, o = f.originM;
    for (final x in [box.x0, box.x1]) {
      for (final y in [box.y0, box.y1]) {
        for (final z in [box.z0, box.z1]) {
          final a = x - o[0], b = y - o[1], c = z - o[2];
          final p0 = r[0] * a + r[3] * b + r[6] * c;
          final p1 = r[1] * a + r[4] * b + r[7] * c;
          final p2 = r[2] * a + r[5] * b + r[8] * c;
          if (p2 <= .01) return null;
          final u = f.fx * p0 / p2 + f.cx, v = f.fy * p1 / p2 + f.cy;
          u0 = math.min(u0, u);
          u1 = math.max(u1, u);
          v0 = math.min(v0, v);
          v1 = math.max(v1, v);
          maxZ = math.max(maxZ, p2);
        }
      }
    }
    if (u0 < 0 || v0 < 0 || u1 >= f.width || v1 >= f.height) return null;
    return [u0.floor(), u1.floor(), v0.floor(), v1.floor(), maxZ];
  }

  bool _freeIn(CameraVisibleDepthFrame f, _Box box) {
    final p = _project(f, box);
    if (p == null) return false;
    final index = _indexes[f]!;
    final x0 = p[0].toInt(), x1 = p[1].toInt();
    final y0 = p[2].toInt(), y1 = p[3].toInt();
    return index.freeBad.count(x0, x1, y0, y1) == 0 &&
        index.minimum(x0, x1, y0, y1) - f.errorM > p[4];
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
    return _indexes[f]!.floorBad.count(
          p[0].toInt(),
          p[1].toInt(),
          p[2].toInt(),
          p[3].toInt(),
        ) ==
        0;
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
          final p = f.worldPoint(x, y, _indexes[f]!.centreZ[i]);
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
