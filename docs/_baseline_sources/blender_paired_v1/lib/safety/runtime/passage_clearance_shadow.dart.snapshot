import '../perception/passage_clearance.dart';

/// Explicit opt-in experiment for the opening hypothesis, always shadow.
/// The active calibration and body-volume request are supplied independently
/// of observations. No default camera/model source or app wiring is provided.
class PassageClearanceShadowConfiguration {
  final PassageCalibration calibration;
  final PassageClearanceRequest request;
  final PassageClearancePolicy policy;
  final double minimumPoseQuality;

  /// Camera experiments require an explicit current observation, including a
  /// negative/unavailable one. Legacy hypothesis-only oracles remain optional.
  final bool requireCameraEvidence;
  final bool associateCameraTracks;
  final String? cameraTrackModelHash;

  const PassageClearanceShadowConfiguration({
    required this.calibration,
    required this.request,
    required this.policy,
    this.minimumPoseQuality = 0.9,
    this.requireCameraEvidence = false,
    this.associateCameraTracks = false,
    this.cameraTrackModelHash,
  });

  bool acceptsPose(double quality) =>
      minimumPoseQuality.isFinite &&
      minimumPoseQuality > 0 &&
      minimumPoseQuality <= 1 &&
      quality.isFinite &&
      quality >= minimumPoseQuality &&
      quality <= 1;
}
