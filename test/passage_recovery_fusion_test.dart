import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/passage_clearance_contract/scenarios.dart';

final _origin = DateTime.utc(2026, 10, 2);
const _request = PassageClearanceRequest(
  referenceFrameId: 'walking-frame-fixture-v1',
  lateralCenterM: 0,
  widthM: .9,
  headroomM: 1.8,
  forwardStartM: .2,
  forwardEndM: 3.5,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);

PassageEvaluationContext _context(
  DateTime at, {
  int frame = 2,
  int session = 1,
  String transform = 'upright-fixture-v1',
}) => PassageEvaluationContext(
  nowUs: at.microsecondsSinceEpoch,
  rgbTimestampUs: at.microsecondsSinceEpoch,
  timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
  sessionGeneration: session,
  frameId: frame,
  transformId: transform,
);

PassageClearanceResult _certificate(
  DateTime at, {
  PassageClearanceRequest request = _request,
}) => const PassageClearanceEvaluator(policy: contractPolicy).evaluate(
  request: request,
  context: _context(at),
  calibration: fixtureCalibration(),
  observation: fixtureObservation(
    frame: 2,
    rgbUs: at.microsecondsSinceEpoch,
    depthUs: at.microsecondsSinceEpoch,
    producedUs: at.microsecondsSinceEpoch,
    sections: [
      fixtureSection(start: request.forwardStartM, end: request.forwardEndM),
    ],
  ),
);

SpatialEvidence _gap(
  DateTime at, {
  String? scope = 'same-volume',
  double occupancy = 0,
  double drop = 0,
  double moving = 0,
}) => SpatialEvidence(
  elementId: 'forward',
  coordinateMode: SceneCoordinateMode.relative,
  sourceId: 'initial-gap',
  source: SpatialEvidenceSource.depth,
  observedAt: at,
  validUntil: at.add(const Duration(seconds: 1)),
  observedFraction: 0,
  confidence: 1,
  unknownProbability: 1,
  unknownScopeId: scope,
  occupancyProbability: occupancy,
  dropProbability: drop,
  movingThreatRisk: moving,
);

SpatialEvidence _clear(
  DateTime at, {
  PassageClearanceResult? certificate,
  PassageEvaluationContext? context,
  String scope = 'same-volume',
  bool full = true,
}) => SpatialEvidence(
  elementId: 'forward',
  coordinateMode: SceneCoordinateMode.relative,
  sourceId: 'full-visible-depth',
  source: SpatialEvidenceSource.depth,
  observedAt: at,
  validUntil: at.add(const Duration(milliseconds: 400)),
  observedFraction: full ? 1 : .99,
  confidence: 1,
  unknownProbability: full ? 0 : .01,
  traversabilityProbability: 1,
  unknownScopeId: scope,
  coverageResolution: certificate ?? _certificate(at),
  passageContext: context ?? _context(at),
);

FusedSceneElement _fuse(
  DateTime now,
  List<SpatialEvidence> input, {
  FusedSceneElement? previous,
  SceneFusionPolicy policy = const SceneFusionPolicy(),
}) => policy.fuse(
  elementId: 'forward',
  coordinateMode: SceneCoordinateMode.relative,
  previous: previous,
  evidence: input,
  now: now,
  useIndependentEvidenceClocks: true,
)!;

