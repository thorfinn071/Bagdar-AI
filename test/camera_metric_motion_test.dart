import 'dart:math';

import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

const calibration = PassageCalibration(
  id: 'metric',
  providerId: 'depth',
  modelId: 'first-return',
  modelHash: 'metric-hash',
  preprocessId: 'visible',
  referenceFrameId: 'walking',
  transformId: 'optical',
  timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
  metricScaleValidated: true,
  alignmentValidated: true,
  floorReferenceValidated: true,
);
List<int> image({int shift = 0, bool plain = false, bool repeated = false}) {
  final random = Random(31),
      original = List.generate(96 * 64 * 3, (_) => random.nextInt(256));
  return [
    for (var y = 0; y < 64; y++)
      for (var x = 0; x < 96; x++)
        for (var c = 0; c < 3; c++)
          plain
              ? 127
              : repeated
              ? ((x + shift) % 4 < 2 ? 20 : 230)
              : original[(y * 96 + (x - shift) % 96) * 3 + c],
  ];
}

CameraMetricMotionInput input(
  int frame, {
  double axis = 2.5,
  double origin = 0,
  int shift = 0,
  bool plain = false,
  bool repeated = false,
  bool healthy = true,
  double pose = 1,
  bool missing = false,
  bool unbounded = false,
  bool conflict = false,
  String model = 'metric-hash',
  String transform = 'optical',
  String cameraId = 'one',
  String provider = 'ncnn',
  int session = 1,
  int? timestamp,
  double positionError = .0001,
  double angleError = 0,
  double depthError = 0,
  PassageUnits units = PassageUnits.metricMeters,
  bool mismatch = false,
}) {
  final stamp = timestamp ?? 1000000 + (frame - 1) * 200000;
  final rotation = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0],
      cameraOrigin = [origin, 0.0, 1.45];
  final depth = CameraVisibleDepthFrame(
    width: 96,
    height: 64,
    frameId: frame,
    capturedAtUs: stamp,
    sessionGeneration: session,
    fx: 80,
    fy: 80,
    cx: 48,
    cy: 32,
    errorM: depthError,
    poseQuality: pose,
    cameraId: cameraId,
    modelHash: model,
    transformId: transform,
    referenceFrameId: 'walking',
    units: units,
    providerHealthy: healthy,
    rotation: rotation,
    originM: cameraOrigin,
    rangeM: [
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 96; x++)
          axis *
              sqrt(1 + pow((x + .5 - 48) / 80, 2) + pow((y + .5 - 32) / 80, 2)),
    ],
    freeZLowerM: List.filled(96 * 64, conflict ? axis + 1 : axis),
    surfaceZUpperM: List.filled(96 * 64, unbounded ? double.nan : axis),
    valid: List.filled(96 * 64, !missing),
  );
  final header = ObservationHeader(
    providerId: provider,
    modelId: 'midas-small-ncnn',
    modelHash: 'relative',
    preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
    sessionGeneration: session,
    frameId: frame,
    sourceTimestampUs: stamp,
    producedAtUs: stamp + 1000,
    transformId: transform,
    confidence: 1,
    health: ObservationHealth.healthy,
  );
  return CameraMetricMotionInput(
    camera: CameraTrackAssociationInput(
      rgbHeader: header,
      depth: depth,
      imageGeometry: CameraTrackImageGeometry(
        cameraId: cameraId,
        width: 96,
        height: 64,
        fx: mismatch ? 81 : 80,
        fy: 80,
        cx: 48,
        cy: 32,
        rotation: rotation,
        originM: cameraOrigin,
      ),
    ),
    rgb: image(shift: shift, plain: plain, repeated: repeated),
    positionErrorM: positionError,
    angularErrorRad: angleError,
  );
}

CameraMetricMotionSource source() => CameraMetricMotionSource(
  calibration: calibration,
  relativeModelHash: 'relative',
);
CameraMetricMotionResult pair(
  CameraMetricMotionInput a,
  CameraMetricMotionInput b,
) {
  final s = source();
  s.observe(a, nowUs: a.camera.depth.capturedAtUs + 2000);
  return s.observe(b, nowUs: b.camera.depth.capturedAtUs + 2000);
}

