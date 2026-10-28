import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/passage_clearance_contract/scenarios.dart';
import 'harness/camera_visible_passage_fixture.dart';

PassageClearanceObservation _aged(int oldest) {
  final o = fixtureObservation();
  return PassageClearanceObservation(
    providerId: o.providerId,
    modelId: o.modelId,
    modelHash: o.modelHash,
    preprocessId: o.preprocessId,
    calibrationId: o.calibrationId,
    referenceFrameId: o.referenceFrameId,
    rgbTransformId: o.rgbTransformId,
    depthTransformId: o.depthTransformId,
    timestampDomain: o.timestampDomain,
    units: o.units,
    sessionGeneration: o.sessionGeneration,
    frameId: o.frameId,
    rgbTimestampUs: o.rgbTimestampUs,
    depthTimestampUs: o.depthTimestampUs,
    producedAtUs: o.producedAtUs,
    oldestEvidenceTimestampUs: oldest,
    providerHealthy: o.providerHealthy,
    sections: o.sections,
  );
}

void main() {
  test(
    'scan age uses earliest evidence, pair skew and processing stay separate',
    () {
      final result = const PassageClearanceEvaluator(policy: contractPolicy)
          .evaluate(
            request: contractRequest,
            context: contractContext,
            calibration: fixtureCalibration(),
            observation: _aged(700000),
          );
      expect(result.status, PassageClearanceStatus.measuredClear);
      expect(result.validUntilUs, 1100000);
      expect(result.reasons, isEmpty);
    },
  );
  test('invalid future oldest timestamp and expired scan reject', () {
    for (final oldest in [-1, 1000001, 500000]) {
      final result = const PassageClearanceEvaluator(policy: contractPolicy)
          .evaluate(
            request: contractRequest,
            context: contractContext,
            calibration: fixtureCalibration(),
            observation: _aged(oldest),
          );
      expect(result.status, PassageClearanceStatus.unavailable);
    }
  });
  test('single visible frame preserves the blind near-floor volume', () {
    final fixture = VisibleFixture(),
        layout = (VisibleFixture().manifest['layouts'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((l) => l['id'] == 'validation-wide-r0-p0-v0');
    final f = fixture.frames(layout).first;
    final source = CameraPassageClearanceSource(
      calibration: fixture.calibration(),
      request: visibleRequest,
      frames: [f],
      producedAtUs: f.capturedAtUs + 1000,
    );
    final c = PassageEvaluationContext(
      nowUs: f.capturedAtUs + 2000,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: 1,
      frameId: f.frameId,
      rgbTimestampUs: f.capturedAtUs,
      transformId: f.transformId,
    );
    final result = const PassageClearanceEvaluator(policy: visibleSinglePolicy)
        .evaluate(
          request: visibleRequest,
          context: c,
          calibration: fixture.calibration(),
          observation: source.observationFor(c),
        );
    expect(result.status, PassageClearanceStatus.unavailable);
  });
  for (final fault in [
    'pose',
    'rotation',
    'session',
    'model',
    'transform',
    'relative',
    'provider',
    'translation',
    'reordered',
    'duplicate',
    'missing',
    'subpixel-centres-only',
    'reference',
    'camera-change',
    'bounds-behind-return',
  ]) {
    test('camera source fails closed: $fault', () {
      final fixture = VisibleFixture();
      final layout = (fixture.manifest['layouts'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['id'] == 'validation-wide-r0-p0-v0');
      final original = fixture.frames(layout).first;
      final f = copyVisibleFrame(
        original,
        pose: fault == 'pose' ? .2 : null,
        rotation: fault == 'rotation' ? List.filled(9, 0) : null,
        session: fault == 'session' ? 2 : null,
        modelHash: fault == 'model' ? 'other' : null,
        transform: fault == 'transform' ? 'other' : null,
        units: fault == 'relative' ? PassageUnits.relativeProximity : null,
        healthy: fault == 'provider' ? false : null,
        valid: fault == 'missing'
            ? List.filled(original.valid.length, false)
            : null,
        lower: fault == 'subpixel-centres-only'
            ? List.filled(original.valid.length, double.nan)
            : fault == 'bounds-behind-return'
            ? List.filled(original.valid.length, 100)
            : null,
        referenceFrame: fault == 'reference' ? 'other' : null,
      );
      final second = copyVisibleFrame(
        f,
        frameId: 2,
        timestamp: f.capturedAtUs + 200000,
        origin: fault == 'translation' ? [.1, 0, 1.45] : null,
        cameraId: fault == 'camera-change' ? 'other-camera' : null,
      );
      final input = fault == 'reordered'
          ? [second, f]
          : fault == 'duplicate'
          ? [f, f]
          : fault == 'translation' || fault == 'camera-change'
          ? [f, second]
          : [f];
      final source = CameraPassageClearanceSource(
        calibration: fixture.calibration(),
        request: visibleRequest,
        frames: input,
        producedAtUs: second.capturedAtUs + 1000,
        allowStaticSyntheticScan: input.length > 1,
      );
      final c = PassageEvaluationContext(
        nowUs: second.capturedAtUs + 2000,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: 1,
        frameId: input.last.frameId,
        rgbTimestampUs: input.last.capturedAtUs,
        transformId: original.transformId,
      );
      final result = const PassageClearanceEvaluator(policy: visibleScanPolicy)
          .evaluate(
            request: visibleRequest,
            context: c,
            calibration: fixture.calibration(),
            observation: source.observationFor(c),
          );
      expect(result.status, PassageClearanceStatus.unavailable);
    });
  }
  test('multi-frame union requires explicit synthetic scan opt-in', () {
    final fixture = VisibleFixture();
    final layout = (fixture.manifest['layouts'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((l) => l['id'] == 'validation-wide-r0-p0-v0');
    final frames = fixture.frames(layout);
    final source = CameraPassageClearanceSource(
      calibration: fixture.calibration(),
      request: visibleRequest,
      frames: frames,
      producedAtUs: frames.last.capturedAtUs + 1000,
    );
    expect(source.diagnostics, contains('invalid_scan_configuration'));
  });
  test(
    'covered scan proves complete volume; oldest capture expires and frame cannot be reused',
    () {
      final fixture = VisibleFixture();
      final layout = (fixture.manifest['layouts'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['id'] == 'validation-covered-wide-r0-p5-v0');
      final frames = fixture.frames(layout).skip(1).toList();
      final last = frames.last;
      final source = CameraPassageClearanceSource(
        calibration: fixture.calibration(),
        request: visibleRequest,
        frames: frames,
        producedAtUs: last.capturedAtUs + 1000,
        allowStaticSyntheticScan: true,
      );
      PassageClearanceResult evaluate(int now, int frameId) {
        final c = PassageEvaluationContext(
          nowUs: now,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          sessionGeneration: 1,
          frameId: frameId,
          rgbTimestampUs: last.capturedAtUs,
          transformId: last.transformId,
        );
        return const PassageClearanceEvaluator(
          policy: visibleScanPolicy,
        ).evaluate(
          request: visibleRequest,
          context: c,
          calibration: fixture.calibration(),
          observation: source.observationFor(c),
        );
      }

      expect(
        evaluate(last.capturedAtUs + 2000, last.frameId).status,
        PassageClearanceStatus.measuredClear,
      );
      expect(
        evaluate(frames.first.capturedAtUs + 3000001, last.frameId).status,
        PassageClearanceStatus.unavailable,
      );
      expect(
        evaluate(last.capturedAtUs + 2000, last.frameId + 1).status,
        PassageClearanceStatus.unavailable,
      );
    },
  );
  test(
    'static scan invalidates proof on conflicting occupied and free returns',
    () {
      final fixture = VisibleFixture();
      Map<String, dynamic> layout(String kind) =>
          (fixture.manifest['layouts'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((l) => l['id'] == 'validation-$kind-r0-p0-v0');
      final pole = fixture.frames(layout('pole')).first;
      final free = copyVisibleFrame(
        fixture.frames(layout('wide')).first,
        frameId: 2,
        timestamp: pole.capturedAtUs + 200000,
      );
      final source = CameraPassageClearanceSource(
        calibration: fixture.calibration(),
        request: visibleRequest,
        frames: [pole, free],
        producedAtUs: free.capturedAtUs + 1000,
        allowStaticSyntheticScan: true,
      );
      expect(source.diagnostics, contains('temporal_surface_conflict'));
      final c = PassageEvaluationContext(
        nowUs: free.capturedAtUs + 2000,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: 1,
        frameId: 2,
        rgbTimestampUs: free.capturedAtUs,
        transformId: free.transformId,
      );
      expect(
        source
            .observationFor(c)!
            .sections
            .any((s) => s.state == PassageSectionState.measured),
        false,
      );
    },
  );
}
