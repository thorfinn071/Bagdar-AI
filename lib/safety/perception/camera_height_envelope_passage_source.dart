import 'dart:math' as math;

import 'camera_passage_clearance_source.dart';
import 'passage_clearance.dart';

/// Independent whole-pixel height and free-Z bounds of the visible first return.
/// Experimental synthetic input. No labels, plane fitting or filled holes.
class CameraHeightEnvelopeFrame {
  final CameraVisibleDepthFrame depth;
  final List<double> heightLowerM, heightUpperM, firstZLowerM;

  CameraHeightEnvelopeFrame({
    required this.depth,
    required List<double> heightLowerM,
    required List<double> heightUpperM,
    required List<double> firstZLowerM,
  }) : heightLowerM = List.unmodifiable(heightLowerM),
       heightUpperM = List.unmodifiable(heightUpperM),
       firstZLowerM = List.unmodifiable(firstZLowerM);

  bool get structurallyValid {
    if (!depth.structurallyValid ||
        heightLowerM.length != depth.width * depth.height ||
        heightUpperM.length != heightLowerM.length ||
        firstZLowerM.length != heightLowerM.length) {
      return false;
    }
    for (var i = 0; i < heightLowerM.length; i++) {
      final lo = heightLowerM[i], hi = heightUpperM[i];
      final firstZ = firstZLowerM[i];
      final x = i % depth.width, y = i ~/ depth.width;
      final norm = math.sqrt(
        1 +
            math.pow((x + .5 - depth.cx) / depth.fx, 2) +
            math.pow((y + .5 - depth.cy) / depth.fy, 2),
      );
      final centreZ = depth.rangeM[i] / norm;
      if (!firstZ.isNaN &&
          (!firstZ.isFinite ||
              firstZ < 0 ||
              !centreZ.isFinite ||
              !depth.valid[i] ||
              firstZ > centreZ + depth.errorM + 1e-5 ||
              firstZ < depth.freeZLowerM[i] - depth.errorM - 2e-5)) {
        return false;
      }
      // Missing floor support is unknown, independently of body free space.
      if (lo.isNaN && hi.isNaN) continue;
      if (firstZ.isNaN) return false;
      if (!lo.isFinite || !hi.isFinite || lo > hi || !depth.valid[i]) {
        return false;
      }
      final h = depth.worldPoint(x, y, depth.rangeM[i] / norm)[2];
      if (!h.isFinite ||
          h < lo - depth.errorM - 1e-5 ||
          h > hi + depth.errorM + 1e-5) {
        return false;
      }
    }
    return true;
  }
}

CameraVisibleDepthFrame _bodyFrame(CameraHeightEnvelopeFrame envelope) {
  final f = envelope.depth;
  if (envelope.firstZLowerM.length != f.width * f.height ||
      !f.structurallyValid) {
    return f;
  }
  return CameraVisibleDepthFrame(
    width: f.width,
    height: f.height,
    frameId: f.frameId,
    capturedAtUs: f.capturedAtUs,
    sessionGeneration: f.sessionGeneration,
    fx: f.fx,
    fy: f.fy,
    cx: f.cx,
    cy: f.cy,
    errorM: f.errorM,
    poseQuality: f.poseQuality,
    cameraId: f.cameraId,
    modelHash: f.modelHash,
    transformId: f.transformId,
    referenceFrameId: f.referenceFrameId,
    units: f.units,
    providerHealthy: f.providerHealthy,
    rotation: f.rotation,
    originM: f.originM,
    rangeM: f.rangeM,
    surfaceZUpperM: f.surfaceZUpperM,
    valid: f.valid,
    freeZLowerM: [
      for (var i = 0; i < f.width * f.height; i++)
        envelope.firstZLowerM[i].isFinite
            ? envelope.firstZLowerM[i]
            : f.freeZLowerM[i],
    ],
  );
}