void main() {
  test(
    'same RGB/depth admits local stationary intervals, never global absence/free space',
    () {
      final r = pair(input(1), input(2));
      expect(r.available, true);
      expect(r.patches.every((p) => !p.establishesMotion), true);
      expect(r.toDiagnosticMap()['absenceOfMotionCertified'], false);
      expect(r.toDiagnosticMap()['freeSpaceCertified'], false);
      expect(r.oldestEvidenceTimestampUs, 1000000);
      expect(r.isLiveAt(1300001), false);
    },
  );
  test('forward metric change yields approaching and receding intervals', () {
    expect(
      pair(
        input(1),
        input(2, axis: 2.3),
      ).patches.any((p) => p.classification == VisiblePatchMotion.approaching),
      true,
    );
    expect(
      pair(
        input(1),
        input(2, axis: 2.7),
      ).patches.any((p) => p.classification == VisiblePatchMotion.receding),
      true,
    );
  });
  test(
    'lateral textured displacement adds risk independent of relative proximity',
    () {
      final r = pair(input(1), input(2, shift: -6));
      expect(
        r.patches.any((p) => p.classification == VisiblePatchMotion.lateral),
        true,
      );
      expect(r.addsMotionRisk, true);
    },
  );
  test('camera translation is compensated in walking coordinates', () {
    final r = pair(input(1), input(2, shift: -4, origin: .125));
    expect(r.available, true);
    expect(r.patches.every((p) => !p.establishesMotion), true);
  });
  test(
    'plain and repeated patches are unavailable rather than zero motion',
    () {
      expect(
        pair(input(1, plain: true), input(2, plain: true)).available,
        false,
      );
      expect(
        pair(input(1, repeated: true), input(2, repeated: true)).available,
        false,
      );
    },
  );
  for (final entry in <String, CameraMetricMotionInput Function(int)>{
    'provider loss': (n) => input(n, healthy: false),
    'pose loss': (n) => input(n, pose: 0),
    'metric units': (n) => input(n, units: PassageUnits.relativeProximity),
    'projection mismatch': (n) => input(n, mismatch: true),
    'depth conflict': (n) => input(n, conflict: true),
    'depth holes': (n) => input(n, missing: true),
    'unbounded first surface': (n) => input(n, unbounded: true),
    'model mismatch': (n) => input(n, model: 'different'),
    'transform mismatch': (n) => input(n, transform: 'other'),
  }.entries) {
    test('${entry.key} invalidates motion authority', () {
      final r = pair(input(1), entry.value(2));
      expect(r.available, false);
      expect(r.addsMotionRisk, false);
    });
  }
  for (final entry in <String, CameraMetricMotionInput Function(int)>{
    'new session': (n) => input(n, session: 2),
    'provider change': (n) => input(n, provider: 'new'),
    'camera change': (n) => input(n, cameraId: 'two'),
    'pair expired': (n) => input(n, timestamp: 1400000),
    'out of order': (n) => input(n, timestamp: 999999),
  }.entries) {
    test('${entry.key} requires a new compatible pair', () {
      expect(
        pair(input(1), entry.value(2)).reason,
        'incompatible_pair_or_interval',
      );
    });
  }
  test(
    'stale and future frame remove accumulated evidence; recovery needs pair',
    () {
      final s = source();
      s.observe(input(1), nowUs: 1002000);
      expect(s.observe(input(2), nowUs: 1300001).available, false);
      expect(s.observe(input(3), nowUs: 1402000).reason, 'new_pair_required');
      expect(s.observe(input(4), nowUs: 1599999).available, false);
      expect(s.observe(input(5), nowUs: 1802000).reason, 'new_pair_required');
      s.invalidate();
      expect(s.observe(input(6), nowUs: 2002000).reason, 'new_pair_required');
    },
  );
  test(
    'pose error widens intervals rather than asserting stationary/moving',
    () {
      final r = pair(
        input(1, positionError: .06),
        input(2, positionError: .06),
      );
      expect(r.available, true);
      expect(
        r.patches.every(
          (p) => p.classification == VisiblePatchMotion.uncertain,
        ),
        true,
      );
    },
  );
  for (final error in [.005, .020]) {
    test(
      'declared ${error * 1000}mm depth noise stays within motion uncertainty',
      () {
        final r = pair(
          input(1, depthError: error),
          input(2, axis: 2.5 + error, depthError: error),
        );
        expect(r.available, true);
        expect(r.patches.every((p) => !p.establishesMotion), true);
      },
    );
  }
  test(
    'malformed RGB and missing alignment calibration invalidate the pair',
    () {
      final a = input(1);
      final bad = CameraMetricMotionInput(
        camera: a.camera,
        rgb: [],
        positionErrorM: 0,
        angularErrorRad: 0,
      );
      expect(source().observe(bad, nowUs: 1002000).available, false);
      const relativeCalibration = PassageCalibration(
        id: 'bad',
        providerId: 'depth',
        modelId: 'first-return',
        modelHash: 'metric-hash',
        preprocessId: 'visible',
        referenceFrameId: 'walking',
        transformId: 'optical',
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        metricScaleValidated: false,
        alignmentValidated: false,
        floorReferenceValidated: true,
      );
      expect(
        CameraMetricMotionSource(
          calibration: relativeCalibration,
          relativeModelHash: 'relative',
        ).observe(a, nowUs: 1002000).available,
        false,
      );
    },
  );
}
