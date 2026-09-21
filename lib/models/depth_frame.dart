import 'dart:typed_data';

import '../utils/depth_hazard.dart';
import 'generic_obstacle_mode.dart';
import 'plane_fit_quality.dart';

enum DepthProviderKind { arcoreMetric, ncnnRelative, unavailable }

enum DepthValueSemantics {
  /// Finite positive metres; smaller means nearer.
  metricMeters,

  /// Normalized 0..1; larger means nearer.
  relativeProximity,
}

enum DepthCapability {
  healthyMetric,
  healthyRelative,
  temporarilyLowConfidence,
  unalignedOrStale,
  providerUnavailable,
  legacyOnlyDegraded,
}

class CameraIntrinsics {
  final double fx;
  final double fy;
  final double cx;
  final double cy;

  const CameraIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
  });

  bool get isUsable =>
      fx.isFinite &&
      fy.isFinite &&
      cx.isFinite &&
      cy.isFinite &&
      fx > 1 &&
      fy > 1;
}

class DepthHealthComponents {
  final double validCoverage;
  final double dynamicRange;
  final double temporalStability;
  final double blurLightGate;
  final double providerState;

  const DepthHealthComponents({
    required this.validCoverage,
    required this.dynamicRange,
    required this.temporalStability,
    required this.blurLightGate,
    required this.providerState,
  });

  double get combined =>
      (0.30 * validCoverage +
              0.20 * dynamicRange +
              0.20 * temporalStability +
              0.15 * blurLightGate +
              0.15 * providerState)
          .clamp(0.0, 1.0);

  Map<String, double> toLogMap() => <String, double>{
    'validCoverage': validCoverage,
    'dynamicRange': dynamicRange,
    'temporalStability': temporalStability,
    'blurLightGate': blurLightGate,
    'providerState': providerState,
    'combined': combined,
  };
}

class DepthHealth {
  final DepthCapability capability;
  final DepthHealthComponents components;
  final bool genericObstacleAvailable;
  final String? rejectionReason;
  final DepthProviderKind provider;

  const DepthHealth({
    required this.capability,
    required this.components,
    required this.genericObstacleAvailable,
    required this.provider,
    this.rejectionReason,
  });

  factory DepthHealth.unavailable({
    required DepthProviderKind provider,
    required String reason,
  }) => DepthHealth(
    capability: DepthCapability.providerUnavailable,
    components: const DepthHealthComponents(
      validCoverage: 0,
      dynamicRange: 0,
      temporalStability: 0,
      blurLightGate: 0,
      providerState: 0,
    ),
    genericObstacleAvailable: false,
    provider: provider,
    rejectionReason: reason,
  );

  factory DepthHealth.legacyOnly({
    required DepthProviderKind provider,
    required String reason,
    DepthHealthComponents? components,
  }) => DepthHealth(
    capability: DepthCapability.legacyOnlyDegraded,
    components:
        components ??
        const DepthHealthComponents(
          validCoverage: 0,
          dynamicRange: 0,
          temporalStability: 0,
          blurLightGate: 0,
          providerState: 0.3,
        ),
    genericObstacleAvailable: false,
    provider: provider,
    rejectionReason: reason,
  );

  bool get isHealthyGeometry =>
      genericObstacleAvailable &&
      (capability == DepthCapability.healthyMetric ||
          capability == DepthCapability.healthyRelative);
}

class DepthFrame {
  final Float32List values;
  final Float32List confidence01;
  final int width;
  final int height;
  final int timestampUs;
  final DepthProviderKind provider;
  final DepthValueSemantics semantics;
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final CameraIntrinsics? intrinsics;

  /// Source-sensor transform already applied to [values]. Consumers use it
  /// only to bring raw camera/YOLO coordinates into the same upright space.
  final int rotationDegrees;
  final bool mirrored;
  final double cropTopFraction;
  final double frameQuality;
  final bool alignedToImage;
  final int? nativeOutputWidth;
  final int? nativeOutputHeight;

  DepthFrame({
    required this.values,
    required this.confidence01,
    required this.width,
    required this.height,
    required this.timestampUs,
    required this.provider,
    required this.semantics,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    required this.cropTopFraction,
    required this.frameQuality,
    required this.alignedToImage,
    this.intrinsics,
    this.rotationDegrees = 0,
    this.mirrored = false,
    this.nativeOutputWidth,
    this.nativeOutputHeight,
  }) {
    if (modelId.isEmpty || modelHash.isEmpty || preprocessId.isEmpty) {
      throw ArgumentError('depth model identity must be complete');
    }
    final n = width * height;
    if (values.length != n) {
      throw ArgumentError('values length ${values.length} != $n');
    }
    if (confidence01.length != n) {
      throw ArgumentError('confidence01 length ${confidence01.length} != $n');
    }
  }

  int get length => width * height;

  double valueAt(int x, int y) => values[y * width + x];

