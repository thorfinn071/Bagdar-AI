import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_indexed_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_scalar_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_typed_height_envelope_frame.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/scan_processing_support.dart';
import 'harness/blender_scan_complete_fixture.dart';
import 'harness/blender_scan_coverage_fixture.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'harness/replay_source_contract.dart';
import 'single_camera_observability_test.dart'
    show opticalFrame, opticalRequest, opticalCalibration;

List<CameraHeightEnvelopeFrame> transported(
  List<CameraHeightEnvelopeFrame> frames,
) => [
  for (var i = 0; i < frames.length; i++)
    i.isEven
        ? CameraTypedHeightEnvelopeFrame.copy(frames[i])
        : CameraTypedHeightEnvelopeFrame.fromTransferable(
            metadata: frames[i].depth,
            storage: CameraTypedHeightEnvelopeFrame.pack(frames[i]),
          ),
];

PassageClearanceEvidenceSource comparedSource(
  String implementation,
  PassageCalibration c,
  List<CameraHeightEnvelopeFrame> frames,
  int at,
) => implementation == 'scalar'
    ? CameraScalarHeightEnvelopePassageSource(
        calibration: c,
        request: pairedBodyRequest,
        frames: transported(frames),
        producedAtUs: at,
      )
    : scanSource('indexed', c, frames, at);

