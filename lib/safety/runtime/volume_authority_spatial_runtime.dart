import 'dart:math' as math;

import '../../core/core_health_coordinator.dart';
import '../../models/depth_frame.dart';
import '../perception/camera_fast_motion_types.dart';
import 'confidence_authority_spatial_runtime.dart'
    show ConfidenceAuthorityGuidance;
import '../../models/generic_obstacle.dart';
import '../../tracker/generic_obstacle_tracker.dart';
import '../../utils/depth_hazard.dart';
import '../alerts/alert_arbiter.dart';
import '../perception/camera_track_association.dart';
import '../perception/observation_header.dart';
import '../perception/passage_clearance.dart';
import '../planning/guidance_state_machine.dart';
import '../world/local_scene_model.dart';
import '../world/local_scene_snapshot.dart';
import '../world/scene_fusion_policy.dart';
import 'passage_clearance_shadow.dart';
import 'spatial_safety_runtime.dart';

/// Opt-in current-volume evidence authority. Preserves the original confidence
/// policy, scene history and guidance; never certifies whole-object stationarity.
class VolumeAuthoritySpatialRuntime extends SpatialSafetyRuntime {
  final _VolumeSceneModel _confidenceScene;

  factory VolumeAuthoritySpatialRuntime({
    required CoreHealthCoordinator healthCoordinator,
    AlertArbiter? arbiter,
    GuidanceStateMachine? planner,
    PassageClearanceShadowConfiguration? shadowPassage,
  }) {
    if (planner != null && planner is! ConfidenceAuthorityGuidance) {
      throw ArgumentError('Confidence authority requires its matching planner');
    }
    return VolumeAuthoritySpatialRuntime._(
      _VolumeSceneModel(),
      healthCoordinator,
      arbiter,
      planner ?? ConfidenceAuthorityGuidance(),
      shadowPassage,
    );
  }

  VolumeAuthoritySpatialRuntime._(
    this._confidenceScene,
    CoreHealthCoordinator health,
    AlertArbiter? arbiter,
    GuidanceStateMachine planner,
    PassageClearanceShadowConfiguration? passage,
  ) : super(
        healthCoordinator: health,
        arbiter: arbiter,
        sceneModel: _confidenceScene,
        planner: planner,
        shadowPassage: passage,
      ) {
    _confidenceScene.outside = (track) =>
        cameraTrackAssociations[track.id]?.relation ==
        CameraTrackRelation.outsidePassage;
  }

