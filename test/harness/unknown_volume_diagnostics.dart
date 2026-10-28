import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/single_camera_observability.dart';

import 'camera_view_coverage_diagnostics.dart';

const unknownVolumeReasonLabels = <String, String>{
  'observed': 'Подтверждено производителем',
  'outsideFrustum': 'Ячейка выходит из поля зрения',
  'invalidPixel': 'Нет допустимого возврата',
  'missingPixelBounds': 'Нет необходимых границ глубины',
  'incompatiblePixelBounds': 'Границы противоречат возврату',
  'firstReturnIntersectsVolume': 'Граница свободного объёма недостаточна',
  'floorHeightUncertain': 'Высота поверхности не ограничена допуском пола',
  'blocked': 'Сечение заблокировано производителем',
  'conflicting': 'Сечение с конфликтом измерений',
};

/// A read-only explanation of already-unknown cells. It is deliberately not an
/// evidence source. An occlusion witness concerns ONE intersecting centre ray,
/// never an entire cell, and never changes the existing coverage verdict.
class UnknownVolumeDiagnostics {
  final CameraVisibleDepthFrame frame;
  final PassageClearanceRequest request;

  const UnknownVolumeDiagnostics({required this.frame, required this.request});

  List<String> outsideSides(List<double> bounds) {
    final sides = <String>{};
    for (final x in [bounds[0], bounds[1]]) {
      for (final d in [bounds[2], bounds[3]]) {
        for (final h in [bounds[4], bounds[5]]) {
          final p = frame.cameraPoint([x, d, h]);
          if (p[2] <= .01) {
            sides.add('nearPlane');
            continue;
          }
          final u = frame.fx * p[0] / p[2] + frame.cx;
          final v = frame.fy * p[1] / p[2] + frame.cy;
          if (u < 0) sides.add('left');
          if (u >= frame.width) sides.add('right');
          if (v < 0) sides.add('top');
          if (v >= frame.height) sides.add('bottom');
        }
      }
    }
    return sides.toList()..sort();
  }

