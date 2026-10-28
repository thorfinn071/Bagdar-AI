import 'dart:math' as math;

import 'camera_fast_motion_types.dart';
import 'camera_passage_clearance_source.dart';
import 'camera_track_association.dart';
import 'passage_clearance.dart';

/// Diagnostic admission only. Visible matches never clear motion priority,
/// historical risk, hidden object extent or unknown space.
class CameraTrackMotionCoverage {
  final String reason;
  final int previousPixels, currentPixels, previousMatched, currentMatched;
  final int localMovingCentres;
  final bool available;

  const CameraTrackMotionCoverage._(
    this.reason, {
    this.available = false,
    this.previousPixels = 0,
    this.currentPixels = 0,
    this.previousMatched = 0,
    this.currentMatched = 0,
    this.localMovingCentres = 0,
  });

  bool get completeVisibleSupport =>
      available &&
      previousPixels > 0 &&
      currentPixels > 0 &&
      previousMatched == previousPixels &&
      currentMatched == currentPixels;

  Map<String, Object?> toDiagnosticMap() => {
    'available': available,
    'reason': reason,
    'previousFootprintPixels': previousPixels,
    'currentFootprintPixels': currentPixels,
    'previousMatchedCentres': previousMatched,
    'currentMatchedCentres': currentMatched,
    'previousCoverage': previousPixels == 0
        ? null
        : previousMatched / previousPixels,
    'currentCoverage': currentPixels == 0
        ? null
        : currentMatched / currentPixels,
    'localMovingCentres': localMovingCentres,
    'completeVisibleSupport': completeVisibleSupport,
    'wholeObjectStationarityCertified': false,
    'mayResolveMotionPriority': false,
    'freeSpaceCertified': false,
    'priorityResolutionReason':
        'whole_object_extent_and_motion_absence_unestablished',
  };

  /// The same whole-pixel footprint and one source-pixel registration margin as
  /// CameraTrackAssociator. Count measured centres, never template/search area.
  static Set<int>? footprint(
    CameraComponentSupport? s,
    int expectedCount,
    int width,
    int height,
    int capturedAtUs,
  ) {
    if (s == null ||
        s.width != 256 ||
        s.height != 256 ||
        s.cropTopFraction != 0 ||
        s.capturedAtUs != capturedAtUs ||
        s.indices.isEmpty ||
        s.indices.length != expectedCount ||
        s.indices.length > 65536 ||
        s.indices.toSet().length != s.indices.length ||
        width <= 0 ||
        height <= 0 ||
        width * height > 1048576) {
      return null;
    }
    final result = <int>{};
    for (final index in s.indices) {
      if (index < 0 || index >= 65536) return null;
      final x = index % 256, y = index ~/ 256;
      final x0 = math.max(0, (math.max(0, (x - 1) / 256) * width).floor());
      final x1 = math.min(
        width - 1,
        (math.min(1, (x + 2) / 256) * width).ceil() - 1,
      );
      final y0 = math.max(0, (math.max(0, (y - 1) / 256) * height).floor());
      final y1 = math.min(
        height - 1,
        (math.min(1, (y + 2) / 256) * height).ceil() - 1,
      );
      for (var yy = y0; yy <= y1; yy++) {
        for (var xx = x0; xx <= x1; xx++) {
          result.add(yy * width + xx);
        }
      }
    }
    return result;
  }

