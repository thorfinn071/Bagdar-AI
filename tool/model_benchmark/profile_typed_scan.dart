import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_scalar_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_typed_height_envelope_frame.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';

import '../../test/harness/blender_scan_complete_fixture.dart';
import '../../test/harness/blender_visible_body_fixture.dart';
import '../../test/harness/camera_visible_passage_fixture.dart'
    show copyVisibleFrame;
import 'scan_processing_support.dart';

const modes = ['generic', 'typedCopy', 'typedTransfer'];

List<CameraHeightEnvelopeFrame> publish(
  String mode,
  List<CameraHeightEnvelopeFrame> frames,
) => switch (mode) {
  'typedCopy' => frames.map(CameraTypedHeightEnvelopeFrame.copy).toList(),
  'typedTransfer' => [
    for (final f in frames)
      CameraTypedHeightEnvelopeFrame.fromTransferable(
        metadata: f.depth,
        storage: CameraTypedHeightEnvelopeFrame.pack(f),
      ),
  ],
  _ => frames,
};

void main(List<String> args) {
  if (args.length != 1 || File(args.single).existsSync()) {
    throw ArgumentError('Supply a new write-once receipt path');
  }
  const root = 'scratch/typed-scan-transport-2026-10-11';
  final prereg = bodyJson('$root/preregistration.json');
  for (final entry in (prereg['sources'] as Map).entries) {
    if (bodySha(entry.key as String) != entry.value) {
      throw StateError('Frozen source changed: ${entry.key}');
    }
  }
  final plan = bodyJson(
    'scratch/single-camera-minimal-scan-2026-10-11/geometry-plan.json',
  );
  final fixture = ScanCompleteFixture(), preload = Stopwatch()..start();
  final inputs = <String, List<CameraHeightEnvelopeFrame>>{};
  for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
    final id = layout['sceneId'] as String;
    final key = (plan['layouts'] as List).cast<Map>().singleWhere(
      (p) => p['sceneId'] == id,
    )['geometrySha256'];
    final indices =
        ((plan['plans'] as List).cast<Map>().singleWhere(
                  (p) => p['geometrySha256'] == key,
                )['selectedIndices']
                as List)
            .cast<int>();
    final full = fixture.frames(layout);
    inputs[id] = [
      for (var i = 0; i < indices.length; i++)
        completeFrameCopy(
          full[indices[i]],
          depth: copyVisibleFrame(
            full[indices[i]].depth,
            timestamp:
                full.first.depth.capturedAtUs + (i * 1000000 + 60) ~/ 120,
          ),
        ),
    ];
  }
  preload.stop();
  var warmupPairs = 0;
  for (final entry in inputs.entries) {
    String? expected;
    for (final mode in modes) {
      final frames = publish(mode, entry.value),
          now = entry.value.last.depth.capturedAtUs + 2000;
      final source = CameraScalarHeightEnvelopePassageSource(
        calibration: fixture.calibration(entry.key),
        request: pairedBodyRequest,
        frames: frames,
        producedAtUs: now,
      );
      final encoded = jsonEncode(
        scanObservationRecord(
          source.observationFor(scanContext(frames.last, now))!,
        ),
      );
      expected ??= encoded;
      if (encoded != expected) {
        throw StateError('Typed observation drift: ${entry.key} $mode');
      }
      if (mode != 'generic') warmupPairs++;
    }
  }
  stdout.writeln(
    'Warmed 12 scenes, three modes; publication remains inside measured compute',
  );
  final rows = <Map<String, Object?>>[];
  for (var round = 0; round < 3; round++) {
    for (final entry in inputs.entries) {
      for (final mode in (round.isEven ? modes : modes.reversed)) {
        final frames = entry.value, c = fixture.calibration(entry.key);
        final watch = Stopwatch()..start();
        final anchor = frames.last.depth.capturedAtUs + 2000;
        int clock() => anchor + watch.elapsedMicroseconds;
        final start = clock(), context = scanContext(frames.last, clock());
        final gate = CameraScanAgeGate(clockUs: clock)
          ..beginSession(frames.last.depth.sessionGeneration);
        int? publicationUs;
        CameraScalarHeightEnvelopePassageSource? source;
        final result = gate.release(
          gate.process(
            oldestCaptureUs: frames.first.depth.capturedAtUs,
            captureContext: context,
            calibration: c,
            request: pairedBodyRequest,
            compute: () {
              final beginPublication = clock();
              final packets = publish(mode, frames);
              publicationUs = clock() - beginPublication;
              source = CameraScalarHeightEnvelopePassageSource(
                calibration: c,
                request: pairedBodyRequest,
                frames: packets,
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
          'mode': mode,
          'round': round,
          'elapsedPipelineUs': finish - start,
          'publicationUs': publicationUs,
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
    for (final mode in modes)
      mode: scanPercentiles(
        rows
            .where((r) => r['mode'] == mode)
            .map((r) => r['elapsedPipelineUs'] as int),
      ),
  };
  writeScanReceipt(args.single, {
    'scope':
        'Windows AOT; full publication inside compute; counterfactual acquisition clocks',
    'preloadUs': preload.elapsedMicroseconds,
    'warmupParityPairs': warmupPairs,
    'publicationIncluded': true,
    'neuralLoad': false,
    'captureMeasured': false,
    'isolateDispatchMeasured': false,
    'sceneMotionValidated': false,
    'phoneValidated': false,
    'promotionAllowed': false,
    'canAuthorizeMovement': false,
    'rows': rows,
    'summaries': summaries,
  });
  stdout.writeln(summaries);
}
