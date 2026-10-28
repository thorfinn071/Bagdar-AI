import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_scale_metric_motion.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
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
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'camera_visible_passage_fixture.dart';
import 'frozen_replay_sources.dart';

Map<String, Object?> scoreScaleCorrespondence(
  String root,
  Map<String, dynamic> label,
  CameraMetricMotionResult? result,
  int? previousFrameId,
  int width,
) {
  final scoring = label['visibleObjectFrames'] as List?;
  if (scoring == null ||
      scoring.isEmpty ||
      result == null ||
      previousFrameId == null) {
    return {'available': false};
  }
  List<int> mask(int id) {
    final asset =
        scoring.singleWhere((f) => f['frameId'] == id)['visibleObjectMask']
            as Map;
    final path = '$root/${asset['path']}';
    expect(visibleSha(path), asset['sha256']);
    return gzip.decode(File(path).readAsBytesSync());
  }

  final a = mask(previousFrameId), b = mask(result.frameId);
  final frameLabel = (label['frames'] as List).singleWhere(
    (f) => f['frameId'] == result.frameId,
  );
  final velocity = (frameLabel['objectVelocityMps'] as List).cast<num>();
  var objectMatches = 0, backgroundMatches = 0, surfaceMismatch = 0;
  var correctObjectMotion = 0,
      incorrectIntervals = 0,
      falseBackgroundMotion = 0;
  for (final patch in result.patches) {
    final sourceObject =
        a[patch.previousPixel[1] * width + patch.previousPixel[0]] == 1;
    final targetObject =
        b[patch.currentPixel[1] * width + patch.currentPixel[0]] == 1;
    if (sourceObject != targetObject) {
      surfaceMismatch++;
      continue;
    }
    final truth = sourceObject ? velocity : [0, 0, 0];
    final contains = List.generate(
      3,
      (j) =>
          patch.velocityLowerMps[j] <= truth[j] &&
          patch.velocityUpperMps[j] >= truth[j],
    ).every((v) => v);
    if (!contains) incorrectIntervals++;
    if (sourceObject) {
      objectMatches++;
      if (contains && patch.establishesMotion) correctObjectMotion++;
    } else {
      backgroundMatches++;
      if (patch.establishesMotion) falseBackgroundMotion++;
    }
  }
  return {
    'available': true,
    'objectMatches': objectMatches,
    'backgroundMatches': backgroundMatches,
    'surfaceMismatch': surfaceMismatch,
    'correctObjectMotion': correctObjectMotion,
    'incorrectVelocityIntervals': incorrectIntervals,
    'falseBackgroundMotion': falseBackgroundMotion,
  };
}

const scaleMotionRoot = 'test/fixtures/spatial_safety/camera-scale-motion-v1';
const scaleMotionFreeze =
    'docs/_baseline_logs/camera_scale_motion_development_freeze.json';
const scaleMotionModes = ['fixed-patch', 'spatial-only', 'scale-motion'];

double? scaleMotionPercentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  values.sort();
  return values[((values.length * fraction).ceil() - 1).clamp(
    0,
    values.length - 1,
  )];
}

Map<String, String> scaleMotionSourceHashes(String root) {
  final previous = visibleJson(
    'docs/_baseline_logs/camera_metric_motion_development_freeze.json',
  );
  final paths = <String>{
    ...(previous['sourceSha256'] as Map<String, dynamic>).keys,
    'lib/services/frame_stable_generic_obstacle_detector.dart',
    'test/harness/camera_scale_motion_benchmark.dart',
    'lib/safety/perception/camera_scale_metric_motion.dart',
    'lib/safety/runtime/camera_metric_motion_shadow_scene.dart',
    'lib/safety/perception/camera_metric_motion.dart',
    'test/camera_scale_metric_motion_contract_test.dart',
    'test/camera_scale_metric_motion_test.dart',
    'test/camera_scale_motion_development_test.dart',
    'test/camera_scale_motion_replay_test.dart',
    'test/frame_stable_generic_obstacle_detector_test.dart',
    'tool/blender/generate_scale_motion_corpus.py',
    'tool/model_benchmark/generate_scale_motion_ncnn.py',
    'tool/model_benchmark/verify_scale_motion_assets.py',
    'tool/model_benchmark/freeze_scale_motion_development.py',
    'tool/model_benchmark/evaluate_scale_motion.dart',
    'tool/model_benchmark/generate_context_ncnn_depth.py',
    'docs/camera-scale-motion-protocol-2026-10-03.md',
    'assets/midas_small.ncnn.param',
    'assets/midas_small.ncnn.bin',
    '$root/manifest.json',
    '$root/annotations.json',
    '$root/ncnn/manifest.json',
  };
  return {for (final path in paths) path: visibleSha(path)};
}

