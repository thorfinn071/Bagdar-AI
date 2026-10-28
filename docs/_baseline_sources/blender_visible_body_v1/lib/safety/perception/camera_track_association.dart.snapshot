import 'dart:math' as math;

import 'camera_passage_clearance_source.dart';
import 'observation_header.dart';
import 'passage_clearance.dart';

/// Complete segmentation support on the depth image, before full-frame mapping.
/// Consumers must reject incomplete, duplicated or out-of-bounds support.
class CameraComponentSupport {
  final int width, height;
  final double cropTopFraction;
  final int capturedAtUs;
  final List<int> indices;

  CameraComponentSupport({
    required this.width,
    required this.height,
    required this.cropTopFraction,
    required this.capturedAtUs,
    required List<int> indices,
  }) : indices = List.unmodifiable(indices);
}

/// RGB geometry is declared separately from the depth packet. A depth packet
/// with a different optical centre, projection or pose cannot localize a track.
class CameraTrackImageGeometry {
  final String cameraId;
  final int width, height;
  final double fx, fy, cx, cy;
  final List<double> rotation, originM;

  CameraTrackImageGeometry({
    required this.cameraId,
    required this.width,
    required this.height,
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required List<double> rotation,
    required List<double> originM,
  }) : rotation = List.unmodifiable(rotation),
       originM = List.unmodifiable(originM);
}

class CameraTrackAssociationInput {
  final ObservationHeader rgbHeader;
  final CameraTrackImageGeometry imageGeometry;
  final CameraVisibleDepthFrame depth;

  const CameraTrackAssociationInput({
    required this.rgbHeader,
    required this.imageGeometry,
    required this.depth,
  });
}

enum CameraTrackRelation { outsidePassage, intersectsPassage, unknown }

class CameraTrackAssociation {
  final CameraTrackRelation relation;
  final String reason;
  final int checkedPixels, unknownPixels, intersectingPixels;
  final int excludedUnboundedPixels;
  final List<double>? surfaceBoundsM;

  const CameraTrackAssociation(
    this.relation,
    this.reason, {
    this.checkedPixels = 0,
    this.unknownPixels = 0,
    this.intersectingPixels = 0,
    this.excludedUnboundedPixels = 0,
    this.surfaceBoundsM,
  });

  Map<String, Object?> toDiagnosticMap() => {
    'relation': relation.name,
    'reason': reason,
    'checkedPixels': checkedPixels,
    'unknownPixels': unknownPixels,
    'intersectingPixels': intersectingPixels,
    'excludedUnboundedPixels': excludedUnboundedPixels,
    'boundedSurfaceEnvelopeM': surfaceBoundsM,
  };
}

/// Camera-only localization of first visible surfaces; never reads scene labels
/// or hidden geometry. This does not certify free space behind those surfaces.
class CameraTrackAssociator {
  final CameraTrackAssociationInput input;
  final ObservationHeader header;
  final PassageCalibration calibration;
  final PassageClearanceRequest request;
  final int nowUs;
  final String relativeModelHash;
  static const metricMarginM = .02;

  const CameraTrackAssociator({
    required this.input,
    required this.header,
    required this.calibration,
    required this.request,
    required this.nowUs,
    required this.relativeModelHash,
  });

