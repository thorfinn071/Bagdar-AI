import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'camera_visible_passage_fixture.dart';
import 'frozen_replay_sources.dart';

const temporalRoot = 'test/fixtures/spatial_safety/camera-temporal-passage-v1';
const temporalFreeze =
    'docs/_baseline_logs/camera_temporal_development_freeze.json';
const temporalModes = [
  'ncnn-control',
  'associated-stateful',
  'associated-stable',
];

double? temporalPercentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  values.sort();
  return values[((values.length * fraction).ceil() - 1).clamp(
    0,
    values.length - 1,
  )];
}

Map<String, String> temporalSourceHashes(String root) {
  final previous = visibleJson(
    'docs/_baseline_logs/camera_track_development_freeze.json',
  );
  final paths = <String>{
    ...(previous['sourceSha256'] as Map<String, dynamic>).keys,
    'lib/services/frame_stable_generic_obstacle_detector.dart',
    'test/harness/camera_temporal_passage_benchmark.dart',
    'test/frame_stable_generic_obstacle_detector_test.dart',
    'tool/blender/generate_temporal_passage_corpus.py',
    'tool/model_benchmark/generate_temporal_passage_ncnn.py',
    'tool/model_benchmark/verify_temporal_passage_assets.py',
    'tool/model_benchmark/freeze_temporal_passage_development.py',
    'tool/model_benchmark/evaluate_temporal_passage.dart',
    'tool/model_benchmark/generate_context_ncnn_depth.py',
    'docs/camera-temporal-stability-protocol-2026-10-03.md',
    'assets/midas_small.ncnn.param',
    'assets/midas_small.ncnn.bin',
    '$root/manifest.json',
    '$root/annotations.json',
    '$root/ncnn/manifest.json',
  };
  return {for (final path in paths) path: visibleSha(path)};
}

