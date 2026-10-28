import 'dart:math' as math;

enum PassageUnits { metricMeters, relativeProximity }

enum PassageTimestampDomain {
  utcEpochMicroseconds,
  elapsedRealtimeMicroseconds,
}

enum PassageSectionState { measured, blocked, unknown, conflicting }

enum PassageClearanceStatus { measuredClear, blocked, unavailable }

enum PassageClearanceReason {
  invalidPolicy,
  invalidRequest,
  invalidContext,
  missingCalibration,
  unverifiedCalibration,
  missingObservation,
  invalidIdentity,
  providerUnhealthy,
  nonMetricMeasurements,
  calibrationMismatch,
  modelMismatch,
  referenceFrameMismatch,
  transformMismatch,
  clockMismatch,
  sessionMismatch,
  frameMismatch,
  invalidTimestamp,
  futureObservation,
  staleObservation,
  pairSkew,
  processingLatency,
  missingSections,
  tooManySections,
  invalidSection,
  missingMeasurements,
  insufficientConfidence,
  unobservedBody,
  unobservedFloor,
  conflictingMeasurements,
  blockedSection,
  narrowPassage,
  corridorOutsideOpening,
  insufficientHeadroom,
  floorRise,
  floorDrop,
  coverageGap,
}

/// Declared calibration receipt, supplied independently of the observation.
/// These declarations require device/recording validation outside this module.
class PassageCalibration {
  final String id;
  final String providerId;
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final String referenceFrameId;
  final String transformId;
  final PassageTimestampDomain timestampDomain;
  final bool metricScaleValidated;
  final bool alignmentValidated;
  final bool floorReferenceValidated;

  const PassageCalibration({
    required this.id,
    required this.providerId,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    required this.referenceFrameId,
    required this.transformId,
    required this.timestampDomain,
    required this.metricScaleValidated,
    required this.alignmentValidated,
    required this.floorReferenceValidated,
  });
}

/// Requested volume in a calibrated walking frame: lateral x, forward z and
/// height above the local floor. Dimensions/margins are explicit, not inferred
/// from image pixels or a device-independent body-size assumption.
class PassageClearanceRequest {
  final String referenceFrameId;
  final double lateralCenterM;
  final double widthM;
  final double headroomM;
  final double forwardStartM;
  final double forwardEndM;
  final double maximumFloorRiseM;
  final double maximumFloorDropM;

  const PassageClearanceRequest({
    required this.referenceFrameId,
    required this.lateralCenterM,
    required this.widthM,
    required this.headroomM,
    required this.forwardStartM,
    required this.forwardEndM,
    required this.maximumFloorRiseM,
    required this.maximumFloorDropM,
  });
}

class PassageEvaluationContext {
  final int nowUs;
  final PassageTimestampDomain timestampDomain;
  final int sessionGeneration;
  final int frameId;
  final int rgbTimestampUs;
  final String transformId;

  const PassageEvaluationContext({
    required this.nowUs,
    required this.timestampDomain,
    required this.sessionGeneration,
    required this.frameId,
    required this.rgbTimestampUs,
    required this.transformId,
  });
}

/// Bounds over an entire forward interval, not sparse endpoint samples.
/// Intervals are closed: an obstacle at the requested endpoint still blocks it.
///
/// The free lateral interval must be contiguous and contain no internal pole,
/// person or other occupancy. Boundary/headroom bounds already include the
/// producer's measurement error: left moves inward to its upper bound, right
/// to its lower bound, and headroom is the minimum over the ENTIRE declared
/// lateral interval and forward interval. Floor limits are upper bounds on
/// discontinuities over that same volume, not a narrower sampled lane. Body
/// and floor observed fractions also cover this entire volume. This allows
/// requests contained by those bounds without reusing lane-specific evidence.
/// Missing/unbounded measurements remain null; interpolation is not proof.
class PassageSection {
  final double forwardStartM;
  final double forwardEndM;
  final PassageSectionState state;
  final double bodyObservedFraction;
  final double floorObservedFraction;
  final double confidence;
  final double? leftBoundaryUpperM;
  final double? rightBoundaryLowerM;
  final double? headroomLowerBoundM;
  final double? floorRiseUpperBoundM;
  final double? floorDropUpperBoundM;

