import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/camera_track_motion_coverage.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'camera_scale_metric_motion_contract_test.dart' as fixture;
import 'camera_fast_motion_test.dart' as fast;

CameraComponentSupport support(int stamp, {List<int>? indices}) =>
    CameraComponentSupport(
      width: 256,
      height: 256,
      cropTopFraction: 0,
      capturedAtUs: stamp,
      indices: indices ?? [128 * 256 + 128],
    );

FastPatchMotion patch(
  int x,
  int y, {
  int? toX,
  bool moving = false,
  bool crossing = false,
}) => FastPatchMotion(
  previousPixel: [x, y],
  currentPixel: [toX ?? x, y],
  positionLowerM: [-.1, 2.4, 1.3],
  positionUpperM: [.1, 2.6, 1.5],
  velocityLowerMps: [crossing ? 1 : 0, moving ? -1 : -.1, 0],
  velocityUpperMps: [crossing ? 1.2 : 0, moving ? -.8 : .1, 0],
  classification: crossing
      ? FastPatchClassification.lateral
      : moving
      ? FastPatchClassification.approaching
      : FastPatchClassification.consistentWithStationary,
  possibleBodyIntersection: true,
);

FastMetricMotionResult result({
  List<FastPatchMotion>? patches,
  int frame = 2,
  int stamp = 1200000,
  int oldest = 1000000,
  int until = 1300000,
  String reason = 'visible_patch_intervals',
}) => FastMetricMotionResult(
  reason: reason,
  sessionGeneration: 1,
  frameId: frame,
  capturedAtUs: stamp,
  oldestEvidenceTimestampUs: oldest,
  validUntilUs: until,
  transformId: 'optical',
  candidates: 16,
  unknownPatches: 0,
  patches: patches ?? [patch(48, 32)],
);

CameraTrackMotionCoverage evaluate({
  FastMetricMotionInput? current,
  FastMetricMotionInput? previous,
  FastMetricMotionResult? motion,
  CameraComponentSupport? after,
  CameraComponentSupport? before,
  int currentCount = 1,
  int previousId = 7,
  bool observed = true,
  int now = 1202000,
}) => CameraTrackMotionCoverage.evaluate(
  trackId: 7,
  previousTrackId: previousId,
  currentlyObserved: observed,
  previouslyObserved: true,
  currentSupport: after ?? support(1200000),
  previousSupport: before ?? support(1000000),
  currentPixelCount: currentCount,
  previousPixelCount: 1,
  current: current ?? fast.capture(fixture.input(2)),
  previous: previous ?? fast.capture(fixture.input(1)),
  motion: motion ?? result(),
  calibration: fixture.calibration,
  rgbContract: fast.rgbContract,
  nowUs: now,
);

void noAuthority(CameraTrackMotionCoverage r) {
  for (final key in [
    'wholeObjectStationarityCertified',
    'mayResolveMotionPriority',
    'freeSpaceCertified',
  ]) {
    expect(r.toDiagnosticMap()[key], false, reason: key);
  }
}

