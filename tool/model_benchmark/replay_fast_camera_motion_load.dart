import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_load_worker.dart';
import '../../test/harness/camera_visible_passage_fixture.dart';
import 'fast_camera_motion_fixture.dart';
import 'profile_fast_camera_motion.dart' show fastPercentiles;

// The neural worker is only a competing slow branch in this measurement.
// Its output never supplies fast-branch identity, capture time, depth or pose.
class _NeuralWorker {
  final Process process;
  final StreamIterator<String> lines;
  _NeuralWorker(this.process, this.lines);
  static Future<_NeuralWorker> start() async {
    final p = await Process.start('tools/ncnn/.venv/Scripts/python.exe', [
      '-u',
      'tool/model_benchmark/camera_processing_ncnn_worker.py',
    ]);
    p.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 60)) ||
          (jsonDecode(lines.current) as Map)['ready'] != true) {
        throw StateError('Live pinned NN unavailable');
      }
      return _NeuralWorker(p, lines);
    } catch (_) {
      p.kill();
      await lines.cancel();
      rethrow;
    }
  }

  Future<Map> infer(String layout, int frame) async {
    process.stdin.writeln(jsonEncode({'layoutId': layout, 'frameId': frame}));
    await process.stdin.flush();
    if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('Neural worker exited');
    }
    final result = jsonDecode(lines.current) as Map;
    if (result['ok'] != true ||
        result['outputMatchesPinned'] != true ||
        result['layoutId'] != layout ||
        result['frameId'] != frame) {
      throw StateError('Pinned NN identity/output drift');
    }
    return result;
  }

  Future<void> close() async {
    await process.stdin.close();
    await lines.cancel();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (code != 0) throw StateError('Neural worker failed');
  }
}

