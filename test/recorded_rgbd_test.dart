import 'dart:typed_data';

import 'package:bagdar/research/recorded_rgbd.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

const request = PassageClearanceRequest(
  referenceFrameId: 'walking',
  lateralCenterM: 0,
  widthM: .9,
  headroomM: 1.85,
  forwardStartM: .2,
  forwardEndM: 3.5,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);
const identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const placement = <double>[1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 1.42, 0, 0, 0, 1];
const policy = PassageClearancePolicy(
  maximumAgeUs: 100000,
  maximumPairSkewUs: 0,
  maximumProcessingLatencyUs: 100000,
  minimumConfidence: .99,
);

RecordedRgbdFrame frame({
  String session = 'capture-1',
  int id = 1,
  int stamp = 1230000,
  String tracking = 'normal',
  Float32List? depth,
  Uint8List? validity,
  Uint8List? confidence,
  List<double> pose = identity,
}) => RecordedRgbdFrame(
  recordingId: session,
  sourceIdentity: 'synthetic-contract-fixture',
  deviceModel: 'fixture',
  trackingState: tracking,
  frameId: id,
  sourceTimestampUs: stamp,
  width: 2,
  height: 2,
  rgbWidth: 2,
  rgbHeight: 2,
  axisDepthM: depth ?? Float32List.fromList([3, 3, 3, 3]),
  confidence: confidence ?? Uint8List.fromList([2, 2, 2, 2]),
  validity: validity ?? Uint8List.fromList([1, 1, 1, 1]),
  rgbIntrinsics: [2, 0, 0, 0, 2, 0, 1, 1, 1],
  cameraTransform: pose,
);

RecordedPassageEvidenceSource source(
  RecordedRgbdFrame f, {
  bool placed = false,
  int? produced,
}) {
  return RecordedPassageEvidenceSource(
    frame: f,
    clock: RecordedReplayClock(f.recordingId, f.sourceTimestampUs),
    profile: PhysicalEvidenceProfile(
      id: 'profile',
      recordingId: f.recordingId,
      diagnosticWorldToWalking: placed ? placement : null,
    ),
    request: request,
    producedAtUs: produced ?? RecordedReplayClock.anchorUs,
  );
}

PassageEvaluationContext context(
  RecordedPassageEvidenceSource s, {
  int age = 0,
  int? id,
}) => PassageEvaluationContext(
  nowUs: s.clock.timestamp(s.frame) + age,
  timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
  sessionGeneration: 1,
  frameId: id ?? s.frame.frameId,
  rgbTimestampUs: s.clock.timestamp(s.frame),
  transformId: s.transformId,
);

