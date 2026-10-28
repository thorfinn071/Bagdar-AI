import 'dart:convert';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

import '../../tool/model_benchmark/stop_cause_diagnostics.dart';
import 'blender_visible_body_fixture.dart';
import 'camera_visible_passage_fixture.dart' show copyVisibleFrame;

/// Copies a decision after ingestion. This function has no runtime reference
/// and cannot alter the planner, clocks, source or arbiter.
Map<String, Object?> captureStopTelemetry({
  required SpatialRuntimeResult result,
  required ObservationHeader header,
  required GenericObstacleDetectResult detection,
  required String corpus,
  required String sceneId,
  required String variant,
  required String sampleKind,
  required int nowUs,
  required bool moving,
  PassageClearanceResult? producerProof,
  PassageClearanceObservation? observation,
  CameraPassageClearanceSource? source,
}) {
  final decision = result.decision;
  final forward = decision?.candidates.singleWhere(
    (c) => c.direction.name == 'forward',
  );
  final floors = observation?.sections
      .map((s) => s.floorObservedFraction)
      .toList();
  final measured = source != null && observation?.providerHealthy == true;
  final depth = source?.frames.length == 1 ? source!.frames.single : null;
  return {
    'corpus': corpus,
    'sceneId': sceneId,
    'frameId': header.frameId,
    'variant': variant,
    'sampleKind': sampleKind,
    'clockMode': 'fixed_known_corpus_replay',
    'capturedAtUs': header.sourceTimestampUs,
    'evaluatedAtUs': nowUs,
    'replayAgeUs': nowUs - header.sourceTimestampUs,
    'captureToDecisionMs': null,
    'header': header.toDiagnosticMap(),
    'providerHealth': header.health.name,
    'runtimeAccepted': result.accepted,
    'runtimeStatus': result.status.name,
    'runtimeReason': result.reason,
    'sceneRevision': result.snapshot.revision,
    'action': decision?.action.kind.name,
    'ruleId': decision?.action.ruleId,
    'cause': decision?.action.cause,
    'delivery': result.submittedAction?.delivery.name,
    'plannerState': decision?.state.name,
    'previousPlannerState': decision?.previousState.name,
    'userMoving': moving,
    'positiveCorridor': forward?.hasPositiveEvidence,
    'corridorRejections': forward?.rejectionReasons.map((v) => v.name).toList(),
    'forwardObservedFraction': forward?.observedFraction,
    'forwardUnknownRisk': forward?.unknownRisk,
    'forwardCollisionRisk': forward?.collisionRisk,
    'forwardDropRisk': forward?.dropRisk,
    'forwardMovingThreatRisk': forward?.movingThreatRisk,
    'passageApplied': result.passageClearanceApplied,
    'passageStatus': result.passageClearance?.status.name,
    'passageReasons': result.passageClearance?.reasons
        .map((v) => v.name)
        .toList(),
    'producerPassageStatus': producerProof?.status.name,
    'producerPassageReasons': producerProof?.reasons
        .map((v) => v.name)
        .toList(),
    'producerDiagnostics': source == null ? null : List.of(source.diagnostics),
    'depthInput': depth == null
        ? null
        : {
            'units': depth.units.name,
            'providerHealthy': depth.providerHealthy,
            'modelMatchesCalibration':
                depth.modelHash == source!.calibration.modelHash,
            'transformMatchesCalibration':
                depth.transformId == source.calibration.transformId,
            'referenceFrameMatchesCalibration':
                depth.referenceFrameId == source.calibration.referenceFrameId,
          },
    // Counters start at zero even when the source never measured this input.
    'observedBodyCells': measured ? source.certifiedBodyBoxes : null,
    'unknownBodyCells': measured ? source.unknownBodyBoxes : null,
    'unknownBodyCellCentersSampleM': measured
        ? [for (final p in source.unobservedBodyCellCenters) List.of(p)]
        : null,
    'minimumFloorObservedFraction': floors == null || floors.isEmpty
        ? null
        : floors.reduce((a, b) => a < b ? a : b),
    'detectorRejectReason': detection.rejectReason.name,
    'detectorUnknownReasons': detection.unknownReasons
        .map((v) => v.name)
        .toList(),
    'groundSurfaceObservedFraction': detection.surfaceEvidence.observedFraction,
    'groundSurfaceContinuity': detection.surfaceEvidence.continuity,
  };
}