/// Actual detector/tracker/runtime replay; annotations only score decisions.
Future<Map<String, Object?>> runScaleMotionBenchmark({
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
      ? 'test/fixtures/spatial_safety/camera-metric-motion-v1'
      : scaleMotionRoot;
  final fixture = VisibleFixture(root: root);
  String? freezeHash;
  if (!developmentOnly && !knownRegression) {
    final freeze = visibleJson(scaleMotionFreeze);
    verifyFrozenReplaySources(
      freeze['sourceSha256'] as Map<String, dynamic>,
      allowHistoricalSources: knownCorpusRegression,
    );
    expect(freeze['corpusManifestSha256'], fixture.modelHash);
    freezeHash = visibleSha(scaleMotionFreeze);
  }
  final labels = {
    for (final l in visibleJson('$root/annotations.json')['layouts'] as List)
      l['layoutId']: l as Map<String, dynamic>,
  };
  final rows = <Map<String, Object?>>[], timings = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    if (knownRegression && layout['id'] != 'test-metric-motion-approach-08') {
      continue;
    }
    if (!knownRegression &&
        developmentOnly &&
        layout['split'] != 'validation') {
      continue;
    }
    if (!knownRegression && !developmentOnly && layout['split'] != 'test') {
      continue;
    }
    final label = labels[layout['id']]!;
    final exact = fixture.frames(layout);
    final staticScan = layout['staticSyntheticScan'] == true;
    final decisions = exact
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId))
        .toList();
    final frameLabels = {
      for (final l in label['frames'] as List)
        l['frameId']: l as Map<String, dynamic>,
    };
    for (final mode in scaleMotionModes) {
      final fixedSource = CameraMetricMotionSource(
        calibration: fixture.calibration(),
        relativeModelHash: fixture.ncnn['modelBinSha256'] as String,
      );
      final scaleSource = CameraScaleMetricMotionSource(
        calibration: fixture.calibration(),
        relativeModelHash: fixture.ncnn['modelBinSha256'] as String,
        enableScaleMatching: mode == 'scale-motion',
      );
      final motionScene = CameraMetricMotionShadowScene();
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
            sceneModel: motionScene,
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
            .firstWhere((f) => f['frameId'] == current.frameId);
        // Each temporal RGB has its own NCNN output, independently verified.
        final raw = fixture.raw(layout, current.frameId);
        final normalizationTimer = Stopwatch()..start();
        final relative = DepthMapOps.normalizeRelativeProximity(
          Float32List.fromList(raw),
        );
        normalizationTimer.stop();
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
        final detection = stable.detect(
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
        final motionTimer = Stopwatch()..start();
        CameraMetricMotionResult? motionResult;
        if (true) {
          final pixels =
              (fixture.ncnn['frames'] as List)
                      .cast<Map<String, dynamic>>()
                      .singleWhere(
                        (r) =>
                            r['layoutId'] == layout['id'] &&
                            r['frameId'] == current.frameId,
                      )['rgbPixels']
                  as Map<String, dynamic>;
          final rgbPath = '$root/ncnn/${pixels['path']}';
          expect(visibleSha(rgbPath), pixels['sha256']);
          final motionInput = CameraMetricMotionInput(
            camera: CameraTrackAssociationInput(
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
            rgb: gzip.decode(File(rgbPath).readAsBytesSync()),
            positionErrorM: .0001,
            angularErrorRad: 0,
          );
          motionResult = mode == 'fixed-patch'
              ? fixedSource.observe(motionInput, nowUs: stamp + 2000)
              : scaleSource.observe(motionInput, nowUs: stamp + 2000);
          motionScene.setMotion(
            motionResult,
            sessionGeneration: header.sessionGeneration,
            frameId: header.frameId,
            capturedAtUs: header.sourceTimestampUs,
            transformId: header.transformId,
          );
        }
        motionTimer.stop();
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
        final hazardous =
            frameLabels[current.frameId]!['physicalHazard'] == true;
        final sufficient =
            frameLabels[current.frameId]!['observationSufficient'] == true;
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
          'scaleMotion': motionResult.toDiagnosticMap(),
          'correspondenceScore': scoreScaleCorrespondence(
            root,
            label,
            motionResult,
            step == 0 ? null : decisions[step - 1].frameId,
            current.width,
          ),
          'motionApplied': result.snapshot.polarSectors.any(
            (e) => e.sourceMask.contains(
              'visible-metric-motion:1:${current.frameId}',
            ),
          ),
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
            'scaleMotionMs': motionTimer.elapsedMicroseconds / 1000,
            'normalizationMs': normalizationTimer.elapsedMicroseconds / 1000,
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
        'motionKindLabel': (label['frames'] as List).first['motionKind'],
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
  for (final mode in scaleMotionModes) {
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
  final motionRows = rows.where((r) => r['split'] == summarySplit).toList();
  final motionSummary = <String, Object?>{};
  for (final row in motionRows) {
    final frames = (row['decisions'] as List).cast<Map<String, Object?>>();
    final measured = frames
        .where((f) => (f['scaleMotion'] as Map?)?['available'] == true)
        .toList();
    final patches = frames
        .expand(
          (f) => ((f['scaleMotion'] as Map?)?['patches'] as List? ?? const []),
        )
        .cast<Map>();
    motionSummary['${row['layoutId']}/${row['mode']}'] = {
      'mode': row['mode'],
      'motionKindLabel': row['motionKindLabel'],
      'decisionFrames': frames.length,
      'framesWithLocalMatches': measured.length,
      'framesAddingMotionRisk': frames
          .where((f) => (f['scaleMotion'] as Map?)?['addsMotionRisk'] == true)
          .length,
      'framesApplyingMotionRisk': frames
          .where((f) => f['motionApplied'] == true)
          .length,
      'unknownPatches': frames.fold<int>(
        0,
        (n, f) =>
            n + (((f['scaleMotion'] as Map?)?['unknownPatches'] as int?) ?? 0),
      ),
      'patchClassifications': {
        for (final kind in VisiblePatchMotion.values)
          kind.name: patches
              .where((p) => p['classification'] == kind.name)
              .length,
      },
      'minimumForwardUpperMps': patches.isEmpty
          ? null
          : patches
                .map(
                  (p) => ((p['velocityUpperMps'] as List)[1] as num).toDouble(),
                )
                .reduce((a, b) => a < b ? a : b),
      'maximumForwardLowerMps': patches.isEmpty
          ? null
          : patches
                .map(
                  (p) => ((p['velocityLowerMps'] as List)[1] as num).toDouble(),
                )
                .reduce((a, b) => a > b ? a : b),
      'minimumLateralUpperMps': patches.isEmpty
          ? null
          : patches
                .map(
                  (p) => ((p['velocityUpperMps'] as List)[0] as num).toDouble(),
                )
                .reduce((a, b) => a < b ? a : b),
      'legacyMaximumApproachTrend': row['maximumApproachTrend'],
      'correspondenceScores': {
        for (final key in [
          'objectMatches',
          'backgroundMatches',
          'surfaceMismatch',
          'correctObjectMotion',
          'incorrectVelocityIntervals',
          'falseBackgroundMotion',
        ])
          key: frames.fold<int>(
            0,
            (n, f) =>
                n + (((f['correspondenceScore'] as Map)[key] as int?) ?? 0),
          ),
      },
    };
  }
  final report = <String, Object?>{
    'schemaVersion': 1,
    if (knownCorpusRegression) 'evaluationScope': 'knownCorpusRegression',
    'benchmarkId': fixture.manifest['corpusId'],
    'motionAuthority':
        'local matched visible patches only; never certifies object stationarity or free space',
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
    'sourceSha256': scaleMotionSourceHashes(root),
    'summaries': summaries,
    'motionSummary': motionSummary,
    'sequences': rows,
  };
  final stem = knownRegression
      ? 'camera_scale_motion_known_regression'
      : developmentOnly
      ? 'camera_scale_motion_development'
      : 'camera_scale_motion';
  final reportPath = 'docs/_baseline_logs/$stem.json';
  final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  if (write) {
    File(reportPath).writeAsStringSync(rendered);
    File('docs/_baseline_logs/${stem}_decision_timing.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'scope': 'measured desktop wall clock, separate from functional reaction offsets; excludes scan and NN',
        'frames': timings,
        'summaries': {
          for (final mode in scaleMotionModes) mode: {
              for (final key in ['normalizationMs', 'scaleMotionMs', 'detectorTrackerMs', 'reconstructionMs', 'runtimeMs', 'decisionComputeMs']) key: {
                  for (final q in [.5, .95]) q == .5 ? 'p50' : 'p95': scaleMotionPercentile(timings.where((r) => r['mode'] == mode).map((r) => r[key] as double).toList(), q),
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