Future<void> main(List<String> args) async {
  if ((args.length != 2 && args.length != 3) ||
      !['--functional', '--elapsed', '--elapsed-nn'].contains(args[0])) {
    throw ArgumentError(
      'Usage: replay_fast_camera_motion --functional|--elapsed|--elapsed-nn output.json',
    );
  }
  final functional = args[0] == '--functional',
      withNN = args[0] == '--elapsed-nn';
  final nativePath = args.length == 3 ? File(args[2]).absolute.path : null;
  final fixture = VisibleFixture(root: fastCorpus);
  final reference = visibleJson(
    'docs/_baseline_logs/camera_processing_parity.json',
  );
  final layouts = (fixture.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>();
  final inputs = <String, List<FastMetricMotionInput>>{};
  final preload = Stopwatch()..start();
  for (final layout in layouts) {
    inputs[layout['id'] as String] = fixture
        .frames(layout)
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId))
        .map((f) => fastInput(fixture, layout, f))
        .toList();
  }
  preload.stop();
  final neural = withNN ? await _NeuralWorker.start() : null;
  final rows = <Map<String, Object?>>[];
  final computations = <Map<String, Object?>>[];
  var diagnosticOverflow = 0;
  var preparedFrames = 0, preparationComputeUs = 0;
  try {
    for (final layout in layouts) {
      final id = layout['id'] as String, frames = inputs[id]!;
      var manualNow = frames.first.camera.depth.capturedAtUs + 2000;
      final stopwatch = Stopwatch();
      int clock() => functional
          ? manualNow
          : frames.first.camera.depth.capturedAtUs +
                2000 +
                stopwatch.elapsedMicroseconds;
      final worker =
          await CameraFastMotionLoadWorker.start(
              calibration: fixture.calibration(),
              rgbContract: fastRgbContract,
              clockUs: clock,
              nativeLibraryPath: nativePath,
            )
            ..beginSession(1);
      stopwatch.start();
      try {
        for (final input in frames) {
          final f = input.camera.depth;
          if (functional) {
            manualNow = f.capturedAtUs + 2000;
          } else {
            final wait = f.capturedAtUs + 2000 - clock();
            if (wait > 0) {
              await Future<void>.delayed(Duration(microseconds: wait));
            }
          }
          var nnCompleted = false, ownerEvents = 0;
          final nnStart = clock();
          final nnFuture = neural?.infer(id, f.frameId).then((r) {
            nnCompleted = true;
            return (r: r, at: clock());
          });
          final ticker = Timer.periodic(
            const Duration(milliseconds: 5),
            (_) => ownerEvents++,
          );
          final task = worker.offer(input);
          final computed = await task;
          final completed = clock();
          final released = worker.release(computed);
          final at = clock();
          ticker.cancel();
          final nnStillRunningAtFastRelease = withNN && !nnCompleted;
          final expected =
              (reference['frames'] as List)
                      .cast<Map<String, dynamic>>()
                      .singleWhere(
                        (r) => r['layoutId'] == id && r['frameId'] == f.frameId,
                      )['result']
                  as Map;
          if (released.admitted && released.result != null) {
            final old = (reference['frames'] as List)
                .cast<Map<String, dynamic>>()
                .singleWhere(
                  (r) => r['layoutId'] == id && r['frameId'] == f.frameId,
                )['result'];
            if (functional &&
                jsonEncode(released.result!.toDiagnosticMap()) !=
                    jsonEncode(old)) {
              throw StateError(
                'Worker full diagnostic parity drift $id/${f.frameId}',
              );
            }
          } else if (functional) {
            throw StateError('Functional worker rejected $id/${f.frameId}');
          }
          final nnResult = await nnFuture;
          rows.add({
            'layoutId': id,
            'frameId': f.frameId,
            'status': released.status.name,
            'admitted': released.admitted,
            'ageAtReleaseUs': at - f.capturedAtUs,
            'workerComputeUs': released.workerComputeUs,
            if (!functional) 'packingUs': worker.lastPackingUs,
            if (!functional)
              'stagesUs': released.workerComputeUs > 0
                  ? worker.lastStagesUs
                  : null,
            'ownerEventsDuringCompute': ownerEvents,
            'result': released.result?.toDiagnosticMap(),
            'nnStillRunningAtFastRelease': nnStillRunningAtFastRelease,
            'nnAgeAtCompletionUs': nnResult == null
                ? null
                : nnResult.at - f.capturedAtUs,
            'nnWaitMs': nnResult == null
                ? null
                : (nnResult.at - nnStart) / 1000,
            'completionOffsetUs': functional
                ? null
                : completed - f.capturedAtUs,
            if (!functional)
              'functionalReferenceAddsMotionRisk': expected['addsMotionRisk'],
          });
        }
        stdout.writeln('Fast ${args[0]} $id completed');
      } finally {
        await worker.close();
        preparedFrames += worker.preparedFrames;
        preparationComputeUs += worker.preparationComputeUs;
        computations.addAll(
          worker.computationDiagnostics.map((r) => {'layoutId': id, ...r}),
        );
        diagnosticOverflow += worker.diagnosticOverflow;
      }
    }
  } finally {
    await neural?.close();
  }
  final live = rows.where((r) => r['admitted'] == true).toList();
  if (live.any((r) => (r['ageAtReleaseUs'] as int) > 100000)) {
    throw StateError('Stale release');
  }
  final report = {
    'scope': functional
        ? 'known regression independent worker fixed capture+2ms; not latency'
        : 'desktop AOT/JIT elapsed independent motion worker; preloaded synthetic RGB/metric depth; no capture or user delivery',
    'promotionAllowed': false,
    'newIndependentHoldout': false,
    'nnAwaitedByFastBranch': false,
    'neuralBranchLive': withNN,
    'captureToCommandMeasured': false,
    'currentAgeLimitUs': 100000,
    if (!functional) 'nativeMatcher': nativePath != null,
    'runtimeVersion': functional ? null : Platform.version,
    'executable': functional ? null : Platform.resolvedExecutable,
    'fixtureLoadMs': functional ? null : preload.elapsedMicroseconds / 1000,
    'summary': {
      'frames': rows.length,
      'admitted': live.length,
      'expiredOrRejected': rows.length - live.length,
      'freshMotionRiskFrames': live
          .where((r) => (r['result'] as Map)['addsMotionRisk'] == true)
          .length,
      'approachRiskPairs': live
          .where(
            (r) =>
                (r['layoutId'] as String).startsWith(
                  'test-scale-motion-approach',
                ) &&
                (r['result'] as Map)['addsMotionRisk'] == true,
          )
          .length,
      'staleReleases': 0,
      'freeSpaceCertifiedFrames': live
          .where((r) => (r['result'] as Map)['freeSpaceCertified'] == true)
          .length,
      'fastReleasedBeforeNeuralCompletion': rows
          .where((r) => r['nnStillRunningAtFastRelease'] == true)
          .length,
      'ownerEventsDuringCompute': rows.fold<int>(
        0,
        (sum, r) => sum + (r['ownerEventsDuringCompute'] as int),
      ),
      'ageAtReleaseMs': functional
          ? null
          : fastPercentiles(
              rows.map((r) => (r['ageAtReleaseUs'] as int) / 1000),
            ),
      'workerComputeMs': functional
          ? null
          : fastPercentiles(
              rows
                  .where((r) => (r['workerComputeUs'] as int) > 0)
                  .map((r) => (r['workerComputeUs'] as int) / 1000),
            ),
      'workerComputationsNotReturnedBeforeDeadline': rows
          .where((r) => (r['workerComputeUs'] as int) == 0)
          .length,
      if (!functional) 'numericPreparationFrames': preparedFrames,
      if (!functional) 'numericPreparationTotalMs': preparationComputeUs / 1000,
      if (!functional)
        'referenceMotionRiskFrames': rows
            .where((r) => r['functionalReferenceAddsMotionRisk'] == true)
            .length,
      if (!functional)
        'referenceRiskFramesLostToTimingOrPairReset': rows
            .where(
              (r) =>
                  r['functionalReferenceAddsMotionRisk'] == true &&
                  (r['admitted'] != true ||
                      (r['result'] as Map?)?['addsMotionRisk'] != true),
            )
            .length,
    },
    'frames': rows,
    if (!functional) 'computationDiagnostics': computations,
    if (!functional) 'diagnosticOverflow': diagnosticOverflow,
  };
  if (functional) {
    for (final r in rows) {
      r.remove('workerComputeUs');
      r.remove('ownerEventsDuringCompute');
      r.remove('completionOffsetUs');
    }
    (report['summary'] as Map).remove('ownerEventsDuringCompute');
  }
  final file = File(args[1])..parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report['summary']));
}
