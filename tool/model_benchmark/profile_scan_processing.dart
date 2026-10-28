import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_indexed_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';

import '../../test/harness/blender_scan_complete_fixture.dart';
import '../../test/harness/blender_visible_body_fixture.dart';
import 'scan_processing_support.dart';

class _NeuralLoad {
  final Process process;
  final StreamIterator<String> lines;
  final Map ready;
  _NeuralLoad(this.process, this.lines, this.ready);

  static Future<_NeuralLoad> start() async {
    final process = await Process.start('tools/ncnn/.venv/Scripts/python.exe', [
      '-u',
      'tool/model_benchmark/scan_processing_ncnn_load.py',
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 60))) {
        throw StateError('Neural worker exited before warmup');
      }
      final ready = jsonDecode(lines.current) as Map;
      if (ready['ready'] != true) throw StateError('Neural worker not ready');
      process.stdin.writeln(jsonEncode({'command': 'start'}));
      await process.stdin.flush();
      if (!await lines.moveNext().timeout(const Duration(seconds: 30)) ||
          (jsonDecode(lines.current) as Map)['started'] != true) {
        throw StateError('Neural load did not start');
      }
      return _NeuralLoad(process, lines, ready);
    } catch (_) {
      process.kill();
      await lines.cancel();
      rethrow;
    }
  }

  Future<Map<String, Object?>> close() async {
    try {
      process.stdin.writeln(jsonEncode({'command': 'stop'}));
      await process.stdin.flush();
      await process.stdin.close();
      if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
        throw StateError('Neural load exited without receipt');
      }
      final result = jsonDecode(lines.current) as Map;
      if (result['stopped'] != true ||
          result['allOutputsMatchPinned'] != true ||
          (result['inferences'] as int) < 1) {
        throw StateError('Neural load/output validation failed');
      }
      await lines.cancel();
      if (await process.exitCode.timeout(const Duration(seconds: 30)) != 0) {
        throw StateError('Neural process failed');
      }
      return {'ready': ready, 'result': result};
    } finally {
      process.kill();
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || args[0] != '--output') {
    throw ArgumentError(
      'Usage: profile_scan_processing --output receipt.json [--nn] [--rounds=N]',
    );
  }
  final output = args[1], withNN = args.contains('--nn');
  final rounds = int.parse(
    args
        .firstWhere(
          (a) => a.startsWith('--rounds='),
          orElse: () => '--rounds=3',
        )
        .split('=')
        .last,
  );
  if (rounds < 1 || rounds > 10 || File(output).existsSync()) {
    throw ArgumentError('Invalid rounds or existing write-once output');
  }
  final preload = Stopwatch()..start();
  final fixture = ScanCompleteFixture();
  final layouts = (fixture.manifest['layouts'] as List).cast<Map>().toList();
  final inputs = <String, List<CameraHeightEnvelopeFrame>>{
    for (final l in layouts) l['sceneId'] as String: fixture.frames(l),
  };
  preload.stop();
  final parity = <Map<String, Object?>>[];
  final expected = <String, String>{};
  // Untimed geometry control and warmup. The 3 s diagnostic clock does not
  // grant admission and is never used for the elapsed pipeline measurements.
  for (final layout in layouts) {
    final id = layout['sceneId'] as String, frames = inputs[id]!;
    final c = fixture.calibration(id);
    final context = scanContext(
      frames.last,
      frames.last.depth.capturedAtUs + 2000,
    );
    String? original;
    PassageClearanceResult? geometry;
    for (final implementation in ['frozen', 'indexed']) {
      final source = scanSource(
        implementation,
        c,
        frames,
        context.nowUs - 1000,
      );
      final observation = source.observationFor(context)!;
      final encoded = jsonEncode(scanObservationRecord(observation));
      original ??= encoded;
      if (encoded != original) throw StateError('Observation drift: $id');
      geometry = scanDecision(c, context, observation, strict: false);
      expected[id] = original;
    }
    // Scoring labels are read only after both producer variants have run.
    final hazard = scanHazard(fixture, id);
    if (geometry!.status !=
        (hazard
            ? PassageClearanceStatus.blocked
            : PassageClearanceStatus.measuredClear)) {
      throw StateError('Geometry regression: $id');
    }
    final current = frames
        .where(
          (f) =>
              context.nowUs - f.depth.capturedAtUs <=
              CameraScanAgeGate.maximumAgeUs,
        )
        .toList();
    final currentSource = scanSource(
      'indexed',
      c,
      current,
      context.nowUs - 1000,
    );
    final currentGeometry = scanDecision(
      c,
      context,
      currentSource.observationFor(context)!,
      strict: false,
    );
    parity.add({
      'sceneId': id,
      'physicalHazard': hazard,
      'identicalObservation': true,
      'geometryStatus': geometry.status.name,
      'captureSpanUs':
          frames.last.depth.capturedAtUs - frames.first.depth.capturedAtUs,
      'currentWindowViews': current.length,
      'currentWindowGeometryStatus': currentGeometry.status.name,
    });
  }
  stdout.writeln(
    'Geometry parity: ${parity.length}/${layouts.length}; preloaded ${preload.elapsedMilliseconds} ms',
  );
  final neural = withNN ? await _NeuralLoad.start() : null;
  Map<String, Object?>? neuralReceipt;
  final samples = <Map<String, Object?>>[];
  try {
    for (var round = 0; round < rounds; round++) {
      final order = round.isEven
          ? ['frozen', 'indexed']
          : ['indexed', 'frozen'];
      for (final layout in layouts) {
        final id = layout['sceneId'] as String, frames = inputs[id]!;
        final c = fixture.calibration(id);
        final hazard =
            parity.singleWhere((p) => p['sceneId'] == id)['physicalHazard']
                as bool;
        for (final implementation in order) {
          final watch = Stopwatch()..start();
          // Original capture times retained. Each sample is an independent
          // replay anchored at arrival of its last view, not a new acquisition.
          final anchor = frames.last.depth.capturedAtUs + 2000;
          int clock() => anchor + watch.elapsedMicroseconds;
          final start = clock();
          final context = scanContext(frames.last, start);
          final source = scanSource(implementation, c, frames, start);
          final built = clock();
          final observation = source.observationFor(context)!;
          final observed = clock();
          final completed = scanCompletedAt(observation, observed);
          final decision = scanDecision(
            c,
            scanContext(frames.last, clock()),
            completed,
          );
          final evaluated = clock();
          var called = false;
          final gate = CameraScanAgeGate(clockUs: clock)
            ..beginSession(frames.last.depth.sessionGeneration);
          final outcome = gate.process(
            oldestCaptureUs: frames.first.depth.capturedAtUs,
            captureContext: context,
            calibration: c,
            request: pairedBodyRequest,
            compute: () {
              called = true;
              return completed;
            },
          );
          final released = gate.release(outcome);
          final dispatch = clock();
          watch.stop();
          if (called ||
              released.status != CameraScanAgeStatus.expiredBeforeCompute ||
              released.observation != null ||
              released.decision != null ||
              decision.status != PassageClearanceStatus.unavailable ||
              !decision.reasons.contains(
                PassageClearanceReason.staleObservation,
              )) {
            throw StateError('Stale full scan gained authority: $id');
          }
          // Compare outside timing; normalize only producer completion metadata
          // to the original warmup value. Capture times are never changed.
          final comparable = scanCompletedAt(
            observation,
            frames.last.depth.capturedAtUs + 1000,
          );
          if (jsonEncode(scanObservationRecord(comparable)) != expected[id]) {
            throw StateError('Timed observation drift: $id');
          }
          samples.add({
            'round': round,
            'sceneId': id,
            'implementation': implementation,
            'physicalHazard': hazard,
            'sourceBuildUs': built - start,
            'observationUs': observed - built,
            'evaluationUs': evaluated - observed,
            'dispatchGuardUs': dispatch - evaluated,
            'pipelineUs': dispatch - start,
            'oldestAgeAtStartUs': start - frames.first.depth.capturedAtUs,
            'oldestAgeAtDispatchUs': dispatch - frames.first.depth.capturedAtUs,
            'latestAgeAtDispatchUs': dispatch - frames.last.depth.capturedAtUs,
            'strictStatus': decision.status.name,
            'strictReasons': decision.reasons.map((r) => r.name).toList(),
            'releaseStatus': released.status.name,
            'shadowDecision': 'stopUnavailable',
            'unsafeContinue': false,
            'indexedStagesUs':
                source is CameraIndexedHeightEnvelopePassageSource
                ? source.stageComputeUs
                : null,
          });
        }
      }
      stdout.writeln(
        'Measured round ${round + 1}/$rounds (${withNN ? 'continuous NCNN' : 'no NN'})',
      );
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    neuralReceipt = await neural?.close();
  }
  final summaries = <String, Object?>{};
  for (final implementation in ['frozen', 'indexed']) {
    final rows = samples
        .where((r) => r['implementation'] == implementation)
        .toList();
    final hazards = rows.where((r) => r['physicalHazard'] == true).length;
    summaries[implementation] = {
      'pipeline': scanPercentiles(rows.map((r) => r['pipelineUs'] as int)),
      'sourceBuild': scanPercentiles(
        rows.map((r) => r['sourceBuildUs'] as int),
      ),
      'oldestAgeAtDispatch': scanPercentiles(
        rows.map((r) => r['oldestAgeAtDispatchUs'] as int),
      ),
      'latestAgeAtDispatch': scanPercentiles(
        rows.map((r) => r['latestAgeAtDispatchUs'] as int),
      ),
      'strictStaleRejected': rows.length,
      'hazardDecisions': hazards,
      'missedTimelyGeometricHazardDecisions': hazards,
      'fallbackStopsOnHazards': hazards,
      'falseStopsOnPassable': rows.length - hazards,
      'unsafeContinue': 0,
      'captureGateReached': false,
      'computeWithin100ms': rows
          .where((r) => (r['pipelineUs'] as int) <= 100000)
          .length,
    };
  }
  writeScanReceipt(output, {
    'schemaVersion': 1,
    'passed': true,
    'mode': withNN ? 'elapsed-nn' : 'elapsed',
    'runtime': Platform.version,
    'executableSha256': bodySha(Platform.resolvedExecutable),
    'scope':
        'preloaded known frozen Blender geometry; source construction + one observation + strict evaluation + shadow dispatch guard; original 2.2 s capture span; excludes physical capture, decode/hash loading, phone transport, active planner/audio/haptics',
    'captureToCommandMeasured': false,
    'runtimeWired': false,
    'promotionAllowed': false,
    'deviceRuntime': 'not_run',
    'controlledWalking': 'not_run',
    'currentAgeLimitUs': 100000,
    'rounds': rounds,
    'fixtureLoadUs': preload.elapsedMicroseconds,
    'manifestSha256': fixture.modelHash,
    'baselineCoreSha256': bodySha(
      'docs/_baseline_logs/blender_scan_complete_core_rc_v1.json',
    ),
    'sources': {
      for (final path in [
        'lib/safety/perception/camera_indexed_height_envelope_passage_source.dart',
        'lib/safety/runtime/camera_scan_age_gate.dart',
        'tool/model_benchmark/scan_processing_support.dart',
        'tool/model_benchmark/profile_scan_processing.dart',
        'tool/model_benchmark/scan_processing_ncnn_load.py',
        'test/camera_indexed_scan_replay_test.dart',
        'test/camera_scan_age_gate_test.dart',
        'docs/blender-scan-processing-protocol-2026-10-04.md',
      ])
        path: bodySha(path),
    },
    'neuralLoad': neuralReceipt,
    'geometryParity': parity,
    'summaries': summaries,
    'samples': samples,
  });
  stdout.writeln(jsonEncode(summaries));
}