  const PassageSection({
    required this.forwardStartM,
    required this.forwardEndM,
    required this.state,
    required this.bodyObservedFraction,
    required this.floorObservedFraction,
    required this.confidence,
    this.leftBoundaryUpperM,
    this.rightBoundaryLowerM,
    this.headroomLowerBoundM,
    this.floorRiseUpperBoundM,
    this.floorDropUpperBoundM,
  });
}

class PassageClearanceObservation {
  final String providerId;
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final String calibrationId;
  final String referenceFrameId;
  final String rgbTransformId;
  final String depthTransformId;
  final PassageTimestampDomain timestampDomain;
  final PassageUnits units;
  final int sessionGeneration;
  final int frameId;
  final int rgbTimestampUs;
  final int depthTimestampUs;

  /// Earliest contributing capture, including prior views in a scan. Pair
  /// skew still applies to the final RGB/depth pair, independently of this age.
  final int oldestEvidenceTimestampUs;
  final int producedAtUs;
  final bool providerHealthy;
  final List<PassageSection> sections;

  PassageClearanceObservation({
    required this.providerId,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    required this.calibrationId,
    required this.referenceFrameId,
    required this.rgbTransformId,
    required this.depthTransformId,
    required this.timestampDomain,
    required this.units,
    required this.sessionGeneration,
    required this.frameId,
    required this.rgbTimestampUs,
    required this.depthTimestampUs,
    int? oldestEvidenceTimestampUs,
    required this.producedAtUs,
    required this.providerHealthy,
    required List<PassageSection> sections,
  }) : oldestEvidenceTimestampUs =
           oldestEvidenceTimestampUs ??
           math.min(rgbTimestampUs, depthTimestampUs),
       sections = List.unmodifiable(sections);
}

/// Boundary for a future calibrated producer. No current NCNN/ARCore adapter
/// implements it, and this contract does not grant planner/audio authority.
abstract interface class PassageClearanceEvidenceSource {
  String get providerId;

  PassageClearanceObservation? observationFor(PassageEvaluationContext context);
}

class PassageClearancePolicy {
  final int maximumAgeUs;
  final int maximumPairSkewUs;
  final int maximumProcessingLatencyUs;
  final double minimumConfidence;
  final int maximumSections;

  const PassageClearancePolicy({
    required this.maximumAgeUs,
    required this.maximumPairSkewUs,
    required this.maximumProcessingLatencyUs,
    required this.minimumConfidence,
    this.maximumSections = 128,
  });
}

class PassageClearanceResult {
  final PassageClearanceStatus status;
  final List<PassageClearanceReason> reasons;
  final double? minimumWidthLowerBoundM;
  final double? minimumHeadroomLowerBoundM;
  final double? minimumEvidenceConfidence;
  final int? validUntilUs;
  final PassageClearanceRequest request;
  final PassageEvaluationContext context;

  PassageClearanceResult._({
    required this.status,
    required Iterable<PassageClearanceReason> reasons,
    required this.request,
    required this.context,
    this.minimumWidthLowerBoundM,
    this.minimumHeadroomLowerBoundM,
    this.minimumEvidenceConfidence,
    this.validUntilUs,
  }) : reasons = List.unmodifiable(reasons);

  /// The complete centred volume used by the camera recovery experiment.
  /// A shorter or narrower request cannot retire a forward coverage gap.
  bool get coversCameraRecoveryVolume =>
      status == PassageClearanceStatus.measuredClear &&
      request.lateralCenterM == 0 &&
      request.widthM >= .9 &&
      request.headroomM >= 1.8 &&
      request.forwardStartM <= .2 &&
      request.forwardEndM >= 3.5 &&
      request.maximumFloorRiseM <= .05 &&
      request.maximumFloorDropM <= .05;

