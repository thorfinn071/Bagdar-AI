import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';

import '../../test/harness/blender_synchronized_rig_fixture.dart';
import '../../test/harness/blender_visible_body_fixture.dart';
import 'scan_processing_support.dart';
import 'synchronized_rig_neural_load.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 || args[0] != '--output' || File(args[1]).existsSync()) {
    throw ArgumentError(
      'Usage: profile_synchronized_rig --output NEW.json [--nn]',
    );
  }
  final withNN = args.contains('--nn');
  final preload = Stopwatch()..start();
  final fixture = SynchronizedRigFixture();
  final inputs = <String, List<CameraHeightEnvelopeFrame>>{};
  for (final batch in fixture.batches) {
    for (final mode in ['single', 'batch']) {
      inputs['${batch['id']}/$mode'] = fixture.frames(batch, mode);
    }
  }
  preload.stop();
  final geometry = <Map<String, Object?>>[];
  final expected = <String, String>{};
  for (final batch in fixture.batches) {
    final at = batch['capturedAtUs'] as int;
    for (final mode in ['single', 'batch']) {
      final frames = inputs['${batch['id']}/$mode']!;
      final source = fixture.source(batch, mode, frames, at + 1000);
      final context = fixture.context(batch, mode, at + 2000);
      final observation = source.observationFor(context)!;
      final decision = rigDecision(
        fixture.calibration(batch, mode),
        context,
        observation,
      );
      expected['${batch['id']}/$mode'] = jsonEncode(
        scanObservationRecord(observation),
      );
      // Labels enter scoring only after the complete observation/evaluation.
      final label = fixture.label(batch['id'] as String);
      if (label['physicalHazardAtCapture'] == true &&
          decision.status == PassageClearanceStatus.measuredClear) {
        throw StateError('Incorrect clear in ${batch['id']}');
      }
      if (label['dynamic'] == true &&
          decision.status != PassageClearanceStatus.unavailable) {
        throw StateError('Dynamic scene gained static clearance authority');
      }
      geometry.add({
        'id': batch['id'],
        'mode': mode,
        'physicalHazard': label['physicalHazardAtCapture'],
        'dynamic': label['dynamic'],
        'channels': frames.length,
        'captureSpanUs': 0,
        'status': decision.status.name,
        'diagnostics': source.diagnostics,
        'bodyObservedMinimum': observation.sections.isEmpty
            ? null
            : observation.sections
                  .map((s) => s.bodyObservedFraction)
                  .reduce((a, b) => a < b ? a : b),
        'floorObservedMinimum': observation.sections.isEmpty
            ? null
            : observation.sections
                  .map((s) => s.floorObservedFraction)
                  .reduce((a, b) => a < b ? a : b),
        'sections': scanObservationRecord(observation)['sections'],
      });
    }
  }
  stdout.writeln(
    'New geometry: ${geometry.length} single/batch observations; preload ${preload.elapsedMilliseconds} ms',
  );
  final neural = withNN ? await SynchronizedRigNeuralLoad.start() : null;
  Map<String, Object?>? neuralReceipt;
  final samples = <Map<String, Object?>>[];
  try {
    for (var round = 0; round < 3; round++) {
      final modes = round.isEven ? ['single', 'batch'] : ['batch', 'single'];
      for (final batch in fixture.batches) {
        for (final mode in modes) {
          final key = '${batch['id']}/$mode', frames = inputs[key]!;
          final calibration = fixture.calibration(batch, mode);
          final at = batch['capturedAtUs'] as int;
          final watch = Stopwatch()..start();
          int clock() => at + 2000 + watch.elapsedMicroseconds;
          final start = clock();
          final context = fixture.context(batch, mode, start);
          final gate = CameraScanAgeGate(clockUs: clock)
            ..beginSession(batch['sessionGeneration'] as int);
          CameraSynchronizedEnvelopeSource? source;
          PassageClearanceObservation? observed;
          var built = start, observedAt = start;
          final outcome = gate.process(
            oldestCaptureUs: at,
            captureContext: context,
            calibration: calibration,
            request: synchronizedRigRequest,
            compute: () {
              source = fixture.source(batch, mode, frames, clock());
              built = clock();
              observed = source!.observationFor(context);
              observedAt = clock();
              return observed == null
                  ? null
                  : scanCompletedAt(observed!, observedAt);
            },
          );
          final processed = clock();
          final released = gate.release(outcome);
          final dispatch = clock();
          watch.stop();
          if (source == null || observed == null) {
            throw StateError('Unexpected precompute expiry');
          }
          final comparable = scanCompletedAt(observed!, at + 1000);
          if (jsonEncode(scanObservationRecord(comparable)) != expected[key]) {
            throw StateError('Timed geometry changed: $key');
          }
          final label = fixture.label(batch['id'] as String);
          final status =
              released.decision?.status ?? PassageClearanceStatus.unavailable;
          final clear = status == PassageClearanceStatus.measuredClear;
          if (clear &&
              (label['physicalHazardAtCapture'] == true ||
                  label['dynamic'] == true ||
                  dispatch - at > 100000)) {
            throw StateError('Unsafe/stale/dynamic clear');
          }
          samples.add({
            'round': round,
            'id': batch['id'],
            'mode': mode,
            'physicalHazard': label['physicalHazardAtCapture'],
            'dynamic': label['dynamic'],
            'captureSpanUs': 0,
            'sourceBuildUs': built - start,
            'observationUs': observedAt - built,
            'gateProcessRemainderUs': processed - observedAt,
            'dispatchGuardUs': dispatch - processed,
            'pipelineUs': dispatch - start,
            'ageAtStartUs': start - at,
            'ageAtDispatchUs': dispatch - at,
            'releaseStatus': released.status.name,
            'strictStatus': status.name,
            'shadowDecision': clear
                ? 'continueForward'
                : status == PassageClearanceStatus.blocked
                ? 'stopBlocked'
                : 'stopUnavailable',
            'unsafeContinue': false,
            'stagesUs': source!.stageComputeUs,
          });
        }
      }
      stdout.writeln(
        'Measured rig round ${round + 1}/3 (${withNN ? 'NCNN' : 'no NN'})',
      );
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    neuralReceipt = await neural?.close();
  }
  final summaries = <String, Object?>{};
  for (final mode in ['single', 'batch']) {
    final rows = samples
        .where((r) => r['mode'] == mode && r['dynamic'] == false)
        .toList();
    final hazards = rows.where((r) => r['physicalHazard'] == true).toList();
    summaries[mode] = {
      'staticSamples': rows.length,
      'pipeline': scanPercentiles(rows.map((r) => r['pipelineUs'] as int)),
      'ageAtDispatch': scanPercentiles(
        rows.map((r) => r['ageAtDispatchUs'] as int),
      ),
      'computeWithin100ms': rows
          .where((r) => (r['pipelineUs'] as int) <= 100000)
          .length,
      'admittedClear': rows
          .where((r) => r['strictStatus'] == 'measuredClear')
          .length,
      'timelyGeometricHazardDecisions': hazards
          .where((r) => r['strictStatus'] == 'blocked')
          .length,
      'missedTimelyGeometricHazardDecisions': hazards
          .where((r) => r['strictStatus'] != 'blocked')
          .length,
      'fallbackStopsOnHazards': hazards
          .where((r) => r['strictStatus'] == 'unavailable')
          .length,
      'falseStopsOnPassable': rows
          .where(
            (r) =>
                r['physicalHazard'] == false &&
                r['strictStatus'] != 'measuredClear',
          )
          .length,
      'unsafeContinue': 0,
      'expired': rows
          .where((r) => (r['ageAtDispatchUs'] as int) > 100000)
          .length,
      'dynamicRejected': samples
          .where(
            (r) =>
                r['mode'] == mode &&
                r['dynamic'] == true &&
                r['strictStatus'] == 'unavailable',
          )
          .length,
    };
  }
  writeScanReceipt(args[1], {
    'schemaVersion': 1,
    'passed': true,
    'mode': withNN ? 'elapsed-nn' : 'elapsed',
    'rounds': 3,
    'runtime': Platform.version,
    'executableSha256': bodySha(Platform.resolvedExecutable),
    'manifestSha256': fixture.modelHash,
    'fixtureLoadUs': preload.elapsedMicroseconds,
    'promotionAllowed': false,
    'runtimeWired': false,
    'captureToCommandMeasured': false,
    'currentAgeLimitUs': 100000,
    'rigPhysicalRealization': 'not_established',
    'scope':
        'preloaded synthetic rig source+observation+strict gate+single-use shadow release; excludes capture/transport/load/active planner/audio/haptics',
    'sources': {
      for (final path in [
        'lib/safety/perception/camera_synchronized_envelope_source.dart',
        'lib/safety/runtime/camera_scan_age_gate.dart',
        'test/harness/blender_synchronized_rig_fixture.dart',
        'tool/model_benchmark/profile_synchronized_rig.dart',
        'tool/model_benchmark/synchronized_rig_neural_load.dart',
        'tool/model_benchmark/scan_processing_ncnn_load.py',
        'tool/model_benchmark/scan_processing_support.dart',
        'docs/blender-synchronized-rig-protocol-2026-10-04.md',
      ])
        path: bodySha(path),
    },
    'neuralLoad': neuralReceipt,
    'geometry': geometry,
    'summaries': summaries,
    'samples': samples,
  });
  stdout.writeln(jsonEncode(summaries));
}
