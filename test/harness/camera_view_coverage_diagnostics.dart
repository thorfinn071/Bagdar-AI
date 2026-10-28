import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

/// Read-only observer. Its whole-cell replica MUST match the frozen producer
/// before any map is accepted. It is never a passage evidence source.
class CameraViewCoverageDiagnostics {
  final CameraVisibleDepthFrame frame;
  final PassageClearanceRequest request;
  final int refinementDepth;
  final double cellSizeM;

  const CameraViewCoverageDiagnostics({
    required this.frame,
    required this.request,
    this.refinementDepth = 4,
    this.cellSizeM = .15,
  });

  List<num>? _project(List<double> b) {
    var u0 = double.infinity, v0 = double.infinity;
    var u1 = -double.infinity, v1 = -double.infinity, maxZ = 0.0;
    for (final x in [b[0], b[1]]) {
      for (final y in [b[2], b[3]]) {
        for (final z in [b[4], b[5]]) {
          final p = frame.cameraPoint([x, y, z]);
          if (p[2] <= .01) return null;
          final u = frame.fx * p[0] / p[2] + frame.cx;
          final v = frame.fy * p[1] / p[2] + frame.cy;
          u0 = math.min(u0, u);
          v0 = math.min(v0, v);
          u1 = math.max(u1, u);
          v1 = math.max(v1, v);
          maxZ = math.max(maxZ, p[2]);
        }
      }
    }
    if (u0 < 0 || v0 < 0 || u1 >= frame.width || v1 >= frame.height) {
      return null;
    }
    return [u0.floor(), u1.floor(), v0.floor(), v1.floor(), maxZ];
  }

  String? _pixelFailure(int x, int y, {required bool floor}) {
    final f = frame, i = y * f.width + x;
    final lo = f.freeZLowerM[i], hi = f.surfaceZUpperM[i];
    if (!f.valid[i] || !f.rangeM[i].isFinite || f.rangeM[i] <= 0) {
      return 'invalidPixel';
    }
    if (!lo.isFinite || lo < 0 || (floor && (!hi.isFinite || hi < lo))) {
      return 'missingPixelBounds';
    }
    final norm = math.sqrt(
      1 +
          math.pow((x + .5 - f.cx) / f.fx, 2) +
          math.pow((y + .5 - f.cy) / f.fy, 2),
    );
    final centreZ = f.rangeM[i] / norm;
    if (!(lo <= centreZ + f.errorM + 1e-5 &&
        (hi.isNaN || hi.isFinite && hi >= centreZ - f.errorM - 1e-5))) {
      return 'incompatiblePixelBounds';
    }
    return null;
  }

  String? _direct(List<double> b, {required bool floor}) {
    final p = _project(b);
    if (p == null) return 'outsideFrustum';
    for (var y = p[2].toInt(); y <= p[3]; y++) {
      for (var x = p[0].toInt(); x <= p[1]; x++) {
        final invalid = _pixelFailure(x, y, floor: floor);
        if (invalid != null) return invalid;
        final i = y * frame.width + x, lo = frame.freeZLowerM[i];
        if (!floor) {
          if (lo - frame.errorM <= p[4]) return 'firstReturnIntersectsVolume';
          continue;
        }
        for (final u in [x.toDouble(), x + 1.0]) {
          for (final v in [y.toDouble(), y + 1.0]) {
            for (final z in [
              math.max(0, lo - frame.errorM),
              frame.surfaceZUpperM[i] + frame.errorM,
            ]) {
              final a = (u - frame.cx) / frame.fx;
              final d = (v - frame.cy) / frame.fy;
              final h =
                  frame.originM[2] +
                  z *
                      (frame.rotation[6] * a +
                          frame.rotation[7] * d +
                          frame.rotation[8]);
              if (h > request.maximumFloorRiseM ||
                  h < -request.maximumFloorDropM) {
                return 'floorHeightUncertain';
              }
            }
          }
        }
      }
    }
    return null;
  }

  String? _proof(List<double> b, int depth, {required bool floor}) {
    final direct = _direct(b, floor: floor);
    if (direct == null || depth == 0) return direct;
    final xm = (b[0] + b[1]) / 2, ym = (b[2] + b[3]) / 2;
    final zm = (b[4] + b[5]) / 2;
    for (final x in [
      [b[0], xm],
      [xm, b[1]],
    ]) {
      for (final y in [
        [b[2], ym],
        [ym, b[3]],
      ]) {
        for (final z
            in floor
                ? [
                    [0.0, 0.0],
                  ]
                : [
                    [b[4], zm],
                    [zm, b[5]],
                  ]) {
          final reason = _proof(
            [x[0], x[1], y[0], y[1], z[0], z[1]],
            depth - 1,
            floor: floor,
          );
          if (reason != null) return reason;
        }
      }
    }
    return null;
  }