  Map<String, Object?> toDiagnosticMap() => {
    'status': status.name,
    'reasons': reasons.map((reason) => reason.name).toList(growable: false),
    'minimumWidthLowerBoundM': minimumWidthLowerBoundM,
    'minimumHeadroomLowerBoundM': minimumHeadroomLowerBoundM,
    'minimumEvidenceConfidence': minimumEvidenceConfidence,
    'validUntilUs': validUntilUs,
    'sessionGeneration': context.sessionGeneration,
    'frameId': context.frameId,
    'evaluatedAtUs': context.nowUs,
    'timestampDomain': context.timestampDomain.name,
    'referenceFrameId': request.referenceFrameId,
  };

  /// Result reuse is limited to the same request and RGB frame. A consumer
  /// must still check its current provider/pose health and active calibration.
  /// This predicate grants no planner or assistive authority.
  bool appliesTo({
    required PassageClearanceRequest request,
    required PassageEvaluationContext context,
  }) =>
      status == PassageClearanceStatus.measuredClear &&
      validUntilUs != null &&
      context.nowUs >= this.context.nowUs &&
      context.nowUs <= validUntilUs! &&
      context.timestampDomain == this.context.timestampDomain &&
      context.sessionGeneration == this.context.sessionGeneration &&
      context.frameId == this.context.frameId &&
      context.rgbTimestampUs == this.context.rgbTimestampUs &&
      context.transformId == this.context.transformId &&
      request.referenceFrameId == this.request.referenceFrameId &&
      request.lateralCenterM == this.request.lateralCenterM &&
      request.widthM == this.request.widthM &&
      request.headroomM == this.request.headroomM &&
      request.forwardStartM == this.request.forwardStartM &&
      request.forwardEndM == this.request.forwardEndM &&
      request.maximumFloorRiseM == this.request.maximumFloorRiseM &&
      request.maximumFloorDropM == this.request.maximumFloorDropM;
}

/// Pure, stateless admission of declared metric bounds. A measured-clear
/// result establishes only contract conformance, never model/device accuracy.
class PassageClearanceEvaluator {
  final PassageClearancePolicy policy;

  const PassageClearanceEvaluator({required this.policy});

