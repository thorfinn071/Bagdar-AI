import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/single_camera_scan_window.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/scan_processing_support.dart';
import 'harness/blender_scan_complete_fixture.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'harness/replay_source_contract.dart';
import 'single_camera_fresh_scan_experiment_test.dart' show rotationDegrees;

const root = 'scratch/single-camera-minimal-scan-2026-10-11';
const schedules = [
  (id: 'original', fps: 0, compute: 0),
  (id: '30fps', fps: 30, compute: 0),
  (id: '60fps', fps: 60, compute: 0),
  (id: '90fps', fps: 90, compute: 0),
  (id: '120fps', fps: 120, compute: 0),
  (id: '120fps-compute15ms', fps: 120, compute: 15000),
  (id: '120fps-compute25ms', fps: 120, compute: 25000),
];
const faults = [
  'relative',
  'invalidPixels',
  'missingHeight',
  'missingFirstReturn',
  'badPose',
  'wrongModel',
  'mixedSessions',
];

List<CameraHeightEnvelopeFrame> assignClocks(
  List<CameraHeightEnvelopeFrame> original,
  List<int> indices,
  int fps,
) => [
  for (var i = 0; i < indices.length; i++)
    fps == 0
        ? original[indices[i]]
        : completeFrameCopy(
            original[indices[i]],
            depth: copyVisibleFrame(
              original[indices[i]].depth,
              timestamp:
                  original.first.depth.capturedAtUs +
                  (i * 1000000 + fps ~/ 2) ~/ fps,
            ),
          ),
];

CameraHeightEnvelopeFrame corrupt(CameraHeightEnvelopeFrame f, String fault) {
  final n = f.depth.rangeM.length;
  return switch (fault) {
    'relative' => completeFrameCopy(
      f,
      depth: copyVisibleFrame(f.depth, units: PassageUnits.relativeProximity),
    ),
    'invalidPixels' => completeFrameCopy(
      f,
      depth: copyVisibleFrame(f.depth, valid: List.filled(n, false)),
    ),
    'missingHeight' => completeFrameCopy(
      f,
      heightLower: List.filled(n, double.nan),
      heightUpper: List.filled(n, double.nan),
    ),
    'missingFirstReturn' => completeFrameCopy(
      f,
      firstZLower: List.filled(n, double.nan),
    ),
    'badPose' => completeFrameCopy(
      f,
      depth: copyVisibleFrame(f.depth, rotation: List.filled(9, 0)),
    ),
    'wrongModel' => completeFrameCopy(
      f,
      depth: copyVisibleFrame(f.depth, modelHash: 'unbound-model'),
    ),
    'mixedSessions' => completeFrameCopy(
      f,
      depth: copyVisibleFrame(f.depth, session: f.depth.sessionGeneration + 1),
    ),
    _ => throw ArgumentError.value(fault),
  };
}

