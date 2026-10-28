import 'dart:typed_data';

import '../models/depth_frame.dart';
import '../models/generic_obstacle.dart';
import 'fall_detector.dart' show MotionState;
import 'generic_obstacle_detector.dart';

/// Explicit shadow experiment: repeat the RANSAC sampling schedule per input.
///
/// The legacy detector advances three random streams between calls. On an
/// unchanged depth map this can change the ground plane, component support and
/// nearest relative proximity, which the persistent tracker interprets as
/// approach. A fresh segmentation engine uses the original seed and budgets
/// for every current input. No predictions, masks or prior results are cached.
///
/// Detection has no consumed temporal state (its residual history is only
/// written). Tracking, physical evidence and planner history belong to callers
/// and must remain persistent. This facade never resets or edits that history.
/// It takes no scene labels, metric ground truth or declared object motion.
/// The normal camera pipeline retains the legacy detector until promotion.
class FrameStableGenericObstacleDetector {
  final GenericObstacleConfig config;
  final bool collectOpeningDiagnostics;
  final bool collectCameraSupport;

  FrameStableGenericObstacleDetector({
    GenericObstacleConfig? config,
    this.collectOpeningDiagnostics = false,
    this.collectCameraSupport = false,
  }) : config = config ?? GenericObstacleConfig.engineeringDefaults;

  GenericObstacleDetectResult detect({
    required DepthFrame? frame,
    required double pitchDeg,
    required double rollDeg,
    required MotionState motion,
    int? imageTimestampUs,
    Uint8List? lumaMap,
  }) =>
      GenericObstacleDetector(
        config: config,
        collectOpeningDiagnostics: collectOpeningDiagnostics,
        collectCameraSupport: collectCameraSupport,
      ).detect(
        frame: frame,
        pitchDeg: pitchDeg,
        rollDeg: rollDeg,
        motion: motion,
        imageTimestampUs: imageTimestampUs,
        lumaMap: lumaMap,
      );
}