  double confidenceAt(int x, int y) => confidence01[y * width + x];
}

class DepthAnalysisResult {
  final DepthFrame? frame;

  /// Camera luma transformed with the exact same rotation, mirror, crop, and
  /// resize as [frame]. It is optional because metric providers may not own
  /// the camera image. Missing luma is never positive edge evidence.
  final Uint8List? alignedLuma;
  final List<DepthHazard> legacyHazards;
  final DepthHealth health;
  final PlaneFitQuality? planeFitQuality;

  const DepthAnalysisResult({
    required this.legacyHazards,
    required this.health,
    this.frame,
    this.alignedLuma,
    this.planeFitQuality,
  });

  static const emptyUnavailable = DepthAnalysisResult(
    frame: null,
    legacyHazards: <DepthHazard>[],
    health: DepthHealth(
      capability: DepthCapability.providerUnavailable,
      components: DepthHealthComponents(
        validCoverage: 0,
        dynamicRange: 0,
        temporalStability: 0,
        blurLightGate: 0,
        providerState: 0,
      ),
      genericObstacleAvailable: false,
      provider: DepthProviderKind.unavailable,
      rejectionReason: 'empty',
    ),
  );
}

/// Centralized engineering defaults. Tune only against recorded evidence.
class GenericObstacleConfig {
  final int mapSize;
  final double corridorWidthFrac;
  final double corridorCenterX;
  final double minPixelConfidence;
  final double minValidCoverage;
  final double occupancyMargin;
  final double wallCoverageFrac;
  final double poleMaxWidthFrac;
  final double poleMinHeightFrac;
  final double poleMinCorridorOverlap;
  final double lowObstacleMaxHeightFrac;
  final double overheadMaxRowFrac;
  final int minComponentPixels;
  final int thinMinPixels;
  final double monitorProximity;
  final double warningProximity;
  final double criticalProximity;
  final double metricMinM;
  final double metricMaxM;
  final double bodyWidthM;
  final double corridorWidthM;
  final double headHeightM;
  final double ankleHeightM;
  final double groundInlierM;
  final int ransacIters;
  final int confirmNeedRelative;
  final int confirmWindowRelative;
  final int confirmNeedMetric;
  final int confirmWindowMetric;
  final int expireMissedFrames;
  final double recedeProximityDelta;
  final double approachProximityDelta;
  final double semanticMatchIou;
  final double semanticMinConf;
  final int maxImageDepthDeltaUs;
  final double edgeOnlyMaxRisk; // monitor only
  final double minHealthyFrameQuality;
  final double trackMinIou;
  final double trackMaxCentroidDistance;
  final int semanticMaxAgeUs;
  final double maxSupportedRollDeg;
  final double minGroundInlierRatio;
  final GenericObstacleMode defaultMode;

  const GenericObstacleConfig({
    this.mapSize = 256,
    this.corridorWidthFrac = 0.42,
    this.corridorCenterX = 0.5,
    this.minPixelConfidence = 0.15,
    this.minValidCoverage = 0.08,
    this.occupancyMargin = 0.12,
    this.wallCoverageFrac = 0.55,
    this.poleMaxWidthFrac = 0.10,
    this.poleMinHeightFrac = 0.32,
    this.poleMinCorridorOverlap = 0.35,
    this.lowObstacleMaxHeightFrac = 0.30,
    this.overheadMaxRowFrac = 0.40,
    this.minComponentPixels = 18,
    this.thinMinPixels = 8,
    this.monitorProximity = 0.45,
    this.warningProximity = 0.60,
    this.criticalProximity = 0.80,
    this.metricMinM = 0.15,
    this.metricMaxM = 8.0,
    this.bodyWidthM = 0.70,
    this.corridorWidthM = 0.90,
    this.headHeightM = 1.80,
    this.ankleHeightM = 0.12,
    this.groundInlierM = 0.08,
    this.ransacIters = 40,
    this.confirmNeedRelative = 3,
    this.confirmWindowRelative = 5,
    this.confirmNeedMetric = 2,
    this.confirmWindowMetric = 4,
    this.expireMissedFrames = 3,
    this.recedeProximityDelta = 0.06,
    this.approachProximityDelta = 0.05,
    this.semanticMatchIou = 0.25,
    this.semanticMinConf = 0.55,
    this.maxImageDepthDeltaUs = 80000,
    this.edgeOnlyMaxRisk = 0.0,
    this.minHealthyFrameQuality = 0.55,
    this.trackMinIou = 0.02,
    this.trackMaxCentroidDistance = 0.18,
    this.semanticMaxAgeUs = 1500000,
    this.maxSupportedRollDeg = 25.0,
    this.minGroundInlierRatio = 0.20,
    this.defaultMode = GenericObstacleMode.shadow,
  });

  static const engineeringDefaults = GenericObstacleConfig();
}
