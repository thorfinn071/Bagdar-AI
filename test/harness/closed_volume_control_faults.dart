// Versioned diagnostic harness derived from test/harness/volume_holdout_faults.dart.
// Frozen predecessors stay unchanged; only corpus identity and declared scope differ.
import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/volume_authority_spatial_runtime.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

import 'blender_visible_body_fixture.dart';
import 'blender_synchronized_rig_fixture.dart' show rigCopyFrame;
import 'camera_visible_passage_fixture.dart';
import 'sequence_first_return_replay.dart' show sequenceAssociationInput;
import 'closed_volume_control_fixture.dart';

const closedFaultNames = [
  'missingPrimary',
  'invalidReturns',
  'nonmetric',
  'foreignModel',
  'foreignPose',
  'lostUpper',
  'missingRig',
  'partialRig',
  'channelSkew1us',
  'staleCapture',
  'futureProduction',
  'foreignMotion',
];

Map<String, Object?> runClosedVolumeFaults() {
  final original = VisibleFixture(root: closedCorpus);
  final volume = ClosedVolumeFixture();
  final layout = (original.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>()
      .first;
  final frames = original.frames(layout);
  final trials = <Map<String, Object?>>[];
  for (final mode in ['legacy', 'frameStable']) {
    for (final afterClear in [false, true]) {
      for (final fault in closedFaultNames) {
        final legacy = GenericObstacleDetector(
          collectCameraSupport: true,
          collectOpeningDiagnostics: true,
        );
        final stable = FrameStableGenericObstacleDetector(
          collectCameraSupport: true,
          collectOpeningDiagnostics: true,
        );
        final tracker = GenericObstacleTracker();
        final engine =
            VolumeAuthoritySpatialRuntime(
              healthCoordinator: CoreHealthCoordinator(),
              shadowPassage: PassageClearanceShadowConfiguration(
                calibration: volume.calibration(),
                request: visibleRequest,
                policy: pairedBodyPolicy,
                requireCameraEvidence: true,
                associateCameraTracks: true,
                cameraTrackModelHash: original.ncnn['modelBinSha256'],
              ),
            )..beginSession(
              1,
              now: DateTime.fromMicrosecondsSinceEpoch(
                frames.first.capturedAtUs - 1000,
              ),
            );
        final rows = <Map<String, Object?>>[];
        final faultIndex = afterClear ? 1 : 0;
        for (var index = 0; index <= faultIndex + 1; index++) {
          final active = index == faultIndex ? fault : null;
          final f = frames[index], stamp = frames[index].capturedAtUs;
          final meta = (layout['frames'] as List).cast<Map>()[index];
          final nowUs = stamp + (active == 'staleCapture' ? 100001 : 2000);
          final relative = DepthFrame(
            values: DepthMapOps.normalizeRelativeProximity(
              Float32List.fromList(original.raw(layout, f.frameId)),
            ),
            confidence01: Float32List.fromList(List.filled(65536, 1)),
            width: 256,
            height: 256,
            timestampUs: stamp,
            provider: DepthProviderKind.ncnnRelative,
            semantics: DepthValueSemantics.relativeProximity,
            modelId: 'midas-small-ncnn',
            modelHash: original.ncnn['modelBinSha256'],
            preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
            cropTopFraction: 0,
            frameQuality: 1,
            alignedToImage: true,
          );
          final pitch = (meta['pitchDeg'] as num).toDouble(),
              roll = (meta['rollDeg'] as num).toDouble();
          final detection = mode == 'legacy'
              ? legacy.detect(
                  frame: relative,
                  pitchDeg: pitch,
                  rollDeg: roll,
                  motion: MotionState.walking,
                  imageTimestampUs: stamp,
                )
              : stable.detect(
                  frame: relative,
                  pitchDeg: pitch,
                  rollDeg: roll,
                  motion: MotionState.walking,
                  imageTimestampUs: stamp,
                );
          final tracks = tracker.update(
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
          var primary = copyVisibleFrame(f, modelHash: volume.hash);
          final batch = volume.batch(layout['id'], f.frameId);
          var channels = volume.frames(batch);
          switch (active) {
            case 'invalidReturns':
              primary = copyVisibleFrame(
                primary,
                valid: List.filled(primary.valid.length, false),
              );
              channels = [
                for (final c in channels)
                  rigCopyFrame(
                    c,
                    valid: List.filled(c.depth.valid.length, false),
                  ),
              ];
            case 'nonmetric':
              primary = copyVisibleFrame(
                primary,
                units: PassageUnits.relativeProximity,
              );
              channels = [
                for (final c in channels)
                  rigCopyFrame(c, units: PassageUnits.relativeProximity),
              ];
            case 'foreignModel':
              primary = copyVisibleFrame(
                primary,
                modelHash: 'foreign-holdout-model',
              );
            case 'foreignPose':
              primary = copyVisibleFrame(
                primary,
                rotation: const [1, 0, 0, 0, 1, 0, 0, 0, 1],
              );
            case 'lostUpper':
              primary = copyVisibleFrame(
                primary,
                upper: List.filled(primary.surfaceZUpperM.length, double.nan),
              );
              channels = [
                for (final c in channels)
                  rigCopyFrame(
                    c,
                    surfaceZUpperM: List.filled(
                      c.depth.surfaceZUpperM.length,
                      double.nan,
                    ),
                  ),
              ];
            case 'partialRig':
              channels = channels.take(11).toList();
            case 'channelSkew1us':
              channels = [
                rigCopyFrame(channels.first, capturedAtUs: stamp + 1),
                ...channels.skip(1),
              ];
          }
          final source = volume.source(
            batch,
            channels,
            stamp + (active == 'futureProduction' ? 3000 : 1000),
          );
          final observation = source.observationFor(
            volume.context(batch, nowUs),
          );
          final invalidMotion = active == 'foreignMotion'
              ? FastMetricMotionResult(
                  reason: 'foreign holdout fault',
                  sessionGeneration: 2,
                  frameId: f.frameId,
                  capturedAtUs: stamp,
                  oldestEvidenceTimestampUs: stamp,
                  validUntilUs: stamp + 100000,
                  transformId: f.transformId,
                  candidates: 0,
                  unknownPatches: 0,
                  patches: const [],
                )
              : null;
          final before = engine.sceneModel.revision;
          final r = engine.ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: tracks,
            now: DateTime.fromMicrosecondsSinceEpoch(nowUs),
            orientationValid: true,
            userMoving: true,
            poseQuality: 1,
            passageObservation: active == 'missingRig' ? null : observation,
            cameraTrackInput: active == 'missingPrimary'
                ? null
                : sequenceAssociationInput(header, primary, f),
            bodyMotion: invalidMotion,
          );
          if (!r.accepted ||
              r.submittedAction?.delivery.name != 'shadow' ||
              engine.arbiter.active != null ||
              r.snapshot.revision <= before) {
            throw StateError('Fault trial admission/history/shadow invariant');
          }
          rows.add({
            'frameId': f.frameId,
            'capturedAtUs': stamp,
            'nowUs': nowUs,
            'phase': active != null
                ? 'fault'
                : index < faultIndex
                ? 'clearPrecondition'
                : 'movingRecovery',
            'action': r.decision!.action.kind.name,
            'rule': r.decision!.action.ruleId,
            'delivery': r.submittedAction!.delivery.name,
            'arbiterActive': false,
            'previousRevision': before,
            'revision': r.snapshot.revision,
            'userMoving': true,
          });
        }
        trials.add({
          'mode': mode,
          'fault': fault,
          'afterClear': afterClear,
          'sessionStarts': 1,
          'frames': rows,
        });
      }
    }
  }
  final phases = [for (final t in trials) ...(t['frames'] as List).cast<Map>()];
  final faults = phases.where((v) => v['phase'] == 'fault').toList();
  final recoveries = phases
      .where((v) => v['phase'] == 'movingRecovery')
      .toList();
  final preconditions = phases
      .where((v) => v['phase'] == 'clearPrecondition')
      .toList();
  return {
    'scope':
        'derived measurement fault and retained-history controls; separate from 21 diagnostic captures',
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'trials': trials,
    'summary': {
      'trials': trials.length,
      'faultStops': faults.where((v) => v['action'] == 'stopNow').length,
      'movingRecoveryStops': recoveries
          .where((v) => v['action'] == 'stopNow')
          .length,
      'clearPreconditions': preconditions.length,
      'clearPreconditionsPassed': preconditions
          .where((v) => v['action'] == 'continueForward')
          .length,
    },
  };
}
