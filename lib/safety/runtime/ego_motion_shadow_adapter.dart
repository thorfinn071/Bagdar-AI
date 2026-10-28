import '../perception/camera_ego_motion.dart';
import '../perception/camera_metric_motion.dart';
import 'camera_metric_motion_shadow_scene.dart';

/// Opt-in, additive experiment adapter. No relative-track or clearance authority.
bool applyEgoMotionShadow(
  EgoMotionEvidence evidence,
  CameraMetricMotionShadowScene scene, {
  required int sessionGeneration,
  required int frameId,
  required int capturedAtUs,
  required String transformId,
  required int nowUs,
}) {
  final r = evidence.bodyRelativeMotion;
  if (!evidence.poseAccepted ||
      !r.isLiveAt(nowUs) ||
      r.sessionGeneration != sessionGeneration ||
      r.frameId != frameId ||
      r.capturedAtUs != capturedAtUs ||
      r.transformId != transformId) {
    return false;
  }
  scene.setMotion(
    CameraMetricMotionResult(
      reason: r.reason,
      sessionGeneration: r.sessionGeneration,
      frameId: r.frameId,
      capturedAtUs: r.capturedAtUs,
      oldestEvidenceTimestampUs: r.oldestEvidenceTimestampUs,
      validUntilUs: r.validUntilUs,
      transformId: r.transformId,
      candidates: r.candidates,
      unknownPatches: r.unknownPatches,
      patches: [
        for (final p in r.patches)
          MetricPatchMotion(
            previousPixel: p.previousPixel,
            currentPixel: p.currentPixel,
            positionLowerM: p.positionLowerM,
            positionUpperM: p.positionUpperM,
            velocityLowerMps: p.velocityLowerMps,
            velocityUpperMps: p.velocityUpperMps,
            classification: VisiblePatchMotion.values.singleWhere(
              (v) => v.name == p.classification.name,
            ),
            possibleBodyIntersection: p.possibleBodyIntersection,
          ),
      ],
    ),
    sessionGeneration: sessionGeneration,
    frameId: frameId,
    capturedAtUs: capturedAtUs,
    transformId: transformId,
  );
  return r.addsMotionRisk;
}