  @override
  SpatialRuntimeResult ingestGenericGeometry({
    required ObservationHeader header,
    required GenericObstacleDetectResult detection,
    required List<GenericObstacleTrack> tracks,
    required DateTime now,
    required bool orientationValid,
    required bool userMoving,
    required double poseQuality,
    PassageClearanceObservation? passageObservation,
    CameraTrackAssociationInput? cameraTrackInput,
    FastMetricMotionResult? bodyMotion,
  }) {
    _confidenceScene.proof = null;
    _confidenceScene.motion = null;
    _confidenceScene.volumeAuthority = false;
    _confidenceScene.blockingWitness = false;
    _confidenceScene.motionUnavailable = false;
    final configuration = shadowPassage;
    final stamp = header.sourceTimestampUs;
    final nowUs = now.microsecondsSinceEpoch;
    final motionBound =
        bodyMotion == null ||
        (bodyMotion.sessionGeneration == header.sessionGeneration &&
            bodyMotion.frameId == header.frameId &&
            bodyMotion.capturedAtUs == stamp &&
            bodyMotion.transformId == header.transformId &&
            bodyMotion.isLiveAt(nowUs) &&
            bodyMotion.validUntilUs <= stamp + 100000 &&
            bodyMotion.oldestEvidenceTimestampUs <= stamp &&
            stamp - bodyMotion.oldestEvidenceTimestampUs <= 400000);
    if (motionBound) _confidenceScene.motion = bodyMotion;
    _confidenceScene.motionUnavailable = !motionBound;
    final explicitRisk = tracks.any(
      (t) =>
          t.last.source != DepthProviderKind.ncnnRelative ||
          t.last.nearestDistanceM != null ||
          t.last.approachRateMps != null ||
          t.last.timeToCollisionS != null ||
          t.last.semantic != null ||
          t.metricVelocityMps() != null,
    );
    final primaryBound =
        configuration != null &&
        cameraTrackInput != null &&
        CameraTrackAssociator(
                  input: cameraTrackInput,
                  header: header,
                  calibration: configuration.calibration,
                  request: configuration.request,
                  nowUs: nowUs,
                  relativeModelHash: configuration.cameraTrackModelHash ?? '',
                )
                // Exercise the immutable identity gate without requesting a surface
                // verdict. No pixel/absence conclusion is taken from this probe.
                .associate(
                  normalizedBounds: const [],
                  trackTimestampUs: stamp,
                  currentlyObserved: true,
                  motionOrSemanticRisk: false,
                )
                .reason ==
            'invalid_component_bounds' &&
        cameraTrackInput.depth.valid.any((v) => v) &&
        cameraTrackInput.depth.surfaceZUpperM.any((v) => v.isFinite);
    _confidenceScene.primaryBound = configuration == null || primaryBound;
    if (primaryBound) {
      final f = cameraTrackInput.depth, request = configuration.request;
      final margin = f.errorM + .02;
      // Positive metric point witnesses can veto a contradictory volume proof.
      // Absence of a witness grants no clearance: the complete volume/floor
      // certificate remains mandatory. Never use point samples as coverage.
      for (var y = 0; y < f.height && !_confidenceScene.blockingWitness; y++) {
        for (var x = 0; x < f.width; x++) {
          final i = y * f.width + x;
          if (!f.valid[i] || !f.rangeM[i].isFinite || f.rangeM[i] <= 0) {
            continue;
          }
          final z =
              f.rangeM[i] /
              math.sqrt(
                1 +
                    math.pow((x + .5 - f.cx) / f.fx, 2) +
                    math.pow((y + .5 - f.cy) / f.fy, 2),
              );
          final p = f.worldPoint(x, y, z);
          if (p[0] > -request.widthM / 2 + margin &&
              p[0] < request.widthM / 2 - margin &&
              p[1] > request.forwardStartM + margin &&
              p[1] < request.forwardEndM - margin &&
              p[2] > request.maximumFloorRiseM + margin &&
              p[2] < request.headroomM - margin) {
            _confidenceScene.blockingWitness = true;
            break;
          }
        }
      }
    }
    if (configuration != null &&
        configuration.requireCameraEvidence &&
        configuration.associateCameraTracks &&
        primaryBound &&
        motionBound &&
        !explicitRisk &&
        !_confidenceScene.blockingWitness &&
        bodyMotion?.addsMotionRisk != true &&
        orientationValid &&
        configuration.acceptsPose(poseQuality) &&
        header.health == ObservationHealth.healthy &&
        (detection.rejectReason == ObstacleRejectReason.none ||
            detection.rejectReason == ObstacleRejectReason.emptyCorridor) &&
        nowUs >= stamp &&
        nowUs - stamp <= 100000 &&
        header.producedAtUs >= stamp &&
        header.producedAtUs <= nowUs &&
        detection.unknownProbabilityFloor <= .65 &&
        detection.unknownReasons.every(
          (v) =>
              v == ObstacleUnknownReason.unverifiedAperture ||
              v == ObstacleUnknownReason.groundModelDisagreement,
        )) {
      final proof = PassageClearanceEvaluator(policy: configuration.policy)
          .evaluate(
            request: configuration.request,
            context: PassageEvaluationContext(
              nowUs: nowUs,
              timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
              sessionGeneration: header.sessionGeneration,
              frameId: header.frameId,
              rgbTimestampUs: stamp,
              transformId: header.transformId,
            ),
            calibration: configuration.calibration,
            observation: passageObservation,
          );
      if (proof.status == PassageClearanceStatus.measuredClear &&
          proof.coversCameraRecoveryVolume &&
          proof.validUntilUs != null &&
          proof.validUntilUs! <= stamp + 100000) {
        _confidenceScene.proof = proof;
        _confidenceScene.volumeAuthority = true;
      }
    }
    _confidenceScene.pending = switch (detection.rejectReason) {
      ObstacleRejectReason.none || ObstacleRejectReason.emptyCorridor => tracks,
      _ => const [],
    };
    try {
      return super.ingestGenericGeometry(
        header: header,
        detection: detection,
        tracks: tracks,
        now: now,
        orientationValid: orientationValid,
        userMoving: userMoving,
        poseQuality: poseQuality,
        passageObservation: passageObservation,
        cameraTrackInput: cameraTrackInput,
      );
    } finally {
      // Rejected observations never leave candidates for another frame/update.
      _confidenceScene.pending = const [];
      _confidenceScene.proof = null;
      _confidenceScene.motion = null;
      _confidenceScene.volumeAuthority = false;
      _confidenceScene.primaryBound = true;
      _confidenceScene.blockingWitness = false;
      _confidenceScene.motionUnavailable = false;
    }
  }
}