  bool get _compatible {
    final f = input.depth, g = input.imageGeometry, h = input.rgbHeader;
    bool same(List<double> a, List<double> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].isFinite && b[i].isFinite && (a[i] - b[i]).abs() <= 1e-6,
        ).every((v) => v);
    return f.structurallyValid &&
        calibration.metricScaleValidated &&
        calibration.alignmentValidated &&
        calibration.floorReferenceValidated &&
        calibration.timestampDomain ==
            PassageTimestampDomain.utcEpochMicroseconds &&
        header.health == ObservationHealth.healthy &&
        h.health == ObservationHealth.healthy &&
        header.producedAtUs == h.producedAtUs &&
        header.producedAtUs >= header.sourceTimestampUs &&
        header.producedAtUs <= nowUs &&
        relativeModelHash.isNotEmpty &&
        header.modelHash == relativeModelHash &&
        header.providerId == h.providerId &&
        header.modelId == h.modelId &&
        header.modelHash == h.modelHash &&
        header.preprocessId == h.preprocessId &&
        header.sessionGeneration == h.sessionGeneration &&
        header.frameId == h.frameId &&
        header.sourceTimestampUs == h.sourceTimestampUs &&
        header.transformId == h.transformId &&
        header.preprocessId == 'rgb01-chw-256-nearest-stretch-no-crop-v1' &&
        header.modelId == 'midas-small-ncnn' &&
        f.frameId == header.frameId &&
        f.capturedAtUs == header.sourceTimestampUs &&
        f.sessionGeneration == header.sessionGeneration &&
        f.transformId == header.transformId &&
        f.transformId == calibration.transformId &&
        f.modelHash == calibration.modelHash &&
        f.referenceFrameId == calibration.referenceFrameId &&
        f.referenceFrameId == request.referenceFrameId &&
        f.cameraId == g.cameraId &&
        f.width == g.width &&
        f.height == g.height &&
        same([f.fx, f.fy, f.cx, f.cy], [g.fx, g.fy, g.cx, g.cy]) &&
        same(f.rotation, g.rotation) &&
        same(f.originM, g.originM) &&
        nowUs >= f.capturedAtUs &&
        nowUs - f.capturedAtUs <= 100000 &&
        request.lateralCenterM == 0 &&
        request.widthM >= .9 &&
        request.widthM <= 3 &&
        request.headroomM >= 1.8 &&
        request.headroomM <= 3 &&
        request.forwardStartM >= 0 &&
        request.forwardStartM <= .2 &&
        request.forwardEndM >= 3.5 &&
        request.forwardEndM <= 10 &&
        request.maximumFloorRiseM >= 0 &&
        request.maximumFloorRiseM <= .05 &&
        request.maximumFloorDropM >= 0 &&
        request.maximumFloorDropM <= .05;
  }

  CameraTrackAssociation associate({
    required List<double> normalizedBounds,
    required int trackTimestampUs,
    required bool currentlyObserved,
    required bool motionOrSemanticRisk,
    CameraComponentSupport? support,
    int? expectedPixelCount,
  }) {
    CameraTrackAssociation unknown(String reason) =>
        CameraTrackAssociation(CameraTrackRelation.unknown, reason);
    if (!_compatible) {
      return unknown('incompatible_identity_projection_pose_or_time');
    }
    if (!currentlyObserved || trackTimestampUs != header.sourceTimestampUs) {
      return unknown('track_not_observed_in_matching_frame');
    }
    if (motionOrSemanticRisk) return unknown('motion_or_semantic_priority');
    if (normalizedBounds.length != 4 ||
        normalizedBounds.any((v) => !v.isFinite || v < 0 || v > 1) ||
        normalizedBounds[0] >= normalizedBounds[2] ||
        normalizedBounds[1] >= normalizedBounds[3]) {
      return unknown('invalid_component_bounds');
    }
    final f = input.depth;
    final pixels = <int>{};
    void rectangle(double l, double t, double r, double b) {
      // Include whole footprint, with an additional source-pixel registration margin.
      final x0 = math.max(0, (l * f.width).floor()),
          x1 = math.min(f.width - 1, (r * f.width).ceil() - 1);
      final y0 = math.max(0, (t * f.height).floor()),
          y1 = math.min(f.height - 1, (b * f.height).ceil() - 1);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          pixels.add(y * f.width + x);
        }
      }
    }

    if (support == null) {
      rectangle(
        math.max(0, normalizedBounds[0] - 1 / 256),
        math.max(0, normalizedBounds[1] - 1 / 256),
        math.min(1, normalizedBounds[2] + 1 / 256),
        math.min(1, normalizedBounds[3] + 1 / 256),
      );
    } else {
      if (support.width != 256 ||
          support.height != 256 ||
          support.cropTopFraction != 0 ||
          support.capturedAtUs != header.sourceTimestampUs ||
          support.indices.isEmpty ||
          support.indices.length > 65536 ||
          support.indices.length != expectedPixelCount ||
          support.indices.toSet().length != support.indices.length) {
        return unknown('invalid_or_incomplete_support');
      }
      for (final i in support.indices) {
        if (i < 0 || i >= 65536) return unknown('invalid_support_index');
        final x = i % 256, y = i ~/ 256;
        final l = x / 256, t = y / 256, r = (x + 1) / 256, b = (y + 1) / 256;
        if (l < normalizedBounds[0] - 1e-6 ||
            t < normalizedBounds[1] - 1e-6 ||
            r > normalizedBounds[2] + 1e-6 ||
            b > normalizedBounds[3] + 1e-6) {
          return unknown('support_outside_component');
        }
        rectangle(
          math.max(0, l - 1 / 256),
          math.max(0, t - 1 / 256),
          math.min(1, r + 1 / 256),
          math.min(1, b + 1 / 256),
        );
      }
    }
    if (pixels.isEmpty) return unknown('empty_support');
    var missing = 0, intersects = 0, excludedUnbounded = 0;
    final lo = List<double>.filled(3, double.infinity),
        hi = List<double>.filled(3, -double.infinity);
    for (final i in pixels) {
      final x = i % f.width,
          y = i ~/ f.width,
          lower = f.freeZLowerM[i],
          upper = f.surfaceZUpperM[i],
          range = f.rangeM[i];
      final norm = math.sqrt(
        1 +
            math.pow((x + .5 - f.cx) / f.fx, 2) +
            math.pow((y + .5 - f.cy) / f.fy, 2),
      );
      final centre = range / norm;
      if (!f.valid[i] ||
          !range.isFinite ||
          range <= 0 ||
          !lower.isFinite ||
          lower < 0 ||
          (!upper.isNaN && (!upper.isFinite || upper < lower)) ||
          lower > centre + f.errorM + 1e-5 ||
          (!upper.isNaN && upper < centre - f.errorM - 1e-5)) {
        missing++;
        continue;
      }
      if (upper.isNaN) {
        // No upper surface bound: consider EVERY possible first return from
        // the certified lower depth to infinity. A separating plane can prove
        // that this entire pixel frustum stays outside; its hidden geometry is
        // irrelevant. Never use a centre-ray return to supply a missing upper.
        final directions = <List<double>>[];
        final starts = <List<double>>[];
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
        bool beyond(int axis, double boundary, bool positive) => List.generate(
          4,
          (j) => positive
              ? starts[j][axis] > boundary && directions[j][axis] >= 0
              : starts[j][axis] < boundary && directions[j][axis] <= 0,
        ).every((v) => v);
        if (beyond(0, -request.widthM / 2 - metricMarginM, false) ||
            beyond(0, request.widthM / 2 + metricMarginM, true) ||
            beyond(1, request.forwardEndM + metricMarginM, true) ||
            beyond(
              2,
              request.headroomM + request.maximumFloorRiseM + metricMarginM,
              true,
            )) {
          excludedUnbounded++;
        } else {
          missing++;
        }
        continue;
      }
      final pLo = List<double>.filled(3, double.infinity),
          pHi = List<double>.filled(3, -double.infinity);
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
              pLo[j] = math.min(pLo[j], p);
              pHi[j] = math.max(pHi[j], p);
            }
          }
        }
      }
      for (var j = 0; j < 3; j++) {
        lo[j] = math.min(lo[j], pLo[j]);
        hi[j] = math.max(hi[j], pHi[j]);
      }
      // Extend to zero: a near obstacle must not be excluded by the .2m request.
      // Floor is outside only when the entire measured patch is within limits;
      // a drop never counts as harmless ground. Add a 20mm lateral/head margin.
      final outside =
          pHi[0] < -request.widthM / 2 - metricMarginM ||
          pLo[0] > request.widthM / 2 + metricMarginM ||
          pLo[1] > request.forwardEndM + metricMarginM ||
          pLo[2] >
              request.headroomM + request.maximumFloorRiseM + metricMarginM ||
          (pLo[2] >= -request.maximumFloorDropM &&
              pHi[2] <= request.maximumFloorRiseM);
      if (!outside) intersects++;
    }
    final bounds = lo.every((v) => v.isFinite)
        ? List<double>.unmodifiable([...lo, ...hi])
        : null;
    return CameraTrackAssociation(
      intersects > 0
          ? CameraTrackRelation.intersectsPassage
          : missing > 0
          ? CameraTrackRelation.unknown
          : CameraTrackRelation.outsidePassage,
      intersects > 0
          ? 'first_surface_may_intersect_protected_volume'
          : missing > 0
          ? 'missing_or_unbounded_first_surface'
          : 'all_first_surface_footprints_outside',
      checkedPixels: pixels.length,
      unknownPixels: missing,
      intersectingPixels: intersects,
      excludedUnboundedPixels: excludedUnbounded,
      surfaceBoundsM: bounds,
    );
  }
}
