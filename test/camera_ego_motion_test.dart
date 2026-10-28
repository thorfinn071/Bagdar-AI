import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/camera_ego_motion.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'camera_fast_motion_test.dart' as fast;
import 'camera_scale_metric_motion_contract_test.dart' as fixture;

const poseContract = WalkingPoseContract(
  providerId: 'pose',
  revision: 'v1',
  localReferenceFrameId: 'walking',
  worldReferenceFrameId: 'world',
);
CameraEgoMotionSource source() => CameraEgoMotionSource(
  poseContract: poseContract,
  localCalibration: fixture.calibration,
  rgbContract: fast.rgbContract,
);
WalkingOriginPose pose(
  FastMetricMotionInput input, {
  List<double> origin = const [0, 0, 0],
  String provider = 'pose',
  String revision = 'v1',
  String local = 'walking',
  String world = 'world',
  int frameDelta = 0,
  int captureDelta = 0,
  int sessionDelta = 0,
  int producedDelta = 1000,
  double error = .0001,
  double confidence = 1,
  bool healthy = true,
  bool fixedHeading = true,
}) => WalkingOriginPose(
  providerId: provider,
  revision: revision,
  localReferenceFrameId: local,
  worldReferenceFrameId: world,
  frameId: input.camera.depth.frameId + frameDelta,
  capturedAtUs: input.camera.depth.capturedAtUs + captureDelta,
  sessionGeneration: input.camera.depth.sessionGeneration + sessionDelta,
  producedAtUs: input.camera.depth.capturedAtUs + producedDelta,
  originWorldM: origin,
  positionErrorM: error,
  confidence: confidence,
  healthy: healthy,
  fixedHeading: fixedHeading,
);
EgoMotionEvidence observe(
  CameraEgoMotionSource s,
  FastMetricMotionInput input, {
  WalkingOriginPose? walkingPose,
  int age = 2000,
}) => s.observe(
  input,
  pose: walkingPose ?? pose(input),
  nowUs: input.camera.depth.capturedAtUs + age,
);