void main() {
  test(
    'geometry-selected scan never substitutes visibility for measurement',
    () {
      verifyReplaySourceContract(
        'test/fixtures/spatial_safety/scan-replay-source-contract-v1.json',
      );
      final plan = bodyJson('$root/geometry-plan.json');
      final fixture = ScanCompleteFixture();
      final rows = <Map<String, Object?>>[],
          negatives = <Map<String, Object?>>[];
      for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
        final id = layout['sceneId'] as String;
        final key = (plan['layouts'] as List).cast<Map>().singleWhere(
          (l) => l['sceneId'] == id,
        )['geometrySha256'];
        final chosen = (plan['plans'] as List).cast<Map>().singleWhere(
          (p) => p['geometrySha256'] == key,
        );
        final indices = (chosen['selectedIndices'] as List).cast<int>();
        final original = fixture.frames(layout),
            calibration = fixture.calibration(id);
        for (final selection in ['full', 'minimal']) {
          final selectedIndices = selection == 'full'
              ? List.generate(12, (i) => i)
              : indices;
          for (final schedule in schedules) {
            final frames = assignClocks(
              original,
              selectedIndices,
              schedule.fps,
            );
            final window = SingleCameraScanWindow(
              request: pairedBodyRequest,
              sessionGeneration: frames.last.depth.sessionGeneration,
            );
            for (final f in frames) {
              expect(
                window.admit(
                  frame: f.depth,
                  calibration: calibration,
                  context: scanContext(f, f.depth.capturedAtUs + 2000),
                ),
                true,
              );
            }
            var now = frames.last.depth.capturedAtUs + 2000;
            final snapshot = window.inspect(now);
            final retained = frames
                .where((f) => snapshot.frames.contains(f.depth))
                .toList();
            final source = scanSource('indexed', calibration, retained, now);
            final observation = source.observationFor(
              scanContext(frames.last, now),
            )!;
            final before = scanDecision(
              calibration,
              scanContext(frames.last, now),
              observation,
            );
            final start = now;
            final gate = CameraScanAgeGate(clockUs: () => now)
              ..beginSession(frames.last.depth.sessionGeneration);
            final result = gate.release(
              gate.process(
                oldestCaptureUs: retained.first.depth.capturedAtUs,
                captureContext: scanContext(frames.last, now),
                calibration: calibration,
                request: pairedBodyRequest,
                compute: () {
                  now += schedule.compute;
                  return scanCompletedAt(observation, now);
                },
              ),
            );
            final hazard = scanHazard(fixture, id);
            if (hazard) {
              expect(result.decision?.status.name, isNot('measuredClear'));
            }
            final angles = [
              for (var i = 1; i < frames.length; i++)
                rotationDegrees(
                  frames[i - 1].depth.rotation,
                  frames[i].depth.rotation,
                ),
            ];
            final rates = [
              for (var i = 1; i < frames.length; i++)
                angles[i - 1] *
                    1000000 /
                    (frames[i].depth.capturedAtUs -
                        frames[i - 1].depth.capturedAtUs),
            ];
            rows.add({
              'sceneId': id,
              'selection': selection,
              'scheduleId': schedule.id,
              'fps': schedule.fps,
              'simulatedComputeUs': schedule.compute,
              'physicalHazard': hazard,
              'counterfactualClock': schedule.fps != 0,
              'selectedOriginalIndices': selectedIndices,
              'retainedOriginalIndices': retained
                  .map((f) => selectedIndices[frames.indexOf(f)])
                  .toList(),
              'assignedCaptureTimesUs': frames
                  .map((f) => f.depth.capturedAtUs)
                  .toList(),
              'snapshot': snapshot.toDiagnosticMap(),
              'oldestAgeAtStartUs': start - retained.first.depth.capturedAtUs,
              'oldestAgeAtCompletionUs':
                  now - retained.first.depth.capturedAtUs,
              'observation': scanObservationRecord(observation),
              'preCompletionMeasurement': before.toDiagnosticMap(),
              'ageStatus': result.status.name,
              'releasedMeasurement': result.decision?.toDiagnosticMap(),
              'releasedObservationPresent': result.observation != null,
              'rotationTotalDegrees': angles.reduce((a, b) => a + b),
              'peakRequiredRotationDegPerSec': rates.reduce(math.max),
            });
          }
        }
        final frames = assignClocks(original, indices, 120);
        for (final fault in faults) {
          final damaged = [
            for (var i = 0; i < frames.length; i++)
              fault == 'mixedSessions' && i != 0
                  ? frames[i]
                  : corrupt(frames[i], fault),
          ];
          final now = frames.last.depth.capturedAtUs + 2000;
          final source = scanSource('indexed', calibration, damaged, now);
          final observation = source.observationFor(
            scanContext(frames.last, now),
          )!;
          final decision = scanDecision(
            calibration,
            scanContext(frames.last, now),
            observation,
          );
          expect(
            decision.status,
            isNot(PassageClearanceStatus.measuredClear),
            reason: '$id $fault',
          );
          negatives.add({
            'sceneId': id,
            'fault': fault,
            'measurement': decision.toDiagnosticMap(),
          });
        }
      }
      expect(rows.length, 168);
      expect(negatives.length, 84);
      final report = {
        'scope': 'known static finite-pose experiment; assigned clocks only',
        'maximumAgeUs': 100000,
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'latencyMeasured': false,
        'sceneMotionValidated': false,
        'singleCameraDynamicsValidated': false,
        'canAuthorizeMovement': false,
        'rows': rows,
        'negatives': negatives,
      };
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$root/experiment.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_MINIMAL_SCAN')) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(rendered);
      }
      if (!const bool.fromEnvironment('BAGDAR_WRITE_MINIMAL_SCAN')) {
        expect(file.readAsStringSync(), rendered);
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
