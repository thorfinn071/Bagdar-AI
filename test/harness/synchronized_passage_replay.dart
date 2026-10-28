import 'dart:typed_data';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

import '../../tool/model_benchmark/scan_processing_support.dart';
import 'blender_synchronized_rig_fixture.dart' show rigCopyFrame;
import 'blender_visible_body_fixture.dart';
import 'synchronized_passage_fixture.dart';

Map<String, Object?> runSynchronizedPassageReplay() {
  final fixture = SynchronizedPassageFixture();
  final neural = bodyJson('${fixture.root}/neural.json');
  if (neural['manifestSha256'] != fixture.modelHash ||
      neural['promotionAllowed'] != false) {
    throw StateError('Neural identity drift');
  }
  for (final e in (neural['sources'] as Map).entries) {
    if (bodySha(e.key as String) != e.value) {
      throw StateError('Changed neural source');
    }
  }
  final relativeHash =
      'param:${neural['modelParamSha256']};bin:${neural['modelBinSha256']}';
  if (bodySha('assets/midas_small.ncnn.param') != neural['modelParamSha256'] ||
      bodySha('assets/midas_small.ncnn.bin') != neural['modelBinSha256']) {
    throw StateError('Model drift');
  }
  final rows = <Map<String, Object?>>[], faults = <Map<String, Object?>>[];
  for (final batch in fixture.batches) {
    final input = fixture.frames(batch), primary = fixture.primary(batch);
    final at = batch['capturedAtUs'] as int;
    final rig = fixture.source(batch, input, at + 1000);
    final observation = rig.observationFor(fixture.context(batch, at + 2000))!;
    final sourceDecision =
        const PassageClearanceEvaluator(policy: pairedBodyPolicy).evaluate(
          request: pairedBodyRequest,
          context: fixture.context(batch, at + 2000),
          calibration: fixture.calibration(batch, 'rig'),
          observation: observation,
        );
    final record = (neural['frames'] as List).cast<Map>().singleWhere(
      (r) => r['id'] == batch['id'],
    );
    bodyAsset(fixture.root, (batch['primary'] as Map)['rgb'] as Map);
    if (record['rgbSha256'] !=
            ((batch['primary'] as Map)['rgb'] as Map)['sha256'] ||
        record['rawOutputMatchesPrior'] != true ||
        record['canonicalRgbU8Sha256'] != record['priorCanonicalRgbU8Sha256']) {
      throw StateError('Unverified primary camera binding');
    }
    final raw = bodyFloats(bodyAsset(fixture.root, record['asset'] as Map));
    final frame = DepthFrame(
      values: DepthMapOps.normalizeRelativeProximity(Float32List.fromList(raw)),
      confidence01: Float32List.fromList(List.filled(65536, 1)),
      width: 256,
      height: 256,
      timestampUs: at,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: 'midas-small-ncnn',
      modelHash: relativeHash,
      preprocessId: neural['preprocessId'] as String,
      cropTopFraction: 0,
      frameQuality: 1,
      alignedToImage: true,
    );
    final detection =
        GenericObstacleDetector(
          collectCameraSupport: true,
          collectOpeningDiagnostics: true,
        ).detect(
          frame: frame,
          pitchDeg: 12,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: at,
        );
    final tracks = GenericObstacleTracker().update(
      observations: detection.observations,
      timestampUs: at,
      relative: true,
    );
    final header = ObservationHeader(
      providerId: 'desktop-midas',
      modelId: frame.modelId,
      modelHash: frame.modelHash,
      preprocessId: frame.preprocessId,
      sessionGeneration: primary.sessionGeneration,
      frameId: primary.frameId,
      sourceTimestampUs: at,
      producedAtUs: at + 1000,
      transformId: fixture.transform(batch),
      confidence: detection.detectorQuality.clamp(0, 1),
      health: ObservationHealth.healthy,
    );
    Map<String, Object?> ingest(
      PassageClearanceObservation? supplied, {
      int ageUs = 2000,
      String mode = 'rig',
    }) {
      final runtime =
          ConfidenceAuthoritySpatialRuntime(
            healthCoordinator: CoreHealthCoordinator(),
            planner: CoverageAwareStopGuidance(),
            shadowPassage: PassageClearanceShadowConfiguration(
              calibration: fixture.calibration(batch, mode),
              request: pairedBodyRequest,
              policy: pairedBodyPolicy,
              requireCameraEvidence: true,
              associateCameraTracks: true,
              cameraTrackModelHash: relativeHash,
            ),
          )..beginSession(
            primary.sessionGeneration,
            now: DateTime.fromMicrosecondsSinceEpoch(at - 1000),
          );
      final result = runtime.ingestGenericGeometry(
        header: header,
        detection: detection,
        tracks: tracks,
        now: DateTime.fromMicrosecondsSinceEpoch(at + ageUs),
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
        passageObservation: supplied,
        cameraTrackInput: CameraTrackAssociationInput(
          rgbHeader: header,
          depth: primary,
          imageGeometry: CameraTrackImageGeometry(
            cameraId: primary.cameraId,
            width: primary.width,
            height: primary.height,
            fx: primary.fx,
            fy: primary.fy,
            cx: primary.cx,
            cy: primary.cy,
            rotation: primary.rotation,
            originM: primary.originM,
          ),
        ),
      );
      if (!result.accepted ||
          result.submittedAction?.delivery.name != 'shadow' ||
          runtime.arbiter.active != null) {
        throw StateError('Unexpected active or rejected runtime');
      }
      final forward = RelativePolarGrid.fromSnapshot(
        result.snapshot,
        orientationValid: true,
        userMoving: true,
      ).sector(RelativeSectorDirection.forward);
      return {
        'action': result.decision!.action.kind.name,
        'rule': result.decision!.action.ruleId,
        'delivery': result.submittedAction!.delivery.name,
        'passageApplied': result.passageClearanceApplied,
        'passage': result.passageClearance?.toDiagnosticMap(),
        'forwardUnknown': forward.unknownProbability,
        'forwardOccupancy': forward.occupancyProbability,
        'associations': [
          for (final e in runtime.cameraTrackAssociations.entries)
            {'trackId': e.key, ...e.value.toDiagnosticMap()},
        ],
      };
    }

    final single = CameraPassageClearanceSource(
      calibration: fixture.calibration(batch, 'single'),
      request: pairedBodyRequest,
      frames: [primary],
      producedAtUs: at + 1000,
    ).observationFor(fixture.context(batch, at + 2000));
    final before = ingest(single, mode: 'single'), after = ingest(observation);
    // Labels only enter after source and runtime computations.
    final hazard = batch['physicalHazard'] as bool;
    if (hazard &&
        (sourceDecision.status == PassageClearanceStatus.measuredClear ||
            after['action'] == 'continueForward')) {
      throw StateError('Unsafe continue in ${batch['id']}');
    }
    rows.add({
      'id': batch['id'],
      'physicalHazard': hazard,
      'sourcePassage': sourceDecision.toDiagnosticMap(),
      'sourceDiagnostics': rig.diagnostics,
      'observedBodyBoxes': rig.certifiedBodyBoxes,
      'unknownBodyBoxes': rig.unknownBodyBoxes,
      'sections': scanObservationRecord(observation)['sections'],
      'controlWithoutRig': before,
      'withRig': after,
      'rgbPixelParity': true,
      'neuralOutputParity': true,
    });
    if (!hazard) {
      final cases = <String, List<CameraHeightEnvelopeFrame>>{
        'missingChannel': input.take(11).toList(),
        'reorderedChannels': input.reversed.toList(),
        'captureSkew1us': [
          rigCopyFrame(input.first, capturedAtUs: at + 1),
          ...input.skip(1),
        ],
        'relativeUnits': [
          rigCopyFrame(input.first, units: PassageUnits.relativeProximity),
          ...input.skip(1),
        ],
        'foreignPose': [
          rigCopyFrame(input.first, rotation: input.last.depth.rotation),
          ...input.skip(1),
        ],
        'incompleteFirstZ': [
          rigCopyFrame(input.first, firstZLowerM: []),
          ...input.skip(1),
        ],
        'providerFailed': [
          rigCopyFrame(input.first, providerHealthy: false),
          ...input.skip(1),
        ],
        'noReturns': [
          for (final e in input)
            rigCopyFrame(
              e,
              valid: List.filled(e.depth.valid.length, false),
              rangeM: List.filled(e.depth.valid.length, double.nan),
              freeZLowerM: List.filled(e.depth.valid.length, double.nan),
              surfaceZUpperM: List.filled(e.depth.valid.length, double.nan),
              heightLowerM: List.filled(e.depth.valid.length, double.nan),
              heightUpperM: List.filled(e.depth.valid.length, double.nan),
              firstZLowerM: List.filled(e.depth.valid.length, double.nan),
            ),
        ],
      };
      for (final e in cases.entries) {
        final bad = fixture.source(batch, e.value, at + 1000);
        final o = bad.observationFor(fixture.context(batch, at + 2000));
        final r = ingest(o);
        if (r['action'] != 'stopNow' ||
            r['passageApplied'] != false ||
            (r['passage'] as Map?)?['status'] != 'unavailable') {
          throw StateError('Fault gained clearance ${e.key}');
        }
        faults.add({'id': batch['id'], 'fault': e.key, ...r});
      }
      final dynamic = fixture.source(
        batch,
        input,
        at + 1000,
        staticScene: false,
      );
      final rejectedDynamic = ingest(
        dynamic.observationFor(fixture.context(batch, at + 2000)),
      );
      final stale = ingest(observation, ageUs: 100001);
      for (final e in {
        'unestablishedMotion': rejectedDynamic,
        'staleOriginalCapture': stale,
      }.entries) {
        if (e.value['action'] != 'stopNow' ||
            e.value['passageApplied'] != false) {
          throw StateError('Unsafe ${e.key}');
        }
        faults.add({'id': batch['id'], 'fault': e.key, ...e.value});
      }
    }
  }
  final clear = rows.where((r) => r['physicalHazard'] == false).toList();
  final hazards = rows.where((r) => r['physicalHazard'] == true).toList();
  return {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'captureToCommandMeasured': false,
    'temporalRecoveryEstablished': false,
    'manifestSha256': fixture.modelHash,
    'neuralReceiptSha256': bodySha('${fixture.root}/neural.json'),
    'maximumAgeUs': 100000,
    'scope':
        'known synthetic current snapshots; pinned primary MiDaS plus ideal simultaneous metric envelopes; real shadow runtime',
    'summary': {
      'passableSnapshots': clear.length,
      'completePassages': clear
          .where(
            (r) => (r['sourcePassage'] as Map)['status'] == 'measuredClear',
          )
          .length,
      'controlStops': clear
          .where((r) => (r['controlWithoutRig'] as Map)['action'] == 'stopNow')
          .length,
      'rigStops': clear
          .where((r) => (r['withRig'] as Map)['action'] == 'stopNow')
          .length,
      'rigContinues': clear
          .where((r) => (r['withRig'] as Map)['action'] == 'continueForward')
          .length,
      'hazardSnapshots': hazards.length,
      'hazardStops': hazards
          .where((r) => (r['withRig'] as Map)['action'] == 'stopNow')
          .length,
      'hazardUnsafeContinues': hazards
          .where((r) => (r['withRig'] as Map)['action'] == 'continueForward')
          .length,
      'faultStops': faults.length,
    },
    'frames': rows,
    'faultControls': faults,
  };
}
