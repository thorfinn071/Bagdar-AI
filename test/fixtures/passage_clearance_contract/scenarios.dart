import 'package:bagdar/safety/perception/passage_clearance.dart';

// Declared metric intervals, not measurements from a phone or a depth model.
// These dimensions and thresholds are explicit software-fixture parameters.
const contractPolicy = PassageClearancePolicy(
  maximumAgeUs: 400000,
  maximumPairSkewUs: 50000,
  maximumProcessingLatencyUs: 100000,
  minimumConfidence: 0.9,
);
const contractContext = PassageEvaluationContext(
  nowUs: 1020000,
  timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
  sessionGeneration: 1,
  frameId: 1,
  rgbTimestampUs: 1000000,
  transformId: 'upright-fixture-v1',
);
const contractRequest = PassageClearanceRequest(
  referenceFrameId: 'walking-frame-fixture-v1',
  lateralCenterM: 0,
  widthM: 0.9,
  headroomM: 1.8,
  forwardStartM: 0,
  forwardEndM: 1.5,
  maximumFloorRiseM: 0.05,
  maximumFloorDropM: 0.05,
);

PassageCalibration fixtureCalibration({
  bool metricScaleValidated = true,
  bool alignmentValidated = true,
  bool floorReferenceValidated = true,
}) => PassageCalibration(
  id: 'synthetic-calibration-v1',
  providerId: 'synthetic-conservative-bounds',
  modelId: 'bounds-fixture-v1',
  modelHash: 'synthetic-bounds-hash-v1',
  preprocessId: 'bounds-fixture-preprocess-v1',
  referenceFrameId: 'walking-frame-fixture-v1',
  transformId: 'upright-fixture-v1',
  timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
  metricScaleValidated: metricScaleValidated,
  alignmentValidated: alignmentValidated,
  floorReferenceValidated: floorReferenceValidated,
);

PassageSection fixtureSection({
  double start = 0,
  double end = 1.5,
  PassageSectionState state = PassageSectionState.measured,
  double body = 1,
  double floor = 1,
  double confidence = 0.99,
  double? left = -0.7,
  double? right = 0.7,
  double? headroom = 2.2,
  double? rise = 0,
  double? drop = 0,
}) => PassageSection(
  forwardStartM: start,
  forwardEndM: end,
  state: state,
  bodyObservedFraction: body,
  floorObservedFraction: floor,
  confidence: confidence,
  leftBoundaryUpperM: left,
  rightBoundaryLowerM: right,
  headroomLowerBoundM: headroom,
  floorRiseUpperBoundM: rise,
  floorDropUpperBoundM: drop,
);

PassageClearanceObservation fixtureObservation({
  List<PassageSection>? sections,
  String provider = 'synthetic-conservative-bounds',
  String modelHash = 'synthetic-bounds-hash-v1',
  String calibrationId = 'synthetic-calibration-v1',
  String reference = 'walking-frame-fixture-v1',
  String depthTransform = 'upright-fixture-v1',
  PassageTimestampDomain domain =
      PassageTimestampDomain.elapsedRealtimeMicroseconds,
  PassageUnits units = PassageUnits.metricMeters,
  int session = 1,
  int frame = 1,
  int rgbUs = 1000000,
  int depthUs = 1000000,
  int producedUs = 1010000,
  bool healthy = true,
}) => PassageClearanceObservation(
  providerId: provider,
  modelId: 'bounds-fixture-v1',
  modelHash: modelHash,
  preprocessId: 'bounds-fixture-preprocess-v1',
  calibrationId: calibrationId,
  referenceFrameId: reference,
  rgbTransformId: 'upright-fixture-v1',
  depthTransformId: depthTransform,
  timestampDomain: domain,
  units: units,
  sessionGeneration: session,
  frameId: frame,
  rgbTimestampUs: rgbUs,
  depthTimestampUs: depthUs,
  producedAtUs: producedUs,
  providerHealthy: healthy,
  sections: sections ?? [fixtureSection()],
);

class PassageContractCase {
  final String id;
  final PassageClearanceObservation? observation;
  final PassageClearanceStatus expectedStatus;
  final List<PassageClearanceReason> expectedReasons;
  final PassageEvaluationContext context;
  final PassageCalibration? calibration;

  PassageContractCase({
    required this.id,
    required this.observation,
    required this.expectedStatus,
    this.expectedReasons = const [],
    this.context = contractContext,
    PassageCalibration? calibration,
    bool missingCalibration = false,
  }) : calibration = missingCalibration
           ? null
           : calibration ?? fixtureCalibration();

