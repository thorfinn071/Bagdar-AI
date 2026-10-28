import 'dart:typed_data';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_ego_motion.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/separated_motion_risk.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/ego_motion_shadow_adapter.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import '../../tool/model_benchmark/fast_camera_motion_fixture.dart';
import 'camera_visible_passage_fixture.dart';

const egoRoot = 'scratch/ego-motion-2026-10-10';
const egoCorpus = '$egoRoot/corpus';
const egoPoseContract = WalkingPoseContract(
  providerId: 'synthetic-original-capture-pose',
  revision: 'translation-fixed-heading-v1',
  localReferenceFrameId: 'synthetic-walking-frame-v1',
  worldReferenceFrameId: 'synthetic-fixed-ego-world-v1',
);

DepthFrame _relative(List<double> raw, int stamp, String hash) => DepthFrame(
  values: DepthMapOps.normalizeRelativeProximity(Float32List.fromList(raw)),
  confidence01: Float32List.fromList(List.filled(raw.length, 1)),
  width: 256,
  height: 256,
  timestampUs: stamp,
  provider: DepthProviderKind.ncnnRelative,
  semantics: DepthValueSemantics.relativeProximity,
  modelId: 'midas-small-ncnn',
  modelHash: hash,
  preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
  cropTopFraction: 0,
  frameQuality: 1,
  alignedToImage: true,
);

Map<String, Object?> _decision(
  SpatialSafetyRuntime engine,
  SpatialRuntimeResult result,
  int previous,
) {
  if (!result.accepted ||
      result.submittedAction?.delivery.name != 'shadow' ||
      engine.arbiter.active != null ||
      result.snapshot.revision <= previous) {
    throw StateError('Invalid shadow admission/clock/history');
  }
  final f = result.snapshot.polarSectors.firstWhere((e) => e.id == 'forward');
  return {
    'action': result.decision!.action.kind.name,
    'rule': result.decision!.action.ruleId,
    'delivery': result.submittedAction!.delivery.name,
    'arbiterActive': false,
    'previousRevision': previous,
    'revision': result.snapshot.revision,
    'unknown': f.unknownProbability,
    'occupancy': f.occupancyProbability,
    'movingThreatRisk': f.movingThreatRisk,
    'observedFraction': result.snapshot.observedField.observedFraction,
  };
}

