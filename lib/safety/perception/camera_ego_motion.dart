import 'dart:math' as math;
import 'camera_fast_metric_motion.dart';
import 'camera_fast_motion_types.dart';
import 'camera_passage_clearance_source.dart';
import 'passage_clearance.dart';

class WalkingPoseContract {
  final String providerId,
      revision,
      localReferenceFrameId,
      worldReferenceFrameId;
  const WalkingPoseContract({
    required this.providerId,
    required this.revision,
    required this.localReferenceFrameId,
    required this.worldReferenceFrameId,
  });
  bool get valid =>
      [
        providerId,
        revision,
        localReferenceFrameId,
        worldReferenceFrameId,
      ].every((v) => v.isNotEmpty) &&
      localReferenceFrameId != worldReferenceFrameId;
}

/// Original-capture translation of the walking origin in fixed world axes.
/// Camera rotation stays in the optical packet. Heading changes are rejected.
class WalkingOriginPose {
  final String providerId,
      revision,
      localReferenceFrameId,
      worldReferenceFrameId;
  final int frameId, capturedAtUs, sessionGeneration, producedAtUs;
  final List<double> originWorldM;
  final double positionErrorM, confidence;
  final bool healthy, fixedHeading;
  WalkingOriginPose({
    required this.providerId,
    required this.revision,
    required this.localReferenceFrameId,
    required this.worldReferenceFrameId,
    required this.frameId,
    required this.capturedAtUs,
    required this.sessionGeneration,
    required this.producedAtUs,
    required List<double> originWorldM,
    required this.positionErrorM,
    required this.confidence,
    required this.healthy,
    required this.fixedHeading,
  }) : originWorldM = List.unmodifiable(originWorldM);

  bool matches(
    FastMetricMotionInput input,
    WalkingPoseContract contract,
    int nowUs,
  ) {
    final f = input.camera.depth;
    return contract.valid &&
        healthy &&
        fixedHeading &&
        confidence.isFinite &&
        confidence >= .9 &&
        confidence <= 1 &&
        positionErrorM.isFinite &&
        positionErrorM >= 0 &&
        positionErrorM <= .05 &&
        originWorldM.length == 3 &&
        originWorldM.every((v) => v.isFinite) &&
        providerId == contract.providerId &&
        revision == contract.revision &&
        localReferenceFrameId == contract.localReferenceFrameId &&
        worldReferenceFrameId == contract.worldReferenceFrameId &&
        f.referenceFrameId == localReferenceFrameId &&
        frameId == f.frameId &&
        sessionGeneration == f.sessionGeneration &&
        capturedAtUs == f.capturedAtUs &&
        producedAtUs >= capturedAtUs &&
        producedAtUs <= nowUs &&
        nowUs >= capturedAtUs &&
        nowUs - capturedAtUs <= 100000;
  }
}

class EgoMotionEvidence {
  final String reason;
  final FastMetricMotionResult worldMotion, bodyRelativeMotion;
  final List<double>? originVelocityLowerMps, originVelocityUpperMps;
  final bool poseAccepted;
  const EgoMotionEvidence({
    required this.reason,
    required this.worldMotion,
    required this.bodyRelativeMotion,
    required this.poseAccepted,
    this.originVelocityLowerMps,
    this.originVelocityUpperMps,
  });
  Map<String, Object?> toDiagnosticMap() => {
    'reason': reason,
    'poseAccepted': poseAccepted,
    'originVelocityLowerMps': originVelocityLowerMps,
    'originVelocityUpperMps': originVelocityUpperMps,
    'worldMotion': worldMotion.toDiagnosticMap(),
    'bodyRelativeMotion': bodyRelativeMotion.toDiagnosticMap(),
    'wholeObjectStationarityCertified': false,
    'relativeHypothesisResolved': false,
    'freeSpaceCertified': false,
    'promotionAllowed': false,
  };
}

