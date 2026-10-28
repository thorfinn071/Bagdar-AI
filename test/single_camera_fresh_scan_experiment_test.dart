import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/single_camera_scan_window.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/scan_processing_support.dart';
import 'harness/blender_scan_complete_fixture.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'harness/replay_source_contract.dart';

const outputRoot = 'scratch/single-camera-fresh-scan-2026-10-11';
const schedules = [
  (id: 'original-2200ms', fps: 0, lag: 2000, compute: 0),
  (id: '30fps-2ms', fps: 30, lag: 2000, compute: 0),
  (id: '60fps-2ms', fps: 60, lag: 2000, compute: 0),
  (id: '120fps-2ms', fps: 120, lag: 2000, compute: 0),
  (id: '120fps-25ms', fps: 120, lag: 25000, compute: 0),
  (id: '120fps-2ms-compute15ms', fps: 120, lag: 2000, compute: 15000),
];

double rotationDegrees(List<double> a, List<double> b) {
  var trace = 0.0;
  for (var i = 0; i < 9; i++) {
    trace += a[i] * b[i];
  }
  return math.acos(((trace - 1) / 2).clamp(-1, 1)) * 180 / math.pi;
}

void main() {
  test(
    'fresh single-camera suffix, static measurement and completion expiry',
    () {
      verifyReplaySourceContract(
        'test/fixtures/spatial_safety/scan-replay-source-contract-v1.json',
      );
      final fixture = ScanCompleteFixture();
      final rows = <Map<String, Object?>>[];
      for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
        final id = layout['sceneId'] as String;
        final original = fixture.frames(layout);
        expect(original.length, 12);
        final calibration = fixture.calibration(id);
        final base = original.first.depth.capturedAtUs;
        for (final schedule in schedules) {
          final frames = <CameraHeightEnvelopeFrame>[
            for (var i = 0; i < original.length; i++)
              if (schedule.fps == 0)
                original[i]
              else
                completeFrameCopy(
                  original[i],
                  depth: copyVisibleFrame(
                    original[i].depth,
                    timestamp:
                        base +
                        (i * 1000000 + schedule.fps ~/ 2) ~/ schedule.fps,
                  ),
                ),
          ];
          final window = SingleCameraScanWindow(
            request: pairedBodyRequest,
            sessionGeneration: frames.last.depth.sessionGeneration,
          );
          for (final f in frames) {
            expect(
              window.admit(
                frame: f.depth,
                calibration: calibration,
                context: scanContext(f, f.depth.capturedAtUs + schedule.lag),
              ),
              true,
              reason: '$id ${schedule.id} ${f.depth.frameId}',
            );
          }
          var now = frames.last.depth.capturedAtUs + schedule.lag;
          final snapshot = window.inspect(now);
          final selected = frames
              .where((f) => snapshot.frames.contains(f.depth))
              .toList();
          expect(selected, isNotEmpty);
          final expected = frames
              .where((f) => now - f.depth.capturedAtUs <= 100000)
              .toList();
          expect(selected, expected);
          final source = scanSource('indexed', calibration, selected, now);
          final observation = source.observationFor(
            scanContext(frames.last, now),
          )!;
          expect(
            observation.oldestEvidenceTimestampUs,
            selected.first.depth.capturedAtUs,
          );
          final before = scanDecision(
            calibration,
            scanContext(frames.last, now),
            observation,
          );
          final start = now;
          final gate = CameraScanAgeGate(clockUs: () => now)
            ..beginSession(frames.last.depth.sessionGeneration);
          final outcome = gate.process(
            oldestCaptureUs: selected.first.depth.capturedAtUs,
            captureContext: scanContext(frames.last, now),
            calibration: calibration,
            request: pairedBodyRequest,
            compute: () {
              now += schedule.compute;
              return scanCompletedAt(observation, now);
            },
          );
          final released = gate.release(outcome);
          if (now - selected.first.depth.capturedAtUs > 100000) {
            expect(released.status, CameraScanAgeStatus.expiredAfterCompute);
            expect(released.observation, isNull);
            expect(released.decision, isNull);
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
          // Score only after the measurement consumers and age gate have run.
          final hazard = scanHazard(fixture, id);
          if (hazard) {
            expect(released.decision?.status.name, isNot('measuredClear'));
          }
          rows.add({
            'sceneId': id,
            'scheduleId': schedule.id,
            'fps': schedule.fps,
            'startLagUs': schedule.lag,
            'simulatedComputeUs': schedule.compute,
            'physicalHazard': hazard,
            'counterfactualClock': schedule.fps != 0,
            'sceneMotionValidated': false,
            'singleCameraDynamicsValidated': false,
            'canAuthorizeMovement': false,
            'originalCaptureTimesUs': original
                .map((f) => f.depth.capturedAtUs)
                .toList(),
            'assignedCaptureTimesUs': frames
                .map((f) => f.depth.capturedAtUs)
                .toList(),
            'assignedFrameIds': frames.map((f) => f.depth.frameId).toList(),
            'snapshot': snapshot.toDiagnosticMap(),
            'selectedIndices': selected.map((f) => frames.indexOf(f)).toList(),
            'oldestAgeAtStartUs': start - selected.first.depth.capturedAtUs,
            'oldestAgeAtCompletionUs': now - selected.first.depth.capturedAtUs,
            'preCompletionMeasurement': before.toDiagnosticMap(),
            'observation': scanObservationRecord(observation),
            'ageStatus': released.status.name,
            'releasedMeasurement': released.decision?.toDiagnosticMap(),
            'releasedObservationPresent': released.observation != null,
            'afterCompute': window.inspect(now).toDiagnosticMap(),
            'sweepDurationUs': frames.last.depth.capturedAtUs - base,
            'rotationStepDegrees': angles,
            'rotationTotalDegrees': angles.reduce((a, b) => a + b),
            'peakRequiredRotationDegPerSec': rates.reduce(math.max),
          });
        }
      }
      expect(rows.length, 72);
      final report = {
        'schemaVersion': 1,
        'scope':
            'known static optical snapshots; counterfactual clocks, no phone or temporal-scene proof',
        'maximumAgeUs': 100000,
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'latencyMeasured': false,
        'rows': rows,
      };
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$outputRoot/experiment.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_FRESH_SCAN')) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(rendered);
      }
      if (!const bool.fromEnvironment('BAGDAR_WRITE_FRESH_SCAN')) {
        expect(file.readAsStringSync(), rendered);
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
