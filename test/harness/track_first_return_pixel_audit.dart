import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';

import 'blender_visible_body_fixture.dart';

/// Post-decision audit only. Counts must match the unchanged production associator.
Map<String, Object?> firstReturnPixelAudit(
  CameraVisibleDepthFrame f,
  CameraComponentSupport support,
  CameraTrackAssociation actual,
) {
  final pixels = <int>{};
  for (final i in support.indices) {
    final x = i % 256, y = i ~/ 256;
    final x0 = math.max(0, (math.max(0, x / 256 - 1 / 256) * f.width).floor());
    final x1 = math.min(
      f.width - 1,
      (math.min(1, (x + 1) / 256 + 1 / 256) * f.width).ceil() - 1,
    );
    final y0 = math.max(0, (math.max(0, y / 256 - 1 / 256) * f.height).floor());
    final y1 = math.min(
      f.height - 1,
      (math.min(1, (y + 1) / 256 + 1 / 256) * f.height).ceil() - 1,
    );
    for (var yy = y0; yy <= y1; yy++) {
      for (var xx = x0; xx <= x1; xx++) {
        pixels.add(yy * f.width + xx);
      }
    }
  }
  final unknown = <Map<String, Object?>>[], categories = <String, int>{};
  final mask = <String, List<int>>{};
  var missing = 0, intersects = 0, excluded = 0;
  for (final i in pixels) {
    final x = i % f.width, y = i ~/ f.width;
    final lower = f.freeZLowerM[i],
        upper = f.surfaceZUpperM[i],
        range = f.rangeM[i];
    final norm = math.sqrt(
      1 +
          math.pow((x + .5 - f.cx) / f.fx, 2) +
          math.pow((y + .5 - f.cy) / f.fy, 2),
    );
    final centre = range / norm;
    String category;
    if (!f.valid[i] ||
        !range.isFinite ||
        range <= 0 ||
        !lower.isFinite ||
        lower < 0 ||
        (!upper.isNaN && (!upper.isFinite || upper < lower)) ||
        lower > centre + f.errorM + 1e-5 ||
        (!upper.isNaN && upper < centre - f.errorM - 1e-5)) {
      category = 'invalidReturnOrBounds';
      missing++;
    } else if (upper.isNaN) {
      final directions = <List<double>>[], starts = <List<double>>[];
      for (final u in [x.toDouble(), x + 1.0]) {
        for (final v in [y.toDouble(), y + 1.0]) {
          final a = (u - f.cx) / f.fx, b = (v - f.cy) / f.fy;
          final d = List.generate(
            3,
            (j) =>
                f.rotation[j * 3] * a +
                f.rotation[j * 3 + 1] * b +
                f.rotation[j * 3 + 2],
          );
          directions.add(d);
          starts.add(
            List.generate(
              3,
              (j) => f.originM[j] + math.max(0, lower - f.errorM) * d[j],
            ),
          );
        }
      }
      bool beyond(int axis, double edge, bool positive) => List.generate(
        4,
        (j) => positive
            ? starts[j][axis] > edge && directions[j][axis] >= 0
            : starts[j][axis] < edge && directions[j][axis] <= 0,
      ).every((v) => v);
      const request = pairedBodyRequest;
      const margin = CameraTrackAssociator.metricMarginM;
      if (beyond(0, -request.widthM / 2 - margin, false) ||
          beyond(0, request.widthM / 2 + margin, true) ||
          beyond(1, request.forwardEndM + margin, true) ||
          beyond(
            2,
            request.headroomM + request.maximumFloorRiseM + margin,
            true,
          )) {
        category = 'unboundedButOutside';
        excluded++;
      } else {
        category = 'unboundedMayIntersect';
        missing++;
      }
    } else {
      final lo = List.filled(3, double.infinity),
          hi = List.filled(3, -double.infinity);
      for (final u in [x.toDouble(), x + 1.0]) {
        for (final v in [y.toDouble(), y + 1.0]) {
          for (final z in [math.max(0, lower - f.errorM), upper + f.errorM]) {
            final a = (u - f.cx) / f.fx, b = (v - f.cy) / f.fy;
            for (var j = 0; j < 3; j++) {
              final p =
                  f.originM[j] +
                  z *
                      (f.rotation[j * 3] * a +
                          f.rotation[j * 3 + 1] * b +
                          f.rotation[j * 3 + 2]);
              lo[j] = math.min(lo[j], p);
              hi[j] = math.max(hi[j], p);
            }
          }
        }
      }
      const request = pairedBodyRequest;
      const margin = CameraTrackAssociator.metricMarginM;
      final outside =
          hi[0] < -request.widthM / 2 - margin ||
          lo[0] > request.widthM / 2 + margin ||
          lo[1] > request.forwardEndM + margin ||
          lo[2] > request.headroomM + request.maximumFloorRiseM + margin ||
          (lo[2] >= -pairedBodyRequest.maximumFloorDropM &&
              hi[2] <= pairedBodyRequest.maximumFloorRiseM);
      category = outside ? 'boundedOutside' : 'boundedIntersects';
      if (!outside) intersects++;
    }
    categories[category] = (categories[category] ?? 0) + 1;
    (mask[category] ??= []).add(i);
    if (category == 'invalidReturnOrBounds' ||
        category == 'unboundedMayIntersect') {
      unknown.add({
        'index': i,
        'x': x,
        'y': y,
        'category': category,
        'rangeM': range.isFinite ? range : null,
        'freeZLowerM': lower.isFinite ? lower : null,
        'surfaceZUpperM': upper.isFinite ? upper : null,
      });
    }
  }
  final relation = intersects > 0
      ? CameraTrackRelation.intersectsPassage
      : missing > 0
      ? CameraTrackRelation.unknown
      : CameraTrackRelation.outsidePassage;
  if (actual.checkedPixels != pixels.length ||
      actual.unknownPixels != missing ||
      actual.intersectingPixels != intersects ||
      actual.excludedUnboundedPixels != excluded ||
      actual.relation != relation) {
    throw StateError('Pixel audit/production association disagreement');
  }
  return {
    'checkedPixels': pixels.length,
    'categories': categories,
    'unknownPixels': unknown,
    'mask': mask,
    'productionCountParity': true,
  };
}
