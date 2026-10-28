import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';

import '../../test/harness/blender_visible_body_fixture.dart';
import '../../test/harness/synchronized_passage_fixture.dart';
import 'scan_processing_support.dart';
import 'synchronized_rig_neural_load.dart';

Future<void> main(List<String> args) async {
  final index = args.indexOf('--output');
  if (index < 0 ||
      index + 1 >= args.length ||
      File(args[index + 1]).existsSync()) {
    throw ArgumentError('Use --output NEW.json [--pilot] [--nn]');
  }
  final fixture = SynchronizedPassageFixture(pilot: args.contains('--pilot'));
  final preload = Stopwatch()..start();
  final frames = <String, List<CameraHeightEnvelopeFrame>>{};
  final primary = <String, CameraVisibleDepthFrame>{};
  for (final batch in fixture.batches) {
    frames[batch['id'] as String] = fixture.frames(batch);
    primary[batch['id'] as String] = fixture.primary(batch);
  }
  preload.stop();
  PassageClearanceEvidenceSource source(Map batch, String mode, int produced) =>
      mode == 'rig'
      ? fixture.source(batch, frames[batch['id']]!, produced)
      : CameraPassageClearanceSource(
          calibration: fixture.calibration(batch, 'single'),
          request: pairedBodyRequest,
          frames: [primary[batch['id']]!],
          producedAtUs: produced,
        );
  final geometry = <Map<String, Object?>>[];
  final expected = <String, String>{};
  for (final batch in fixture.batches) {
    final at = batch['capturedAtUs'] as int;
    for (final mode in ['single', 'rig']) {
      final producer = source(batch, mode, at + 1000);
      final observation = producer.observationFor(
        fixture.context(batch, at + 2000),
      )!;
      final decision = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
          .evaluate(
            request: pairedBodyRequest,
            context: fixture.context(batch, at + 2000),
            calibration: fixture.calibration(batch, mode),
            observation: observation,
          );
      if (batch['physicalHazard'] == true &&
          decision.status == PassageClearanceStatus.measuredClear) {
        throw StateError('Unsafe source clear ${batch['id']}');
      }
      expected['${batch['id']}/$mode'] = jsonEncode(
        scanObservationRecord(observation),
      );
      geometry.add({
        'id': batch['id'],
        'mode': mode,
        'physicalHazard': batch['physicalHazard'],
        'status': decision.status.name,
        'providerHealthy': observation.providerHealthy,
        'sections': scanObservationRecord(observation)['sections'],
      });
    }
  }
  final neural = args.contains('--nn')
      ? await SynchronizedRigNeuralLoad.start()
      : null;
  Map<String, Object?>? nnReceipt;
  final samples = <Map<String, Object?>>[];
  try {
    for (var round = 0; round < 3; round++) {
      for (final batch in fixture.batches) {
        for (final mode
            in round.isEven ? ['single', 'rig'] : ['rig', 'single']) {
          final at = batch['capturedAtUs'] as int;
          final watch = Stopwatch()..start();
          int clock() => at + 2000 + watch.elapsedMicroseconds;
          final calibration = fixture.calibration(batch, mode);
          final gate = CameraScanAgeGate(clockUs: clock)
            ..beginSession(batch['sessionGeneration'] as int);
          PassageClearanceObservation? raw;
          final outcome = gate.process(
            oldestCaptureUs: at,
            captureContext: fixture.context(batch, clock()),
            calibration: calibration,
            request: pairedBodyRequest,
            compute: () {
              final producer = source(batch, mode, clock());
              raw = producer.observationFor(fixture.context(batch, clock()));
              return raw == null ? null : scanCompletedAt(raw!, clock());
            },
          );
          final released = gate.release(outcome);
          final dispatch = clock();
          watch.stop();
          if (raw == null ||
              jsonEncode(
                    scanObservationRecord(scanCompletedAt(raw!, at + 1000)),
                  ) !=
                  expected['${batch['id']}/$mode']) {
            throw StateError('Timed source parity drift');
          }
          final status =
              released.decision?.status ?? PassageClearanceStatus.unavailable;
          if (status == PassageClearanceStatus.measuredClear &&
              (batch['physicalHazard'] == true || dispatch - at > 100000)) {
            throw StateError('Unsafe or stale clear');
          }
          samples.add({
            'round': round,
            'id': batch['id'],
            'mode': mode,
            'physicalHazard': batch['physicalHazard'],
            'pipelineUs': watch.elapsedMicroseconds,
            'ageAtDispatchUs': dispatch - at,
            'gate': released.status.name,
            'strictStatus': status.name,
            'unsafeContinue': false,
          });
        }
      }
      stdout.writeln('Synchronized passage round ${round + 1}/3');
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    nnReceipt = await neural?.close();
  }
  final summaries = <String, Object?>{};
  for (final mode in ['single', 'rig']) {
    final rows = samples.where((r) => r['mode'] == mode).toList();
    final hazards = rows.where((r) => r['physicalHazard'] == true).toList();
    final clear = rows.where((r) => r['physicalHazard'] == false).toList();
    summaries[mode] = {
      'samples': rows.length,
      'pipeline': scanPercentiles(rows.map((r) => r['pipelineUs'] as int)),
      'ageAtDispatch': scanPercentiles(
        rows.map((r) => r['ageAtDispatchUs'] as int),
      ),
      'maximumAgeMs':
          rows
              .map((r) => r['ageAtDispatchUs'] as int)
              .reduce((a, b) => a > b ? a : b) /
          1000,
      'expired': rows
          .where((r) => (r['ageAtDispatchUs'] as int) > 100000)
          .length,
      'admittedClear': clear
          .where((r) => r['strictStatus'] == 'measuredClear')
          .length,
      'passableTrials': clear.length,
      'blockedHazards': hazards
          .where((r) => r['strictStatus'] == 'blocked')
          .length,
      'fallbackStoppedHazards': hazards
          .where((r) => r['strictStatus'] == 'unavailable')
          .length,
      'hazardTrials': hazards.length,
      'unsafeContinue': 0,
    };
  }
  final report = {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'runtimeWired': false,
    'currentAgeLimitUs': 100000,
    'captureToCommandMeasured': false,
    'mode': args.contains('--nn') ? 'concurrent-NCNN' : 'no-NN',
    'preloadMs': preload.elapsedMilliseconds,
    'manifestSha256': fixture.modelHash,
    'geometry': geometry,
    'samples': samples,
    'summary': summaries,
    'neuralCompetition': nnReceipt,
    'scope':
        'preloaded synthetic source/evaluator/age-gate; capture, decode, primary inference, tracker, planner and feedback excluded',
    'sources': {
      for (final p in [
        'tool/model_benchmark/profile_synchronized_passage.dart',
        'test/harness/synchronized_passage_fixture.dart',
        'lib/safety/perception/camera_synchronized_envelope_source.dart',
        'lib/safety/runtime/camera_scan_age_gate.dart',
      ])
        p: bodySha(p),
    },
  };
  File(args[index + 1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(summaries));
}
