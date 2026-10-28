import 'dart:math' as math;

import 'camera_passage_clearance_source.dart';
import 'passage_clearance.dart';

/// Geometric possibility only. This is deliberately not a clearance result or
/// evidence source: seeing a volume does not establish its first returns/floor.
class SingleCameraObservability {
  final bool inputsAdmitted;
  final String reason;
  final double? visibleStartM, visibleEndM;
  final PassageClearanceRequest request;

  const SingleCameraObservability._({
    required this.inputsAdmitted,
    required this.reason,
    required this.request,
    this.visibleStartM,
    this.visibleEndM,
  });

  bool get entireRequestInView =>
      inputsAdmitted &&
      visibleStartM != null &&
      visibleStartM! <= request.forwardStartM &&
      visibleEndM! >= request.forwardEndM;

  bool get canCertifyFreeSpace => false;
  bool get canAuthorizeMovement => false;

  Map<String, Object?> toDiagnosticMap() => {
    'inputsAdmitted': inputsAdmitted,
    'reason': reason,
    'visibleStartM': visibleStartM,
    'visibleEndM': visibleEndM,
    'entireRequestInView': entireRequestInView,
    'nearGapM': visibleStartM == null
        ? null
        : visibleStartM! - request.forwardStartM,
    'farGapM': visibleEndM == null ? null : request.forwardEndM - visibleEndM!,
    'canCertifyFreeSpace': canCertifyFreeSpace,
    'canAuthorizeMovement': canAuthorizeMovement,
  };
}

/// Negative capability gate for one view of a fixed walking volume. No pixel
/// interpolation, temporal accumulation, corridor shortening or planner wiring.
class SingleCameraObservabilityPreflight {
  static const maximumAgeUs = 100000;
  static const _borderInsetPixels = 1e-7;

  const SingleCameraObservabilityPreflight();

  SingleCameraObservability assess({
    required CameraVisibleDepthFrame frame,
    required PassageCalibration calibration,
    required PassageClearanceRequest request,
    required PassageEvaluationContext context,
  }) {
    SingleCameraObservability reject(String reason) =>
        SingleCameraObservability._(
          inputsAdmitted: false,
          reason: reason,
          request: request,
        );
    final values = [
      request.lateralCenterM,
      request.widthM,
      request.headroomM,
      request.forwardStartM,
      request.forwardEndM,
      request.maximumFloorRiseM,
      request.maximumFloorDropM,
    ];
    final left = request.lateralCenterM - request.widthM / 2;
    final right = request.lateralCenterM + request.widthM / 2;
    final top = request.headroomM + request.maximumFloorRiseM;
    if (values.any((x) => !x.isFinite) ||
        !left.isFinite ||
        !right.isFinite ||
        !top.isFinite ||
        request.referenceFrameId.trim().isEmpty ||
        request.widthM <= 0 ||
        request.headroomM <= .05 ||
        request.forwardStartM < 0 ||
        request.forwardEndM <= request.forwardStartM ||
        request.maximumFloorRiseM < 0 ||
        request.maximumFloorDropM < 0) {
      return reject('invalid_request');
    }
    if (frame.units != PassageUnits.metricMeters ||
        !calibration.metricScaleValidated ||
        !calibration.alignmentValidated ||
        !calibration.floorReferenceValidated) {
      return reject('unverified_metric_pose');
    }
    if (!frame.structurallyValid) return reject('invalid_frame_or_pose');
    if ([
          calibration.id,
          calibration.providerId,
          calibration.modelId,
          calibration.preprocessId,
          calibration.modelHash,
          calibration.referenceFrameId,
          calibration.transformId,
        ].any((x) => x.trim().isEmpty) ||
        frame.modelHash != calibration.modelHash ||
        frame.referenceFrameId != calibration.referenceFrameId ||
        request.referenceFrameId != calibration.referenceFrameId ||
        frame.transformId != calibration.transformId ||
        frame.transformId != context.transformId ||
        frame.sessionGeneration != context.sessionGeneration ||
        frame.frameId != context.frameId ||
        frame.capturedAtUs != context.rgbTimestampUs ||
        calibration.timestampDomain != context.timestampDomain) {
      return reject('identity_or_clock_mismatch');
    }
    if (context.nowUs < frame.capturedAtUs ||
        context.nowUs - frame.capturedAtUs > maximumAgeUs) {
      return reject('future_or_stale_frame');
    }

    var lower = request.forwardStartM, upper = request.forwardEndM;
    var possible = true;
    // Intersect a * distance + b >= 0. All frustum constraints are affine
    // because each walking-forward slice keeps lateral/height bounds fixed.
    void intersect(double a, double b) {
      if (!a.isFinite || !b.isFinite) {
        possible = false;
        return;
      }
      if (a == 0) {
        if (b < 0) possible = false;
      } else if (a > 0) {
        lower = math.max(lower, -b / a);
      } else {
        upper = math.min(upper, -b / a);
      }
    }

    final r = frame.rotation;
    for (final x in [left, right]) {
      // Body extrema plus the local floor. These are visibility checks, not
      // claims that the floor exists or meets its rise/drop tolerances.
      for (final height in [0.0, .05, top]) {
        final b = frame.cameraPoint([x, 0, height]);
        final a = [r[3], r[4], r[5]];
        intersect(a[2], b[2] - .0100001);
        intersect(
          frame.fx * a[0] + (frame.cx - _borderInsetPixels) * a[2],
          frame.fx * b[0] + (frame.cx - _borderInsetPixels) * b[2],
        );
        intersect(
          (frame.width - frame.cx - _borderInsetPixels) * a[2] -
              frame.fx * a[0],
          (frame.width - frame.cx - _borderInsetPixels) * b[2] -
              frame.fx * b[0],
        );
        intersect(
          frame.fy * a[1] + (frame.cy - _borderInsetPixels) * a[2],
          frame.fy * b[1] + (frame.cy - _borderInsetPixels) * b[2],
        );
        intersect(
          (frame.height - frame.cy - _borderInsetPixels) * a[2] -
              frame.fy * a[1],
          (frame.height - frame.cy - _borderInsetPixels) * b[2] -
              frame.fy * b[1],
        );
      }
    }
    if (!possible || !lower.isFinite || !upper.isFinite || upper <= lower) {
      return SingleCameraObservability._(
        inputsAdmitted: true,
        reason: 'no_complete_cross_section_in_view',
        request: request,
      );
    }
    return SingleCameraObservability._(
      inputsAdmitted: true,
      reason: lower == request.forwardStartM && upper == request.forwardEndM
          ? 'frustum_contains_request_measurements_still_required'
          : 'requested_volume_outside_view',
      request: request,
      visibleStartM: lower,
      visibleEndM: upper,
    );
  }
}
