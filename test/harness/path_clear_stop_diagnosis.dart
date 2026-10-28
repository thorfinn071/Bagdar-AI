import 'dart:convert';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

import 'blender_visible_body_fixture.dart';
import 'camera_visible_passage_fixture.dart' show copyVisibleFrame;

Map<String, Object?> authorityFields(SafetyAction a) => {
  'id': a.actionId,
  'kind': a.kind.name,
  'priority': a.priority.name,
  'delivery': a.delivery.name,
  'revision': a.sceneRevision,
  'hazards': a.hazardIds,
  'summary': a.evidenceSummary,
  'direction': a.direction?.name,
  'confidence': a.confidence,
  'createdUs': a.createdAt.microsecondsSinceEpoch,
  'validUntilUs': a.validUntil.microsecondsSinceEpoch,
};

/// Runs pinned MiDaS-derived inputs and actual camera-visible metric packets.
/// Labels are never sent to detector, association, fusion or planner. Fresh
/// planner/no-track variants are explicit causal ablations, never producers.
Map<String, Object?> runPathClearStopDiagnosis() {
  final fixture = PairedBodyFixture();
  final prior = bodyJson(
    'docs/_baseline_logs/blender_visible_body_shadow_v2.json',
  );
  final priorSequences =
      ((prior['modes'] as List).cast<Map>().singleWhere(
                (m) => m['mode'] == 'midas-plus-visible-metric-single',
              )['sequences']
              as List)
          .cast<Map>();
  final rows = <Map<String, Object?>>[];
  final failures = <String>[];
  for (final id in ['path-clear', 'path-box']) {
    final seq = (fixture.corpus['sequences'] as List).cast<Map>().singleWhere(
      (s) => s['sceneId'] == id,
    );
    final optics = (fixture.manifest['sequences'] as List)
        .cast<Map>()
        .singleWhere((s) => s['sceneId'] == id);
    final calibration = fixture.calibration(id);
    final configuration = PassageClearanceShadowConfiguration(
      calibration: calibration,
      request: pairedBodyRequest,
      policy: pairedBodyPolicy,
      requireCameraEvidence: true,
      associateCameraTracks: true,
      cameraTrackModelHash: fixture.relativeHash,
    );
    ConfidenceAuthoritySpatialRuntime runtime({bool corrected = false}) =>
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          shadowPassage: configuration,
          planner: corrected
              ? CoverageAwareStopGuidance()
              : ConfidenceAuthorityGuidance(),
        )..beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(pairedBodyStamp - 1000),
        );
    final baseline = runtime(), corrected = runtime(corrected: true);
    final detector = GenericObstacleDetector(
      collectOpeningDiagnostics: true,
      collectCameraSupport: true,
    );
    final tracker = GenericObstacleTracker();
    for (final original in (seq['frames'] as List).cast<Map>()) {
      final index = original['frameIndex'] as int;
      final packet = (optics['single'] as List)[index] as Map;
      if (packet['rgbSha256'] != (original['rgb'] as Map)['sha256']) {
        throw StateError('Optical/RGB identity drift');
      }
      final depth = fixture.visible(packet, id);
      final us = depth.capturedAtUs;
      final frame = fixture.relative(
        original,
        id,
        us,
        canonicalPreprocess: true,
      );
      final detection = detector.detect(
        frame: frame,
        pitchDeg: ((original['cameraPose'] as Map)['pitchDownDeg'] as num)
            .toDouble(),
        rollDeg: 0,
        motion: MotionState.walking,
        imageTimestampUs: us,
      );
      final tracks = tracker.update(
        observations: detection.observations,
        timestampUs: us,
        relative: true,
      );
      final header = ObservationHeader(
        providerId: 'desktop-midas',
        modelId: frame.modelId,
        modelHash: frame.modelHash,
        preprocessId: frame.preprocessId,
        sessionGeneration: 1,
        frameId: index + 1,
        sourceTimestampUs: us,
        producedAtUs: us + 1000,
        transformId: fixture.transform(id),
        confidence: detection.detectorQuality.clamp(0.0, 1.0),
        health: ObservationHealth.healthy,
      );
      CameraTrackAssociationInput cameraInput(CameraVisibleDepthFrame f) =>
          CameraTrackAssociationInput(
            rgbHeader: header,
            depth: f,
            imageGeometry: CameraTrackImageGeometry(
              cameraId: f.cameraId,
              width: f.width,
              height: f.height,
              fx: f.fx,
              fy: f.fy,
              cx: f.cx,
              cy: f.cy,
              rotation: f.rotation,
              originM: f.originM,
            ),
          );
      final source = CameraPassageClearanceSource(
        calibration: calibration,
        request: pairedBodyRequest,
        frames: [depth],
        producedAtUs: us + 1000,
      );
      final context = PassageEvaluationContext(
        nowUs: us + 2000,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: 1,
        frameId: index + 1,
        rgbTimestampUs: us,
        transformId: fixture.transform(id),
      );
      final observation = source.observationFor(context);
      SpatialRuntimeResult ingest(
        ConfidenceAuthoritySpatialRuntime target, {
        bool noTracks = false,
        bool moving = true,
        int ageUs = 2000,
        CameraVisibleDepthFrame? camera,
        PassageClearanceObservation? supplied,
      }) => target.ingestGenericGeometry(
        header: header,
        detection: detection,
        tracks: noTracks ? const [] : tracks,
        now: DateTime.fromMicrosecondsSinceEpoch(us + ageUs),
        orientationValid: true,
        userMoving: moving,
        poseQuality: 1,
        passageObservation: supplied ?? observation,
        cameraTrackInput: cameraInput(camera ?? depth),
      );
      Map<String, Object?> resultMap(
        SpatialRuntimeResult result, {
        ConfidenceAuthoritySpatialRuntime? owner,
      }) {
        if (!result.accepted ||
            result.decision == null ||
            result.submittedAction?.delivery != SafetyActionDelivery.shadow) {
          throw StateError(
            'Expected admitted shadow decision: ${result.reason}',
          );
        }
        final grid = RelativePolarGrid.fromSnapshot(
          result.snapshot,
          orientationValid: true,
          userMoving: true,
        );
        final forward = grid.sector(RelativeSectorDirection.forward);
        final candidate = result.decision!.candidates.singleWhere(
          (c) => c.direction.name == 'forward',
        );
        return {
          'action': result.decision!.action.kind.name,
          'rule': result.decision!.action.ruleId,
          'cause': result.decision!.action.cause,
          'passageApplied': result.passageClearanceApplied,
          'passage': result.passageClearance?.toDiagnosticMap(),
          'forwardUnknown': forward.unknownProbability,
          'forwardOccupancy': forward.occupancyProbability,
          'positiveCorridor': candidate.hasPositiveEvidence,
          'rejectionReasons': candidate.rejectionReasons
              .map((r) => r.name)
              .toList(),
          'associations': [
            for (final e
                in (owner?.cameraTrackAssociations ??
                        <int, CameraTrackAssociation>{})
                    .entries)
              {'track': e.key, ...e.value.toDiagnosticMap()},
          ],
        };
      }

      final old = ingest(baseline), current = ingest(corrected);
      final oldRow = resultMap(old, owner: baseline),
          currentRow = resultMap(current, owner: corrected);
      final frozen =
          (priorSequences.singleWhere((s) => s['sceneId'] == id)['frames']
                  as List)[index]
              as Map;
      for (final key in [
        'action',
        'rule',
        'forwardUnknown',
        'forwardOccupancy',
        'passageApplied',
      ]) {
        if (oldRow[key] != frozen[key]) {
          failures.add('Frozen diagnostic drift $id/$index/$key');
        }
      }
      if (jsonEncode(authorityFields(old.decision!.action)) !=
          jsonEncode(authorityFields(current.decision!.action))) {
        failures.add('Authority drift $id/$index');
      }
      final ablations = <String, Object?>{};
      if (id == 'path-clear') {
        ablations['freshPlanner'] = resultMap(ingest(runtime()));
        ablations['noTracksFreshMoving'] = resultMap(
          ingest(runtime(), noTracks: true),
        );
        ablations['noTracksFreshStationary'] = resultMap(
          ingest(runtime(), noTracks: true, moving: false),
        );
      }
      rows.add({
        'sceneId': id,
        'frameIndex': index,
        'capturedAtUs': us,
        'input': {
          'rgbSha256': (original['rgb'] as Map)['sha256'],
          'geometryReject': detection.rejectReason.name,
          'geometryQuality': detection.detectorQuality,
          'groundDisagreementPixels': detection.groundDisagreementPixels,
          'unknownReasons': detection.unknownReasons
              .map((r) => r.name)
              .toList(),
          'observations': detection.observations.length,
          'tracks': tracks.length,
          'groundSurfaceObserved': detection.surfaceEvidence.observedFraction,
          'groundSurfaceContinuity': detection.surfaceEvidence.continuity,
          'observedBodyBoxes': source.certifiedBodyBoxes,
          'unknownBodyBoxes': source.unknownBodyBoxes,
          'unknownBodyCentersSampleM': source.unobservedBodyCellCenters
              .take(6)
              .toList(),
          'minimumFloorObserved': observation?.sections
              .map((s) => s.floorObservedFraction)
              .reduce((a, b) => a < b ? a : b),
        },
        'baseline': oldRow,
        'correctedCause': currentRow,
        'testOnlyAblations': ablations,
      });
      if (baseline.arbiter.active != null || corrected.arbiter.active != null) {
        failures.add('Non-shadow feedback $id/$index');
      }
      if (id == 'path-clear' && index == 0) {
        final holes = copyVisibleFrame(
          depth,
          valid: List.filled(depth.valid.length, false),
        );
        final relative = copyVisibleFrame(
          depth,
          units: PassageUnits.relativeProximity,
        );
        for (final fault in {
          'holes': holes,
          'relativeUnits': relative,
        }.entries) {
          final bad = CameraPassageClearanceSource(
            calibration: calibration,
            request: pairedBodyRequest,
            frames: [fault.value],
            producedAtUs: us + 1000,
          ).observationFor(context);
          // An unavailable source is represented explicitly, not replaced by
          // the original optical observation through a null fallback.
          final r = runtime(corrected: true).ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: tracks,
            now: DateTime.fromMicrosecondsSinceEpoch(us + 2000),
            orientationValid: true,
            userMoving: true,
            poseQuality: 1,
            passageObservation: bad,
            cameraTrackInput: cameraInput(fault.value),
          );
          ablations[fault.key] = resultMap(r);
        }
        ablations['staleMetricObservation'] = resultMap(
          ingest(runtime(corrected: true), ageUs: 100001),
        );
      }
    }
  }
  final passable = rows.where((r) => r['sceneId'] == 'path-clear').toList();
  final hazards = rows.where((r) => r['sceneId'] == 'path-box').toList();
  int count(
    Iterable<Map<String, Object?>> input,
    String variant,
    String action,
  ) => input.where((r) => (r[variant] as Map)['action'] == action).length;
  final summary = {
    'frames': rows.length,
    'passableFrames': passable.length,
    'hazardFrames': hazards.length,
    'baselineFalseStops': count(passable, 'baseline', 'stopNow'),
    'correctedFalseStops': count(passable, 'correctedCause', 'stopNow'),
    'hazardStops': count(hazards, 'correctedCause', 'stopNow'),
    'hazardUnsafeContinues': count(
      hazards,
      'correctedCause',
      'continueForward',
    ),
    'reasonCorrections': rows
        .where(
          (r) =>
              (r['baseline'] as Map)['rule'] !=
              (r['correctedCause'] as Map)['rule'],
        )
        .length,
    'passableWithoutLatchStops': passable
        .where(
          (r) =>
              ((r['testOnlyAblations'] as Map)['freshPlanner']
                  as Map)['action'] ==
              'stopNow',
        )
        .length,
    'passableWithoutTracksMovingStops': passable
        .where(
          (r) =>
              ((r['testOnlyAblations'] as Map)['noTracksFreshMoving']
                  as Map)['action'] ==
              'stopNow',
        )
        .length,
    'passableWithoutTracksStationaryHolds': passable
        .where(
          (r) =>
              ((r['testOnlyAblations'] as Map)['noTracksFreshStationary']
                  as Map)['action'] ==
              'holdAndScan',
        )
        .length,
  };
  return {
    'schemaVersion': 1,
    'scope':
        'known paired scene causal diagnosis; pinned neural output and independent synthetic metric inputs',
    'ordinaryCameraWired': false,
    'promotionAllowed': false,
    'falseStopReductionEstablished': false,
    'captureToCommandMeasured': false,
    'namedDeviceRuntime': 'not_run',
    'priorVisibleBodyReportSha256': bodySha(
      'docs/_baseline_logs/blender_visible_body_shadow_v2.json',
    ),
    'corpusManifestSha256': fixture.manifest['sourceCorpusSha256'],
    'visibleManifestSha256': fixture.modelHash,
    'summary': summary,
    'failures': failures,
    'frames': rows,
  };
}