/// Actual detector/tracker/runtime replay; annotations only score decisions.
Future<Map<String, Object?>> runTemporalPassageBenchmark({
  bool developmentOnly = false,
  bool knownRegression = false,
  bool write = false,
  bool check = false,
  bool knownCorpusRegression = false,
}) async {
  if (knownCorpusRegression &&
      (write || check || developmentOnly || knownRegression)) {
    throw ArgumentError('Known-corpus replay cannot replace frozen reports.');
  }
  final root = knownRegression
      ? 'test/fixtures/spatial_safety/camera-track-passage-v1'
      : temporalRoot;
  final fixture = VisibleFixture(root: root);
  String? freezeHash;
  if (!developmentOnly && !knownRegression) {
    final freeze = visibleJson(temporalFreeze);
    verifyFrozenReplaySources(
      freeze['sourceSha256'] as Map<String, dynamic>,
      allowHistoricalSources: knownCorpusRegression,
    );
    expect(freeze['corpusManifestSha256'], fixture.modelHash);
    freezeHash = visibleSha(temporalFreeze);
  }
  final labels = {
    for (final l in visibleJson('$root/annotations.json')['layouts'] as List)
      l['layoutId']: l as Map<String, dynamic>,
  };
  final rows = <Map<String, Object?>>[], timings = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    if (knownRegression && layout['id'] != 'test-association-wide-08') continue;
    if (!knownRegression &&
        developmentOnly &&
        layout['split'] != 'validation') {
      continue;
    }
    final label = labels[layout['id']]!;
    final exact = fixture.frames(layout);
    final staticScan = layout['staticSyntheticScan'] == true;
    final decisions = knownRegression
        ? [
            exact.first,
            for (var i = 0; i < 3; i++)
              copyVisibleFrame(
                exact.first,
                frameId: 11 + i,
                timestamp: visibleStamp + 2000000 + i * 200000,
              ),
          ]
        : exact
              .where(
                (f) => (layout['decisionFrameIds'] as List).contains(f.frameId),
              )
              .toList();
    final frameLabels = knownRegression
        ? null
        : {
            for (final l in label['frames'] as List)
              l['frameId']: l as Map<String, dynamic>,
          };
    for (final mode in temporalModes) {
      final legacy = GenericObstacleDetector(collectCameraSupport: true);
      final stable = FrameStableGenericObstacleDetector(
        collectCameraSupport: true,
      );
      final tracker =
          GenericObstacleTracker(); // Persistent for the entire sequence.
      final calibration = fixture.calibration();
      final policy = staticScan ? visibleScanPolicy : visibleSinglePolicy;
      final runtime =
          SpatialSafetyRuntime(
            healthCoordinator: CoreHealthCoordinator(),
            shadowPassage: mode == 'ncnn-control'
                ? null
                : PassageClearanceShadowConfiguration(
                    calibration: calibration,
                    request: visibleRequest,
                    policy: policy,
                    requireCameraEvidence: true,
                    associateCameraTracks: true,
                    cameraTrackModelHash:
                        fixture.ncnn['modelBinSha256'] as String,
                  ),
          )..beginSession(
            1,
            now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1),
          );
      final traces = <Map<String, Object?>>[];
      final onset = label['criticalOnsetOffsetUs'] as int?;
      int? firstHazardStop;
      var previouslyStopped = false, onsetAlreadyStopped = false;
      var unsafe = 0, unjustified = 0, hazardSteps = 0, heldHazardSteps = 0;
      var movingTracks = 0, maximumApproach = 0.0;
      for (var step = 0; step < decisions.length; step++) {
        final current = decisions[step], stamp = current.capturedAtUs;
        final offset = stamp - visibleStamp;
        final metadata = (layout['frames'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (f) => f['frameId'] == (knownRegression ? 1 : current.frameId),
            );
        // Each temporal RGB has its own NCNN output, independently verified.
        final raw = fixture.raw(layout, knownRegression ? 1 : current.frameId);
        final relative = DepthMapOps.normalizeRelativeProximity(
          Float32List.fromList(raw),
        );
        final depth = DepthFrame(
          values: relative,
          confidence01: Float32List.fromList(List.filled(relative.length, 1)),
          width: 256,
          height: 256,
          timestampUs: stamp,
          provider: DepthProviderKind.ncnnRelative,
          semantics: DepthValueSemantics.relativeProximity,
          modelId: 'midas-small-ncnn',
          modelHash: fixture.ncnn['modelBinSha256'] as String,
          preprocessId: fixture.ncnn['preprocessId'] as String,
          cropTopFraction: 0,
          frameQuality: 1,
          alignedToImage: true,
        );
        final moving = step == 0 || step == decisions.length - 1;
        final total = Stopwatch()..start(),
            detectorTimer = Stopwatch()..start();
        final detection =
            (mode == 'associated-stable' ? stable.detect : legacy.detect)(
              frame: depth,
              pitchDeg: (metadata['pitchDeg'] as num).toDouble(),
              rollDeg: (metadata['rollDeg'] as num).toDouble(),
              motion: moving ? MotionState.walking : MotionState.stationary,
              imageTimestampUs: stamp,
            );
        final tracks = tracker.update(
          observations: detection.observations,
          timestampUs: stamp,
          relative: true,
        );
        detectorTimer.stop();
        final context = PassageEvaluationContext(
          nowUs: stamp + 2000,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          sessionGeneration: 1,
          frameId: current.frameId,
          rgbTimestampUs: stamp,
          transformId: calibration.transformId,
        );
        final reconstruction = Stopwatch()..start();
        CameraPassageClearanceSource? source;
        PassageClearanceObservation? observation;
        PassageClearanceResult? passage;
        if (mode != 'ncnn-control') {
          source = CameraPassageClearanceSource(
            calibration: calibration,
            request: visibleRequest,
            // Never accumulate old camera views in dynamic sequences.
            frames: staticScan && step > 0
                ? [...exact.sublist(1, 10), current]
                : [current],
            producedAtUs: stamp + 1000,
            allowStaticSyntheticScan: staticScan && step > 0,
          );
          observation = source.observationFor(context);
          passage = PassageClearanceEvaluator(policy: policy).evaluate(
            request: visibleRequest,
            context: context,
            calibration: calibration,
            observation: observation,
          );
        }
        reconstruction.stop();
        final header = ObservationHeader(
          providerId: 'desktop-ncnn-midas-depth',
          modelId: depth.modelId,
          modelHash: depth.modelHash,
          preprocessId: depth.preprocessId,
          sessionGeneration: 1,
          frameId: current.frameId,
          sourceTimestampUs: stamp,
          producedAtUs: stamp + 1000,
          transformId: calibration.transformId,
          confidence: detection.detectorQuality,
          health: ObservationHealth.healthy,
        );
        final runtimeTimer = Stopwatch()..start();
        final result = runtime.ingestGenericGeometry(
          header: header,
          detection: detection,
          tracks: tracks,
          now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
          orientationValid: true,
          userMoving: moving,
          poseQuality: current.poseQuality,
          passageObservation: observation,
          cameraTrackInput: mode == 'ncnn-control'
              ? null
              : CameraTrackAssociationInput(
                  rgbHeader: header,
                  depth: current,
                  imageGeometry: CameraTrackImageGeometry(
                    cameraId: current.cameraId,
                    width: current.width,
                    height: current.height,
                    fx: current.fx,
                    fy: current.fy,
                    cx: current.cx,
                    cy: current.cy,
                    rotation: current.rotation,
                    originM: current.originM,
                  ),
                ),
        );
        runtimeTimer.stop();
        total.stop();
        expect(result.accepted, isTrue);
        expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
        expect(runtime.arbiter.active, isNull);
        final action = result.decision!.action.kind;
        // Labels are consulted only after producer, contract and runtime finish.
        final hazardous = knownRegression
            ? false
            : frameLabels![current.frameId]!['physicalHazard'] == true;
        final sufficient = knownRegression
            ? step > 0
            : frameLabels![current.frameId]!['observationSufficient'] == true;
        if (hazardous) {
          hazardSteps++;
          if (action == SafetyActionKind.stopNow) {
            firstHazardStop ??= offset + 2000;
          }
          if (firstHazardStop == null &&
              action == SafetyActionKind.holdAndScan &&
              previouslyStopped &&
              !moving) {
            firstHazardStop = offset + 2000;
            onsetAlreadyStopped = true;
          }
          if (action == SafetyActionKind.holdAndScan) heldHazardSteps++;
          if (action == SafetyActionKind.continueForward) unsafe++;
          if (mode != 'ncnn-control') {
            expect(
              action,
              isNot(SafetyActionKind.continueForward),
              reason:
                  'Unsafe temporal decision ${layout['id']} $mode ${current.frameId}',
            );
          }
        }
        if (action == SafetyActionKind.stopNow) previouslyStopped = true;
        if (action == SafetyActionKind.continueForward) {
          previouslyStopped = false;
        }
        if (passage?.status == PassageClearanceStatus.measuredClear &&
            (!sufficient || hazardous)) {
          unjustified++;
        }
        if (mode != 'ncnn-control') expect(unjustified, 0);
        final forward = result.decision!.candidates.firstWhere(
          (c) => c.direction.name == 'forward',
        );
        for (final track in tracks) {
          final trend = track.approachTrend();
          if (trend > maximumApproach) maximumApproach = trend;
          if (trend > 0 && track.misses == 0) movingTracks++;
        }
        final trace = <String, Object?>{
          'frameId': current.frameId,
          'captureOffsetUs': offset,
          'rgbSha256': metadata['rgb']['sha256'],
          'physicalHazard': hazardous,
          'sufficientObservationLabel': sufficient,
          'userMoving': moving,
          'pose': {'rotation': current.rotation, 'originM': current.originM},
          'oldestEvidenceTimestampUs': observation?.oldestEvidenceTimestampUs,
          'producer': source?.diagnostics,
          'sections': observation?.sections
              .map(
                (s) => {
                  'startM': s.forwardStartM,
                  'endM': s.forwardEndM,
                  'state': s.state.name,
                  'bodyObservedFraction': s.bodyObservedFraction,
                  'floorObservedFraction': s.floorObservedFraction,
                  'leftUpperM': s.leftBoundaryUpperM,
                  'rightLowerM': s.rightBoundaryLowerM,
                  'headroomLowerM': s.headroomLowerBoundM,
                  'floorRiseUpperM': s.floorRiseUpperBoundM,
                  'floorDropUpperM': s.floorDropUpperBoundM,
                },
              )
              .toList(),
          'passage': passage?.toDiagnosticMap(),
          'runtimePassage': result.passageClearance?.toDiagnosticMap(),
          'runtimePassageApplied': result.passageClearanceApplied,
          'groundConfidence': detection.groundConfidence,
          'groundDisagreementPixels': detection.groundDisagreementPixels,
          'detectorReject': detection.rejectReason.name,
          'unknownReasons': detection.unknownReasons
              .map((r) => r.name)
              .toList(),
          'tracks': [
            for (final track in tracks)
              {
                'id': track.id,
                'confirmed': track.confirmed,
                'hits': track.hits,
                'misses': track.misses,
                'geometry': track.last.geometry.name,
                'zone': track.last.zone.name,
                'pixelCount': track.last.pixelCount,
                'proximity': track.last.relativeProximity,
                'approachTrend': track.approachTrend(),
                'proximityHistory': track.proximityHist.toList(),
                'bounds': [
                  track.last.normalizedBounds.left,
                  track.last.normalizedBounds.top,
                  track.last.normalizedBounds.right,
                  track.last.normalizedBounds.bottom,
                ],
                'supportSha256': track.last.cameraSupport == null
                    ? null
                    : sha256
                          .convert(
                            utf8.encode(
                              jsonEncode(track.last.cameraSupport!.indices),
                            ),
                          )
                          .toString(),
                'association': runtime.cameraTrackAssociations[track.id]
                    ?.toDiagnosticMap(),
              },
          ],
          'action': action.name,
          'ruleId': result.decision!.action.ruleId,
          'plannerState': result.decision!.state.name,
          'plannerPreviousState': result.decision!.previousState.name,
          'plannerForward': {
            'observedFraction': forward.observedFraction,
            'unknownRisk': forward.unknownRisk,
            'collisionRisk': forward.collisionRisk,
            'movingThreatRisk': forward.movingThreatRisk,
            'dropRisk': forward.dropRisk,
            'positiveEvidencePassed': forward.positiveEvidencePassed,
            'rejectionReasons': forward.rejectionReasons
                .map((r) => r.name)
                .toList(),
          },
        };
        traces.add(trace);
        if (write) {
          timings.add({
            'layoutId': layout['id'],
            'mode': mode,
            'frameId': current.frameId,
            'captureOffsetUs': offset,
            'action': action.name,
            'detectorTrackerMs': detectorTimer.elapsedMicroseconds / 1000,
            'reconstructionMs': reconstruction.elapsedMicroseconds / 1000,
            'runtimeMs': runtimeTimer.elapsedMicroseconds / 1000,
            'decisionComputeMs': total.elapsedMicroseconds / 1000,
          });
        }
      }
      // Maintained hold is reported separately; timely explicit stops use stopNow.
      rows.add({
        'layoutId': layout['id'],
        'split': knownRegression ? 'known-regression' : layout['split'],
        'mode': mode,
        'staticSyntheticScan': staticScan,
        'physicalHazard': label['physicalHazard'],
        'hazardSteps': hazardSteps,
        'heldHazardSteps': heldHazardSteps,
        'criticalOnsetOffsetUs': onset,
        'firstHazardStopOffsetUs': firstHazardStop,
        'hazardOnsetAlreadyStopped': onsetAlreadyStopped,
        'onTimeStop':
            onset != null &&
            firstHazardStop != null &&
            firstHazardStop <= onset + 300000,
        'unsafeContinueSteps': unsafe,
        'unjustifiedClearances': unjustified,
        'positiveApproachTrackSteps': movingTracks,
        'maximumApproachTrend': maximumApproach,
        'scanDurationUs': staticScan ? 2000000 : 0,
        'decisions': traces,
        'final': traces.last,
      });
    }
  }
  final summarySplit = knownRegression
      ? 'known-regression'
      : developmentOnly
      ? 'validation'
      : 'test';
  final summaries = <String, Object?>{};
  for (final mode in temporalModes) {
    final set = rows
        .where((r) => r['split'] == summarySplit && r['mode'] == mode)
        .toList();
    final hazards = set.where((r) => r['physicalHazard'] == true).toList();
    final sufficient = set
        .where((r) => (r['final'] as Map)['sufficientObservationLabel'] == true)
        .toList();
    summaries[mode] = {
      'sequences': set.length,
      'hazardSequences': hazards.length,
      'onTimeStops': hazards.where((r) => r['onTimeStop'] == true).length,
      'lateStops': hazards
          .where(
            (r) =>
                r['firstHazardStopOffsetUs'] != null && r['onTimeStop'] != true,
          )
          .length,
      'missedStops': hazards
          .where((r) => r['firstHazardStopOffsetUs'] == null)
          .length,
      'hazardOnsetsAlreadyStopped': hazards
          .where((r) => r['hazardOnsetAlreadyStopped'] == true)
          .length,
      'heldHazardSteps': hazards.fold<int>(
        0,
        (n, r) => n + (r['heldHazardSteps'] as int),
      ),
      'unsafeContinueSteps': hazards.fold<int>(
        0,
        (n, r) => n + (r['unsafeContinueSteps'] as int),
      ),
      'sufficientPassableSequences': sufficient.length,
      'falseStopSequences': sufficient
          .where((r) => (r['final'] as Map)['action'] == 'stopNow')
          .length,
      'falseHoldSequences': sufficient
          .where((r) => (r['final'] as Map)['action'] == 'holdAndScan')
          .length,
      'producerClearSufficient': sufficient
          .where(
            (r) =>
                ((r['final'] as Map)['passage'] as Map?)?['status'] ==
                'measuredClear',
          )
          .length,
      'runtimeAppliedSufficient': sufficient
          .where((r) => (r['final'] as Map)['runtimePassageApplied'] == true)
          .length,
      'insufficientFinalStops': set
          .where(
            (r) =>
                (r['final'] as Map)['sufficientObservationLabel'] != true &&
                (r['final'] as Map)['action'] == 'stopNow',
          )
          .length,
      'insufficientFinalHolds': set
          .where(
            (r) =>
                (r['final'] as Map)['sufficientObservationLabel'] != true &&
                (r['final'] as Map)['action'] == 'holdAndScan',
          )
          .length,
      'unjustifiedClearances': set.fold<int>(
        0,
        (n, r) => n + (r['unjustifiedClearances'] as int),
      ),
    };
  }
  final report = <String, Object?>{
    'schemaVersion': 1,
    if (knownCorpusRegression) 'evaluationScope': 'knownCorpusRegression',
    'benchmarkId': fixture.manifest['corpusId'],
    'scope':
        'synthetic desktop shadow; static inspection and actual temporal RGB tested separately',
    'promotionAllowed': false,
    'summarySplit': summarySplit,
    'developmentFreezeSha256': freezeHash,
    'functionalProcessingOffsetUs': 2000,
    'functionalOffsetIsMeasuredLatency': false,
    'temporalObservationPolicy':
        'current first-visible depth only; no static scan accumulation',
    'relativeDepthUnits':
        'relative proximity; no metric interpretation or new calibration fit',
    'sourceSha256': temporalSourceHashes(root),
    'summaries': summaries,
    'sequences': rows,
  };
  final stem = knownRegression
      ? 'camera_temporal_known_regression'
      : developmentOnly
      ? 'camera_temporal_development'
      : 'camera_temporal_passage';
  final reportPath = 'docs/_baseline_logs/$stem.json';
  final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  if (write) {
    File(reportPath).writeAsStringSync(rendered);
    File('docs/_baseline_logs/${stem}_decision_timing.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'scope': 'measured desktop wall clock, separate from functional reaction offsets; excludes scan and NN',
        'frames': timings,
        'summaries': {
          for (final mode in temporalModes) mode: {
              for (final key in ['detectorTrackerMs', 'reconstructionMs', 'runtimeMs', 'decisionComputeMs']) key: {
                  for (final q in [.5, .95]) q == .5 ? 'p50' : 'p95': temporalPercentile(timings.where((r) => r['mode'] == mode).map((r) => r[key] as double).toList(), q),
                },
            },
        },
      })}\n',
    );
  }
  if (check) {
    expect(
      File(reportPath).readAsStringSync(),
      rendered,
      reason: 'Temporal functional report drift',
    );
  }
  return report;
}
