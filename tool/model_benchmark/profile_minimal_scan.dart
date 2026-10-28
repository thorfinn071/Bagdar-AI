import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_indexed_height_envelope_passage_source.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';

import '../../test/harness/blender_scan_complete_fixture.dart';
import '../../test/harness/blender_visible_body_fixture.dart';
import '../../test/harness/camera_visible_passage_fixture.dart'
    show copyVisibleFrame;
import 'scan_processing_support.dart';

void main(List<String> args) {
  if (args.length != 1 || File(args.single).existsSync()) {
    throw ArgumentError('Supply a new write-once output JSON path');
  }
  const root = 'scratch/single-camera-minimal-scan-2026-10-11';
  final prereg = bodyJson('$root/preregistration.json');
  for (final entry in (prereg['sources'] as Map).entries) {
    if (bodySha(entry.key as String) != entry.value) {
      throw StateError('Frozen source changed: ${entry.key}');
    }
  }
  final plan = bodyJson('$root/geometry-plan.json');
  final fixture = ScanCompleteFixture();
  final preload = Stopwatch()..start();
  final inputs = <String, Map<String, List<CameraHeightEnvelopeFrame>>>{};
  for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
    final id = layout['sceneId'] as String;
    final geometryKey = (plan['layouts'] as List).cast<Map>().singleWhere(
      (l) => l['sceneId'] == id,
    )['geometrySha256'];
    final selected =
        ((plan['plans'] as List).cast<Map>().singleWhere(
                  (p) => p['geometrySha256'] == geometryKey,
                )['selectedIndices']
                as List)
            .cast<int>();
    final original = fixture.frames(layout);
    inputs[id] = {
      for (final mode in ['full', 'minimal'])
        mode: [
          for (var i = 0; i < (mode == 'full' ? 12 : selected.length); i++)
            completeFrameCopy(
              original[mode == 'full' ? i : selected[i]],
              depth: copyVisibleFrame(
                original[mode == 'full' ? i : selected[i]].depth,
                timestamp:
                    original.first.depth.capturedAtUs +
                    (i * 1000000 + 60) ~/ 120,
              ),
            ),
        ],
    };
  }
  preload.stop();
  // One warmup for each input, outside all measured samples.
  for (final entry in inputs.entries) {
    for (final frames in entry.value.values) {
      final now = frames.last.depth.capturedAtUs + 2000;
      scanSource(
        'indexed',
        fixture.calibration(entry.key),
        frames,
        now,
      ).observationFor(scanContext(frames.last, now));
    }
  }
  stdout.writeln(
    'Preloaded/warmed ${inputs.length} scenes; timing three alternating rounds',
  );
  final rows = <Map<String, Object?>>[];
  for (var round = 0; round < 3; round++) {
    for (final entry in inputs.entries) {
      for (final mode
          in (round.isEven ? ['full', 'minimal'] : ['minimal', 'full'])) {
        final frames = entry.value[mode]!, c = fixture.calibration(entry.key);
        final watch = Stopwatch()..start();
        final anchor = frames.last.depth.capturedAtUs + 2000;
        int clock() => anchor + watch.elapsedMicroseconds;
        final start = clock(), context = scanContext(frames.last, clock());
        final gate = CameraScanAgeGate(clockUs: clock)
          ..beginSession(frames.last.depth.sessionGeneration);
        CameraIndexedHeightEnvelopePassageSource? source;
        final result = gate.release(
          gate.process(
            oldestCaptureUs: frames.first.depth.capturedAtUs,
            captureContext: context,
            calibration: c,
            request: pairedBodyRequest,
            compute: () {
              source = CameraIndexedHeightEnvelopePassageSource(
                calibration: c,
                request: pairedBodyRequest,
                frames: frames,
                producedAtUs: clock(),
              );
              return scanCompletedAt(source!.observationFor(context)!, clock());
            },
          ),
        );
        final finish = clock();
        watch.stop();
        rows.add({
          'sceneId': entry.key,
          'selection': mode,
          'round': round,
          'elapsedPipelineUs': finish - start,
          'sourceStagesUs': source?.stageComputeUs,
          'oldestAgeAtStartUs': start - frames.first.depth.capturedAtUs,
          'oldestAgeAtCompletionUs': finish - frames.first.depth.capturedAtUs,
          'ageStatus': result.status.name,
          'releasedStatus': result.decision?.status.name,
          'releasedObservationPresent': result.observation != null,
        });
      }
    }
  }
  final summaries = {
    for (final mode in ['full', 'minimal'])
      mode: scanPercentiles(
        rows
            .where((r) => r['selection'] == mode)
            .map((r) => r['elapsedPipelineUs'] as int),
      ),
  };
  writeScanReceipt(args.single, {
    'scope':
        'Windows Dart AOT; preloaded known static packets; counterfactual acquisition clocks',
    'preloadUs': preload.elapsedMicroseconds,
    'neuralLoad': false,
    'captureMeasured': false,
    'sceneMotionValidated': false,
    'phoneValidated': false,
    'promotionAllowed': false,
    'canAuthorizeMovement': false,
    'rows': rows,
    'summaries': summaries,
  });
  stdout.writeln(summaries);
}
