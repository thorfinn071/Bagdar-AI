import '../perception/camera_metric_motion.dart';
import '../world/local_scene_model.dart';
import '../world/local_scene_snapshot.dart';
import '../world/scene_fusion_policy.dart';

/// Opt-in dependency supplied to SpatialSafetyRuntime in the experiment only.
/// Adds measured threats; never removes existing evidence or resets history.
class CameraMetricMotionShadowScene extends LocalSceneModel {
  CameraMetricMotionResult? _motion;
  CameraMetricMotionShadowScene() : super.relative();

  void setMotion(
    CameraMetricMotionResult result, {
    required int sessionGeneration,
    required int frameId,
    required int capturedAtUs,
    required String transformId,
  }) {
    _motion =
        result.sessionGeneration == sessionGeneration &&
            result.frameId == frameId &&
            result.capturedAtUs == capturedAtUs &&
            result.transformId == transformId
        ? result
        : null;
  }

  @override
  void reset() {
    _motion = null;
    super.reset();
  }

  @override
  LocalSceneUpdateResult update(LocalSceneUpdate update) {
    final motion = _motion;
    _motion = null; // Single-use, not silently reused by the next frame/tick.
    if (motion == null ||
        !motion.isLiveAt(update.at.microsecondsSinceEpoch) ||
        !motion.addsMotionRisk) {
      return super.update(update);
    }
    final at = DateTime.fromMicrosecondsSinceEpoch(motion.capturedAtUs);
    final until = DateTime.fromMicrosecondsSinceEpoch(motion.validUntilUs);
    return super.update(
      LocalSceneUpdate(
        coordinateMode: update.coordinateMode,
        at: update.at,
        validUntil: update.validUntil,
        poseQuality: update.poseQuality,
        sensorHealth: update.sensorHealth,
        evidence: [
          ...update.evidence,
          SpatialEvidence(
            elementId: 'forward',
            coordinateMode: SceneCoordinateMode.relative,
            sourceId:
                'visible-metric-motion:${motion.sessionGeneration}:${motion.frameId}',
            source: SpatialEvidenceSource.motion,
            observedAt: at,
            validUntil: until,
            observedFraction: 0,
            confidence: .9,
            movingThreatRisk: .9,
            hazardIds: ['visible-motion:${motion.frameId}'],
          ),
        ],
        hazardTracks: update.hazardTracks,
        movingThreats: [
          ...update.movingThreats,
          MovingThreatSnapshot(
            id: 'visible-motion:${motion.frameId}',
            elementId: 'forward',
            intersectionRisk: .9,
            lastObservedAt: at,
          ),
        ],
        useIndependentEvidenceClocks: true,
      ),
    );
  }
}