void main() {
  test('static wall in world remains approaching when the user advances', () {
    final s = source(), a = fast.capture(fixture.input(1));
    observe(s, a);
    final b = fast.capture(fixture.input(2, axis: 2.4));
    final r = observe(s, b, walkingPose: pose(b, origin: [0, .1, 0]));
    expect(r.worldMotion.available, true);
    expect(
      r.worldMotion.patches.where(
        (p) => p.classification == FastPatchClassification.approaching,
      ),
      isEmpty,
    );
    expect(r.bodyRelativeMotion.addsMotionRisk, true);
    expect(r.originVelocityLowerMps![1], closeTo(.499, 1e-9));
    expect(r.toDiagnosticMap()['relativeHypothesisResolved'], false);
  });
  for (final cameraMove in [0.0, .025]) {
    test(
      'true object approach retained with camera translation $cameraMove',
      () {
        final s = source(), a = fast.capture(fixture.input(1));
        observe(s, a);
        final b = fast.capture(fixture.input(2, axis: 2.4));
        final r = observe(
          s,
          b,
          walkingPose: pose(b, origin: [0, cameraMove, 0]),
        );
        expect(r.worldMotion.addsMotionRisk, true);
        expect(r.bodyRelativeMotion.addsMotionRisk, true);
        expect(r.toDiagnosticMap()['freeSpaceCertified'], false);
      },
    );
  }
  final invalidPoses =
      <String, WalkingOriginPose Function(FastMetricMotionInput)>{
        'provider': (i) => pose(i, provider: 'foreign'),
        'revision': (i) => pose(i, revision: 'v2'),
        'local frame': (i) => pose(i, local: 'foreign'),
        'world frame': (i) => pose(i, world: 'foreign'),
        'capture id': (i) => pose(i, frameDelta: 1),
        'timestamp': (i) => pose(i, captureDelta: 1),
        'session': (i) => pose(i, sessionDelta: 1),
        'future production': (i) => pose(i, producedDelta: 2001),
        'pre-capture production': (i) => pose(i, producedDelta: -1),
        'unhealthy': (i) => pose(i, healthy: false),
        'heading change': (i) => pose(i, fixedHeading: false),
        'low confidence': (i) => pose(i, confidence: .89),
        'nonfinite confidence': (i) => pose(i, confidence: double.nan),
        'excess confidence': (i) => pose(i, confidence: 1.1),
        'negative error': (i) => pose(i, error: -.01),
        'unbounded error': (i) => pose(i, error: .051),
        'nonfinite origin': (i) => pose(i, origin: [0, double.nan, 0]),
        'short origin': (i) => pose(i, origin: [0, 0]),
      };
  for (final entry in invalidPoses.entries) {
    test('rejects ${entry.key} and requires a fresh pair', () {
      final s = source(), a = fast.capture(fixture.input(1));
      observe(s, a);
      final b = fast.capture(fixture.input(2, axis: 2.2));
      final rejected = observe(s, b, walkingPose: entry.value(b));
      expect(rejected.poseAccepted, false);
      expect(rejected.bodyRelativeMotion.available, false);
      final c = fast.capture(fixture.input(3, axis: 2.0));
      expect(observe(s, c).reason, 'new_pair_required');
    });
  }
  test('missing pose and freshness fail closed', () {
    final s = source(), a = fast.capture(fixture.input(1));
    expect(s.observe(a, pose: null, nowUs: 1002000).poseAccepted, false);
    expect(observe(s, a, age: 100001).poseAccepted, false);
    expect(observe(s, a, age: -1).poseAccepted, false);
    expect(observe(s, a).reason, 'new_pair_required');
  });
  for (final fault in ['rgb', 'depth', 'units', 'identity']) {
    test('pose transformation cannot repair invalid $fault', () {
      final s = source(), a = fast.capture(fixture.input(1));
      observe(s, a);
      final b = fast.capture(
        fixture.input(
          2,
          mismatch: fault == 'rgb',
          missing: fault == 'depth',
          model: fault == 'identity' ? 'wrong' : 'metric-hash',
          units: fault == 'units'
              ? PassageUnits.relativeProximity
              : PassageUnits.metricMeters,
        ),
      );
      final r = observe(s, b);
      expect(r.bodyRelativeMotion.available, false);
      expect(r.bodyRelativeMotion.addsMotionRisk, false);
    });
  }
  test('results expire at original capture TTL without refreshing clocks', () {
    final s = source(), a = fast.capture(fixture.input(1));
    observe(s, a);
    final b = fast.capture(fixture.input(2, axis: 2.2));
    final r = observe(s, b);
    expect(r.bodyRelativeMotion.capturedAtUs, 1200000);
    expect(r.bodyRelativeMotion.oldestEvidenceTimestampUs, 1000000);
    expect(r.bodyRelativeMotion.validUntilUs, 1300000);
    expect(r.bodyRelativeMotion.isLiveAt(1300001), false);
    s.invalidate();
    expect(
      observe(s, fast.capture(fixture.input(3))).reason,
      'new_pair_required',
    );
  });
  test('lateral camera translation is separated from world motion', () {
    final s = source();
    observe(s, fast.capture(fixture.input(1)));
    final b = fast.capture(fixture.input(2, shift: -6));
    final r = observe(s, b, walkingPose: pose(b, origin: [.1875, 0, 0]));
    expect(r.worldMotion.available, true);
    expect(
      r.bodyRelativeMotion.patches.where(
        (p) => p.classification == FastPatchClassification.lateral,
      ),
      isNotEmpty,
    );
    expect(
      r.worldMotion.patches.where(
        (p) => p.classification == FastPatchClassification.lateral,
      ),
      isEmpty,
    );
  });
  test('combined position uncertainty is not silently clamped', () {
    final s = source();
    final b = fast.capture(fixture.input(1, positionError: .06));
    expect(observe(s, b, walkingPose: pose(b, error: .05)).poseAccepted, false);
  });
  test('a different camera or an old pair requires new evidence', () {
    final s = source();
    observe(s, fast.capture(fixture.input(1)));
    final b = fast.capture(fixture.input(2, cameraId: 'other'));
    expect(observe(s, b).bodyRelativeMotion.available, false);
    final c = fast.capture(fixture.input(5, cameraId: 'other'));
    expect(observe(s, c).bodyRelativeMotion.available, false);
  });
}