  Map<String, Object?> inspect(
    CameraPassageClearanceSource source,
    PassageClearanceObservation observation,
  ) {
    if (!observation.providerHealthy || !frame.structurallyValid) {
      throw StateError('Maps require admitted structural inputs');
    }
    final nx = (request.widthM / cellSizeM).ceil();
    final ny = ((request.forwardEndM - request.forwardStartM) / cellSizeM)
        .ceil();
    final bodyTop = request.headroomM + request.maximumFloorRiseM;
    final nz = ((bodyTop - .05) / cellSizeM).ceil();
    final left = request.lateralCenterM - request.widthM / 2;
    final body = <List<Object>>[], floor = <List<Object>>[];
    final causes = <String, int>{};
    var certified = 0, unknown = 0;
    for (var iy = 0; iy < ny; iy++) {
      final s = observation.sections[iy];
      final skipped =
          s.state == PassageSectionState.blocked ||
          s.state == PassageSectionState.conflicting;
      var bodyCount = 0, floorCount = 0;
      for (var ix = 0; ix < nx; ix++) {
        final x0 = left + request.widthM * ix / nx;
        final x1 = left + request.widthM * (ix + 1) / nx;
        final fb = [x0, x1, s.forwardStartM, s.forwardEndM, 0.0, 0.0];
        String status(List<double> b, {required bool isFloor}) {
          if (skipped) return s.state.name;
          final failure = _proof(b, refinementDepth, floor: isFloor);
          if (failure == null) return 'observed';
          // If any corner of the complete cell is outside the convex frustum,
          // one subcell must remain unobserved, irrespective of centre depths.
          return _project(b) == null ? 'outsideFrustum' : failure;
        }

        final fs = status(fb, isFloor: true);
        if (fs == 'observed') floorCount++;
        floor.add([ix, iy, fs]);
        for (var iz = 0; iz < nz; iz++) {
          final z0 = .05 + (bodyTop - .05) * iz / nz;
          final z1 = .05 + (bodyTop - .05) * (iz + 1) / nz;
          final bs = status([
            x0,
            x1,
            s.forwardStartM,
            s.forwardEndM,
            z0,
            z1,
          ], isFloor: false);
          body.add([ix, iy, iz, bs]);
          if (!skipped) {
            if (bs == 'observed') {
              certified++;
              bodyCount++;
            } else {
              unknown++;
              causes.update(bs, (v) => v + 1, ifAbsent: () => 1);
            }
          }
        }
      }
      if (s.bodyObservedFraction != bodyCount / (nx * nz) ||
          s.floorObservedFraction != floorCount / nx) {
        throw StateError('Coverage replica diverged from source section $iy');
      }
    }
    if (certified != source.certifiedBodyBoxes ||
        unknown != source.unknownBodyBoxes) {
      throw StateError('Coverage replica diverged from source box counts');
    }
    return {
      'replicaMatchesSource': true,
      'nx': nx,
      'ny': ny,
      'nz': nz,
      'bodyCells': body,
      'floorCells': floor,
      'certifiedBodyBoxes': certified,
      'unknownBodyBoxes': unknown,
      'unknownBodyCauses': causes,
      'horizontalFovDeg':
          2 * math.atan(frame.width / (2 * frame.fx)) * 180 / math.pi,
      'verticalFovDeg':
          2 * math.atan(frame.height / (2 * frame.fy)) * 180 / math.pi,
      'nearBodyVerticalAngularSpanDeg':
          (math.atan2(bodyTop - frame.originM[2], request.forwardStartM) -
              math.atan2(.05 - frame.originM[2], request.forwardStartM)) *
          180 /
          math.pi,
      'nearBodyAzimuthSpanDeg':
          2 *
          math.atan2(request.widthM / 2, request.forwardStartM) *
          180 /
          math.pi,
      'sections': [
        for (final s in observation.sections)
          {
            'startM': s.forwardStartM,
            'endM': s.forwardEndM,
            'state': s.state.name,
            'body': s.bodyObservedFraction,
            'floor': s.floorObservedFraction,
          },
      ],
    };
  }
}
