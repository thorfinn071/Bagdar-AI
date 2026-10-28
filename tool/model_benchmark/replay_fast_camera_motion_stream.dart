import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/core/performance/perception_scheduler.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_load_worker.dart'
    as control;
import 'package:bagdar/safety/runtime/camera_fast_motion_packed_worker.dart';

import '../../test/harness/camera_visible_passage_fixture.dart';
import 'fast_camera_motion_fixture.dart';
import 'independent_replay_feed.dart';
import 'pinned_depth_load_worker.dart';
import 'profile_fast_camera_motion.dart' show fastPercentiles;
import 'replay_depth_load_lane.dart';

Future<void> main(List<String> arguments) async {
  final useControl = arguments.contains('--control');
  final args = arguments.where((arg) => arg != '--control').toList();
  if ((args.length != 2 && args.length != 3) ||
      !['--functional', '--elapsed', '--elapsed-nn'].contains(args.first)) {
    throw ArgumentError(
      'Usage: replay_fast_camera_motion_stream --functional|--elapsed|--elapsed-nn '
      'output.json [native.dll] [--control]',
    );
  }
  final functional = args.first == '--functional';
  final withNN = args.first == '--elapsed-nn';
  if (!functional && File(args[1]).existsSync()) {
    throw StateError('Use a new output path; elapsed evidence is write-once');
  }
  final nativePath = args.length == 3 ? File(args[2]).absolute.path : null;
  final fixture = VisibleFixture(root: fastCorpus);
  final reference = visibleJson(
    'docs/_baseline_logs/camera_processing_parity.json',
  );
  final expected = <String, Map>{
    for (final row in (reference['frames'] as List).cast<Map>())
      '${row['layoutId']}/${row['frameId']}': row['result'] as Map,
  };
  final layouts = (fixture.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>();
  final inputs = <String, List<FastMetricMotionInput>>{};
  for (final layout in layouts) {
    inputs[layout['id'] as String] = fixture
        .frames(layout)
        .where(
          (frame) =>
              (layout['decisionFrameIds'] as List).contains(frame.frameId),
        )
        .map((frame) => fastInput(fixture, layout, frame))
        .toList();
  }
  final neural = withNN ? await PinnedDepthLoadWorker.start() : null;
  final rows = <Map<String, Object?>>[];
  final computations = <Map<String, Object?>>[];
  final neuralJobs = <Map<String, Object?>>[];
  var nnOffered = 0, nnSkipped = 0, nnMaximumActive = 0;
  var maxFastActive = 0, maxFastPending = 0;
  try {
    for (final layout in layouts) {
      final id = layout['id'] as String, frames = inputs[id]!;
      final watch = Stopwatch();
      var manualNow = frames.first.camera.depth.capturedAtUs + 2000;
      final clockBase = manualNow;
      int clock() =>
          functional ? manualNow : clockBase + watch.elapsedMicroseconds;
      // Both versions use exactly the same caller, capture pacing and load lane.
      final dynamic worker = useControl
          ? await control.CameraFastMotionLoadWorker.start(
              calibration: fixture.calibration(),
              rgbContract: fastRgbContract,
              clockUs: clock,
              nativeLibraryPath: nativePath,
            )
          : await CameraFastMotionPackedWorker.start(
              calibration: fixture.calibration(),
              rgbContract: fastRgbContract,
              clockUs: clock,
              nativeLibraryPath: nativePath,
            );
      worker.beginSession(1);
      final depthLane = neural == null
          ? null
          : ReplayDepthLoadLane(infer: neural.infer, clockUs: clock);
      depthLane?.beginSession(1);
      final sequenceRows = <int, Map<String, Object?>>{};
      watch.start();
      Future<void> capture(FastMetricMotionInput input) async {
        final f = input.camera.depth;
        final callbackAt = clock();
        final job = depthLane?.offer(
          id,
          PerceptionFrameIdentity(
            generation: f.sessionGeneration,
            frameNumber: f.frameId,
            width: f.width,
            height: f.height,
            rotationDegrees: 0,
            mirrored: false,
            timing: CallbackFrameTiming.forTesting(
              f.capturedAtUs,
              () => clock() - f.capturedAtUs,
            ),
          ),
        );
        final offeredAt = clock();
        final task = worker.offer(input) as Future<FastMotionOutcome>;
        if ((worker.inFlightCount as int) > maxFastActive) {
          maxFastActive = worker.inFlightCount as int;
        }
        if ((worker.pendingCount as int) > maxFastPending) {
          maxFastPending = worker.pendingCount as int;
        }
        final outcome = await task;
        final released = worker.release(outcome) as FastMotionOutcome;
        final at = clock();
        final diagnostic = released.result?.toDiagnosticMap();
        final old = expected['$id/${f.frameId}']!;
        if (functional &&
            (!released.admitted || jsonEncode(diagnostic) != jsonEncode(old))) {
          throw StateError('Stream full diagnostic drift $id/${f.frameId}');
        }
        if (released.admitted && at - f.capturedAtUs > 100000) {
          throw StateError('Stream admitted stale authority');
        }
        sequenceRows[f.frameId] = {
          'layoutId': id,
          'frameId': f.frameId,
          'split': layout['split'],
          'capturedAtUs': f.capturedAtUs,
          'callbackAgeUs': callbackAt - f.capturedAtUs,
          'offerAgeUs': offeredAt - f.capturedAtUs,
          'ageAtReleaseUs': at - f.capturedAtUs,
          'status': released.status.name,
          'admitted': released.admitted,
          'workerComputeUs': released.workerComputeUs,
          'result': diagnostic,
          'functionalReferenceAddsMotionRisk': old['addsMotionRisk'],
          'fullDiagnosticEqual': functional ? true : null,
          'neuralStartedForThisCapture': job != null,
          'neuralActiveAtFastRelease': depthLane?.busy ?? false,
        };
      }

      try {
        if (functional) {
          for (final input in frames) {
            manualNow = input.camera.depth.capturedAtUs + 2000;
            await capture(input);
          }
        } else {
          await feedIndependentCaptures(
            frames: frames,
            capturedAtUs: (input) => input.camera.depth.capturedAtUs,
            clockUs: clock,
            onCapture: capture,
          );
        }
        // Joining the load lane happens after every scheduled capture/release.
        await depthLane?.drain();
        rows.addAll(
          frames.map((input) => sequenceRows[input.camera.depth.frameId]!),
        );
        if (depthLane != null) {
          nnOffered += depthLane.offered;
          nnSkipped += depthLane.skipped;
          if (depthLane.maximumActive > nnMaximumActive) {
            nnMaximumActive = depthLane.maximumActive;
          }
          neuralJobs.addAll(depthLane.jobs.map((job) => job.toMap()));
        }
        stdout.writeln(
          'Stream ${useControl ? 'control' : 'packed'} ${args.first} $id completed',
        );
      } finally {
        try {
          await depthLane?.drain();
        } finally {
          await worker.close();
          computations.addAll(
            (worker.computationDiagnostics as List)
                .cast<Map<String, Object?>>()
                .map((r) => {'layoutId': id, ...r}),
          );
        }
      }
    }
  } finally {
    await neural?.close();
  }
  final live = rows.where((r) => r['admitted'] == true).toList();
  bool risk(Map r) =>
      r['admitted'] == true && (r['result'] as Map?)?['addsMotionRisk'] == true;
  final referenceRisk = rows
      .where((r) => r['functionalReferenceAddsMotionRisk'] == true)
      .toList();
  final testRisk = referenceRisk.where((r) => r['split'] == 'test').toList();
  final summary = {
    'frames': rows.length,
    'admitted': live.length,
    'expiredOrRejected': rows.length - live.length,
    'captureCallbacksOlderThan100Ms': rows
        .where((r) => (r['callbackAgeUs'] as int) > 100000)
        .length,
    'offersOlderThan100Ms': rows
        .where((r) => (r['offerAgeUs'] as int) > 100000)
        .length,
    'referenceMotionRiskFrames': referenceRisk.length,
    'freshMotionRiskFrames': live.where(risk).length,
    'referenceRiskFramesLostToTimingOrPairReset': referenceRisk
        .where((r) => !risk(r))
        .length,
    'testReferenceRiskFrames': testRisk.length,
    'testTimelyRiskFrames': testRisk.where(risk).length,
    'unexpectedMotionRiskFrames': live
        .where((r) => risk(r) && r['functionalReferenceAddsMotionRisk'] != true)
        .length,
    'admittedFullDiagnosticMatches': live
        .where(
          (r) =>
              jsonEncode(r['result']) ==
              jsonEncode(expected['${r['layoutId']}/${r['frameId']}']),
        )
        .length,
    'actualStaleAdmissions': live
        .where((r) => (r['ageAtReleaseUs'] as int) > 100000)
        .length,
    'freeSpaceCertifiedFrames': live
        .where((r) => (r['result'] as Map)['freeSpaceCertified'] == true)
        .length,
    'maximumFastActive': maxFastActive,
    'maximumFastPending': maxFastPending,
    'ageAtReleaseMs': functional
        ? null
        : fastPercentiles(rows.map((r) => (r['ageAtReleaseUs'] as int) / 1000)),
    'callbackAgeMs': functional
        ? null
        : fastPercentiles(rows.map((r) => (r['callbackAgeUs'] as int) / 1000)),
    'neuralOffered': nnOffered,
    'neuralCompleted': neuralJobs.length,
    'neuralSkipped': nnSkipped,
    'neuralMaximumActive': nnMaximumActive,
    'neuralQueuedFrames': 0,
    'neuralSchedulingRejected': neuralJobs
        .where((r) => r['status'] != 'validated_load_only')
        .length,
    'neuralActiveAtFastRelease': rows
        .where((r) => r['neuralActiveAtFastRelease'] == true)
        .length,
    'neuralOutputMatchesPinned': neuralJobs
        .where((r) => (r['output'] as Map?)?['outputMatchesPinned'] == true)
        .length,
  };
  final report = {
    'scope':
        'known 109-frame synthetic stream; independent callback pacing and app depth-lane admission; preloaded RGB/metric-depth/pose',
    'version': useControl ? 'frozen-load-control' : 'packed-allocation-fix',
    'functional': functional,
    'nativeMatcher': nativePath != null,
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'newIndependentHoldout': false,
    'captureToCommandMeasured': false,
    'neuralModels': withNN ? ['midas-small-ncnn'] : [],
    'captureDeliveryWaitsForNeural': false,
    'captureDeliveryWaitsForFastCompletion': functional,
    'currentAgeLimitUs': 100000,
    'runtimeVersion': Platform.version,
    'executable': Platform.resolvedExecutable,
    'summary': summary,
    'frames': rows,
    'computationDiagnostics': computations,
    'neuralJobs': neuralJobs,
  };
  final file = File(args[1])..parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(summary));
}