Map<String, Object?> runEgoMotionExperiment() {
  final fixture = VisibleFixture(root: egoCorpus);
  final layouts = (fixture.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>();
  final cases = <Map<String, Object?>>[];
  for (final layout in layouts) {
    final naive = CameraFastMetricMotionSource(
      calibration: fixture.calibration(),
      rgbContract: fastRgbContract,
    );
    final source = CameraEgoMotionSource(
      poseContract: egoPoseContract,
      localCalibration: fixture.calibration(),
      rgbContract: fastRgbContract,
    );
    final canonical = <String, SpatialSafetyRuntime>{};
    final controls = <String, SpatialSafetyRuntime>{},
        augmented = <String, SpatialSafetyRuntime>{};
    final scenes = <String, CameraMetricMotionShadowScene>{};
    final trackers = <String, GenericObstacleTracker>{};
    final legacy = GenericObstacleDetector(
      collectCameraSupport: true,
      collectOpeningDiagnostics: true,
    );
    final stable = FrameStableGenericObstacleDetector(
      collectCameraSupport: true,
      collectOpeningDiagnostics: true,
    );
    for (final mode in ['legacy', 'frameStable']) {
      scenes[mode] = CameraMetricMotionShadowScene();
      trackers[mode] = GenericObstacleTracker();
      canonical[mode] = ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
      );
      controls[mode] = SpatialSafetyRuntime(
        healthCoordinator: CoreHealthCoordinator(),
      );
      augmented[mode] = SpatialSafetyRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        sceneModel: scenes[mode],
      );
      for (final engine in [
        canonical[mode]!,
        controls[mode]!,
        augmented[mode]!,
      ]) {
        engine.beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1000),
        );
      }
    }
    final rows = <Map<String, Object?>>[];
    for (final f in fixture.frames(layout)) {
      final stamp = f.capturedAtUs, now = stamp + 2000;
      final metadata = (layout['frames'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((v) => v['frameId'] == f.frameId);
      final input = fastInput(fixture, layout, f);
      final p = WalkingOriginPose(
        providerId: metadata['poseProviderId'],
        revision: metadata['poseRevision'],
        localReferenceFrameId: egoPoseContract.localReferenceFrameId,
        worldReferenceFrameId: egoPoseContract.worldReferenceFrameId,
        frameId: f.frameId,
        capturedAtUs: stamp,
        sessionGeneration: 1,
        producedAtUs: stamp + 1000,
        originWorldM: (metadata['walkingOriginWorldM'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
        positionErrorM: (metadata['posePositionErrorM'] as num).toDouble(),
        confidence: 1,
        healthy: true,
        fixedHeading: true,
      );
      final n = naive.observe(input, nowUs: now),
          motion = source.observe(input, pose: p, nowUs: now);
      final relative = _relative(
        fixture.raw(layout, f.frameId),
        stamp,
        fixture.ncnn['modelBinSha256'],
      );
      final arms = <String, Object?>{};
      for (final mode in ['legacy', 'frameStable']) {
        final detection = mode == 'legacy'
            ? legacy.detect(
                frame: relative,
                pitchDeg: 6,
                rollDeg: 0,
                motion: MotionState.walking,
                imageTimestampUs: stamp,
              )
            : stable.detect(
                frame: relative,
                pitchDeg: 6,
                rollDeg: 0,
                motion: MotionState.walking,
                imageTimestampUs: stamp,
              );
        final tracks = trackers[mode]!.update(
          observations: detection.observations,
          timestampUs: stamp,
          relative: true,
        );
        final header = ObservationHeader(
          providerId: 'desktop-midas',
          modelId: relative.modelId,
          modelHash: relative.modelHash,
          preprocessId: relative.preprocessId,
          sessionGeneration: 1,
          frameId: f.frameId,
          sourceTimestampUs: stamp,
          producedAtUs: stamp + 1000,
          transformId: f.transformId,
          confidence: detection.detectorQuality.clamp(0, 1),
          health: ObservationHealth.healthy,
        );
        final added = applyEgoMotionShadow(
          motion,
          scenes[mode]!,
          sessionGeneration: 1,
          frameId: f.frameId,
          capturedAtUs: stamp,
          transformId: f.transformId,
          nowUs: now,
        );
        final runtime = <String, Object?>{};
        for (final entry in {
          'canonical': canonical[mode]!,
          'additiveControl': controls[mode]!,
          'additiveShadow': augmented[mode]!,
        }.entries) {
          final before = entry.value.sceneModel.revision;
          final result = entry.value.ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: tracks,
            now: DateTime.fromMicrosecondsSinceEpoch(now),
            orientationValid: true,
            userMoving: true,
            poseQuality: 1,
          );
          runtime[entry.key] = _decision(entry.value, result, before);
        }
        arms[mode] = {
          'rejection': detection.rejectReason.name,
          'quality': detection.detectorQuality,
          'riskAttribution': SeparatedMotionRisk.frame(
            tracks,
            motion.bodyRelativeMotion,
            now,
          ),
          'metricRiskAdded': added,
          'runtime': runtime,
        };
      }
      rows.add({
        'frameId': f.frameId,
        'capturedAtUs': stamp,
        'nowUs': now,
        'sessionStarts': 1,
        'userMoving': true,
        'naiveLocalMotion': n.toDiagnosticMap(),
        'egoMotion': motion.toDiagnosticMap(),
        'arms': arms,
      });
    }
    cases.add({'layoutId': layout['id'], 'frames': rows});
  }
  // Only now read scoring labels, after every consumer output has been computed.
  final labels = visibleJson('$egoCorpus/annotations.json');
  final summary = <String, Object?>{
    'captures': 0,
    'physicalHazardFrames': 0,
    'passableFrames': 0,
  };
  final outcomes = <String, Map<String, int>>{
    for (final mode in ['legacy', 'frameStable'])
      for (final lane in ['canonical', 'additiveControl', 'additiveShadow'])
        '$mode/$lane': {
          'hazardStops': 0,
          'hazardMisses': 0,
          'falseStops': 0,
          'passableContinues': 0,
        },
  };
  final motionCounts = <String, Map<String, int>>{};
  for (final c in cases) {
    final annotation = (labels['layouts'] as List).cast<Map>().singleWhere(
      (v) => v['layoutId'] == c['layoutId'],
    );
    for (final row in (c['frames'] as List).cast<Map<String, Object?>>()) {
      final label = (annotation['frames'] as List).cast<Map>().singleWhere(
        (v) => v['frameId'] == row['frameId'],
      );
      row['scoringOnly'] = label;
      final hazard = label['physicalHazard'] == true;
      summary['captures'] = (summary['captures'] as int) + 1;
      final field = hazard ? 'physicalHazardFrames' : 'passableFrames';
      summary[field] = (summary[field] as int) + 1;
      final ego = row['egoMotion'] as Map;
      for (final entry in {
        'naive': row['naiveLocalMotion'],
        'world': ego['worldMotion'],
        'body': ego['bodyRelativeMotion'],
      }.entries) {
        final count = motionCounts.putIfAbsent(
          '${c['layoutId']}/${entry.key}',
          () => {
            'pairsAvailable': 0,
            'riskFrames': 0,
            'approaching': 0,
            'receding': 0,
            'lateral': 0,
            'consistentWithStationary': 0,
            'uncertain': 0,
          },
        );
        final m = entry.value as Map;
        if (m['available'] == true) {
          count['pairsAvailable'] = count['pairsAvailable']! + 1;
        }
        if (m['addsMotionRisk'] == true) {
          count['riskFrames'] = count['riskFrames']! + 1;
        }
        for (final patch in (m['patches'] as List).cast<Map>()) {
          final name = patch['classification'] as String;
          count[name] = count[name]! + 1;
        }
      }
      for (final arm in (row['arms'] as Map).entries) {
        for (final lane in ((arm.value as Map)['runtime'] as Map).entries) {
          final counts = outcomes['${arm.key}/${lane.key}']!;
          final stop = (lane.value as Map)['action'] == 'stopNow';
          final key = hazard
              ? (stop ? 'hazardStops' : 'hazardMisses')
              : (stop ? 'falseStops' : 'passableContinues');
          counts[key] = counts[key]! + 1;
        }
      }
    }
  }
  summary['runtime'] = outcomes;
  summary['motion'] = motionCounts;
  return {
    'schemaVersion': 1,
    'scope':
        'new synthetic original RGB/visible depth/original-capture poses; fixed replay clock',
    'promotionAllowed': false,
    'newFit': false,
    'latencyMeasured': false,
    'androidReadinessEstablished': false,
    'bodyCoverageEstablished': false,
    'wholeObjectStationarityCertified': false,
    'canonicalRuntimeChanged': false,
    'laneContract':
        'canonical confidence runtime is unchanged; paired plain-scene controls validate additive motion only',
    'corpusManifestSha256': fixture.modelHash,
    'ncnnManifestSha256': visibleSha('$egoCorpus/ncnn/manifest.json'),
    'summary': summary,
    'cases': cases,
  };
}