/// Converts explicitly bound local walking coordinates to one fixed frame.
/// Only positive local body-relative risk may be consumed downstream.
class CameraEgoMotionSource {
  final WalkingPoseContract poseContract;
  final PassageCalibration localCalibration;
  final FastRgbContract rgbContract;
  late final CameraFastMetricMotionSource _source;
  WalkingOriginPose? _previous;

  CameraEgoMotionSource({
    required this.poseContract,
    required this.localCalibration,
    required this.rgbContract,
  }) {
    _source = CameraFastMetricMotionSource(
      calibration: worldCalibration,
      rgbContract: rgbContract,
    );
  }
  PassageCalibration get worldCalibration => PassageCalibration(
    id: '${localCalibration.id}/ego/${poseContract.revision}',
    providerId: localCalibration.providerId,
    modelId: localCalibration.modelId,
    modelHash: localCalibration.modelHash,
    preprocessId: localCalibration.preprocessId,
    referenceFrameId: poseContract.worldReferenceFrameId,
    transformId: localCalibration.transformId,
    timestampDomain: localCalibration.timestampDomain,
    metricScaleValidated: localCalibration.metricScaleValidated,
    alignmentValidated: localCalibration.alignmentValidated,
    floorReferenceValidated: localCalibration.floorReferenceValidated,
  );

  void invalidate() {
    _previous = null;
    _source.invalidate();
  }