  /// Camera-Z parameter interval where this centre ray intersects the box.
  /// Zero-height floor patches are valid closed slabs, not thickened surfaces.
  List<double>? rayInterval(List<double> b, int x, int y) {
    final a = (x + .5 - frame.cx) / frame.fx;
    final d = (y + .5 - frame.cy) / frame.fy;
    final r = frame.rotation;
    final direction = [
      r[0] * a + r[1] * d + r[2],
      r[3] * a + r[4] * d + r[5],
      r[6] * a + r[7] * d + r[8],
    ];
    var enter = 0.0, leave = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final origin = frame.originM[axis], delta = direction[axis];
      if (delta == 0) {
        if (origin < b[axis * 2] || origin > b[axis * 2 + 1]) return null;
      } else {
        final t0 = (b[axis * 2] - origin) / delta;
        final t1 = (b[axis * 2 + 1] - origin) / delta;
        enter = math.max(enter, math.min(t0, t1));
        leave = math.min(leave, math.max(t0, t1));
        if (enter > leave) return null;
      }
    }
    return leave <= 0 || !enter.isFinite ? null : [enter, leave];
  }

  /// Requires a valid, consistent finite upper bound strictly BEFORE the
  /// ray enters the queried cell. A short lower bound alone is not occlusion.
  Map<String, Object?>? occlusionWitness(List<double> b) {
    if (outsideSides(b).isNotEmpty) return null;
    var u0 = double.infinity, v0 = double.infinity;
    var u1 = -double.infinity, v1 = -double.infinity;
    for (final x in [b[0], b[1]]) {
      for (final d in [b[2], b[3]]) {
        for (final h in [b[4], b[5]]) {
          final p = frame.cameraPoint([x, d, h]);
          final u = frame.fx * p[0] / p[2] + frame.cx;
          final v = frame.fy * p[1] / p[2] + frame.cy;
          u0 = math.min(u0, u);
          u1 = math.max(u1, u);
          v0 = math.min(v0, v);
          v1 = math.max(v1, v);
        }
      }
    }
    for (var y = v0.floor(); y <= v1.floor(); y++) {
      for (var x = u0.floor(); x <= u1.floor(); x++) {
        final i = y * frame.width + x;
        final range = frame.rangeM[i], lo = frame.freeZLowerM[i];
        final hi = frame.surfaceZUpperM[i];
        if (!frame.valid[i] ||
            !range.isFinite ||
            range <= 0 ||
            !lo.isFinite ||
            lo < 0 ||
            !hi.isFinite ||
            hi < lo) {
          continue;
        }
        final norm = math.sqrt(
          1 +
              math.pow((x + .5 - frame.cx) / frame.fx, 2) +
              math.pow((y + .5 - frame.cy) / frame.fy, 2),
        );
        final centreZ = range / norm;
        if (lo > centreZ + frame.errorM + 1e-5 ||
            hi < centreZ - frame.errorM - 1e-5) {
          continue;
        }
        final interval = rayInterval(b, x, y);
        if (interval != null && hi + frame.errorM < interval[0]) {
          return {
            'pixel': [x, y],
            'cellBoundsM': List.of(b),
            'rayEntryZ': interval[0],
            'rayExitZ': interval[1],
            'firstReturnUpperZ': hi,
            'errorM': frame.errorM,
            'clearanceAuthority': false,
          };
        }
      }
    }
    return null;
  }

  Map<String, Object?> inspect({
    required CameraPassageClearanceSource source,
    required PassageClearanceObservation observation,
    required PassageEvaluationContext context,
  }) {
    final preflight = const SingleCameraObservabilityPreflight().assess(
      frame: frame,
      calibration: source.calibration,
      request: request,
      context: context,
    );
    if (!preflight.inputsAdmitted ||
        !observation.providerHealthy ||
        source.frames.length != 1 ||
        !identical(source.frames.single, frame) ||
        !identical(source.request, request) ||
        context.nowUs < source.producedAtUs ||
        observation.frameId != frame.frameId ||
        observation.rgbTimestampUs != frame.capturedAtUs ||
        observation.sessionGeneration != frame.sessionGeneration) {
      throw StateError('Unknown-volume map unavailable: ${preflight.reason}');
    }
    // This frozen independent replica checks every section and both complete
    // cell counters against the unchanged producer before publishing a map.
    final coverage = CameraViewCoverageDiagnostics(
      frame: frame,
      request: request,
      refinementDepth: source.refinementDepth,
      cellSizeM: source.cellSizeM,
    ).inspect(source, observation);
    final nx = coverage['nx'] as int, ny = coverage['ny'] as int;
    final nz = coverage['nz'] as int;
    final left = request.lateralCenterM - request.widthM / 2;
    final top = request.headroomM + request.maximumFloorRiseM;
    final xEdges = [
      for (var i = 0; i <= nx; i++) left + request.widthM * i / nx,
    ];
    final dEdges = [
      for (var i = 0; i <= ny; i++)
        request.forwardStartM +
            (request.forwardEndM - request.forwardStartM) * i / ny,
    ];
    final hEdges = [for (var i = 0; i <= nz; i++) .05 + (top - .05) * i / nz];
    final witnesses = <Map<String, Object?>>[];
    final counts = <String, Map<String, int>>{};
    final fovSides = <String, Map<String, int>>{};
    final occluded = <String, int>{};
    List<List<Object?>> mapCells(String kind, List raw) {
      final totals = <String, int>{
        for (final k in unknownVolumeReasonLabels.keys) k: 0,
      };
      final sides = <String, int>{};
      var witnessed = 0;
      final mapped = <List<Object?>>[];
      for (final cell in raw.cast<List>()) {
        final ix = cell[0] as int, iy = cell[1] as int;
        final isFloor = kind == 'floor';
        final iz = isFloor ? null : cell[2] as int;
        final status = cell[isFloor ? 2 : 3] as String;
        if (!totals.containsKey(status)) {
          throw StateError('Unmapped cell status $status');
        }
        totals[status] = totals[status]! + 1;
        final b = [
          xEdges[ix],
          xEdges[ix + 1],
          dEdges[iy],
          dEdges[iy + 1],
          isFloor ? 0.0 : hEdges[iz!],
          isFloor ? 0.0 : hEdges[iz! + 1],
        ];
        final skipped = status == 'blocked' || status == 'conflicting';
        final outside = outsideSides(b);
        if (!skipped && (outside.isNotEmpty != (status == 'outsideFrustum'))) {
          throw StateError('Frustum verdict diverged for $kind/$ix/$iy/$iz');
        }
        if (status == 'outsideFrustum') {
          for (final side in outside) {
            sides.update(side, (n) => n + 1, ifAbsent: () => 1);
          }
        }
        final witness = !skipped && status != 'observed' && outside.isEmpty
            ? occlusionWitness(b)
            : null;
        if (witness != null) {
          witnessed++;
          witnesses.add({
            'kind': kind,
            'cell': [ix, iy, if (iz != null) iz],
            ...witness,
          });
        }
        mapped.add([ix, iy, if (iz != null) iz, status, witness != null]);
      }
      counts[kind] = totals;
      fovSides[kind] = sides;
      occluded[kind] = witnessed;
      return mapped;
    }

    final body = mapCells('body', coverage['bodyCells'] as List);
    final floor = mapCells('floor', coverage['floorCells'] as List);
    return {
      'schemaVersion': 1,
      'scope': 'known synthetic whole-pixel first-return diagnostic only',
      'canAuthorizeMovement': false,
      'canCertifyFreeSpace': false,
      'replicaMatchesSource': true,
      'geometryPreflight': preflight.toDiagnosticMap(),
      'nx': nx,
      'ny': ny,
      'nz': nz,
      'xEdgesM': xEdges,
      'forwardEdgesM': dEdges,
      'heightEdgesM': hEdges,
      'bodyCells': body,
      'floorCells': floor,
      'bodyCellColumns': [
        'ix',
        'iy',
        'iz',
        'producerProofFailure',
        'hasOcclusionWitness',
      ],
      'floorCellColumns': [
        'ix',
        'iy',
        'producerProofFailure',
        'hasOcclusionWitness',
      ],
      'counts': counts,
      'outsideSides': fovSides,
      'occlusionWitnessCells': occluded,
      'occlusionWitnesses': witnesses,
      'certifiedBodyBoxes': source.certifiedBodyBoxes,
      'unknownBodyBoxes': source.unknownBodyBoxes,
      'sections': coverage['sections'],
      'reasonScope':
          'Full cell map; proof failure is the frozen producer-replica first '
          'failing refined branch, not an exhaustive list of physical causes. '
          'Occlusion flags are additional positive centre-ray witnesses for in-view '
          'unknown cells; a false flag does not prove absence of occlusion.',
    };
  }
}