  static CameraTrackMotionCoverage evaluate({
    required int trackId,
    required int previousTrackId,
    required bool currentlyObserved,
    required bool previouslyObserved,
    required CameraComponentSupport? currentSupport,
    required CameraComponentSupport? previousSupport,
    required int currentPixelCount,
    required int previousPixelCount,
    required FastMetricMotionInput current,
    required FastMetricMotionInput previous,
    required FastMetricMotionResult motion,
    required PassageCalibration calibration,
    required FastRgbContract rgbContract,
    required int nowUs,
  }) {
    CameraTrackMotionCoverage unavailable(String reason) =>
        CameraTrackMotionCoverage._(reason);
    final f = current.camera.depth, p = previous.camera.depth;
    if (trackId <= 0 ||
        trackId != previousTrackId ||
        !currentlyObserved ||
        !previouslyObserved) {
      return unavailable('track_not_observed_in_both_original_captures');
    }
    if (!_validInput(current, calibration, rgbContract, nowUs) ||
        !_validInput(
          previous,
          calibration,
          rgbContract,
          math.min(nowUs, p.capturedAtUs + 100000),
        ) ||
        nowUs < f.capturedAtUs ||
        nowUs - f.capturedAtUs > 100000 ||
        nowUs - p.capturedAtUs > 400000 ||
        f.frameId <= p.frameId ||
        f.capturedAtUs - p.capturedAtUs < 50000 ||
        f.capturedAtUs - p.capturedAtUs > 300000 ||
        f.sessionGeneration != p.sessionGeneration ||
        f.cameraId != p.cameraId ||
        f.modelHash != p.modelHash ||
        f.transformId != p.transformId ||
        f.referenceFrameId != p.referenceFrameId ||
        f.width != p.width ||
        f.height != p.height ||
        f.fx != p.fx ||
        f.fy != p.fy ||
        f.cx != p.cx ||
        f.cy != p.cy) {
      return unavailable(
        'incompatible_pair_identity_projection_pose_units_or_time',
      );
    }
    if (motion.frameId != f.frameId ||
        motion.capturedAtUs != f.capturedAtUs ||
        motion.sessionGeneration != f.sessionGeneration ||
        motion.transformId != f.transformId ||
        motion.oldestEvidenceTimestampUs != p.capturedAtUs ||
        motion.validUntilUs >
            math.min(f.capturedAtUs + 100000, p.capturedAtUs + 400000) ||
        !motion.isLiveAt(nowUs) ||
        motion.candidates < motion.patches.length ||
        motion.unknownPatches < 0 ||
        motion.unknownPatches > motion.candidates ||
        (motion.patches.isNotEmpty &&
            motion.reason != 'visible_patch_intervals')) {
      return unavailable('unbound_expired_or_malformed_motion_result');
    }
    final before = footprint(
      previousSupport,
      previousPixelCount,
      p.width,
      p.height,
      p.capturedAtUs,
    );
    final after = footprint(
      currentSupport,
      currentPixelCount,
      f.width,
      f.height,
      f.capturedAtUs,
    );
    if (before == null || after == null) {
      return unavailable('invalid_or_incomplete_component_support');
    }
    if (motion.patches.isEmpty) {
      return unavailable('no_visible_metric_correspondences');
    }
    final previousCentres = <int>{}, currentCentres = <int>{};
    var moving = 0;
    for (final patch in motion.patches) {
      bool point(List<int> xy) =>
          xy.length == 2 &&
          xy[0] >= 0 &&
          xy[0] < f.width &&
          xy[1] >= 0 &&
          xy[1] < f.height;
      bool interval(List<double> a, List<double> b) =>
          a.length == 3 &&
          b.length == 3 &&
          List.generate(
            3,
            (i) => a[i].isFinite && b[i].isFinite && a[i] <= b[i],
          ).every((v) => v);
      if (!point(patch.previousPixel) ||
          !point(patch.currentPixel) ||
          !_boundedCentre(p, patch.previousPixel) ||
          !_boundedCentre(f, patch.currentPixel) ||
          !interval(patch.positionLowerM, patch.positionUpperM) ||
          !interval(patch.velocityLowerMps, patch.velocityUpperMps)) {
        return unavailable('malformed_correspondence');
      }
      final a = patch.previousPixel[1] * p.width + patch.previousPixel[0];
      final b = patch.currentPixel[1] * f.width + patch.currentPixel[0];
      if (!previousCentres.add(a) || !currentCentres.add(b)) {
        return unavailable('duplicate_or_ambiguous_correspondence');
      }
      if (before.contains(a) && after.contains(b) && patch.establishesMotion) {
        moving++;
      }
    }
    // Require both endpoints within this track. A matching background patch
    // cannot cover a component just because its other endpoint is nearby.
    final owned = motion.patches
        .where(
          (patch) =>
              before.contains(
                patch.previousPixel[1] * p.width + patch.previousPixel[0],
              ) &&
              after.contains(
                patch.currentPixel[1] * f.width + patch.currentPixel[0],
              ),
        )
        .toList();
    final n0 = owned
        .map((v) => v.previousPixel[1] * p.width + v.previousPixel[0])
        .toSet()
        .length;
    final n1 = owned
        .map((v) => v.currentPixel[1] * f.width + v.currentPixel[0])
        .toSet()
        .length;
    return CameraTrackMotionCoverage._(
      n0 == before.length && n1 == after.length
          ? 'complete_visible_support_measurements'
          : 'incomplete_visible_support_measurements',
      available: true,
      previousPixels: before.length,
      currentPixels: after.length,
      previousMatched: n0,
      currentMatched: n1,
      localMovingCentres: moving,
    );
  }

