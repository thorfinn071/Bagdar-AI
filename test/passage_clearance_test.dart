import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'fixtures/passage_clearance_contract/scenarios.dart';

PassageClearanceRequest _request({
  double width = 0.9,
  double height = 1.8,
  double center = 0,
  double end = 1.5,
  double rise = 0.05,
}) => PassageClearanceRequest(
  referenceFrameId: contractRequest.referenceFrameId,
  lateralCenterM: center,
  widthM: width,
  headroomM: height,
  forwardStartM: 0,
  forwardEndM: end,
  maximumFloorRiseM: rise,
  maximumFloorDropM: 0.05,
);

PassageEvaluationContext _context({
  int now = 1020000,
  int session = 1,
  int frame = 1,
  int rgb = 1000000,
  String transform = 'upright-fixture-v1',
  PassageTimestampDomain domain =
      PassageTimestampDomain.elapsedRealtimeMicroseconds,
}) => PassageEvaluationContext(
  nowUs: now,
  timestampDomain: domain,
  sessionGeneration: session,
  frameId: frame,
  rgbTimestampUs: rgb,
  transformId: transform,
);

PassageClearanceResult _evaluate({
  PassageClearanceRequest request = contractRequest,
  PassageEvaluationContext context = contractContext,
  PassageClearancePolicy policy = contractPolicy,
  PassageClearanceObservation? observation,
}) => PassageClearanceEvaluator(policy: policy).evaluate(
  request: request,
  context: context,
  calibration: fixtureCalibration(),
  observation: observation ?? fixtureObservation(),
);

void main() {
  for (final scenario in passageContractCases()) {
    test('passage contract: ${scenario.id}', () {
      final result = scenario.evaluate();
      expect(result.status, scenario.expectedStatus);
      expect(result.reasons, containsAll(scenario.expectedReasons));
      if (result.status == PassageClearanceStatus.measuredClear) {
        expect(result.reasons, isEmpty);
        expect(
          result.appliesTo(request: contractRequest, context: scenario.context),
          isTrue,
        );
      } else {
        expect(
          result.appliesTo(request: contractRequest, context: scenario.context),
          isFalse,
        );
      }
    });
  }

  test('a blocker exactly at the requested endpoint is not ignored', () {
    final result = _evaluate(
      observation: fixtureObservation(
        sections: [
          fixtureSection(),
          fixtureSection(
            start: 1.5,
            end: 1.6,
            state: PassageSectionState.blocked,
          ),
        ],
      ),
    );
    expect(result.status, PassageClearanceStatus.blocked);
    expect(result.reasons, contains(PassageClearanceReason.blockedSection));
  });

  test('overlapping sections use worst bounds rather than mean clearance', () {
    final result = _evaluate(
      observation: fixtureObservation(
        sections: [
          fixtureSection(),
          fixtureSection(
            start: 0.5,
            end: 0.7,
            left: -0.5,
            right: 0.5,
            headroom: 2,
          ),
        ],
      ),
    );
    expect(result.status, PassageClearanceStatus.measuredClear);
    expect(result.minimumWidthLowerBoundM, 1);
    expect(result.minimumHeadroomLowerBoundM, 2);
  });

  test('a very small longitudinal hole is still unknown', () {
    final result = _evaluate(
      observation: fixtureObservation(
        sections: [
          fixtureSection(end: 0.7),
          fixtureSection(start: 0.7 + 1e-12),
        ],
      ),
    );
    expect(result.status, PassageClearanceStatus.unavailable);
    expect(result.reasons, contains(PassageClearanceReason.coverageGap));
  });

  test('larger requested width or headroom cannot improve admission', () {
    for (final request in [_request(width: 1.5), _request(height: 2.3)]) {
      expect(
        _evaluate(request: request).status,
        PassageClearanceStatus.blocked,
      );
    }
  });

  test('freshness uses the older RGB/depth timestamp and expires', () {
    final result = _evaluate(observation: fixtureObservation(depthUs: 999000));
    expect(result.status, PassageClearanceStatus.measuredClear);
    expect(result.validUntilUs, 1399000);
    expect(
      result.appliesTo(
        request: contractRequest,
        context: _context(now: 1399000),
      ),
      isTrue,
    );
    expect(
      result.appliesTo(
        request: contractRequest,
        context: _context(now: 1399001),
      ),
      isFalse,
    );
  });

  test(
    'a clear result cannot be reused for another frame, session or request',
    () {
      final result = _evaluate();
      for (final context in [
        _context(frame: 2),
        _context(session: 2),
        _context(rgb: 1000001),
        _context(transform: 'other-transform'),
        _context(now: 1019999),
        _context(domain: PassageTimestampDomain.utcEpochMicroseconds),
      ]) {
        expect(
          result.appliesTo(request: contractRequest, context: context),
          isFalse,
        );
      }
      for (final request in [
        _request(width: 1),
        _request(height: 2),
        _request(center: 0.1),
        _request(end: 2),
        _request(rise: 0.1),
      ]) {
        expect(
          result.appliesTo(request: request, context: contractContext),
          isFalse,
        );
      }
    },
  );

  test('bad policy, request and context are unavailable without throwing', () {
    final badPolicy = _evaluate(
      policy: const PassageClearancePolicy(
        maximumAgeUs: 400000,
        maximumPairSkewUs: 50000,
        maximumProcessingLatencyUs: 100000,
        minimumConfidence: 0,
      ),
    );
    expect(badPolicy.status, PassageClearanceStatus.unavailable);
    expect(badPolicy.reasons, contains(PassageClearanceReason.invalidPolicy));
    for (final request in [
      _request(width: -1),
      _request(height: double.infinity),
      _request(center: double.nan),
      _request(end: 0),
      _request(rise: -1),
    ]) {
      final result = _evaluate(request: request);
      expect(result.status, PassageClearanceStatus.unavailable);
      expect(result.reasons, contains(PassageClearanceReason.invalidRequest));
    }
    final badContext = _evaluate(context: _context(now: -1));
    expect(badContext.reasons, contains(PassageClearanceReason.invalidContext));
  });

  test('nonfinite, inverted and impossible bounds never admit a passage', () {
    for (final section in [
      fixtureSection(body: 1.1),
      fixtureSection(floor: double.nan),
      fixtureSection(confidence: double.infinity),
      fixtureSection(left: 1, right: -1),
      fixtureSection(left: -1e308, right: 1e308),
      fixtureSection(rise: double.nan),
    ]) {
      final result = _evaluate(
        observation: fixtureObservation(sections: [section]),
      );
      expect(result.status, PassageClearanceStatus.unavailable);
      expect(result.reasons, contains(PassageClearanceReason.invalidSection));
    }
  });

  test(
    'an observation snapshots its sections and exposes immutable evidence',
    () {
      final mutable = [fixtureSection()];
      final observation = fixtureObservation(sections: mutable);
      mutable[0] = fixtureSection(state: PassageSectionState.blocked);
      final result = _evaluate(observation: observation);
      expect(result.status, PassageClearanceStatus.measuredClear);
      expect(() => observation.sections.clear(), throwsUnsupportedError);
      expect(
        () => result.reasons.add(PassageClearanceReason.blockedSection),
        throwsUnsupportedError,
      );
    },
  );
}