void main() {
  late ScanCompleteFixture fixture;
  late List<CameraHeightEnvelopeFrame> clear;
  setUpAll(() {
    verifyReplaySourceContract(
      'test/fixtures/spatial_safety/scan-replay-source-contract-v1.json',
    );
    fixture = ScanCompleteFixture();
    clear = fixture.frames(
      (fixture.manifest['layouts'] as List).cast<Map>().singleWhere(
        (l) => l['sceneId'] == 'path-clear',
      ),
    );
  });
  test(
    'typed publication preserves indexed fields on full minimal and partial scans',
    () {
      final rows = <Map<String, Object?>>[];
      final plan = bodyJson(
        'scratch/single-camera-minimal-scan-2026-10-11/geometry-plan.json',
      );
      final indices =
          ((plan['plans'] as List).single as Map)['selectedIndices'] as List;
      for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
        final id = layout['sceneId'] as String;
        final full = id == 'path-clear' ? clear : fixture.frames(layout);
        for (final mode in ['full', 'minimal', 'single', 'suffix6']) {
          final frames = switch (mode) {
            'minimal' => [for (final i in indices.cast<int>()) full[i]],
            'single' => [full.last],
            'suffix6' => full.skip(6).toList(),
            _ => full,
          };
          final calibration = fixture.calibration(id);
          final context = scanContext(
            frames.last,
            frames.last.depth.capturedAtUs + 2000,
          );
          final original = comparedSource(
            'indexed',
            calibration,
            frames,
            context.nowUs - 1000,
          ).observationFor(context)!;
          final indexedSource = comparedSource(
            'scalar',
            calibration,
            frames,
            context.nowUs - 1000,
          );
          final indexed = indexedSource.observationFor(context)!;
          expect(
            scanObservationRecord(indexed),
            scanObservationRecord(original),
            reason: '$id $mode',
          );
          final hazard = scanHazard(fixture, id);
          final geometry = scanDecision(
            calibration,
            context,
            indexed,
            strict: false,
          );
          if (mode == 'full' || mode == 'minimal') {
            expect(
              geometry.status,
              hazard
                  ? PassageClearanceStatus.blocked
                  : PassageClearanceStatus.measuredClear,
              reason: id,
            );
          } else if (hazard) {
            expect(
              geometry.status,
              isNot(PassageClearanceStatus.measuredClear),
            );
          }
          if (mode != 'single') {
            expect(
              scanDecision(calibration, context, indexed).status,
              PassageClearanceStatus.unavailable,
            );
          }
          expect(
            scanObservationRecord(indexedSource.observationFor(context)!),
            scanObservationRecord(indexed),
            reason: '$id repeated query',
          );
          final current = frames
              .where((f) => context.nowUs - f.depth.capturedAtUs <= 100000)
              .toList();
          expect(current.length, 1);
          final single = comparedSource(
            'scalar',
            calibration,
            current,
            context.nowUs - 1000,
          ).observationFor(context)!;
          if (!hazard) {
            expect(
              scanDecision(calibration, context, single, strict: false).status,
              PassageClearanceStatus.unavailable,
              reason: '$id fresh-only coverage',
            );
          }
          rows.add({
            'sceneId': id,
            'selection': mode,
            'physicalHazard': hazard,
            'identicalObservation': true,
            'observation': scanObservationRecord(indexed),
            'geometry': geometry.toDiagnosticMap(),
          });
        }
      }
      final report = {
        'scope': 'known static synthetic typed publication parity only',
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'rows': rows,
      };
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('scratch/typed-scan-transport-2026-10-11/parity.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_TYPED_PARITY')) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(rendered);
      }
      if (!const bool.fromEnvironment('BAGDAR_WRITE_TYPED_PARITY')) {
        expect(file.readAsStringSync(), rendered);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
  for (final fault in [
    'single-view',
    'no-upper',
    'depth-hole',
    'height-hole',
    'first-hole',
    'bad-first',
    'relative',
    'pose',
    'session',
    'no-upward',
    'reordered',
    'empty',
    'pixel-boundary-hole',
    'wrong-model',
    'reflected-pose',
    'inverted-height',
    'infinite-first',
  ]) {
    test('typed/indexed negative observation parity: $fault', () {
      var frames = clear.toList();
      if (fault == 'single-view') frames = [frames.last];
      if (fault == 'empty') frames = [];
      if (fault == 'reordered') frames = frames.reversed.toList();
      if (fault == 'no-upward') frames = frames.take(9).toList();
      if ([
        'no-upper',
        'depth-hole',
        'relative',
        'height-hole',
        'first-hole',
        'bad-first',
        'pixel-boundary-hole',
      ].contains(fault)) {
        frames = frames.map((f) {
          final n = f.depth.width * f.depth.height;
          var lo = f.heightLowerM.toList(), hi = f.heightUpperM.toList();
          if (fault == 'height-hole') {
            lo = List.filled(n, double.nan);
            hi = List.filled(n, double.nan);
          }
          if (fault == 'pixel-boundary-hole') {
            // Crossing index-tile boundaries and image edges must not average
            // away a missing floor pixel or substitute another pixel's height.
            for (final x in [0, 7, 8, 15, 16, f.depth.width - 1]) {
              for (final y in [0, 7, 8, 15, 16, f.depth.height - 1]) {
                lo[y * f.depth.width + x] = hi[y * f.depth.width + x] =
                    double.nan;
              }
            }
          }
          return completeFrameCopy(
            f,
            depth: scanFrameCopy(
              f.depth,
              upper: fault == 'no-upper' ? List.filled(n, double.nan) : null,
              valid: fault == 'depth-hole' ? List.filled(n, false) : null,
              units: fault == 'relative'
                  ? PassageUnits.relativeProximity
                  : null,
            ),
            heightLower: lo,
            heightUpper: hi,
            firstZLower: fault == 'first-hole'
                ? List.filled(n, double.nan)
                : fault == 'bad-first'
                ? List.filled(n, 100)
                : null,
          );
        }).toList();
      }
      if (fault == 'pose' || fault == 'session') {
        frames[0] = completeFrameCopy(
          frames[0],
          depth: scanFrameCopy(
            frames[0].depth,
            origin: fault == 'pose'
                ? [0, .02, frames[0].depth.originM[2]]
                : null,
            session: fault == 'session' ? 2 : null,
          ),
        );
      }
      if (fault == 'wrong-model' || fault == 'reflected-pose') {
        frames[0] = completeFrameCopy(
          frames[0],
          depth: copyVisibleFrame(
            frames[0].depth,
            modelHash: fault == 'wrong-model' ? 'unknown-model' : null,
            rotation: fault == 'reflected-pose'
                ? List.generate(
                    9,
                    (i) => i < 3
                        ? -frames[0].depth.rotation[i]
                        : frames[0].depth.rotation[i],
                  )
                : null,
          ),
        );
      }
      if (fault == 'inverted-height' || fault == 'infinite-first') {
        final n = frames[0].depth.rangeM.length;
        frames[0] = completeFrameCopy(
          frames[0],
          heightLower: fault == 'inverted-height' ? List.filled(n, 2) : null,
          heightUpper: fault == 'inverted-height' ? List.filled(n, 1) : null,
          firstZLower: fault == 'infinite-first'
              ? List.filled(n, double.infinity)
              : null,
        );
      }
      final context = scanContext(
        clear.last,
        clear.last.depth.capturedAtUs + 2000,
      );
      final calibration = fixture.calibration('path-clear');
      final original = comparedSource(
        'indexed',
        calibration,
        frames,
        context.nowUs - 1000,
      ).observationFor(context);
      final indexed = comparedSource(
        'scalar',
        calibration,
        frames,
        context.nowUs - 1000,
      ).observationFor(context);
      expect(
        indexed == null ? null : scanObservationRecord(indexed),
        original == null ? null : scanObservationRecord(original),
      );
      if (indexed != null && fault != 'pixel-boundary-hole') {
        expect(
          scanDecision(calibration, context, indexed, strict: false).status,
          PassageClearanceStatus.unavailable,
        );
      }
    });
  }
  test(
    'seeded small packets preserve arithmetic across intrinsics and invalid pixels',
    () {
      final random = math.Random(1011);
      final c = opticalCalibration(), request = opticalRequest(end: .5);
      for (var trial = 0; trial < 100; trial++) {
        final frames = <CameraHeightEnvelopeFrame>[];
        for (var fi = 0; fi < 3; fi++) {
          final prototype = copyVisibleFrame(
            opticalFrame(focal: .2 + random.nextDouble() * 3),
            frameId: fi + 1,
            timestamp: 1000000 + fi * 1000,
          );
          final range = List.generate(
            16,
            (i) => i == trial % 16 && trial % 3 == 0
                ? double.nan
                : .01 + random.nextDouble() * 5,
          );
          final depth = copyVisibleFrame(
            prototype,
            range: range,
            lower: List.filled(16, 0),
            upper: List.filled(16, double.nan),
            valid: List.generate(16, (i) => random.nextDouble() > .1),
          );
          frames.add(
            CameraHeightEnvelopeFrame(
              depth: depth,
              firstZLowerM: List.filled(16, double.nan),
              heightLowerM: List.filled(16, double.nan),
              heightUpperM: List.filled(16, double.nan),
            ),
          );
        }
        final context = PassageEvaluationContext(
          nowUs: 1003000,
          timestampDomain: c.timestampDomain,
          sessionGeneration: 1,
          frameId: 3,
          rgbTimestampUs: 1002000,
          transformId: c.transformId,
        );
        final scalar = CameraScalarHeightEnvelopePassageSource(
          calibration: c,
          request: request,
          frames: transported(frames),
          producedAtUs: 1003000,
        );
        // Use the indexed source with exactly the same custom request.
        final indexed = CameraIndexedHeightEnvelopePassageSource(
          calibration: c,
          request: request,
          frames: frames,
          producedAtUs: 1003000,
        );
        expect(
          scanObservationRecord(scalar.observationFor(context)!),
          scanObservationRecord(indexed.observationFor(context)!),
          reason: 'trial $trial',
        );
      }
    },
  );
}