void main() {
  test('crossing measurement remains positive local evidence', () {
    final r = evaluate(
      motion: result(patches: [patch(48, 32, crossing: true)]),
    );
    expect(r.available, true);
    expect(r.localMovingCentres, 1);
    noAuthority(r);
  });
  test('invalid RGB bytes cannot be used to cover a track', () {
    final c = fast.capture(fixture.input(2));
    final bad = FastMetricMotionInput(
      camera: c.camera,
      rgb: [-1, ...c.rgb.skip(1)],
      positionErrorM: c.positionErrorM,
      angularErrorRad: c.angularErrorRad,
    );
    expect(evaluate(current: bad).available, false);
  });
  test('out of image or unbounded correspondence cannot be counted', () {
    final malformed = FastPatchMotion(
      previousPixel: [48, 32],
      currentPixel: [48, 32],
      positionLowerM: [0, double.nan, 1],
      positionUpperM: [1, 3, 2],
      velocityLowerMps: [0, 0, 0],
      velocityUpperMps: [0, 0, 0],
      classification: FastPatchClassification.consistentWithStationary,
      possibleBodyIntersection: true,
    );
    for (final p in [patch(-1, 32), patch(96, 32), patch(0, 0), malformed]) {
      expect(evaluate(motion: result(patches: [p])).available, false);
    }
  });
  test('sparse centre is not dense registration or photometric support', () {
    final r = evaluate();
    expect(r.available, true);
    expect(r.currentPixels, 4);
    expect(r.currentMatched, 1);
    expect(r.toDiagnosticMap()['currentCoverage'], .25);
    expect(r.completeVisibleSupport, false);
    noAuthority(r);
  });
  test(
    'complete visible coverage still cannot clear whole object priority',
    () {
      final r = evaluate(
        motion: result(
          patches: [
            for (final y in [31, 32])
              for (final x in [47, 48]) patch(x, y),
          ],
        ),
      );
      expect(r.completeVisibleSupport, true);
      noAuthority(r);
    },
  );
  test('approaching measurement remains positive local evidence', () {
    final r = evaluate(motion: result(patches: [patch(48, 32, moving: true)]));
    expect(r.localMovingCentres, 1);
    expect(r.completeVisibleSupport, false);
    noAuthority(r);
  });
  test('background or one-sided membership never covers a track', () {
    for (final p in [patch(10, 10), patch(48, 32, toX: 49)]) {
      final r = evaluate(motion: result(patches: [p]));
      expect(r.available, true);
      expect(r.currentMatched, 0);
      noAuthority(r);
    }
  });
  test(
    'duplicate destinations or sources invalidate the correspondence set',
    () {
      for (final ps in [
        [patch(48, 32), patch(48, 32, toX: 47)],
        [patch(48, 32), patch(47, 32, toX: 48)],
      ]) {
        expect(evaluate(motion: result(patches: ps)).available, false);
      }
    },
  );
  test(
    'missing, retimed, duplicate and partial component support fail closed',
    () {
      for (final s in [
        support(1200001),
        support(1200000, indices: []),
        support(1200000, indices: [32896, 32896]),
        support(1200000, indices: [-1]),
      ]) {
        expect(evaluate(after: s).available, false);
      }
      expect(evaluate(currentCount: 2).available, false);
      expect(evaluate(observed: false).available, false);
      expect(evaluate(previousId: 8).available, false);
    },
  );
  test('empty motion and foreign result identities fail closed', () {
    for (final r in [
      result(patches: []),
      result(frame: 3),
      result(stamp: 1200001),
      result(oldest: 1000001),
      result(until: 1300001),
      result(reason: 'unknown'),
    ]) {
      expect(evaluate(motion: r).available, false);
    }
  });
  test('freshness is never extended or shifted for the support admission', () {
    expect(evaluate(now: 1300000).available, true);
    expect(evaluate(now: 1300001).available, false);
    expect(evaluate(now: 1199999).available, false);
    expect(
      evaluate(
        previous: fast.capture(fixture.input(1, timestamp: 800000)),
      ).available,
      false,
    );
  });
  test(
    'valid previous production delay is judged at its own original time',
    () {
      final p = fast.capture(fixture.input(1), producedDelta: 30000);
      expect(evaluate(previous: p).available, true);
      expect(
        evaluate(
          previous: fast.capture(fixture.input(1), producedDelta: 100000),
        ).available,
        false,
      );
    },
  );
  final faults = <String, FastMetricMotionInput Function()>{
    'relative units': () =>
        fast.capture(fixture.input(2, units: PassageUnits.relativeProximity)),
    'missing depth': () => fast.capture(fixture.input(2, missing: true)),
    'unbounded surface': () => fast.capture(fixture.input(2, unbounded: true)),
    'contradictory bounds': () =>
        fast.capture(fixture.input(2, conflict: true)),
    'bad pose': () => fast.capture(fixture.input(2, distortedPose: true)),
    'low pose quality': () => fast.capture(fixture.input(2, pose: .89)),
    'projection mismatch': () => fast.capture(fixture.input(2, mismatch: true)),
    'foreign model': () => fast.capture(fixture.input(2, model: 'foreign')),
    'foreign transform': () =>
        fast.capture(fixture.input(2, transform: 'other')),
    'foreign session': () => fast.capture(fixture.input(2, session: 2)),
    'foreign camera': () => fast.capture(fixture.input(2, cameraId: 'two')),
    'RGB timestamp mismatch': () =>
        fast.capture(fixture.input(2, rgbTimestampDelta: 1)),
    'RGB frame mismatch': () =>
        fast.capture(fixture.input(2, rgbFrameDelta: 1)),
    'unhealthy RGB': () => fast.capture(fixture.input(2), healthy: false),
    'foreign RGB provider': () =>
        fast.capture(fixture.input(2), provider: 'bad'),
    'future production': () =>
        fast.capture(fixture.input(2), producedDelta: 2000),
  };
  for (final e in faults.entries) {
    test('${e.key} cannot admit a stationary result', () {
      final r = evaluate(current: e.value());
      expect(r.available, false);
      noAuthority(r);
    });
  }
}