  PassageClearanceResult evaluate() =>
      const PassageClearanceEvaluator(policy: contractPolicy).evaluate(
        request: contractRequest,
        context: context,
        calibration: calibration,
        observation: observation,
      );
}

List<PassageContractCase> passageContractCases() {
  PassageContractCase unavailable(
    String id,
    PassageClearanceObservation? data,
    PassageClearanceReason reason, {
    PassageEvaluationContext context = contractContext,
    PassageCalibration? calibration,
    bool missingCalibration = false,
  }) => PassageContractCase(
    id: id,
    observation: data,
    expectedStatus: PassageClearanceStatus.unavailable,
    expectedReasons: [reason],
    context: context,
    calibration: calibration,
    missingCalibration: missingCalibration,
  );
  PassageContractCase blocked(
    String id,
    List<PassageSection> sections,
    PassageClearanceReason reason,
  ) => PassageContractCase(
    id: id,
    observation: fixtureObservation(sections: sections),
    expectedStatus: PassageClearanceStatus.blocked,
    expectedReasons: [reason],
  );
  return List.unmodifiable([
    PassageContractCase(
      id: 'wide-clear',
      observation: fixtureObservation(),
      expectedStatus: PassageClearanceStatus.measuredClear,
    ),
    PassageContractCase(
      id: 'unsorted-contiguous-intervals',
      observation: fixtureObservation(
        sections: [
          fixtureSection(start: 1, end: 1.5),
          fixtureSection(start: 0, end: 0.5),
          fixtureSection(start: 0.5, end: 1),
        ],
      ),
      expectedStatus: PassageClearanceStatus.measuredClear,
    ),
    PassageContractCase(
      id: 'exact-conservative-bounds',
      observation: fixtureObservation(
        sections: [
          fixtureSection(
            left: -0.45,
            right: 0.45,
            headroom: 1.8,
            rise: 0.05,
            drop: 0.05,
          ),
        ],
      ),
      expectedStatus: PassageClearanceStatus.measuredClear,
    ),
    blocked('width-bound-too-small', [
      fixtureSection(left: -0.4, right: 0.4),
    ], PassageClearanceReason.narrowPassage),
    blocked('wide-but-offset', [
      fixtureSection(left: 0.1, right: 1.5),
    ], PassageClearanceReason.corridorOutsideOpening),
    blocked('low-lintel', [
      fixtureSection(headroom: 1.6),
    ], PassageClearanceReason.insufficientHeadroom),
    blocked('raised-threshold', [
      fixtureSection(rise: 0.10),
    ], PassageClearanceReason.floorRise),
    blocked('floor-drop', [
      fixtureSection(drop: 0.10),
    ], PassageClearanceReason.floorDrop),
    blocked('interior-pole', [
      fixtureSection(state: PassageSectionState.blocked),
    ], PassageClearanceReason.blockedSection),
    blocked('blocked-overlap-cannot-be-hidden', [
      fixtureSection(),
      fixtureSection(start: 0.5, end: 0.6, state: PassageSectionState.blocked),
    ], PassageClearanceReason.blockedSection),
    unavailable(
      'unknown-interval',
      fixtureObservation(
        sections: [fixtureSection(state: PassageSectionState.unknown)],
      ),
      PassageClearanceReason.missingMeasurements,
    ),
    unavailable(
      'conflicting-bounds',
      fixtureObservation(
        sections: [fixtureSection(state: PassageSectionState.conflicting)],
      ),
      PassageClearanceReason.conflictingMeasurements,
    ),
    unavailable(
      'floor-only',
      fixtureObservation(sections: [fixtureSection(body: 0)]),
      PassageClearanceReason.unobservedBody,
    ),
    unavailable(
      'body-without-floor',
      fixtureObservation(sections: [fixtureSection(floor: 0)]),
      PassageClearanceReason.unobservedFloor,
    ),
    unavailable(
      'longitudinal-gap',
      fixtureObservation(
        sections: [fixtureSection(end: 0.7), fixtureSection(start: 0.8)],
      ),
      PassageClearanceReason.coverageGap,
    ),
    unavailable(
      'missing-headroom',
      fixtureObservation(sections: [fixtureSection(headroom: null)]),
      PassageClearanceReason.missingMeasurements,
    ),
    unavailable(
      'relative-map-cannot-be-metres',
      fixtureObservation(units: PassageUnits.relativeProximity),
      PassageClearanceReason.nonMetricMeasurements,
    ),
    unavailable(
      'stale',
      fixtureObservation(),
      PassageClearanceReason.staleObservation,
      context: const PassageEvaluationContext(
        nowUs: 1500000,
        timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
        sessionGeneration: 1,
        frameId: 1,
        rgbTimestampUs: 1000000,
        transformId: 'upright-fixture-v1',
      ),
    ),
    unavailable(
      'rgb-depth-skew',
      fixtureObservation(depthUs: 900000),
      PassageClearanceReason.pairSkew,
    ),
    unavailable(
      'future-result',
      fixtureObservation(producedUs: 1030000),
      PassageClearanceReason.futureObservation,
    ),
    unavailable(
      'processing-delay',
      fixtureObservation(producedUs: 1120000),
      PassageClearanceReason.processingLatency,
      context: const PassageEvaluationContext(
        nowUs: 1200000,
        timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
        sessionGeneration: 1,
        frameId: 1,
        rgbTimestampUs: 1000000,
        transformId: 'upright-fixture-v1',
      ),
    ),
    unavailable(
      'different-clock',
      fixtureObservation(domain: PassageTimestampDomain.utcEpochMicroseconds),
      PassageClearanceReason.clockMismatch,
    ),
    unavailable(
      'previous-session',
      fixtureObservation(session: 0),
      PassageClearanceReason.sessionMismatch,
    ),
    unavailable(
      'wrong-frame',
      fixtureObservation(frame: 2),
      PassageClearanceReason.frameMismatch,
    ),
    unavailable(
      'wrong-rgb-timestamp',
      fixtureObservation(rgbUs: 1000001),
      PassageClearanceReason.frameMismatch,
    ),
    unavailable(
      'different-transform',
      fixtureObservation(depthTransform: 'other-transform'),
      PassageClearanceReason.transformMismatch,
    ),
    unavailable(
      'different-reference-frame',
      fixtureObservation(reference: 'other-reference'),
      PassageClearanceReason.referenceFrameMismatch,
    ),
    unavailable(
      'foreign-provider',
      fixtureObservation(provider: 'other-provider'),
      PassageClearanceReason.calibrationMismatch,
    ),
    unavailable(
      'changed-model',
      fixtureObservation(modelHash: 'new-model-hash'),
      PassageClearanceReason.modelMismatch,
    ),
    unavailable(
      'missing-calibration',
      fixtureObservation(),
      PassageClearanceReason.missingCalibration,
      missingCalibration: true,
    ),
    unavailable(
      'unverified-scale',
      fixtureObservation(),
      PassageClearanceReason.unverifiedCalibration,
      calibration: fixtureCalibration(metricScaleValidated: false),
    ),
    unavailable(
      'unverified-alignment',
      fixtureObservation(),
      PassageClearanceReason.unverifiedCalibration,
      calibration: fixtureCalibration(alignmentValidated: false),
    ),
    unavailable(
      'unverified-floor-reference',
      fixtureObservation(),
      PassageClearanceReason.unverifiedCalibration,
      calibration: fixtureCalibration(floorReferenceValidated: false),
    ),
    unavailable(
      'unhealthy-provider',
      fixtureObservation(healthy: false),
      PassageClearanceReason.providerUnhealthy,
    ),
    unavailable(
      'empty-sections',
      fixtureObservation(sections: []),
      PassageClearanceReason.missingSections,
    ),
    unavailable(
      'reversed-interval',
      fixtureObservation(sections: [fixtureSection(start: 1, end: 0)]),
      PassageClearanceReason.invalidSection,
    ),
    unavailable(
      'insufficient-confidence',
      fixtureObservation(sections: [fixtureSection(confidence: 0.1)]),
      PassageClearanceReason.insufficientConfidence,
    ),
    unavailable(
      'nonfinite-headroom',
      fixtureObservation(sections: [fixtureSection(headroom: double.nan)]),
      PassageClearanceReason.invalidSection,
    ),
    unavailable(
      'negative-floor-bound',
      fixtureObservation(sections: [fixtureSection(drop: -0.1)]),
      PassageClearanceReason.invalidSection,
    ),
    unavailable(
      'too-many-sections',
      fixtureObservation(sections: List.generate(129, (_) => fixtureSection())),
      PassageClearanceReason.tooManySections,
    ),
    unavailable(
      'missing-observation',
      null,
      PassageClearanceReason.missingObservation,
    ),
    unavailable(
      'empty-identity',
      fixtureObservation(calibrationId: ''),
      PassageClearanceReason.invalidIdentity,
    ),
    unavailable(
      'negative-depth-timestamp',
      fixtureObservation(depthUs: -1),
      PassageClearanceReason.invalidTimestamp,
    ),
    unavailable(
      'result-before-capture',
      fixtureObservation(producedUs: 990000),
      PassageClearanceReason.invalidTimestamp,
    ),
  ]);
}
