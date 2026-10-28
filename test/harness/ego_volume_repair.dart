import 'dart:convert';
import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_ego_motion.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/separated_motion_risk.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/runtime/volume_authority_spatial_runtime.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

import '../../tool/model_benchmark/fast_camera_motion_fixture.dart';
import 'blender_visible_body_fixture.dart';
import 'camera_visible_passage_fixture.dart';
import 'ego_motion_experiment.dart' show egoCorpus, egoRoot, egoPoseContract;
import 'ego_volume_fixture.dart';
import 'sequence_first_return_replay.dart' show sequenceAssociationInput;

const repairRoot = 'scratch/evidence-authority-fix-2026-10-10';

Map<String, Object?> runEgoVolumeRepair() {
  final fixture = VisibleFixture(root: egoCorpus), volume = EgoVolumeFixture();
  final prior = bodyJson('$egoRoot/replay.json');
  final cases = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    final source = CameraEgoMotionSource(
      poseContract: egoPoseContract,
      localCalibration: fixture.calibration(),
      rgbContract: fastRgbContract,
    );
    final legacy = GenericObstacleDetector(
      collectCameraSupport: true,
      collectOpeningDiagnostics: true,
    );
    final stable = FrameStableGenericObstacleDetector(
      collectCameraSupport: true,
      collectOpeningDiagnostics: true,
    );
    final trackers = {
      for (final mode in ['legacy', 'frameStable'])
        mode: GenericObstacleTracker(),
    };
    final engines = <String, SpatialSafetyRuntime>{};
    final config = PassageClearanceShadowConfiguration(
      calibration: volume.calibration(),
      request: visibleRequest,
      policy: pairedBodyPolicy,
      requireCameraEvidence: true,
      associateCameraTracks: true,
      cameraTrackModelHash: fixture.ncnn['modelBinSha256'],
    );
    for (final mode in trackers.keys) {
      engines['$mode/singleViewControl'] = ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
      );
      engines['$mode/fixedSingleView'] = VolumeAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
      );
      engines['$mode/sameRigControl'] = ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        shadowPassage: config,
      );
      engines['$mode/fixedRig'] = VolumeAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        shadowPassage: config,
      );
    }
    for (final e in engines.values) {
      e.beginSession(
        1,
        now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1000),
      );
    }
    final rows = <Map<String, Object?>>[];
    for (final f in fixture.frames(layout)) {
      final stamp = f.capturedAtUs, now = stamp + 2000;
      final meta = (layout['frames'] as List).cast<Map>().singleWhere(
        (v) => v['frameId'] == f.frameId,
      );
      final batch = volume.batch(layout['id'], f.frameId);
      final p = WalkingOriginPose(
        providerId: meta['poseProviderId'],
        revision: meta['poseRevision'],
        localReferenceFrameId: egoPoseContract.localReferenceFrameId,
        worldReferenceFrameId: egoPoseContract.worldReferenceFrameId,
        frameId: f.frameId,
        capturedAtUs: stamp,
        sessionGeneration: 1,
        producedAtUs: stamp + 1000,
        originWorldM: (meta['walkingOriginWorldM'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
        positionErrorM: (meta['posePositionErrorM'] as num).toDouble(),
        confidence: 1,
        healthy: true,
        fixedHeading: true,
      );
      final motion = source.observe(
        fastInput(fixture, layout, f),
        pose: p,
        nowUs: now,
      );
      final relative = DepthFrame(
        values: DepthMapOps.normalizeRelativeProximity(
          Float32List.fromList(fixture.raw(layout, f.frameId)),
        ),
        confidence01: Float32List.fromList(List.filled(65536, 1)),
        width: 256,
        height: 256,
        timestampUs: stamp,
        provider: DepthProviderKind.ncnnRelative,
        semantics: DepthValueSemantics.relativeProximity,
        modelId: 'midas-small-ncnn',
        modelHash: fixture.ncnn['modelBinSha256'],
        preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
        cropTopFraction: 0,
        frameQuality: 1,
        alignedToImage: true,
      );
      final rig = volume.source(batch, volume.frames(batch), stamp + 1000);
      final observation = rig.observationFor(volume.context(batch, now));
      final proof = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
          .evaluate(
            request: visibleRequest,
            context: volume.context(batch, now),
            calibration: volume.calibration(),
            observation: observation,
          );
      final arms = <String, Object?>{};
      final previousRow =
          ((prior['cases'] as List).cast<Map>().singleWhere(
                    (c) => c['layoutId'] == layout['id'],
                  )['frames']
                  as List)
              .cast<Map>()
              .singleWhere((r) => r['frameId'] == f.frameId);
      if (jsonEncode(motion.toDiagnosticMap()) !=
          jsonEncode(previousRow['egoMotion'])) {
        throw StateError('Changed frozen ego motion');
      }
      for (final mode in trackers.keys) {
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
        final attribution = SeparatedMotionRisk.frame(
          tracks,
          motion.bodyRelativeMotion,
          now,
        );
        if (jsonEncode(attribution) !=
            jsonEncode((previousRow['arms'] as Map)[mode]['riskAttribution'])) {
          throw StateError('Raw relative tracks or body motion changed');
        }
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
        final primary = copyVisibleFrame(f, modelHash: volume.hash);
        final outputs = <String, Object?>{};
        for (final lane in [
          'singleViewControl',
          'fixedSingleView',
          'sameRigControl',
          'fixedRig',
        ]) {
          final engine = engines['$mode/$lane']!;
          final hasRig = lane.endsWith('Rig') || lane == 'sameRigControl';
          final before = engine.sceneModel.revision;
          final result = engine is VolumeAuthoritySpatialRuntime
              ? engine.ingestGenericGeometry(
                  header: header,
                  detection: detection,
                  tracks: tracks,
                  now: DateTime.fromMicrosecondsSinceEpoch(now),
                  orientationValid: true,
                  userMoving: true,
                  poseQuality: 1,
                  bodyMotion: motion.bodyRelativeMotion,
                  passageObservation: hasRig ? observation : null,
                  cameraTrackInput: hasRig
                      ? sequenceAssociationInput(header, primary, f)
                      : null,
                )
              : engine.ingestGenericGeometry(
                  header: header,
                  detection: detection,
                  tracks: tracks,
                  now: DateTime.fromMicrosecondsSinceEpoch(now),
                  orientationValid: true,
                  userMoving: true,
                  poseQuality: 1,
                  passageObservation: hasRig ? observation : null,
                  cameraTrackInput: hasRig
                      ? sequenceAssociationInput(header, primary, f)
                      : null,
                );
          if (!result.accepted ||
              result.submittedAction?.delivery.name != 'shadow' ||
              engine.arbiter.active != null ||
              result.snapshot.revision <= before) {
            throw StateError('Invalid shadow admission/clock/history');
          }
          final forward = result.snapshot.polarSectors.singleWhere(
            (s) => s.id == 'forward',
          );
          final row = {
            'action': result.decision!.action.kind.name,
            'rule': result.decision!.action.ruleId,
            'delivery': result.submittedAction!.delivery.name,
            'arbiterActive': false,
            'previousRevision': before,
            'revision': result.snapshot.revision,
            'unknown': forward.unknownProbability,
            'occupancy': forward.occupancyProbability,
            'movingThreatRisk': forward.movingThreatRisk,
          };
          if (lane == 'singleViewControl' &&
              row['action'] !=
                  previousRow['arms'][mode]['runtime']['canonical']['action']) {
            throw StateError('Frozen single-view control changed');
          }
          outputs[lane] = row;
        }
        arms[mode] = {'riskAttribution': attribution, 'runtime': outputs};
      }
      rows.add({
        'frameId': f.frameId,
        'capturedAtUs': stamp,
        'nowUs': now,
        'sessionStarts': 1,
        'userMoving': true,
        'bodyMotion': motion.bodyRelativeMotion.toDiagnosticMap(),
        'volume': {
          'status': proof.status.name,
          'reasons': proof.reasons.map((v) => v.name).toList(),
          'coversCameraRecoveryVolume': proof.coversCameraRecoveryVolume,
          'validUntilUs': proof.validUntilUs,
          'sourceDiagnostics': rig.diagnostics,
        },
        'arms': arms,
      });
    }
    cases.add({'layoutId': layout['id'], 'frames': rows});
  }
  // Scoring is performed only after all consumer decisions.
  final labels = bodyJson('$egoCorpus/annotations.json');
  final outcomes = <String, Map<String, int>>{
    for (final mode in ['legacy', 'frameStable'])
      for (final lane in [
        'singleViewControl',
        'fixedSingleView',
        'sameRigControl',
        'fixedRig',
      ])
        '$mode/$lane': {
          'hazardStops': 0,
          'hazardMisses': 0,
          'falseStops': 0,
          'passableContinues': 0,
        },
  };
  var hazards = 0, passable = 0;
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
      if (hazard) {
        hazards++;
      } else {
        passable++;
      }
      for (final arm in (row['arms'] as Map).entries) {
        for (final lane in (arm.value['runtime'] as Map).entries) {
          final counts = outcomes['${arm.key}/${lane.key}']!;
          final stop = lane.value['action'] == 'stopNow';
          final key = hazard
              ? (stop ? 'hazardStops' : 'hazardMisses')
              : (stop ? 'falseStops' : 'passableContinues');
          counts[key] = counts[key]! + 1;
        }
      }
    }
  }
  return {
    'schemaVersion': 1,
    'scope':
        'synthetic shadow current volume authority repair; original instantaneous scoring unchanged',
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'androidReadinessEstablished': false,
    'latencyMeasured': false,
    'newFit': false,
    'wholeObjectStationarityCertified': false,
    'priorReplaySha256': bodySha('$egoRoot/replay.json'),
    'opticalManifestSha256': volume.hash,
    'corpusManifestSha256': fixture.modelHash,
    'summary': {
      'captures': 42,
      'physicalHazardFrames': hazards,
      'passableFrames': passable,
      'runtime': outcomes,
    },
    'cases': cases,
  };
}
