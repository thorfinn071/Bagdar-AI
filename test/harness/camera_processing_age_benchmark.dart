import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_cached_scale_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/runtime/camera_processing_age_gate.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/model_benchmark/profile_camera_processing.dart';
import 'camera_visible_passage_fixture.dart';

class ProcessingNcnnWorker {
  final Process process;
  final StreamIterator<String> lines;
  final Map<String, dynamic> metadata;
  ProcessingNcnnWorker(this.process, this.lines, this.metadata);

  static Future<ProcessingNcnnWorker> start() async {
    final process = await Process.start('tools/ncnn/.venv/Scripts/python.exe', [
      '-u',
      'tool/model_benchmark/camera_processing_ncnn_worker.py',
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await lines.moveNext().timeout(const Duration(seconds: 60))) {
      throw StateError('NCNN worker did not start');
    }
    final ready = jsonDecode(lines.current) as Map<String, dynamic>;
    if (ready['ready'] != true) throw StateError('NCNN worker not ready');
    return ProcessingNcnnWorker(process, lines, ready);
  }

  Future<Map<String, dynamic>> infer(String layoutId, int frameId) async {
    process.stdin.writeln(
      jsonEncode({'layoutId': layoutId, 'frameId': frameId}),
    );
    await process.stdin.flush();
    if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('NCNN worker exited');
    }
    final result = jsonDecode(lines.current) as Map<String, dynamic>;
    if (result['ok'] != true ||
        result['layoutId'] != layoutId ||
        result['frameId'] != frameId ||
        result['outputMatchesPinned'] != true) {
      throw StateError('Live NCNN mismatch: $result');
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
    if (code != 0) throw StateError('NCNN worker failed: $code');
  }
}

/// Functional, injected-overload, and measured live-NCNN modes stay separate.
/// All fixture IO is preloaded; elapsed mode includes worker IPC/validation and
/// actual computation, but no phone capture, transport, rendering or feedback.
Future<Map<String, Object?>> runProcessingAgeReplay({
  String mode = 'functional',
  bool write = false,
  bool check = false,
}) async {
  if (![
    'functional',
    'overload',
    'runtime-overrun',
    'measured',
  ].contains(mode)) {
    throw ArgumentError.value(mode);
  }
  final fixture = VisibleFixture(root: processingCorpus);
  final baseline = visibleJson('docs/_baseline_logs/camera_scale_motion.json');
  final all = (fixture.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>()
      .where((l) => l['split'] == 'test')
      .toList();
  final prepared = <String, List<CameraMetricMotionInput>>{},
      raw = <String, List<List<double>>>{};
  final exact = <String, List<CameraVisibleDepthFrame>>{};
  final load = Stopwatch()..start();
  for (final layout in all) {
    final id = layout['id'] as String;
    exact[id] = fixture.frames(layout);
    final frames = exact[id]!
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId))
        .toList();
    prepared[id] = frames
        .map((f) => processingInput(fixture, layout, f))
        .toList();
    raw[id] = frames.map((f) => fixture.raw(layout, f.frameId)).toList();
  }
  load.stop();
  final worker = mode == 'measured' ? await ProcessingNcnnWorker.start() : null;
  final sequences = <Map<String, Object?>>[];
  try {
    for (final layout in all) {
      final id = layout['id'] as String, inputs = prepared[id]!;
      final previous = (baseline['sequences'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (s) => s['layoutId'] == id && s['mode'] == 'scale-motion',
          );
      final expected = {
        for (final d
            in (previous['decisions'] as List).cast<Map<String, dynamic>>())
          d['frameId']: d,
      };
      var manualNow = visibleStamp + 2000;
      final watch = Stopwatch()..start();
      int clock() => mode == 'measured'
          ? visibleStamp + 2000 + watch.elapsedMicroseconds
          : manualNow;
      final calibration = fixture.calibration();
      final source = CameraCachedScaleMetricMotionSource(
        calibration: calibration,
        relativeModelHash: fixture.ncnn['modelBinSha256'] as String,
      );
      final gate = CameraProcessingAgeGate(
        clockUs: clock,
        compute: source.observe,
        invalidateProducer: source.invalidate,
      )..beginSession(1);
      final queue = CameraLatestFrameQueue()..beginSession(1);
      final scene = CameraMetricMotionShadowScene();
      final runtime =
          SpatialSafetyRuntime(
            healthCoordinator: CoreHealthCoordinator(),
            sceneModel: scene,
            shadowPassage: PassageClearanceShadowConfiguration(
              calibration: calibration,
              request: visibleRequest,
              policy: layout['staticSyntheticScan'] == true
                  ? visibleScanPolicy
                  : visibleSinglePolicy,
              requireCameraEvidence: true,
              associateCameraTracks: true,
              cameraTrackModelHash: fixture.ncnn['modelBinSha256'] as String,
            ),
          )..beginSession(
            1,
            now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1),
          );
      final stable = FrameStableGenericObstacleDetector(
        collectCameraSupport: true,
      );
      final tracker = GenericObstacleTracker();
      final rows = <Map<String, Object?>>[];
      var discardedClearDecisions = 0;
      var cursor = 0,
          staleApplications = 0,
          unsafe = 0,
          unjustified = 0,
          identityMatches = 0;
      SpatialRuntimeResult unavailable(String reason, bool moving) {
        gate.invalidate();
        return runtime.noteMissingObservation(
          providerId: 'camera-processing-age',
          providerState: SceneSensorState.stale,
          reason: reason,
          now: DateTime.fromMicrosecondsSinceEpoch(clock()),
          orientationValid: true,
          userMoving: moving,
        );
      }

      while (cursor < inputs.length || queue.pendingCount > 0) {
        if (mode == 'functional' || mode == 'runtime-overrun') {
          manualNow = inputs[cursor].camera.depth.capturedAtUs + 2000;
          queue.offer(inputs[cursor++], nowUs: manualNow);
        } else {
          if (queue.pendingCount == 0 &&
              cursor < inputs.length &&
              inputs[cursor].camera.depth.capturedAtUs > clock()) {
            final target = inputs[cursor].camera.depth.capturedAtUs + 2000;
            if (mode == 'measured') {
              final wait = target - clock();
              if (wait > 0) {
                await Future<void>.delayed(Duration(microseconds: wait));
              }
            } else {
              manualNow = target;
            }
          }
          while (cursor < inputs.length &&
              inputs[cursor].camera.depth.capturedAtUs <= clock()) {
            queue.offer(inputs[cursor++], nowUs: clock());
          }
        }
        final input = queue.takeLatest(nowUs: clock());
        if (input == null) {
          unavailable('pending_frame_expired', true);
          continue;
        }
        final f = input.camera.depth, index = inputs.indexOf(input);
        final moving = index == 0 || index == inputs.length - 1;
        final metadata = (layout['frames'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((r) => r['frameId'] == f.frameId);
        final started = clock(), total = Stopwatch()..start();
        final timing = <String, Object?>{};
        Map<String, dynamic>? inference;
        if (mode == 'overload') manualNow += 500000;
        if (worker != null) inference = await worker.infer(id, f.frameId);
        final producedAt = mode == 'functional'
            ? f.capturedAtUs + 1000
            : clock();
        timing['preprocessingMs'] = inference?['preprocessingMs'];
        timing['inferenceMs'] = inference?['inferenceMs'];
        SpatialRuntimeResult result;
        CameraProcessingOutcome? motion;
        String rejection = 'none';
        if (clock() - f.capturedAtUs >
            CameraProcessingAgeGate.maximumCurrentAgeUs) {
          rejection = 'expired_after_nn';
          result = unavailable(rejection, moving);
        } else {
          final normalTimer = Stopwatch()..start();
          final relative = DepthMapOps.normalizeRelativeProximity(
            Float32List.fromList(raw[id]![index]),
          );
          timing['normalizationMs'] = normalTimer.elapsedMicroseconds / 1000;
          final depth = DepthFrame(
            values: relative,
            confidence01: Float32List.fromList(List.filled(relative.length, 1)),
            width: 256,
            height: 256,
            timestampUs: f.capturedAtUs,
            provider: DepthProviderKind.ncnnRelative,
            semantics: DepthValueSemantics.relativeProximity,
            modelId: 'midas-small-ncnn',
            modelHash: fixture.ncnn['modelBinSha256'] as String,
            preprocessId: fixture.ncnn['preprocessId'] as String,
            cropTopFraction: 0,
            frameQuality: 1,
            alignedToImage: true,
          );
          final detectTimer = Stopwatch()..start();
          final detection = stable.detect(
            frame: depth,
            pitchDeg: (metadata['pitchDeg'] as num).toDouble(),
            rollDeg: (metadata['rollDeg'] as num).toDouble(),
            motion: moving ? MotionState.walking : MotionState.stationary,
            imageTimestampUs: f.capturedAtUs,
          );
          final tracks = tracker.update(
            observations: detection.observations,
            timestampUs: f.capturedAtUs,
            relative: true,
          );
          timing['detectorTrackerMs'] = detectTimer.elapsedMicroseconds / 1000;
          final reconstructionTimer = Stopwatch()..start();
          final staticScan = layout['staticSyntheticScan'] == true && index > 0;
          final passageSource = CameraPassageClearanceSource(
            calibration: calibration,
            request: visibleRequest,
            frames: staticScan ? [...exact[id]!.sublist(1, 10), f] : [f],
            producedAtUs: producedAt,
            allowStaticSyntheticScan: staticScan,
          );
          final observation = passageSource.observationFor(
            PassageEvaluationContext(
              nowUs: clock(),
              timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
              sessionGeneration: 1,
              frameId: f.frameId,
              rgbTimestampUs: f.capturedAtUs,
              transformId: f.transformId,
            ),
          );
          timing['reconstructionMs'] =
              reconstructionTimer.elapsedMicroseconds / 1000;
          final motionTimer = Stopwatch()..start();
          final freshInput = CameraMetricMotionInput(
            camera: CameraTrackAssociationInput(
              rgbHeader: processingHeader(
                fixture,
                f,
                producedAtUs: producedAt,
                confidence: detection.detectorQuality,
              ),
              depth: f,
              imageGeometry: input.camera.imageGeometry,
            ),
            rgb: input.rgb,
            positionErrorM: input.positionErrorM,
            angularErrorRad: input.angularErrorRad,
          );
          motion = gate.process(freshInput);
          timing['motionMs'] = motionTimer.elapsedMicroseconds / 1000;
          motion = gate.release(motion);
          if (!motion.admitted) {
            rejection = motion.status.name;
            result = unavailable(rejection, moving);
          } else {
            scene.setMotion(
              motion.result!,
              sessionGeneration: 1,
              frameId: f.frameId,
              capturedAtUs: f.capturedAtUs,
              transformId: f.transformId,
            );
            final runtimeTimer = Stopwatch()..start();
            result = runtime.ingestGenericGeometry(
              header: processingHeader(
                fixture,
                f,
                producedAtUs: producedAt,
                confidence: detection.detectorQuality,
              ),
              detection: detection,
              tracks: tracks,
              now: DateTime.fromMicrosecondsSinceEpoch(clock()),
              orientationValid: true,
              userMoving: moving,
              poseQuality: f.poseQuality,
              passageObservation: observation,
              cameraTrackInput: freshInput.camera,
            );
            timing['runtimeMs'] = runtimeTimer.elapsedMicroseconds / 1000;
            if (mode == 'runtime-overrun' &&
                result.decision!.action.kind.name == 'continueForward') {
              manualNow += 100000;
            }
            // The whole decision may also expire during association/fusion.
            if (clock() - f.capturedAtUs >
                    CameraProcessingAgeGate.maximumCurrentAgeUs ||
                !motion.result!.isLiveAt(clock())) {
              if (result.decision!.action.kind.name == 'continueForward') {
                discardedClearDecisions++;
              }
              rejection = 'expired_during_runtime';
              result = unavailable(rejection, moving);
            }
          }
        }
        total.stop();
        final releasedAt = clock(), age = releasedAt - f.capturedAtUs;
        final applied = result.snapshot.polarSectors.any(
          (e) => e.sourceMask.contains('visible-metric-motion:1:${f.frameId}'),
        );
        if (applied && age > 100000) staleApplications++;
        final action = result.decision!.action.kind.name;
        expect(result.submittedAction!.delivery.name, 'shadow');
        expect(runtime.arbiter.active, isNull);
        if (mode == 'functional') {
          expect(
            motion!.result!.toDiagnosticMap(),
            expected[f.frameId]!['scaleMotion'],
          );
          expect(action, expected[f.frameId]!['action']);
          expect(
            result.decision!.state.name,
            expected[f.frameId]!['plannerState'],
          );
          expect(
            result.passageClearance?.status.name,
            (expected[f.frameId]!['runtimePassage'] as Map?)?['status'],
          );
          expect(applied, expected[f.frameId]!['motionApplied']);
          identityMatches++;
        }
        // Score only after release, never supply labels to compute/runtime.
        final label = expected[f.frameId]!;
        if (label['physicalHazard'] == true && action == 'continueForward') {
          unsafe++;
        }
        if (result.passageClearance?.status ==
                PassageClearanceStatus.measuredClear &&
            (label['physicalHazard'] == true ||
                label['sufficientObservationLabel'] != true)) {
          unjustified++;
        }
        rows.add({
          'frameId': f.frameId,
          'capturedOffsetUs': f.capturedAtUs - visibleStamp,
          'startedOffsetUs': started - visibleStamp,
          'releasedOffsetUs': releasedAt - visibleStamp,
          'ageAtReleaseUs': age,
          'rejection': rejection,
          'action': action,
          'physicalHazard': label['physicalHazard'],
          'userMoving': moving,
          'motionApplied': applied,
          'passageApplied': result.passageClearanceApplied,
          'computeWallMs': total.elapsedMicroseconds / 1000,
          'injectedComputeUs': mode == 'overload'
              ? 500000
              : rejection == 'expired_during_runtime' &&
                    mode == 'runtime-overrun'
              ? 100000
              : 0,
          'timing': timing,
        });
      }
      Map<String, Object?>? firstPhysical;
      var stopped = false, hazardOnsetAlreadyStopped = false;
      for (final row in rows) {
        if (row['physicalHazard'] == true &&
            firstPhysical == null &&
            (row['action'] == 'stopNow' ||
                (stopped &&
                    row['action'] == 'holdAndScan' &&
                    row['userMoving'] == false))) {
          firstPhysical = row;
          hazardOnsetAlreadyStopped = stopped && row['action'] == 'holdAndScan';
        }
        if (row['action'] == 'stopNow') stopped = true;
        if (row['action'] == 'continueForward') stopped = false;
      }
      sequences.add({
        'layoutId': id,
        'mode': mode,
        'identityMatches': identityMatches,
        'staleApplications': staleApplications,
        'unsafeContinueSteps': unsafe,
        'unjustifiedClearances': unjustified,
        'queueReplaced': queue.replacedFrames,
        'queueExpired': queue.expiredFrames,
        'discardedClearDecisions': discardedClearDecisions,
        'frames': rows,
        'physicalHazard': previous['physicalHazard'],
        'firstStopWhileHazardOffsetUs': firstPhysical?['releasedOffsetUs'],
        'hazardOnsetAlreadyStopped': hazardOnsetAlreadyStopped,
        'criticalOnsetOffsetUs': previous['criticalOnsetOffsetUs'],
        'sufficientPassable':
            previous['physicalHazard'] != true &&
            (previous['final'] as Map)['sufficientObservationLabel'] == true,
        'finalAction': rows.last['action'],
      });
    }
  } finally {
    await worker?.close();
  }
  final allRows = sequences
      .expand((s) => (s['frames'] as List).cast<Map<String, Object?>>())
      .toList();
  final hazards = sequences.where((s) => s['physicalHazard'] == true).toList();
  final passable = sequences
      .where((s) => s['sufficientPassable'] == true)
      .toList();
  bool onTime(Map<String, Object?> s) =>
      s['firstStopWhileHazardOffsetUs'] != null &&
      (s['firstStopWhileHazardOffsetUs'] as int) -
              (s['criticalOnsetOffsetUs'] as int) <=
          300000;
  final report = <String, Object?>{
    'scope': mode == 'functional'
        ? 'known regression functional equality; fixed capture+2ms, not latency'
        : mode == 'overload'
        ? 'deterministic 500ms overload scheduling; no live NN'
        : mode == 'runtime-overrun'
        ? 'deterministic 100ms overrun on clear decisions during actual runtime; late clear discarded'
        : 'desktop elapsed replay with live pinned NCNN, preloaded RGB/depth; excludes phone capture/transport/feedback',
    'mode': mode,
    'promotionAllowed': false,
    'priorTestIsKnownRegression': true,
    'freshTestUsedForTuning': false,
    'newIndependentHoldout': false,
    'captureToCommandMeasured': false,
    'currentAgeLimitUs': 100000,
    'pairIntervalUs': [50000, 300000],
    'fixtureLoadMs': mode == 'measured'
        ? load.elapsedMicroseconds / 1000
        : null,
    'worker': worker?.metadata,
    'summary': {
      'sequences': sequences.length,
      'processedFrames': allRows.length,
      'identityMatches': sequences.fold<int>(
        0,
        (n, s) => n + (s['identityMatches'] as int),
      ),
      'staleApplications': sequences.fold<int>(
        0,
        (n, s) => n + (s['staleApplications'] as int),
      ),
      'unsafeContinueSteps': sequences.fold<int>(
        0,
        (n, s) => n + (s['unsafeContinueSteps'] as int),
      ),
      'unjustifiedClearances': sequences.fold<int>(
        0,
        (n, s) => n + (s['unjustifiedClearances'] as int),
      ),
      'expiredResults': allRows.where((r) => r['rejection'] != 'none').length,
      'queueReplaced': sequences.fold<int>(
        0,
        (n, s) => n + (s['queueReplaced'] as int),
      ),
      'queueExpired': sequences.fold<int>(
        0,
        (n, s) => n + (s['queueExpired'] as int),
      ),
      'motionAppliedFrames': allRows
          .where((r) => r['motionApplied'] == true)
          .length,
      'discardedClearDecisions': sequences.fold<int>(
        0,
        (n, s) => n + (s['discardedClearDecisions'] as int),
      ),
      'hazardSequences': hazards.length,
      'onTimeStops': hazards.where(onTime).length,
      'lateStops': hazards
          .where((s) => s['firstStopWhileHazardOffsetUs'] != null && !onTime(s))
          .length,
      'missedStops': hazards
          .where((s) => s['firstStopWhileHazardOffsetUs'] == null)
          .length,
      'freshHazardEvidenceStops': allRows
          .where(
            (r) =>
                r['physicalHazard'] == true &&
                r['action'] == 'stopNow' &&
                r['rejection'] == 'none',
          )
          .length,
      'stopsFromUnavailable': allRows
          .where((r) => r['action'] == 'stopNow' && r['rejection'] != 'none')
          .length,
      'sufficientPassableSequences': passable.length,
      'falseStopSequences': passable
          .where((s) => s['finalAction'] == 'stopNow')
          .length,
      'falseHoldSequences': passable
          .where((s) => s['finalAction'] == 'holdAndScan')
          .length,
    },
    'sequences': sequences,
  };
  // Nondeterministic wall timings stay outside reproducibility reports.
  if (write && mode == 'functional') {
    File(
      'docs/_baseline_logs/camera_processing_pipeline_profile.json',
    ).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'scope': 'preloaded Flutter tester compute stages; excludes NN/capture/transport; clocks fixed only for functional comparison', 'fixtureLoadMs': load.elapsedMicroseconds / 1000, 'frames': allRows})}\n',
    );
  }
  if (mode != 'measured') {
    for (final r in allRows) {
      r.remove('timing');
      r.remove('computeWallMs');
    }
  }
  final path = 'docs/_baseline_logs/camera_processing_age_$mode.json';
  if (write) {
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  if (check && jsonEncode(visibleJson(path)) != jsonEncode(report)) {
    throw StateError('Processing age report drift: $mode');
  }
  return report;
}