class _VolumeSceneModel extends LocalSceneModel {
  _VolumeSceneModel() : super.relative();
  List<GenericObstacleTrack> pending = const [];
  bool Function(GenericObstacleTrack)? outside;
  PassageClearanceResult? proof;
  FastMetricMotionResult? motion;
  bool volumeAuthority = false, primaryBound = true, blockingWitness = false;
  bool motionUnavailable = false;

  @override
  LocalSceneUpdateResult update(LocalSceneUpdate update) {
    // Only the frozen adapter emits this typed, current passage evidence,
    // after validating its volume/context. Filled depth is never such proof.
    final bodyVerified =
        primaryBound &&
        (volumeAuthority ||
            update.evidence.any(
              (e) =>
                  e.elementId == 'forward' &&
                  e.source == SpatialEvidenceSource.depth &&
                  e.sourceId.startsWith('metric-passage:') &&
                  e.observedFraction == 1 &&
                  e.traversabilityProbability == 1 &&
                  e.unknownProbability == 0,
            ));
    final evidence = <SpatialEvidence>[];
    for (final e in update.evidence) {
      final generic =
          e.source == SpatialEvidenceSource.geometry &&
          e.sourceId.startsWith('geometry:');
      // CURRENT relative-image occupancy is a hypothesis, not a metric
      // physical hazard. A complete independent body/floor certificate may
      // resolve that current volume; the raw track and its history stay intact.
      if (volumeAuthority &&
          generic &&
          e.elementId == 'forward' &&
          e.occupancyProbability != null) {
        continue;
      }
      final resolvedForward =
          volumeAuthority &&
          e.elementId == 'forward' &&
          (generic ||
              e.source == SpatialEvidenceSource.depth &&
                  e.sourceId.startsWith('metric-passage:'));
      final invalidPositive =
          !primaryBound &&
          e.elementId == 'forward' &&
          e.source == SpatialEvidenceSource.depth &&
          e.traversabilityProbability != null;
      final frameNeedsBodyProof =
          generic &&
          e.elementId == 'forward' &&
          e.occupancyProbability == null &&
          !bodyVerified;
      evidence.add(
        SpatialEvidence(
          elementId: e.elementId,
          coordinateMode: e.coordinateMode,
          sourceId: e.sourceId,
          source: e.source,
          observedAt: e.observedAt,
          validUntil: e.validUntil,
          observedFraction: resolvedForward
              ? 1
              : invalidPositive
              ? 0
              : e.observedFraction,
          confidence: e.confidence,
          occupancyProbability: generic && e.occupancyProbability != null
              ? e.confidence
              : e.occupancyProbability,
          traversabilityProbability: invalidPositive
              ? null
              : resolvedForward && e.source == SpatialEvidenceSource.depth
              ? 1
              : e.traversabilityProbability,
          dropProbability: e.dropProbability,
          movingThreatRisk: e.movingThreatRisk,
          unknownProbability: invalidPositive
              ? 1
              : resolvedForward
              ? 0
              : frameNeedsBodyProof
              ? ((e.unknownProbability ?? 0) < .65 ? .65 : e.unknownProbability)
              : e.unknownProbability,
          hazardIds: e.hazardIds,
          motionVector: e.motionVector,
          closingRate: e.closingRate,
          unknownScopeId: e.unknownScopeId,
          coverageResolution:
              resolvedForward && e.source == SpatialEvidenceSource.depth
              ? proof
              : invalidPositive
              ? null
              : e.coverageResolution,
          passageContext:
              resolvedForward && e.source == SpatialEvidenceSource.depth
              ? proof?.context
              : invalidPositive
              ? null
              : e.passageContext,
        ),
      );
    }
    final hazards = <HazardTrackSnapshot>[];
    for (final hazard in update.hazardTracks) {
      if (volumeAuthority &&
          hazard.elementId == 'forward' &&
          hazard.id.startsWith('geometry:')) {
        continue;
      }
      final components = update.evidence.where(
        (e) =>
            e.source == SpatialEvidenceSource.geometry &&
            e.sourceId.startsWith('geometry:') &&
            e.hazardIds.contains(hazard.id),
      );
      var risk = hazard.risk;
      if (components.isNotEmpty) {
        risk = 0;
        for (final e in components) {
          if (e.confidence > risk) risk = e.confidence;
          if ((e.movingThreatRisk ?? 0) > risk) risk = e.movingThreatRisk!;
        }
      }
      hazards.add(
        HazardTrackSnapshot(
          id: hazard.id,
          elementId: hazard.elementId,
          risk: risk,
          sourceMask: hazard.sourceMask,
          lastObservedAt: hazard.lastObservedAt,
        ),
      );
    }
    for (final track in pending) {
      if (track.confirmed ||
          track.misses != 0 ||
          track.last.zone != HazardZone.center ||
          outside?.call(track) == true ||
          volumeAuthority) {
        continue;
      }
      hazards.add(
        HazardTrackSnapshot(
          id: 'geometry-candidate:${track.id}',
          elementId: 'forward',
          risk: track.last.confidence,
          sourceMask: {'geometry-candidate'},
          lastObservedAt: update.at,
        ),
      );
      // Even a current body proof must not cancel an unresolved central image
      // component whose first surfaces are not demonstrated outside the body.
      evidence.add(
        SpatialEvidence(
          elementId: 'forward',
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'geometry-candidate:${track.id}',
          source: SpatialEvidenceSource.geometry,
          observedAt: update.at,
          validUntil: update.validUntil,
          observedFraction: 0,
          confidence: track.last.confidence,
          unknownProbability: .65,
        ),
      );
    }
    final moving = [
      for (final m in update.movingThreats)
        if (!(volumeAuthority &&
            m.elementId == 'forward' &&
            m.id.startsWith('moving:')))
          m,
    ];
    final measured = motion;
    if (motionUnavailable) {
      evidence.add(
        SpatialEvidence(
          elementId: 'forward',
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'visible-motion-unavailable',
          source: SpatialEvidenceSource.motion,
          observedAt: update.at,
          validUntil: update.validUntil,
          observedFraction: 0,
          confidence: 1,
          unknownProbability: 1,
        ),
      );
    }
    if (blockingWitness) {
      evidence.add(
        SpatialEvidence(
          elementId: 'forward',
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'metric-primary-blocker',
          source: SpatialEvidenceSource.depth,
          observedAt: update.at,
          validUntil: update.validUntil,
          observedFraction: 0,
          confidence: 1,
          occupancyProbability: 1,
          hazardIds: const ['metric-primary-blocker'],
        ),
      );
    }
    if (measured != null &&
        measured.isLiveAt(update.at.microsecondsSinceEpoch) &&
        measured.addsMotionRisk) {
      evidence.add(
        SpatialEvidence(
          elementId: 'forward',
          coordinateMode: SceneCoordinateMode.relative,
          sourceId:
              'visible-ego-motion:${measured.sessionGeneration}:${measured.frameId}',
          source: SpatialEvidenceSource.motion,
          observedAt: DateTime.fromMicrosecondsSinceEpoch(
            measured.capturedAtUs,
          ),
          validUntil: DateTime.fromMicrosecondsSinceEpoch(
            measured.validUntilUs,
          ),
          observedFraction: 0,
          confidence: .9,
          movingThreatRisk: .9,
          hazardIds: ['visible-ego-motion:${measured.frameId}'],
        ),
      );
      moving.add(
        MovingThreatSnapshot(
          id: 'visible-ego-motion:${measured.frameId}',
          elementId: 'forward',
          intersectionRisk: .9,
          lastObservedAt: DateTime.fromMicrosecondsSinceEpoch(
            measured.capturedAtUs,
          ),
        ),
      );
    }
    return super.update(
      LocalSceneUpdate(
        coordinateMode: update.coordinateMode,
        at: update.at,
        validUntil: update.validUntil,
        poseQuality: update.poseQuality,
        sensorHealth: update.sensorHealth,
        evidence: evidence,
        hazardTracks: hazards,
        movingThreats: moving,
        useIndependentEvidenceClocks: update.useIndependentEvidenceClocks,
      ),
    );
  }
}