  PassageClearanceResult evaluate({
    required PassageClearanceRequest request,
    required PassageEvaluationContext context,
    required PassageCalibration? calibration,
    required PassageClearanceObservation? observation,
  }) {
    final reasons = <PassageClearanceReason>{};
    void reject(PassageClearanceReason reason) => reasons.add(reason);
    PassageClearanceResult unavailable() => PassageClearanceResult._(
      status: PassageClearanceStatus.unavailable,
      reasons: reasons,
      request: request,
      context: context,
    );
    if (policy.maximumAgeUs <= 0 ||
        policy.maximumPairSkewUs < 0 ||
        policy.maximumProcessingLatencyUs < 0 ||
        policy.maximumSections <= 0 ||
        !_positive(policy.minimumConfidence) ||
        policy.minimumConfidence > 1) {
      reject(PassageClearanceReason.invalidPolicy);
      return unavailable();
    }
    final left = request.lateralCenterM - request.widthM / 2;
    final right = request.lateralCenterM + request.widthM / 2;
    if (request.referenceFrameId.trim().isEmpty ||
        !request.lateralCenterM.isFinite ||
        !_positive(request.widthM) ||
        !_positive(request.headroomM) ||
        !left.isFinite ||
        !right.isFinite ||
        !_nonnegative(request.forwardStartM) ||
        !request.forwardEndM.isFinite ||
        request.forwardEndM <= request.forwardStartM ||
        !_nonnegative(request.maximumFloorRiseM) ||
        !_nonnegative(request.maximumFloorDropM)) {
      reject(PassageClearanceReason.invalidRequest);
      return unavailable();
    }
    if (context.nowUs < 0 ||
        context.rgbTimestampUs < 0 ||
        context.rgbTimestampUs > context.nowUs ||
        context.sessionGeneration < 0 ||
        context.frameId <= 0 ||
        context.transformId.trim().isEmpty) {
      reject(PassageClearanceReason.invalidContext);
      return unavailable();
    }
    if (calibration == null) {
      reject(PassageClearanceReason.missingCalibration);
      return unavailable();
    }
    if ([
          calibration.id,
          calibration.providerId,
          calibration.modelId,
          calibration.modelHash,
          calibration.preprocessId,
          calibration.referenceFrameId,
          calibration.transformId,
        ].any((value) => value.trim().isEmpty) ||
        !calibration.metricScaleValidated ||
        !calibration.alignmentValidated ||
        !calibration.floorReferenceValidated) {
      reject(PassageClearanceReason.unverifiedCalibration);
    }
    if (observation == null) {
      reject(PassageClearanceReason.missingObservation);
      return unavailable();
    }
    if ([
          observation.providerId,
          observation.modelId,
          observation.modelHash,
          observation.preprocessId,
          observation.calibrationId,
          observation.referenceFrameId,
          observation.rgbTransformId,
          observation.depthTransformId,
        ].any((value) => value.trim().isEmpty) ||
        observation.sessionGeneration < 0 ||
        observation.frameId <= 0) {
      reject(PassageClearanceReason.invalidIdentity);
    }
    if (!observation.providerHealthy) {
      reject(PassageClearanceReason.providerUnhealthy);
    }
    if (observation.units != PassageUnits.metricMeters) {
      reject(PassageClearanceReason.nonMetricMeasurements);
    }
    if (calibration.id != observation.calibrationId ||
        calibration.providerId != observation.providerId) {
      reject(PassageClearanceReason.calibrationMismatch);
    }
    if (calibration.modelId != observation.modelId ||
        calibration.modelHash != observation.modelHash ||
        calibration.preprocessId != observation.preprocessId) {
      reject(PassageClearanceReason.modelMismatch);
    }
    if (request.referenceFrameId != calibration.referenceFrameId ||
        request.referenceFrameId != observation.referenceFrameId) {
      reject(PassageClearanceReason.referenceFrameMismatch);
    }
    if (context.transformId != calibration.transformId ||
        context.transformId != observation.rgbTransformId ||
        context.transformId != observation.depthTransformId) {
      reject(PassageClearanceReason.transformMismatch);
    }
    if (context.timestampDomain != calibration.timestampDomain ||
        context.timestampDomain != observation.timestampDomain) {
      reject(PassageClearanceReason.clockMismatch);
    }
    if (context.sessionGeneration != observation.sessionGeneration) {
      reject(PassageClearanceReason.sessionMismatch);
    }
    if (context.frameId != observation.frameId ||
        context.rgbTimestampUs != observation.rgbTimestampUs) {
      reject(PassageClearanceReason.frameMismatch);
    }
    final pairOldest = math.min(
      observation.rgbTimestampUs,
      observation.depthTimestampUs,
    );
    final oldest = observation.oldestEvidenceTimestampUs;
    final newest = math.max(
      observation.rgbTimestampUs,
      observation.depthTimestampUs,
    );
    if (oldest < 0 ||
        oldest > pairOldest ||
        observation.producedAtUs < newest) {
      reject(PassageClearanceReason.invalidTimestamp);
    }
    if (newest > context.nowUs || observation.producedAtUs > context.nowUs) {
      reject(PassageClearanceReason.futureObservation);
    }
    if (context.nowUs - oldest > policy.maximumAgeUs) {
      reject(PassageClearanceReason.staleObservation);
    }
    if (newest - pairOldest > policy.maximumPairSkewUs) {
      reject(PassageClearanceReason.pairSkew);
    }
    if (observation.producedAtUs - pairOldest >
        policy.maximumProcessingLatencyUs) {
      reject(PassageClearanceReason.processingLatency);
    }
    if (reasons.isNotEmpty) return unavailable();
    if (observation.sections.isEmpty) {
      reject(PassageClearanceReason.missingSections);
    }
    if (observation.sections.length > policy.maximumSections) {
      reject(PassageClearanceReason.tooManySections);
    }
    if (reasons.isNotEmpty) return unavailable();

    final covering = <PassageSection>[];
    var blocked = false;
    double? minimumWidth;
    double? minimumHeadroom;
    double? minimumConfidence;
    for (final section in observation.sections) {
      if (!_nonnegative(section.forwardStartM) ||
          !section.forwardEndM.isFinite ||
          section.forwardEndM <= section.forwardStartM ||
          !_probability(section.bodyObservedFraction) ||
          !_probability(section.floorObservedFraction) ||
          !_probability(section.confidence)) {
        reject(PassageClearanceReason.invalidSection);
        continue;
      }
      if (section.forwardEndM < request.forwardStartM ||
          section.forwardStartM > request.forwardEndM) {
        continue;
      }
      covering.add(section);
      minimumConfidence = minimumConfidence == null
          ? section.confidence
          : math.min(minimumConfidence, section.confidence);
      if (section.confidence < policy.minimumConfidence) {
        reject(PassageClearanceReason.insufficientConfidence);
        continue;
      }
      // A floor cannot stand in for unobserved body/head space, or vice versa.
      if (section.bodyObservedFraction < 1) {
        reject(PassageClearanceReason.unobservedBody);
      }
      if (section.floorObservedFraction < 1) {
        reject(PassageClearanceReason.unobservedFloor);
      }
      if (section.state == PassageSectionState.unknown) {
        reject(PassageClearanceReason.missingMeasurements);
        continue;
      }
      if (section.state == PassageSectionState.conflicting) {
        reject(PassageClearanceReason.conflictingMeasurements);
        continue;
      }
      if (section.state == PassageSectionState.blocked) {
        blocked = true;
        reject(PassageClearanceReason.blockedSection);
        continue;
      }
      final x0 = section.leftBoundaryUpperM;
      final x1 = section.rightBoundaryLowerM;
      final height = section.headroomLowerBoundM;
      final rise = section.floorRiseUpperBoundM;
      final drop = section.floorDropUpperBoundM;
      if (x0 == null ||
          x1 == null ||
          height == null ||
          rise == null ||
          drop == null) {
        reject(PassageClearanceReason.missingMeasurements);
        continue;
      }
      if (!x0.isFinite ||
          !x1.isFinite ||
          x1 < x0 ||
          !(x1 - x0).isFinite ||
          !_nonnegative(height) ||
          !_nonnegative(rise) ||
          !_nonnegative(drop)) {
        reject(PassageClearanceReason.invalidSection);
        continue;
      }
      final width = x1 - x0;
      minimumWidth = minimumWidth == null
          ? width
          : math.min(minimumWidth, width);
      minimumHeadroom = minimumHeadroom == null
          ? height
          : math.min(minimumHeadroom, height);
      if (width < request.widthM) {
        blocked = true;
        reject(PassageClearanceReason.narrowPassage);
      } else if (x0 > left || x1 < right) {
        blocked = true;
        reject(PassageClearanceReason.corridorOutsideOpening);
      }
      if (height < request.headroomM) {
        blocked = true;
        reject(PassageClearanceReason.insufficientHeadroom);
      }
      if (rise > request.maximumFloorRiseM) {
        blocked = true;
        reject(PassageClearanceReason.floorRise);
      }
      if (drop > request.maximumFloorDropM) {
        blocked = true;
        reject(PassageClearanceReason.floorDrop);
      }
    }
    covering.sort((a, b) => a.forwardStartM.compareTo(b.forwardStartM));
    var coveredUntil = request.forwardStartM;
    for (final section in covering) {
      if (section.forwardStartM > coveredUntil) break;
      coveredUntil = math.max(coveredUntil, section.forwardEndM);
    }
    if (coveredUntil < request.forwardEndM) {
      reject(PassageClearanceReason.coverageGap);
    }
    return PassageClearanceResult._(
      status: blocked
          ? PassageClearanceStatus.blocked
          : reasons.isNotEmpty
          ? PassageClearanceStatus.unavailable
          : PassageClearanceStatus.measuredClear,
      reasons: reasons,
      request: request,
      context: context,
      minimumWidthLowerBoundM: minimumWidth,
      minimumHeadroomLowerBoundM: minimumHeadroom,
      minimumEvidenceConfidence: minimumConfidence,
      validUntilUs: oldest + policy.maximumAgeUs,
    );
  }
}

bool _positive(double value) => value.isFinite && value > 0;
bool _nonnegative(double value) => value.isFinite && value >= 0;
bool _probability(double value) => value.isFinite && value >= 0 && value <= 1;