const stopDiagnosticFaults = [
  'staleMetric',
  'missingDepth',
  'invalidDepth',
  'relativeDepth',
  'foreignModel',
  'invalidOrientation',
  'providerUnavailable',
  'stationaryUnknown',
];

/// Reuses all 12 already-inspected paired scenes; no new holdout claim.
/// Labels are loaded, hash-checked and attached only AFTER every decision.
List<Map<String, Object?>> replayPairedStopCauses() {
  final fixture = PairedBodyFixture();
  final rows = <Map<String, Object?>>[];
  for (final seq in (fixture.corpus['sequences'] as List).cast<Map>()) {
    final id = seq['sceneId'] as String;
    final optics = (fixture.manifest['sequences'] as List)
        .cast<Map>()
        .singleWhere((s) => s['sceneId'] == id);
    final calibration = fixture.calibration(id);
    ConfidenceAuthoritySpatialRuntime engine() =>
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          planner: CoverageAwareStopGuidance(),
          shadowPassage: PassageClearanceShadowConfiguration(
            calibration: calibration,
            request: pairedBodyRequest,
            policy: pairedBodyPolicy,
            requireCameraEvidence: true,
            associateCameraTracks: true,
            cameraTrackModelHash: fixture.relativeHash,
          ),
        )..beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(pairedBodyStamp - 1000),
        );
    final runtime = engine();
    final detector = GenericObstacleDetector(
      collectOpeningDiagnostics: true,
      collectCameraSupport: true,
    );
    final tracker = GenericObstacleTracker();
    for (final original in (seq['frames'] as List).cast<Map>()) {
      final index = original['frameIndex'] as int;
      final packet = (optics['single'] as List)[index] as Map;
      if (packet['rgbSha256'] != (original['rgb'] as Map)['sha256']) {
        throw StateError('Optical/RGB identity mismatch');
      }
      final depth = fixture.visible(packet, id);
      final stamp = depth.capturedAtUs;
      final relative = fixture.relative(
        original,
        id,
        stamp,
        canonicalPreprocess: true,
      );
      final detection = detector.detect(
        frame: relative,
        pitchDeg: ((original['cameraPose'] as Map)['pitchDownDeg'] as num)
            .toDouble(),
        rollDeg: 0,
        motion: MotionState.walking,
        imageTimestampUs: stamp,
      );
      final tracks = tracker.update(
        observations: detection.observations,
        timestampUs: stamp,
        relative: true,
      );
      // Capture normal sequence first. Each intervention has its own runtime;
      // none can reset or contaminate the normal scene's history.
      for (final variant in [
        'normal',
        if (id == 'path-clear' && index == 0) ...stopDiagnosticFaults,
      ]) {
        final target = variant == 'normal' ? runtime : engine();
        final now = stamp + (variant == 'staleMetric' ? 100001 : 2000);
        final moving = variant != 'stationaryUnknown';
        final header = ObservationHeader(
          providerId: 'desktop-midas',
          modelId: relative.modelId,
          modelHash: relative.modelHash,
          preprocessId: relative.preprocessId,
          sessionGeneration: 1,
          frameId: index + 1,
          sourceTimestampUs: stamp,
          producedAtUs: stamp + 1000,
          transformId: fixture.transform(id),
          confidence: detection.detectorQuality.clamp(0, 1),
          health: variant == 'providerUnavailable'
              ? ObservationHealth.unavailable
              : ObservationHealth.healthy,
        );
        final suppliedDepth = switch (variant) {
          'missingDepth' => null,
          'invalidDepth' => copyVisibleFrame(
            depth,
            valid: List.filled(depth.valid.length, false),
          ),
          'relativeDepth' => copyVisibleFrame(
            depth,
            units: PassageUnits.relativeProximity,
          ),
          'foreignModel' => copyVisibleFrame(depth, modelHash: 'foreign-model'),
          _ => depth,
        };
        final source = suppliedDepth == null
            ? null
            : CameraPassageClearanceSource(
                calibration: calibration,
                request: pairedBodyRequest,
                frames: [suppliedDepth],
                producedAtUs: stamp + 1000,
              );
        final context = PassageEvaluationContext(
          nowUs: now,
          timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
          sessionGeneration: 1,
          frameId: index + 1,
          rgbTimestampUs: stamp,
          transformId: fixture.transform(id),
        );
        final observation = source?.observationFor(context);
        final proof = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
            .evaluate(
              request: pairedBodyRequest,
              context: context,
              calibration: calibration,
              observation: observation,
            );
        final before = jsonEncode(header.toDiagnosticMap());
        final result = target.ingestGenericGeometry(
          header: header,
          detection: detection,
          tracks: tracks,
          now: DateTime.fromMicrosecondsSinceEpoch(now),
          orientationValid: variant != 'invalidOrientation',
          userMoving: moving,
          poseQuality: 1,
          passageObservation: observation,
          cameraTrackInput: suppliedDepth == null
              ? null
              : CameraTrackAssociationInput(
                  rgbHeader: header,
                  depth: suppliedDepth,
                  imageGeometry: CameraTrackImageGeometry(
                    cameraId: suppliedDepth.cameraId,
                    width: suppliedDepth.width,
                    height: suppliedDepth.height,
                    fx: suppliedDepth.fx,
                    fy: suppliedDepth.fy,
                    cx: suppliedDepth.cx,
                    cy: suppliedDepth.cy,
                    rotation: suppliedDepth.rotation,
                    originM: suppliedDepth.originM,
                  ),
                ),
        );
        final row = captureStopTelemetry(
          result: result,
          header: header,
          detection: detection,
          corpus: 'paired-visible-body-v1',
          sceneId: id,
          variant: variant == 'normal' ? 'confidence-coverage-aware' : variant,
          sampleKind: variant == 'normal'
              ? 'knownSyntheticReplay'
              : 'syntheticFaultControl',
          nowUs: now,
          moving: moving,
          producerProof: proof,
          observation: observation,
          source: source,
        );
        if (before != jsonEncode(header.toDiagnosticMap()) ||
            target.arbiter.active != null ||
            result.submittedAction?.delivery.name != 'shadow') {
          throw StateError('Telemetry changed input or non-shadow admission');
        }
        rows.add(row);
      }
    }
  }
  // Annotations can affect only the offline outcome, never runtime inputs.
  final labels = <String, Map>{};
  for (final seq in (fixture.corpus['sequences'] as List).cast<Map>()) {
    labels[seq['sceneId'] as String] =
        jsonDecode(
              utf8.decode(bodyAsset(pairedRgbRoot, seq['annotations'] as Map)),
            )
            as Map;
  }
  return [
    for (final row in rows)
      diagnoseStopFrame({
        ...row,
        'scoringOnly': {
          'physicalHazard': labels[row['sceneId']]!['physicalHazard'],
          'referencePassable': labels[row['sceneId']]!['referencePassable'],
          'source': 'hash_checked_predeclared_synthetic_scene_annotation',
        },
      }),
  ];
}

