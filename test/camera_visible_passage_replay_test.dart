import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/camera_visible_passage_fixture.dart';
import 'harness/frozen_replay_sources.dart';

const _report = 'docs/_baseline_logs/camera_visible_passage_replay.json';
const _write = bool.fromEnvironment('BAGDAR_WRITE_VISIBLE_REPORT');
const _check = bool.fromEnvironment('BAGDAR_CHECK_VISIBLE_REPORT');
double? _percentile(List<double> values, double q) {
  if (values.isEmpty) return null;
  values.sort();
  return values[((values.length * q).ceil() - 1).clamp(0, values.length - 1)];
}

void main() {
  test(
    'camera-only visible passage benchmark and shadow stateful decisions',
    () {
      runVisiblePassageBenchmark(
        developmentOnly: const bool.fromEnvironment(
          'BAGDAR_VISIBLE_DEVELOPMENT_ONLY',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Map<String, Object?> runVisiblePassageBenchmark({
  VisibleFixture? inputFixture,
  String reportPath = _report,
  String timingPath = 'docs/_baseline_logs/camera_visible_decision_timing.json',
  String ncnnTimingPath = 'docs/_baseline_logs/camera_visible_ncnn_timing.json',
  bool write = _write,
  bool check = _check,
  bool developmentOnly = false,
  bool associationExperiment = false,
  bool knownCorpusRegression = false,
}) {
  if (knownCorpusRegression && (write || check || developmentOnly)) {
    throw ArgumentError('Known-corpus replay cannot replace frozen reports.');
  }
  final fixture = inputFixture ?? VisibleFixture();
  String? developmentFreezeHash;
  if (associationExperiment &&
      !developmentOnly &&
      fixture.manifest['corpusId'] == 'camera-track-passage-v1') {
    const freezePath =
        'docs/_baseline_logs/camera_track_development_freeze.json';
    final freeze = visibleJson(freezePath);
    verifyFrozenReplaySources(
      freeze['sourceSha256'] as Map<String, dynamic>,
      allowHistoricalSources: knownCorpusRegression,
    );
    if (freeze['corpusManifestSha256'] !=
        visibleSha('${fixture.root}/manifest.json')) {
      throw StateError('Holdout geometry changed after freeze');
    }
    developmentFreezeHash = visibleSha(freezePath);
  }
  // Scoring annotations are read here, never forwarded into the source.
  final labels = {
    for (final label
        in visibleJson('${fixture.root}/annotations.json')['layouts'] as List)
      label['layoutId'] as String: label as Map<String, dynamic>,
  };
  final rows = <Map<String, Object?>>[], timings = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    if (layout['split'] == 'calibration' ||
        (developmentOnly && layout['split'] == 'test')) {
      continue;
    }
    final exact = fixture.frames(layout), anchor = exact.first;
    final label = labels[layout['id']]!;
    final modes = associationExperiment
        ? ['ncnn-control', 'visible-scan', 'visible-associated']
        : [
            'ncnn-control',
            'visible-single',
            'visible-scan',
            'visible-model-grid',
            'midas-diagnostic',
          ];
    if (!associationExperiment &&
        ((layout['id'] as String).contains('-wide-r0-p0-v0') ||
            (layout['id'] as String).contains('-covered-wide-r0-p5-v0'))) {
      modes.addAll([
        'noise5',
        'noise20',
        'drop10',
        'drop40',
        'strip',
        'rgb-noise',
        'rgb-blur',
      ]);
    }
    if (!associationExperiment &&
        [
          '-pole-r0-p0-v0',
          '-low-bar-r0-p0-v0',
          '-subpixel-pole-r0-p0-v0',
        ].any((suffix) => (layout['id'] as String).endsWith(suffix))) {
      modes.addAll(['noise5', 'noise20', 'drop10', 'drop40', 'strip']);
    }
    for (final mode in modes) {
      final detector = GenericObstacleDetector(
            collectCameraSupport: associationExperiment,
          ),
          tracker = GenericObstacleTracker();
      final metric =
          mode != 'midas-diagnostic' ||
          fixture.ncnn['calibration']['accepted'] == true;
      final calibration = fixture.calibration(metric: metric);
      final runtime =
          SpatialSafetyRuntime(
            healthCoordinator: CoreHealthCoordinator(),
            shadowPassage: mode == 'ncnn-control'
                ? null
                : PassageClearanceShadowConfiguration(
                    calibration: calibration,
                    request: visibleRequest,
                    policy: mode == 'visible-single'
                        ? visibleSinglePolicy
                        : visibleScanPolicy,
                    requireCameraEvidence: true,
                    associateCameraTracks: mode == 'visible-associated',
                    cameraTrackModelHash:
                        fixture.ncnn['modelBinSha256'] as String,
                  ),
          )..beginSession(
            1,
            now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1),
          );
      final raw = fixture.raw(
        layout,
        1,
        variant: mode == 'rgb-noise' || mode == 'rgb-blur' ? mode : 'clean',
      );
      final relative = DepthMapOps.normalizeRelativeProximity(
        Float32List.fromList(raw),
      );
      var sources = mode == 'visible-single'
          ? [anchor]
          : exact.skip(1).toList();
      if (['noise5', 'noise20', 'drop10', 'drop40', 'strip'].contains(mode)) {
        sources = sources.map((f) => damagedVisibleFrame(f, mode)).toList();
      }
      if (mode == 'visible-model-grid') {
        sources = sources.map(modelGridReference).toList();
      }
      if (mode == 'midas-diagnostic') {
        sources = sources
            .map(
              (f) => diagnosticMidasFrame(
                f,
                fixture.raw(layout, f.frameId),
                fixture.ncnn['calibration'] as Map<String, dynamic>,
              ),
            )
            .toList();
      }
      final steps = mode == 'visible-single'
          ? [0]
          : [0, 2000000, 2200000, 2400000];
      var stops = 0, holds = 0, continues = 0, applied = 0;
      var unjustifiedClearances = 0;
      final traces = <Map<String, Object?>>[];
      int? firstStop;
      PassageClearanceResult? finalPassage;
      Map<String, Object?>? finalTrace;
      for (var step = 0; step < steps.length; step++) {
        final offset = steps[step],
            stamp = visibleStamp + offset,
            id = step == 0 ? 1 : 10 + step;
        final moving = step == 0 || step == steps.length - 1;
        final orientationValid =
            (layout['frames'][0]['rollDeg'] as num).abs() <= 20;
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
        final total = Stopwatch()..start();
        final detection = detector.detect(
          frame: depth,
          pitchDeg: (layout['frames'][0]['pitchDeg'] as num).toDouble(),
          rollDeg: (layout['frames'][0]['rollDeg'] as num).toDouble(),
          motion: moving ? MotionState.walking : MotionState.stationary,
          imageTimestampUs: stamp,
        );
        final tracks = tracker.update(
          observations: detection.observations,
          timestampUs: stamp,
          relative: true,
        );
        final context = PassageEvaluationContext(
          nowUs: stamp + 2000,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          sessionGeneration: 1,
          frameId: id,
          rgbTimestampUs: stamp,
          transformId: calibration.transformId,
        );
        CameraPassageClearanceSource? source;
        PassageClearanceObservation? observation;
        CameraVisibleDepthFrame? currentDepth;
        final reconstruction = Stopwatch()..start();
        if (mode != 'ncnn-control') {
          final current = copyVisibleFrame(
            mode == 'visible-model-grid'
                ? modelGridReference(anchor)
                : mode == 'midas-diagnostic'
                ? diagnosticMidasFrame(
                    anchor,
                    raw,
                    fixture.ncnn['calibration'] as Map<String, dynamic>,
                  )
                : [
                    'noise5',
                    'noise20',
                    'drop10',
                    'drop40',
                    'strip',
                  ].contains(mode)
                ? damagedVisibleFrame(anchor, mode)
                : anchor,
            frameId: id,
            timestamp: stamp,
          );
          currentDepth = current;
          // No movement/rotation sweep before a completed stationary scan.
          final input = step == 0 ? [current] : [...sources, current];
          source = CameraPassageClearanceSource(
            calibration: calibration,
            request: visibleRequest,
            frames: input,
            producedAtUs: stamp + 1000,
            allowStaticSyntheticScan: step > 0,
          );
          observation = source.observationFor(context);
          finalPassage =
              PassageClearanceEvaluator(
                policy: mode == 'visible-single'
                    ? visibleSinglePolicy
                    : visibleScanPolicy,
              ).evaluate(
                request: visibleRequest,
                context: context,
                calibration: calibration,
                observation: observation,
              );
        }
        reconstruction.stop();
        final runtimeTimer = Stopwatch()..start();
        final header = ObservationHeader(
          providerId: 'desktop-ncnn-midas-depth',
          modelId: depth.modelId,
          modelHash: depth.modelHash,
          preprocessId: depth.preprocessId,
          sessionGeneration: 1,
          frameId: id,
          sourceTimestampUs: stamp,
          producedAtUs: stamp + 1000,
          transformId: calibration.transformId,
          confidence: detection.detectorQuality,
          health: ObservationHealth.healthy,
        );
        final cameraInput = currentDepth == null
            ? null
            : CameraTrackAssociationInput(
                rgbHeader: header,
                depth: currentDepth,
                imageGeometry: CameraTrackImageGeometry(
                  cameraId: anchor.cameraId,
                  width: anchor.width,
                  height: anchor.height,
                  fx: anchor.fx,
                  fy: anchor.fy,
                  cx: anchor.cx,
                  cy: anchor.cy,
                  rotation: anchor.rotation,
                  originM: anchor.originM,
                ),
              );
        final result = runtime.ingestGenericGeometry(
          header: header,
          detection: detection,
          tracks: tracks,
          now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
          orientationValid: orientationValid,
          userMoving: moving,
          poseQuality: 1,
          passageObservation: observation,
          cameraTrackInput: mode == 'visible-associated' ? cameraInput : null,
        );
        runtimeTimer.stop();
        total.stop();
        expect(result.accepted, isTrue);
        expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
        expect(runtime.arbiter.active, isNull);
        final action = result.decision!.action.kind;
        if (action == SafetyActionKind.stopNow) {
          stops++;
          firstStop ??= offset + 2000;
        }
        if (action == SafetyActionKind.holdAndScan) holds++;
        if (action == SafetyActionKind.continueForward) continues++;
        if (result.passageClearanceApplied) applied++;
        final forward = result.decision!.candidates.firstWhere(
          (candidate) => candidate.direction.name == 'forward',
        );
        // Functional time is an explicit 2ms replay model, not CPU latency.
        finalTrace = {
          if (associationExperiment)
            'tracks': [
              for (final track in tracks)
                {
                  'trackId': track.id,
                  'confirmed': track.confirmed,
                  'misses': track.misses,
                  'geometry': track.last.geometry.name,
                  'zone': track.last.zone.name,
                  'normalizedBounds': [
                    track.last.normalizedBounds.left,
                    track.last.normalizedBounds.top,
                    track.last.normalizedBounds.right,
                    track.last.normalizedBounds.bottom,
                  ],
                  'pixelCount': track.last.pixelCount,
                  'confidence': track.last.confidence,
                  'relativeProximity': track.last.relativeProximity,
                  'approachTrend': track.approachTrend(),
                  'lastCapturedAtUs': track.timestampUsHist.isEmpty
                      ? null
                      : track.timestampUsHist.last,
                  'componentSupport': track.last.cameraSupport?.indices,
                  'association': runtime.cameraTrackAssociations[track.id]
                      ?.toDiagnosticMap(),
                },
            ],
          'step': step,
          'captureOffsetUs': offset,
          'userMoving': moving,
          'oldestEvidenceTimestampUs': observation?.oldestEvidenceTimestampUs,
          'action': action.name,
          'ruleId': result.decision!.action.ruleId,
          'plannerState': result.decision!.state.name,
          'plannerPreviousState': result.decision!.previousState.name,
          'plannerForward': {
            'observedFraction': forward.observedFraction,
            'unknownRisk': forward.unknownRisk,
            'collisionRisk': forward.collisionRisk,
            'dropRisk': forward.dropRisk,
            'movingThreatRisk': forward.movingThreatRisk,
            'surfaceContinuity': forward.surfaceContinuity,
            'positiveEvidencePassed': forward.positiveEvidencePassed,
            'rejectionReasons': forward.rejectionReasons
                .map((r) => r.name)
                .toList(),
          },
          'apertureHypothesis': detection.unknownReasons.contains(
            ObstacleUnknownReason.unverifiedAperture,
          ),
          'unknownReasons': detection.unknownReasons
              .map((r) => r.name)
              .toList(),
          'runtimePassageApplied': result.passageClearanceApplied,
          'runtimePassage': result.passageClearance?.toDiagnosticMap(),
          'detectorRejectReason': detection.rejectReason.name,
          'producer': source?.diagnostics,
          'reconstructedSections': observation?.sections
              .map(
                (s) => {
                  'forwardStartM': s.forwardStartM,
                  'forwardEndM': s.forwardEndM,
                  'state': s.state.name,
                  'bodyObservedFraction': s.bodyObservedFraction,
                  'floorObservedFraction': s.floorObservedFraction,
                  'leftBoundaryUpperM': s.leftBoundaryUpperM,
                  'rightBoundaryLowerM': s.rightBoundaryLowerM,
                  'headroomLowerBoundM': s.headroomLowerBoundM,
                  'floorRiseUpperBoundM': s.floorRiseUpperBoundM,
                  'floorDropUpperBoundM': s.floorDropUpperBoundM,
                },
              )
              .toList(),
          'unobservedBodyCellCenters': source?.unobservedBodyCellCenters,
          'bodyObservedFraction':
              observation == null || observation.sections.isEmpty
              ? null
              : observation.sections
                    .map((s) => s.bodyObservedFraction)
                    .reduce((a, b) => a < b ? a : b),
          'floorObservedFraction':
              observation == null || observation.sections.isEmpty
              ? null
              : observation.sections
                    .map((s) => s.floorObservedFraction)
                    .reduce((a, b) => a < b ? a : b),
          'passage': finalPassage?.toDiagnosticMap(),
          'certifiedWidthLowerBoundDeficitM':
              finalPassage?.minimumWidthLowerBoundM == null
              ? null
              : (label['idealWidthM'] as num) -
                    finalPassage!.minimumWidthLowerBoundM!,
          'certifiedHeadroomLowerBoundDeficitM':
              finalPassage?.minimumHeadroomLowerBoundM == null
              ? null
              : (label['idealHeadroomM'] as num) -
                    finalPassage!.minimumHeadroomLowerBoundM!,
          'dimensionSemantics':
              'certified request lower bounds; not estimates of the full doorway',
        };
        traces.add(finalTrace);
        if (write) {
          timings.add({
            'layoutId': layout['id'],
            'mode': mode,
            'step': step,
            'captureOffsetUs': offset,
            'physicalHazard': label['physicalHazard'],
            'action': action.name,
            'latestStopOffsetUs': label['latestStopOffsetUs'],
            'reconstructionMs': reconstruction.elapsedMicroseconds / 1000,
            'runtimeMs': runtimeTimer.elapsedMicroseconds / 1000,
            'decisionComputeMs': total.elapsedMicroseconds / 1000,
          });
        }
        if (mode != 'ncnn-control' &&
            (label['physicalHazard'] == true || !orientationValid)) {
          expect(
            action,
            isNot(SafetyActionKind.continueForward),
            reason: 'unsafe ${layout['id']} $mode step $step',
          );
        }
        if (finalPassage?.status == PassageClearanceStatus.measuredClear) {
          final justified =
              step > 0 &&
              label['scanObservationSufficient'] == true &&
              !['noise20', 'drop10', 'drop40', 'strip'].contains(mode);
          if (!justified || label['physicalHazard'] == true) {
            unjustifiedClearances++;
          }
          expect(
            justified,
            isTrue,
            reason: 'unobserved clearance ${layout['id']} $mode',
          );
          expect(
            label['physicalHazard'],
            false,
            reason: 'unjustified clearance ${layout['id']} $mode',
          );
          expect(orientationValid, isTrue);
        }
      }
      final sufficient =
          mode != 'visible-single' &&
          label['scanObservationSufficient'] == true &&
          !['noise20', 'drop10', 'drop40', 'strip'].contains(mode);
      rows.add({
        'layoutId': layout['id'],
        'split': layout['split'],
        'mode': mode,
        'physicalHazard': label['physicalHazard'],
        'sufficientObservationLabel': sufficient,
        'stops': stops,
        'holds': holds,
        'continues': continues,
        'firstStopOffsetUs': firstStop,
        'onTimeStop':
            label['physicalHazard'] == true &&
            firstStop != null &&
            firstStop <= label['latestStopOffsetUs'],
        'passageApplications': applied,
        'scanDurationUs': mode == 'visible-single' ? 0 : 2000000,
        'unjustifiedClearances': unjustifiedClearances,
        'decisions': traces,
        'final': finalTrace,
      });
    }
  }
  final summaries = <String, Object?>{};
  for (final mode in rows.map((r) => r['mode'] as String).toSet()) {
    final set = rows
        .where((r) => r['split'] == 'test' && r['mode'] == mode)
        .toList();
    final hazards = set.where((r) => r['physicalHazard'] == true).toList();
    final sufficient = set
        .where(
          (r) =>
              r['physicalHazard'] == false &&
              r['sufficientObservationLabel'] == true,
        )
        .toList();
    final falseStops = sufficient
        .where((r) => (r['final'] as Map)['action'] == 'stopNow')
        .length;
    summaries[mode] = {
      'testSequences': set.length,
      'hazardSequences': hazards.length,
      'onTimeStops': hazards.where((r) => r['onTimeStop'] == true).length,
      'lateStops': hazards
          .where(
            (r) => r['firstStopOffsetUs'] != null && r['onTimeStop'] != true,
          )
          .length,
      'missedStops': hazards
          .where((r) => r['firstStopOffsetUs'] == null)
          .length,
      'unsafeContinueSteps': hazards.fold<int>(
        0,
        (n, r) => n + (r['continues'] as int),
      ),
      'explicitlyBlockedHazards': hazards
          .where(
            (r) =>
                ((r['final'] as Map)['passage'] as Map?)?['status'] ==
                'blocked',
          )
          .length,
      'sufficientPassableSequences': sufficient.length,
      'falseStopSequences': falseStops,
      'falseStopRate': sufficient.isEmpty
          ? null
          : falseStops / sufficient.length,
      'falseHoldSequences': sufficient
          .where((r) => (r['final'] as Map)['action'] == 'holdAndScan')
          .length,
      'producerClearSufficientSequences': sufficient
          .where(
            (r) =>
                ((r['final'] as Map)['passage'] as Map?)?['status'] ==
                'measuredClear',
          )
          .length,
      'runtimeAppliedSufficientSequences': sufficient
          .where((r) => (r['final'] as Map)['runtimePassageApplied'] == true)
          .length,
      'certifiedWidthLowerBoundDeficitP50M': _percentile(
        sufficient
            .map((r) => (r['final'] as Map)['certifiedWidthLowerBoundDeficitM'])
            .whereType<double>()
            .toList(),
        .5,
      ),
      'certifiedHeadroomLowerBoundDeficitP50M': _percentile(
        sufficient
            .map(
              (r) => (r['final'] as Map)['certifiedHeadroomLowerBoundDeficitM'],
            )
            .whereType<double>()
            .toList(),
        .5,
      ),
      'insufficientObservationStops': set
          .where(
            (r) =>
                r['sufficientObservationLabel'] != true &&
                (r['final'] as Map)['action'] == 'stopNow',
          )
          .length,
      'insufficientObservationHolds': set
          .where(
            (r) =>
                r['sufficientObservationLabel'] != true &&
                (r['final'] as Map)['action'] == 'holdAndScan',
          )
          .length,
      'unjustifiedClearances': set.fold<int>(
        0,
        (n, r) => n + (r['unjustifiedClearances'] as int),
      ),
    };
  }
  final control = summaries['ncnn-control'] as Map,
      visible = summaries['visible-scan'] as Map;
  final report = {
    'schemaVersion': 1,
    if (knownCorpusRegression) 'evaluationScope': 'knownCorpusRegression',
    'benchmarkId': fixture.manifest['corpusId'],
    'scope': 'synthetic camera first-return, desktop MiDaS CPU, shadow only',
    'sourceSha256': {
      for (final path in [
        'lib/safety/perception/passage_clearance.dart',
        'lib/safety/perception/camera_passage_clearance_source.dart',
        'lib/safety/perception/camera_track_association.dart',
        'lib/models/generic_obstacle.dart',
        'lib/safety/runtime/passage_clearance_shadow.dart',
        'lib/safety/runtime/spatial_safety_runtime.dart',
        'lib/services/generic_obstacle_detector.dart',
        'lib/tracker/generic_obstacle_tracker.dart',
        'lib/safety/world/generic_geometry_scene_adapter.dart',
        'lib/safety/world/local_scene_model.dart',
        'lib/safety/world/scene_fusion_policy.dart',
        'lib/safety/world/relative_polar_grid.dart',
        'lib/safety/planning/guidance_state_machine.dart',
        'lib/safety/planning/corridor_generator.dart',
        'lib/safety/planning/corridor_evaluator.dart',
        'test/harness/camera_visible_passage_fixture.dart',
        'test/camera_visible_passage_replay_test.dart',
        '${fixture.root}/manifest.json',
        '${fixture.root}/annotations.json',
        '${fixture.root}/ncnn/manifest.json',
      ])
        path: visibleSha(path),
    },
    'functionalReplayProcessingUs': 2000,
    'frozenMidasCalibration': fixture.ncnn['calibration'],
    'summaries': summaries,
    'falseStopReductionEstablished':
        (visible['falseStopSequences'] as int) <
        (control['falseStopSequences'] as int),
    'cameraSafetyCriteriaPassed': summaries.entries
        .where((entry) => entry.key != 'ncnn-control')
        .every(
          (entry) =>
              (entry.value as Map)['unsafeContinueSteps'] == 0 &&
              (entry.value as Map)['unjustifiedClearances'] == 0 &&
              (entry.value as Map)['missedStops'] == 0 &&
              (entry.value as Map)['lateStops'] == 0,
        ),
    'deviceCalibrationEstablished': false,
    'promotionAllowed': false,
    if (developmentFreezeHash != null)
      'developmentFreezeSha256': developmentFreezeHash,
    if (associationExperiment)
      'associationImprovementEstablished':
          (summaries['visible-associated'] as Map)['falseStopSequences'] <
          visible['falseStopSequences'],
    'sequences': rows,
  };
  final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  if (developmentOnly) {
    File(
      associationExperiment
          ? 'scratch/camera-track-development.json'
          : 'scratch/passage-recovery-development.json',
    ).writeAsStringSync(rendered);
  }
  if (write) {
    File(reportPath).writeAsStringSync(rendered);
    final reconstruction = timings
        .map((r) => r['reconstructionMs'] as double)
        .toList();
    final decision = timings
        .map((r) => r['decisionComputeMs'] as double)
        .toList();
    final ncnnTiming = visibleJson(ncnnTimingPath);
    final completeStageSums = <double>[];
    final perMode = <String, Object?>{};
    for (final mode in timings.map((r) => r['mode'] as String).toSet()) {
      final set = timings.where((r) => r['mode'] == mode).toList();
      final sums = <double>[];
      final reactionEstimates = <Map<String, Object?>>[];
      final firstStops = <String>{};
      for (final row in set) {
        final variant = ['rgb-noise', 'rgb-blur'].contains(mode)
            ? mode
            : 'clean';
        final network = (ncnnTiming['frames'] as List).singleWhere(
          (f) =>
              f['layoutId'] == row['layoutId'] &&
              f['frameId'] == 1 &&
              f['variant'] == variant,
        );
        final sum =
            (network['preprocessingMs'] as num).toDouble() +
            (network['inferenceMs'] as num).toDouble() +
            (row['decisionComputeMs'] as double);
        sums.add(sum);
        if (row['physicalHazard'] == true &&
            row['action'] == 'stopNow' &&
            firstStops.add(row['layoutId'] as String)) {
          final elapsed = (row['captureOffsetUs'] as int) / 1000 + sum;
          reactionEstimates.add({
            'layoutId': row['layoutId'],
            'serialStageReactionEstimateMs': elapsed,
            'timelyEstimate':
                elapsed <= (row['latestStopOffsetUs'] as int) / 1000,
          });
        }
      }
      completeStageSums.addAll(sums);
      perMode[mode] = {
        'reconstructionP50Ms': _percentile(
          set.map((r) => r['reconstructionMs'] as double).toList(),
          .5,
        ),
        'reconstructionP95Ms': _percentile(
          set.map((r) => r['reconstructionMs'] as double).toList(),
          .95,
        ),
        'serialFullDecisionStageSumP50Ms': _percentile(sums.toList(), .5),
        'serialFullDecisionStageSumP95Ms': _percentile(sums.toList(), .95),
        'stepsExceeding100msProcessingBudget': sums
            .where((ms) => ms > 100)
            .length,
        'steps': sums.length,
        'timelyDesktopStageReactionEstimates': reactionEstimates
            .where((r) => r['timelyEstimate'] == true)
            .length,
        'lateDesktopStageReactionEstimates': reactionEstimates
            .where((r) => r['timelyEstimate'] != true)
            .length,
        'reactionEstimates': reactionEstimates,
      };
    }
    File(timingPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'scope': 'measured desktop stages, not end-to-end capture or Android latency', 'fullDecisionMethod': 'sum of separately measured preprocessing, pinned NCNN inference and Dart decision on matching anchor RGB; excludes asset loading, rendering and the 2000ms scan', 'reconstructionP50Ms': _percentile(reconstruction, .5), 'reconstructionP95Ms': _percentile(reconstruction, .95), 'decisionComputeP50Ms': _percentile(decision, .5), 'decisionComputeP95Ms': _percentile(decision, .95), 'serialFullDecisionStageSumP50Ms': _percentile(completeStageSums.toList(), .5), 'serialFullDecisionStageSumP95Ms': _percentile(completeStageSums.toList(), .95), 'perMode': perMode, 'steps': timings})}\n',
    );
  }
  if (check) {
    expect(
      File(reportPath).readAsStringSync(),
      rendered,
      reason: 'Visible report drift',
    );
  }
  stdout.writeln(jsonEncode(summaries));
  return report;
}