  static bool _validInput(
    FastMetricMotionInput input,
    PassageCalibration c,
    FastRgbContract contract,
    int nowUs,
  ) {
    final f = input.camera.depth,
        h = input.camera.rgbHeader,
        g = input.camera.imageGeometry;
    bool same(List<double> a, List<double> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].isFinite && b[i].isFinite && (a[i] - b[i]).abs() < 1e-6,
        ).every((v) => v);
    return f.structurallyValid &&
        c.id.isNotEmpty &&
        c.providerId.isNotEmpty &&
        c.metricScaleValidated &&
        c.alignmentValidated &&
        c.floorReferenceValidated &&
        c.timestampDomain == PassageTimestampDomain.utcEpochMicroseconds &&
        contract.valid &&
        h.healthy &&
        h.confidence.isFinite &&
        h.confidence >= .9 &&
        h.confidence <= 1 &&
        h.providerId == contract.providerId &&
        h.revision == contract.revision &&
        h.preprocessId == contract.preprocessId &&
        h.frameId == f.frameId &&
        h.sessionGeneration == f.sessionGeneration &&
        h.sourceTimestampUs == f.capturedAtUs &&
        h.transformId == f.transformId &&
        f.transformId == c.transformId &&
        f.modelHash == c.modelHash &&
        f.referenceFrameId == c.referenceFrameId &&
        h.producedAtUs >= f.capturedAtUs &&
        h.producedAtUs <= nowUs &&
        nowUs >= f.capturedAtUs &&
        nowUs - f.capturedAtUs <= 100000 &&
        f.cameraId == g.cameraId &&
        f.width == g.width &&
        f.height == g.height &&
        same([f.fx, f.fy, f.cx, f.cy], [g.fx, g.fy, g.cx, g.cy]) &&
        same(f.rotation, g.rotation) &&
        same(f.originM, g.originM) &&
        input.rgb.length == f.width * f.height * 3 &&
        input.rgb.every((v) => v >= 0 && v <= 255) &&
        input.positionErrorM.isFinite &&
        input.positionErrorM >= 0 &&
        input.positionErrorM <= .1 &&
        input.angularErrorRad.isFinite &&
        input.angularErrorRad >= 0 &&
        input.angularErrorRad <= .02;
  }

  // Registration bounds validate a centre measurement; these neighbouring
  // pixels are never counted as additional material correspondences.
  static bool _boundedCentre(CameraVisibleDepthFrame f, List<int> xy) {
    final x = xy[0], y = xy[1];
    if (x < 1 || y < 1 || x >= f.width - 1 || y >= f.height - 1) {
      return false;
    }
    for (var v = y - 1; v <= y + 1; v++) {
      for (var u = x - 1; u <= x + 1; u++) {
        final k = v * f.width + u;
        final a = f.freeZLowerM[k], b = f.surfaceZUpperM[k], r = f.rangeM[k];
        final z =
            r /
            math.sqrt(
              1 +
                  math.pow((u + .5 - f.cx) / f.fx, 2) +
                  math.pow((v + .5 - f.cy) / f.fy, 2),
            );
        if (!f.valid[k] ||
            !a.isFinite ||
            !b.isFinite ||
            !r.isFinite ||
            r <= 0 ||
            a <= 0 ||
            b < a ||
            z < a - f.errorM - 1e-5 ||
            z > b + f.errorM + 1e-5) {
          return false;
        }
      }
    }
    return true;
  }
}