/// Separate current replay on the known positive control, retaining each
/// detector/runtime arm as a separate denominator. Original receipts stay read-only.
List<Map<String, Object?>> closedControlStopRows(
  Map<String, Object?> report,
) => [
  for (final c in (report['cases'] as List).cast<Map>())
    for (final f in (c['frames'] as List).cast<Map>())
      for (final mode in ['legacy', 'frameStable'])
        for (final lane in ['sameRigControl', 'fixedRig'])
          diagnoseStopFrame({
            'corpus': 'closed-volume-known-control', 'sceneId': c['layoutId'],
            'frameId': f['frameId'], 'variant': '$mode/$lane',
            'sampleKind': 'knownSyntheticReplay',
            'clockMode': 'fixed_known_corpus_replay',
            'capturedAtUs': f['capturedAtUs'], 'evaluatedAtUs': f['nowUs'],
            'captureToDecisionMs': null,
            'runtimeAccepted': true,
            'runtimeStatus': 'accepted_checked_by_closed_control_harness',
            'action': f['arms'][mode]['runtime'][lane]['action'],
            'ruleId': f['arms'][mode]['runtime'][lane]['rule'],
            'delivery': f['arms'][mode]['runtime'][lane]['delivery'],
            // The existing control publishes producer diagnostics but not the
            // runtime's candidate/reason objects. Do not reconstruct them.
            'corridorRejections': null, 'positiveCorridor': null,
            'passageStatus': null, 'passageReasons': null,
            'producerPassageStatus': f['volume']['status'],
            'producerPassageReasons': f['volume']['reasons'],
            'producerDiagnostics': f['volume']['sourceDiagnostics'],
            'unknownBodyCells': null, 'minimumFloorObservedFraction': null,
            'scoringOnly': {
              'physicalHazard': f['scoringOnly']['physicalHazard'],
              'referencePassable': f['scoringOnly']['physicalHazard'] == false,
              'source':
                  'predeclared_synthetic_geometry_scoring_after_decisions',
            },
          }),
];