void main() {
  test('full later certificate resolves only earlier scoped coverage', () {
    final initial = _fuse(_origin, [_gap(_origin)]);
    final at = _origin.add(const Duration(milliseconds: 300));
    final result = _fuse(at, [_clear(at)], previous: initial);
    expect(result.element.unknownProbability, 0);
    expect(result.element.traversabilityProbability, 1);
    expect(result.contributions, hasLength(1));
  });
  for (final scope in [
    null,
    'other-provider',
    'other-session',
    'other-transform',
    'other-volume',
  ]) {
    test('certificate cannot retire unrelated coverage $scope', () {
      final initial = _fuse(_origin, [_gap(_origin, scope: scope)]);
      final at = _origin.add(const Duration(milliseconds: 300));
      expect(
        _fuse(at, [_clear(at)], previous: initial).element.unknownProbability,
        1,
      );
    });
  }
  for (final risk in ['occupancy', 'drop', 'moving']) {
    test('certificate retains $risk and associated uncertainty', () {
      final initial = _fuse(_origin, [
        _gap(
          _origin,
          occupancy: risk == 'occupancy' ? .9 : 0,
          drop: risk == 'drop' ? .9 : 0,
          moving: risk == 'moving' ? .9 : 0,
        ),
      ]);
      final at = _origin.add(const Duration(milliseconds: 300));
      final result = _fuse(at, [_clear(at)], previous: initial);
      expect(result.element.unknownProbability, 1);
      expect([
        result.element.occupancyProbability,
        result.element.dropProbability,
        result.element.movingThreatRisk,
      ], contains(.9));
    });
  }
  for (final fault in [
    'frame',
    'session',
    'transform',
    'expired',
    'partial',
    'short-range',
  ]) {
    test('invalid certificate $fault cannot clear history', () {
      final initial = _fuse(_origin, [_gap(_origin)]);
      final at = _origin.add(const Duration(milliseconds: 500));
      final context = _context(
        at,
        frame: fault == 'frame' ? 3 : 2,
        session: fault == 'session' ? 2 : 1,
        transform: fault == 'transform' ? 'wrong' : 'upright-fixture-v1',
      );
      final proof = fault == 'expired'
          ? _certificate(_origin)
          : _certificate(
              at,
              request: fault == 'short-range' ? contractRequest : _request,
            );
      if (fault == 'short-range') {
        expect(proof.status, PassageClearanceStatus.measuredClear);
      }
      final result = _fuse(at, [
        _clear(
          at,
          certificate: proof,
          context: context,
          full: fault != 'partial',
        ),
      ], previous: initial);
      expect(result.element.unknownProbability, 1);
    });
  }
  test('same-frame unknown and fresh conflict survive certificate', () {
    final result = _fuse(_origin, [
      _clear(_origin),
      _gap(_origin, occupancy: .9),
    ]);
    expect(result.element.unknownProbability, 1);
    expect(result.element.occupancyProbability, .9);
  });
  test('fresh unrelated evidence does not renew prior obstacle clock', () {
    var result = _fuse(_origin, [_gap(_origin, occupancy: .9)]);
    for (final milliseconds in [300, 900, 1500, 2100]) {
      final at = _origin.add(Duration(milliseconds: milliseconds));
      result = _fuse(at, [_clear(at)], previous: result);
    }
    expect(result.element.occupancyProbability, closeTo(.135, 1e-9));
    final at = _origin.add(const Duration(milliseconds: 2401));
    expect(
      _fuse(at, [_clear(at)], previous: result).element.occupancyProbability,
      0,
    );
  });
  test('expired positive depth loses authority despite fresh geometry', () {
    final initial = _fuse(_origin, [_clear(_origin)]);
    final at = _origin.add(const Duration(milliseconds: 401));
    final current = SpatialEvidence(
      elementId: 'forward',
      coordinateMode: SceneCoordinateMode.relative,
      sourceId: 'fresh-geometry',
      source: SpatialEvidenceSource.geometry,
      observedAt: at,
      validUntil: at.add(const Duration(milliseconds: 400)),
      observedFraction: .2,
      confidence: 1,
    );
    final result = _fuse(at, [current], previous: initial);
    expect(result.element.traversabilityProbability, 0);
    expect(result.element.unknownProbability, .8);
  });
  test('bounded contribution overflow stops conservatively', () {
    const policy = SceneFusionPolicy(maximumContributions: 2);
    final result = _fuse(_origin, [
      _clear(_origin),
      _gap(_origin),
      _gap(_origin),
    ], policy: policy);
    expect(result.contributions, hasLength(1));
    expect(result.element.unknownProbability, 1);
    expect(result.element.occupancyProbability, 1);
    expect(result.element.dropProbability, 1);
    expect(result.element.movingThreatRisk, 1);
  });
}