void main() {
  test('recorded arrays have owned immutable storage', () {
    final pixels = Float32List.fromList([1, 2, 3, 4]);
    final conf = Uint8List.fromList([2, 2, 2, 2]);
    final f = frame(depth: pixels, confidence: conf);
    pixels[0] = 8;
    conf[0] = 0;
    expect(f.axisDepthM[0], 1);
    expect(f.confidence[0], 2);
    expect(() => f.axisDepthM[0] = 5, throwsUnsupportedError);
    expect(() => f.confidence[0] = 0, throwsUnsupportedError);
  });

  test('NaN and zero are preserved, never filled', () {
    final f = frame(
      depth: Float32List.fromList([double.nan, 0, -1, 3]),
      validity: Uint8List.fromList([0, 0, 0, 1]),
    );
    expect(f.axisDepthM[0].isNaN, true);
    expect(f.isHighConfidence(0), false);
    expect(f.isHighConfidence(1), false);
    expect(f.isHighConfidence(3), true);
    expect(
      () => frame(depth: Float32List.fromList([double.nan, 0, -1, 3])),
      throwsFormatException,
    );
  });

  test('bad shape and unsupported confidence are rejected', () {
    expect(() => frame(depth: Float32List(3)), throwsFormatException);
    expect(
      () => frame(confidence: Uint8List.fromList([255, 2, 2, 2])),
      throwsFormatException,
    );
  });

  test('scaled and reflected poses are rejected', () {
    for (final value in [-1.0, 2.0]) {
      final pose = [...identity]..[0] = value;
      expect(() => frame(pose: pose), throwsFormatException);
    }
  });

  test('limited tracking and absent confidence cannot qualify samples', () {
    expect(frame(tracking: 'limited').hasSamples, false);
    expect(frame(confidence: Uint8List(0)).hasSamples, false);
  });

  test(
    'replay clock preserves native deltas without claiming native epoch',
    () {
      const c = RecordedReplayClock('capture-1', 1230000);
      expect(
        c.timestamp(frame(stamp: 1263333)),
        RecordedReplayClock.anchorUs + 33333,
      );
      expect(
        () => c.timestamp(frame(session: 'foreign')),
        throwsFormatException,
      );
      expect(() => c.timestamp(frame(stamp: 1229999)), throwsFormatException);
    },
  );

  test('foreign profile does not bind to frame', () {
    expect(
      () => RecordedPassageEvidenceSource(
        frame: frame(),
        clock: const RecordedReplayClock('capture-1', 1230000),
        profile: PhysicalEvidenceProfile(id: 'wrong', recordingId: 'foreign'),
        request: request,
        producedAtUs: 1000000,
      ),
      throwsFormatException,
    );
  });

  test('100ms boundary and future timestamps are diagnosed independently', () {
    final s = source(frame());
    expect(s.reasonsAt(1100000), isNot(contains('stale_frame')));
    expect(s.reasonsAt(1100001), contains('stale_frame'));
    expect(s.reasonsAt(999999), contains('future_frame'));
    expect(
      source(frame(), produced: 1000001).reasonsAt(1000000),
      contains('invalid_production_time'),
    );
  });

  test('high confidence centre points cannot generate whole-pixel proof', () {
    final s = source(frame());
    final c = context(s), o = s.observationFor(c);
    expect(o.providerHealthy, false);
    expect(o.sections.single.state, PassageSectionState.unknown);
    expect(o.sections.single.bodyObservedFraction, 0);
    expect(o.sections.single.floorObservedFraction, 0);
    final result = const PassageClearanceEvaluator(policy: policy).evaluate(
      request: request,
      context: c,
      calibration: s.calibration,
      observation: o,
    );
    expect(result.status, PassageClearanceStatus.unavailable);
    expect(
      result.reasons,
      contains(PassageClearanceReason.unverifiedCalibration),
    );
  });

  test('foreign frame cannot borrow a diagnostic observation', () {
    final s = source(frame());
    expect(s.observationFor(context(s, id: 2)).providerHealthy, false);
  });

  test('unknown floor, thin object and occluded returns stay unproved', () {
    for (final pixels in [
      [.4, 3.0, 3.0, 3.0],
      [0.0, 3.0, 3.0, 3.0],
      [3.0, 3.0, 3.0, 3.0],
    ]) {
      final s = source(
        frame(
          depth: Float32List.fromList(pixels),
          validity: Uint8List.fromList(
            pixels.map((v) => v > 0 ? 1 : 0).toList(),
          ),
        ),
      );
      expect(
        s.observationFor(context(s)).sections.single.state,
        PassageSectionState.unknown,
      );
      expect(s.frame.hasWholePixelBounds, false);
    }
  });

  test('placement is required before any body-frustum illustration', () {
    expect(source(frame()).geometryDiagnostics(1000000)['status'], 'not_run');
  });

  test('conditional placement exposes near blind zone without clearing it', () {
    final s = source(frame(), placed: true);
    final geometry = s.geometryDiagnostics(1000000);
    expect(geometry['status'], 'conditional_geometry_only');
    expect(geometry['entireRequestInView'], false);
    expect(geometry['nearGapM'] as double, greaterThan(0));
    expect(geometry['canAuthorizeMovement'], false);
    expect(geometry['canCertifyFreeSpace'], false);
    expect(s.calibration.floorReferenceValidated, false);
    expect(s.observationFor(context(s)).providerHealthy, false);
  });

  test('empirical error does not grant any physical capability', () {
    final p = PhysicalEvidenceProfile(
      id: 'empirical',
      recordingId: 'capture-1',
      empiricalSampleErrorM: .01,
    );
    expect(p.metricErrorBoundsValidated, false);
    expect(p.wholePixelBoundsValidated, false);
    expect(p.clockBindingValidated, false);
    expect(p.canAuthorizeMovement, false);
    expect(
      () => PhysicalEvidenceProfile(
        id: 'bad',
        recordingId: 'x',
        empiricalSampleErrorM: double.nan,
      ),
      throwsFormatException,
    );
  });
}
