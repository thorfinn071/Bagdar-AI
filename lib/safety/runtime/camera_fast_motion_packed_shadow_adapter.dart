import '../perception/camera_metric_motion.dart';
import 'camera_metric_motion_shadow_scene.dart';
import 'camera_fast_motion_packed_worker.dart';

/// Uses the existing additive shadow scene contract. This branch cannot
/// create positive free-space evidence or cancel other providers' risks.
bool applyFastMotionPackedShadow(
  CameraFastMotionPackedWorker worker,
  CameraMetricMotionShadowScene scene,
  FastMotionOutcome outcome,
) {
  final released = worker.release(outcome);
  final r = released.result;
  if (!released.admitted || r == null) return false;
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
    sessionGeneration: r.sessionGeneration,
    frameId: r.frameId,
    capturedAtUs: r.capturedAtUs,
    transformId: r.transformId,
  );
  return r.addsMotionRisk;
}