  EgoMotionEvidence observe(
    FastMetricMotionInput input, {
    required WalkingOriginPose? pose,
    required int nowUs,
  }) {
    final f = input.camera.depth;
    FastMetricMotionResult empty(String why) => FastMetricMotionResult(
      reason: why,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      capturedAtUs: f.capturedAtUs,
      oldestEvidenceTimestampUs: f.capturedAtUs,
      validUntilUs: f.capturedAtUs + 100000,
      transformId: f.transformId,
      candidates: 0,
      unknownPatches: 0,
      patches: [],
    );
    EgoMotionEvidence unavailable(String why) {
      invalidate();
      final r = empty(why);
      return EgoMotionEvidence(
        reason: why,
        worldMotion: r,
        bodyRelativeMotion: r,
        poseAccepted: false,
      );
    }

    if (pose == null ||
        !pose.matches(input, poseContract, nowUs) ||
        localCalibration.referenceFrameId !=
            poseContract.localReferenceFrameId ||
        !f.structurallyValid) {
      return unavailable('missing_invalid_or_unbound_walking_pose');
    }
    // Validate the separately declared RGB geometry before changing coordinates.
    final g = input.camera.imageGeometry;
    bool same(List<double> a, List<double> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].isFinite && b[i].isFinite && (a[i] - b[i]).abs() < 1e-6,
        ).every((v) => v);
    if (g.cameraId != f.cameraId ||
        g.width != f.width ||
        g.height != f.height ||
        !same([g.fx, g.fy, g.cx, g.cy], [f.fx, f.fy, f.cx, f.cy]) ||
        !same(g.rotation, f.rotation) ||
        !same(g.originM, f.originM) ||
        !input.positionErrorM.isFinite ||
        input.positionErrorM < 0 ||
        input.positionErrorM + pose.positionErrorM > .1) {
      return unavailable('invalid_local_rgb_depth_alignment_or_pose_error');
    }
    final origin = List.generate(3, (i) => f.originM[i] + pose.originWorldM[i]);
    final aligned = FastMetricMotionInput(
      camera: FastCameraInput(
        rgbHeader: input.camera.rgbHeader,
        depth: CameraVisibleDepthFrame(
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
          referenceFrameId: poseContract.worldReferenceFrameId,
          units: f.units,
          providerHealthy: f.providerHealthy,
          rotation: f.rotation,
          originM: origin,
          rangeM: f.rangeM,
          freeZLowerM: f.freeZLowerM,
          surfaceZUpperM: f.surfaceZUpperM,
          valid: f.valid,
        ),
        imageGeometry: FastRgbGeometry(
          cameraId: g.cameraId,
          width: g.width,
          height: g.height,
          fx: g.fx,
          fy: g.fy,
          cx: g.cx,
          cy: g.cy,
          rotation: g.rotation,
          originM: origin,
        ),
      ),
      rgb: input.rgb,
      positionErrorM: input.positionErrorM + pose.positionErrorM,
      angularErrorRad: input.angularErrorRad,
    );
    final prior = _previous;
    final measured = _source.observe(aligned, nowUs: nowUs);
    if (measured.reason == 'invalid_identity_projection_pose_depth_or_age') {
      return unavailable(measured.reason);
    }
    _previous = pose;
    if (prior == null ||
        measured.oldestEvidenceTimestampUs != prior.capturedAtUs ||
        !measured.available) {
      return EgoMotionEvidence(
        reason: measured.reason,
        poseAccepted: true,
        worldMotion: measured,
        bodyRelativeMotion: measured,
      );
    }
    final dt = (pose.capturedAtUs - prior.capturedAtUs) / 1e6;
    final error = pose.positionErrorM + prior.positionErrorM;
    final lo = List.generate(
      3,
      (i) => (pose.originWorldM[i] - prior.originWorldM[i] - error) / dt,
    );
    final hi = List.generate(
      3,
      (i) => (pose.originWorldM[i] - prior.originWorldM[i] + error) / dt,
    );
    final body = [
      for (final p in measured.patches) _relativePatch(p, pose, lo, hi),
    ];
    return EgoMotionEvidence(
      reason: 'world_and_body_relative_intervals',
      poseAccepted: true,
      worldMotion: measured,
      originVelocityLowerMps: lo,
      originVelocityUpperMps: hi,
      bodyRelativeMotion: FastMetricMotionResult(
        reason: measured.reason,
        sessionGeneration: measured.sessionGeneration,
        frameId: measured.frameId,
        capturedAtUs: measured.capturedAtUs,
        oldestEvidenceTimestampUs: measured.oldestEvidenceTimestampUs,
        validUntilUs: measured.validUntilUs,
        transformId: measured.transformId,
        candidates: measured.candidates,
        unknownPatches: measured.unknownPatches,
        patches: body,
      ),
    );
  }

  static FastPatchMotion _relativePatch(
    FastPatchMotion p,
    WalkingOriginPose pose,
    List<double> egoLo,
    List<double> egoHi,
  ) {
    final lo = List.generate(3, (i) => p.velocityLowerMps[i] - egoHi[i]);
    final hi = List.generate(3, (i) => p.velocityUpperMps[i] - egoLo[i]);
    final a = List.generate(
      3,
      (i) => p.positionLowerM[i] - pose.originWorldM[i] - pose.positionErrorM,
    );
    final b = List.generate(
      3,
      (i) => p.positionUpperM[i] - pose.originWorldM[i] + pose.positionErrorM,
    );
    final c = hi[1] < -.20
        ? FastPatchClassification.approaching
        : lo[1] > .20
        ? FastPatchClassification.receding
        : hi[0] < -.20 || lo[0] > .20
        ? FastPatchClassification.lateral
        : List.generate(3, (i) => lo[i] >= -.20 && hi[i] <= .20).every((v) => v)
        ? FastPatchClassification.consistentWithStationary
        : FastPatchClassification.uncertain;
    // Conservative one-second visible-patch sweep in CURRENT walking axes.
    // It adds risk; it never certifies the rest of the object or a clear path.
    final sweepLo = List.generate(3, (i) => math.min(a[i], a[i] + lo[i]));
    final sweepHi = List.generate(3, (i) => math.max(b[i], b[i] + hi[i]));
    final intersects =
        sweepHi[0] >= -.55 &&
        sweepLo[0] <= .55 &&
        sweepHi[1] >= 0 &&
        sweepLo[1] <= 3.5 &&
        sweepHi[2] >= .1 &&
        sweepLo[2] <= 1.9;
    return FastPatchMotion(
      previousPixel: p.previousPixel,
      currentPixel: p.currentPixel,
      positionLowerM: a,
      positionUpperM: b,
      velocityLowerMps: lo,
      velocityUpperMps: hi,
      classification: c,
      possibleBodyIntersection: intersects,
    );
  }
}
