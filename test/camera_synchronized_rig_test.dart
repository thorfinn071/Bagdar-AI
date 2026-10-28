import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_indexed_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/scan_processing_support.dart';
import 'harness/blender_synchronized_rig_fixture.dart';

void main() {
  late SynchronizedRigFixture fixture;
  late Map batch;
  late List<CameraHeightEnvelopeFrame> frames;
  setUpAll(() {
    fixture = SynchronizedRigFixture();
    batch = fixture.batches.first;
    frames = fixture.frames(batch, 'batch');
  });

  PassageClearanceObservation observe(List<CameraHeightEnvelopeFrame> input) =>
      fixture
          .source(batch, 'batch', input, (batch['capturedAtUs'] as int) + 1000)
          .observationFor(
            fixture.context(
              batch,
              'batch',
              (batch['capturedAtUs'] as int) + 2000,
            ),
          )!;

  test(
    'new single and synchronized captures keep time, visible coverage and motion boundary',
    () {
      var positives = 0, blocked = 0, dynamicRejected = 0;
      for (final b in fixture.batches) {
        final at = b['capturedAtUs'] as int;
        for (final mode in ['single', 'batch']) {
          final input = fixture.frames(b, mode);
          expect(input.map((f) => f.depth.capturedAtUs).toSet(), {at});
          expect(
            input.map((f) => f.depth.cameraId).toSet().length,
            input.length,
          );
          final context = fixture.context(b, mode, at + 2000);
          final source = fixture.source(b, mode, input, at + 1000);
          final observation = source.observationFor(context)!;
          expect(observation.oldestEvidenceTimestampUs, at);
          expect(observation.rgbTimestampUs, at);
          expect(
            scanObservationRecord(source.observationFor(context)!),
            scanObservationRecord(observation),
          );
          final result = rigDecision(
            fixture.calibration(b, mode),
            context,
            observation,
          );
          final label = fixture.label(b['id'] as String);
          if (label['dynamic'] == true) {
            expect(result.status, PassageClearanceStatus.unavailable);
            expect(
              source.diagnostics,
              contains('motion_bound_not_established'),
            );
            dynamicRejected++;
          } else if (mode == 'batch') {
            if (label['physicalHazardAtCapture'] == true) {
              expect(
                result.status,
                PassageClearanceStatus.blocked,
                reason: b['id'] as String,
              );
              blocked++;
            } else {
              expect(
                result.status,
                PassageClearanceStatus.measuredClear,
                reason: b['id'] as String,
              );
              expect(
                observation.sections.every(
                  (s) =>
                      s.bodyObservedFraction == 1 &&
                      s.floorObservedFraction == 1,
                ),
                true,
              );
              positives++;
            }
          } else if (label['physicalHazardAtCapture'] == false) {
            expect(result.status, PassageClearanceStatus.unavailable);
          }
          if (label['physicalHazardAtCapture'] == true) {
            expect(result.status, isNot(PassageClearanceStatus.measuredClear));
          }
        }
      }
      expect(positives, 3);
      expect(blocked, 3);
      expect(dynamicRejected, 4);
    },
  );

  final cases =
      <
        String,
        List<CameraHeightEnvelopeFrame> Function(
          List<CameraHeightEnvelopeFrame>,
        )
      >{
        'missing channel': (fs) => fs.sublist(1),
        'reordered channels': (fs) => fs.reversed.toList(),
        'duplicate channel': (fs) => [
          fs.first,
          ...fs.skip(1).take(fs.length - 2),
          fs.first,
        ],
        'one microsecond skew': (fs) => [
          rigCopyFrame(fs.first, capturedAtUs: fs.first.depth.capturedAtUs + 1),
          ...fs.skip(1),
        ],
        'other frame': (fs) => [
          rigCopyFrame(fs.first, frameId: 99),
          ...fs.skip(1),
        ],
        'other session': (fs) => [
          rigCopyFrame(fs.first, sessionGeneration: 99),
          ...fs.skip(1),
        ],
        'foreign channel': (fs) => [
          rigCopyFrame(fs.first, cameraId: 'foreign'),
          ...fs.skip(1),
        ],
        'wrong model': (fs) => [
          rigCopyFrame(fs.first, modelHash: 'unverified'),
          ...fs.skip(1),
        ],
        'wrong transform': (fs) => [
          rigCopyFrame(fs.first, transformId: 'foreign'),
          ...fs.skip(1),
        ],
        'wrong reference': (fs) => [
          rigCopyFrame(fs.first, referenceFrameId: 'foreign'),
          ...fs.skip(1),
        ],
        'relative units': (fs) => [
          rigCopyFrame(fs.first, units: PassageUnits.relativeProximity),
          ...fs.skip(1),
        ],
        'bad pose confidence': (fs) => [
          rigCopyFrame(fs.first, poseQuality: .5),
          ...fs.skip(1),
        ],
        'different valid rotation': (fs) => [
          rigCopyFrame(fs.first, rotation: fs.last.depth.rotation),
          ...fs.skip(1),
        ],
        'wrong optical centre': (fs) => [
          rigCopyFrame(fs.first, originM: [0, 0, 1.48]),
          ...fs.skip(1),
        ],
        'wrong focal length': (fs) => [
          rigCopyFrame(fs.first, fx: fs.first.depth.fx + 1),
          ...fs.skip(1),
        ],
        'provider failed': (fs) => [
          rigCopyFrame(fs.first, providerHealthy: false),
          ...fs.skip(1),
        ],
        'missing first-return bounds': (fs) => [
          rigCopyFrame(fs.first, firstZLowerM: []),
          ...fs.skip(1),
        ],
        'corrupted height interval': (fs) => [
          rigCopyFrame(
            fs.first,
            heightLowerM: List.filled(fs.first.heightLowerM.length, 9),
          ),
          ...fs.skip(1),
        ],
      };
  for (final entry in cases.entries) {
    test('${entry.key} cannot gain coverage authority', () {
      final o = observe(entry.value(frames));
      expect(o.providerHealthy, false);
      expect(o.sections, isEmpty);
      expect(
        rigDecision(
          fixture.calibration(batch, 'batch'),
          fixture.context(
            batch,
            'batch',
            (batch['capturedAtUs'] as int) + 2000,
          ),
          o,
        ).status,
        isNot(PassageClearanceStatus.measuredClear),
      );
    });
  }

  test('missing optical returns stay unknown in every channel', () {
    final unknown = [
      for (final e in frames)
        rigCopyFrame(
          e,
          valid: List.filled(e.depth.valid.length, false),
          rangeM: List.filled(e.depth.rangeM.length, double.nan),
          freeZLowerM: List.filled(e.depth.rangeM.length, double.nan),
          surfaceZUpperM: List.filled(e.depth.rangeM.length, double.nan),
          firstZLowerM: List.filled(e.depth.rangeM.length, double.nan),
          heightLowerM: List.filled(e.depth.rangeM.length, double.nan),
          heightUpperM: List.filled(e.depth.rangeM.length, double.nan),
        ),
    ];
    final o = observe(unknown);
    expect(o.providerHealthy, true);
    expect(
      o.sections.every(
        (s) => s.bodyObservedFraction == 0 && s.floorObservedFraction == 0,
      ),
      true,
    );
    expect(
      rigDecision(
        fixture.calibration(batch, 'batch'),
        fixture.context(batch, 'batch', (batch['capturedAtUs'] as int) + 2000),
        o,
      ).status,
      PassageClearanceStatus.unavailable,
    );
  });

  test('frozen sequential source still rejects simultaneous channels', () {
    final o =
        CameraIndexedHeightEnvelopePassageSource(
          calibration: fixture.calibration(batch, 'batch'),
          request: synchronizedRigRequest,
          frames: frames,
          producedAtUs: (batch['capturedAtUs'] as int) + 1000,
        ).observationFor(
          fixture.context(
            batch,
            'batch',
            (batch['capturedAtUs'] as int) + 2000,
          ),
        )!;
    expect(o.providerHealthy, false);
    expect(o.sections, isEmpty);
  });

  test(
    '100 ms expiry rejects before compute and after compute without retimestamping',
    () {
      final at = batch['capturedAtUs'] as int;
      var now = at + 100001, called = false;
      final gate = CameraScanAgeGate(clockUs: () => now)..beginSession(1);
      CameraScanAgeOutcome process() => gate.process(
        oldestCaptureUs: at,
        captureContext: fixture.context(batch, 'batch', now),
        calibration: fixture.calibration(batch, 'batch'),
        request: synchronizedRigRequest,
        compute: () {
          called = true;
          now = at + 100001;
          return observe(frames);
        },
      );
      expect(process().status, CameraScanAgeStatus.expiredBeforeCompute);
      expect(called, false);
      final freshGate = CameraScanAgeGate(clockUs: () => now)..beginSession(1);
      now = at + 2000;
      final result = freshGate.process(
        oldestCaptureUs: at,
        captureContext: fixture.context(batch, 'batch', now),
        calibration: fixture.calibration(batch, 'batch'),
        request: synchronizedRigRequest,
        compute: () {
          final o = observe(frames);
          now = at + 100001;
          return scanCompletedAt(o, now);
        },
      );
      expect(result.status, CameraScanAgeStatus.expiredAfterCompute);
      expect(freshGate.release(result).decision, null);
      expect(frames.every((f) => f.depth.capturedAtUs == at), true);
    },
  );
}