/// Retains the frozen body/occupancy/conflict producer and supplies a separate
/// correlated surface-height proof for floor support. No runtime wiring.
class CameraHeightEnvelopePassageSource
    implements PassageClearanceEvidenceSource {
  final PassageCalibration calibration;
  final PassageClearanceRequest request;
  final List<CameraHeightEnvelopeFrame> frames;
  final CameraPassageClearanceSource bodySource;
  final int refinementDepth;
  final double cellSizeM;
  late final bool _healthy;

  CameraHeightEnvelopePassageSource({
    required this.calibration,
    required this.request,
    required List<CameraHeightEnvelopeFrame> frames,
    required int producedAtUs,
    this.refinementDepth = 4,
    this.cellSizeM = .15,
  }) : frames = List.unmodifiable(frames),
       bodySource = CameraPassageClearanceSource(
         calibration: calibration,
         request: request,
         frames: frames.map(_bodyFrame).toList(),
         producedAtUs: producedAtUs,
         allowStaticSyntheticScan: true,
         refinementDepth: refinementDepth,
         cellSizeM: cellSizeM,
       ) {
    _healthy = frames.every((f) => f.structurallyValid);
  }

  @override
  String get providerId => calibration.providerId;

  List<int>? _project(
    CameraVisibleDepthFrame f,
    double x0,
    double x1,
    double y0,
    double y1,
  ) {
    var u0 = double.infinity, v0 = double.infinity;
    var u1 = -double.infinity, v1 = -double.infinity;
    for (final x in [x0, x1]) {
      for (final y in [y0, y1]) {
        final p = f.cameraPoint([x, y, 0]);
        if (p[2] <= .01) return null;
        final u = f.fx * p[0] / p[2] + f.cx, v = f.fy * p[1] / p[2] + f.cy;
        u0 = math.min(u0, u);
        u1 = math.max(u1, u);
        v0 = math.min(v0, v);
        v1 = math.max(v1, v);
      }
    }
    if (u0 < 0 || v0 < 0 || u1 >= f.width || v1 >= f.height) return null;
    return [u0.floor(), u1.floor(), v0.floor(), v1.floor()];
  }

  bool _floorIn(
    CameraHeightEnvelopeFrame envelope,
    double x0,
    double x1,
    double y0,
    double y1,
  ) {
    final f = envelope.depth;
    final p = _project(f, x0, x1, y0, y1);
    if (p == null) return false;
    for (var y = p[2]; y <= p[3]; y++) {
      for (var x = p[0]; x <= p[1]; x++) {
        final i = y * f.width + x;
        final lo = envelope.heightLowerM[i], hi = envelope.heightUpperM[i];
        final lowerZ = f.freeZLowerM[i], upperZ = f.surfaceZUpperM[i];
        if (!f.valid[i] ||
            !f.rangeM[i].isFinite ||
            f.rangeM[i] <= 0 ||
            !lowerZ.isFinite ||
            !upperZ.isFinite ||
            lowerZ < 0 ||
            upperZ < lowerZ ||
            !lo.isFinite ||
            !hi.isFinite ||
            lo > hi ||
            lo - f.errorM < -request.maximumFloorDropM ||
            hi + f.errorM > request.maximumFloorRiseM) {
          return false;
        }
        final norm = math.sqrt(
          1 +
              math.pow((x + .5 - f.cx) / f.fx, 2) +
              math.pow((y + .5 - f.cy) / f.fy, 2),
        );
        final centreZ = f.rangeM[i] / norm;
        if (lowerZ > centreZ + f.errorM + 1e-5 ||
            upperZ < centreZ - f.errorM - 1e-5) {
          return false;
        }
      }
    }
    return true;
  }

  bool _floor(double x0, double x1, double y0, double y1, int depth) {
    if (frames.any((f) => _floorIn(f, x0, x1, y0, y1))) return true;
    if (depth == 0) return false;
    final xm = (x0 + x1) / 2, ym = (y0 + y1) / 2;
    for (final x in [
      [x0, xm],
      [xm, x1],
    ]) {
      for (final y in [
        [y0, ym],
        [ym, y1],
      ]) {
        if (!_floor(x[0], x[1], y[0], y[1], depth - 1)) return false;
      }
    }
    return true;
  }

  @override
  PassageClearanceObservation? observationFor(
    PassageEvaluationContext context,
  ) {
    final prior = bodySource.observationFor(context);
    if (prior == null) return null;
    final sections = <PassageSection>[];
    if (_healthy && prior.providerHealthy) {
      final nx = (request.widthM / cellSizeM).ceil();
      final left = request.lateralCenterM - request.widthM / 2;
      for (final s in prior.sections) {
        if (s.state == PassageSectionState.blocked ||
            s.state == PassageSectionState.conflicting) {
          sections.add(s);
          continue;
        }
        var observed = 0;
        for (var ix = 0; ix < nx; ix++) {
          if (_floor(
            left + request.widthM * ix / nx,
            left + request.widthM * (ix + 1) / nx,
            s.forwardStartM,
            s.forwardEndM,
            refinementDepth,
          )) {
            observed++;
          }
        }
        final floor = observed / nx;
        final measured = s.bodyObservedFraction == 1 && floor == 1;
        sections.add(
          PassageSection(
            forwardStartM: s.forwardStartM,
            forwardEndM: s.forwardEndM,
            state: measured
                ? PassageSectionState.measured
                : PassageSectionState.unknown,
            bodyObservedFraction: s.bodyObservedFraction,
            floorObservedFraction: floor,
            confidence: s.confidence,
            leftBoundaryUpperM: measured ? left : null,
            rightBoundaryLowerM: measured ? left + request.widthM : null,
            headroomLowerBoundM: measured ? request.headroomM : null,
            floorRiseUpperBoundM: measured ? request.maximumFloorRiseM : null,
            floorDropUpperBoundM: measured ? request.maximumFloorDropM : null,
          ),
        );
      }
    }
    return PassageClearanceObservation(
      providerId: prior.providerId,
      modelId: prior.modelId,
      modelHash: prior.modelHash,
      preprocessId: prior.preprocessId,
      calibrationId: prior.calibrationId,
      referenceFrameId: prior.referenceFrameId,
      rgbTransformId: prior.rgbTransformId,
      depthTransformId: prior.depthTransformId,
      timestampDomain: prior.timestampDomain,
      units: prior.units,
      sessionGeneration: prior.sessionGeneration,
      frameId: prior.frameId,
      rgbTimestampUs: prior.rgbTimestampUs,
      depthTimestampUs: prior.depthTimestampUs,
      oldestEvidenceTimestampUs: prior.oldestEvidenceTimestampUs,
      producedAtUs: prior.producedAtUs,
      providerHealthy: _healthy && prior.providerHealthy,
      sections: sections,
    );
  }
}
