import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/depth_frame.dart';
import '../models/frame_packet.dart';
import '../models/generic_obstacle.dart';
import '../models/generic_obstacle_mode.dart';
import '../models/ncnn_depth_contract.dart';
import '../safety/perception/observation_header.dart';
import '../services/fall_detector.dart' show MotionState;
import '../services/field_logger.dart';
import '../services/generic_obstacle_detector.dart';
import '../services/model_service.dart';
import '../services/ncnn_depth_provider.dart';
import '../services/orientation_service.dart';
import '../services/settings_service.dart';
import '../tracker/generic_obstacle_tracker.dart';
import '../tracker/track.dart';
import '../tracker/tracker.dart' show isVehicle;
import '../utils/collision_risk_engine.dart';
import '../utils/depth_hazard.dart';
import '../utils/fusion_engine.dart';
import '../viewmodels/camera_view_model.dart';
import 'camera_session.dart';

class DepthHazardAlert {
  final DepthHazard hazard;
  final bool isCritical;

  const DepthHazardAlert({required this.hazard, required this.isCritical});
}

class _ObservationIdentity {
  final String providerId;
  final String modelId;
  final String modelHash;
  final String preprocessId;

  const _ObservationIdentity({
    required this.providerId,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
  });
}

/// Coarse "is depth working?" status the controller exposes to its host.
///
/// Safety audit 3.2 + 3.3: the controller used to silently skip frames
/// when RANSAC plane-fit failed or when MiDaS confidence was below 0.4.
/// The user heard nothing and had no idea depth-based hazard detection
/// had degraded.  The controller now publishes one of these states and
/// the host can speak a single message on transition.
enum DepthPipelineStatus {
  /// Depth pipeline is healthy: plane-fit ok, confidence high enough.
  ok,

  /// Metric geometry (ARCore) is healthy and aligned.
  healthyMetric,

  /// Relative monocular geometry (NCNN) is healthy and aligned.
  healthyRelative,

  /// MiDaS / hardware confidence has been below the rejection floor for
  /// several consecutive frames — depth-based hazards are not running.
  lowConfidence,

  /// RANSAC plane-fit has failed for several consecutive frames — only
  /// plane-independent hazards (foot zone, stairs, near-field, glass)
  /// are running; pothole / curb / lowCurb detection is OFF.
  planeFitFailed,

  /// Image and depth are from different owners/times.
  unalignedStale,

  /// No depth provider is producing frames.
  providerUnavailable,

  /// Legacy hazards may still run; generic geometry is not available.
  legacyOnlyDegraded,
}

extension DepthPipelineStatusX on DepthPipelineStatus {
  bool get isHealthy =>
      this == DepthPipelineStatus.ok ||
      this == DepthPipelineStatus.healthyMetric ||
      this == DepthPipelineStatus.healthyRelative;

  bool get isDegraded => !isHealthy;
}

class DepthPipelineController {
  final CameraViewModel vm;
  final ModelService models;
  final GenericObstacleDetector _genericDetector;
  final GenericObstacleTracker _genericTracker;
  final CollisionRiskEngine _riskEngine;

  List<CollisionRiskDecision> lastGenericDecisions = const [];
  GenericObstacleDetectResult? lastGenericDetection;
  List<GenericObstacleTrack> lastGenericTracks = const [];
  DepthHealth? lastHealth;
  String? lastFrameRejectionReason;
  ObstacleRejectReason lastGenericRejectReason =
      ObstacleRejectReason.detectorOff;
  FramePacket? lastAcceptedPacket;
  ObservationHeader? lastAcceptedObservationHeader;

  DateTime _lastRunAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastYoloAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration interval = const Duration(milliseconds: 800);
  bool _providerReady = false;
  bool _inFlight = false;
  int _activeSessionGeneration;
  int _latestSubmittedFrameId = 0;

  final Duration maxObservationLatency;

  final FusionEngine _fusion = FusionEngine();
  final Map<HazardZone, double> _yoloHazardConfByZone = {};

  static const int _kDegradedFramesToAnnounce = 3;

  /// Safety audit 2026-06 fix: analyze() used to swallow permanent exceptions
  /// in its catch block (debugPrint + return []) without touching the status,
  /// so a persistently throwing provider left the pipeline "ok" forever and a
  /// blind user walked toward stairs with no depth backup and no spoken
  /// notice. Count consecutive analyze exceptions and degrade after this many.
  static const int _kAnalyzeFailuresToAnnounce = 3;

  int _consecutiveLowConfidenceFrames = 0;
  int _consecutivePlaneFitFailures = 0;
  int _consecutiveAnalyzeFailures = 0;
  DepthPipelineStatus _status = DepthPipelineStatus.ok;

  /// Called once per status transition so the host (camera_screen) can
  /// announce a single TTS message + earcon when depth health changes.
  void Function(DepthPipelineStatus from, DepthPipelineStatus to)?
  onStatusChanged;

  void Function(String reason, double confidence)? onFrameRejected;

  DepthPipelineStatus get status => _status;

  DepthPipelineController({
    required this.vm,
    required this.models,
    GenericObstacleDetector? genericDetector,
    GenericObstacleTracker? genericTracker,
    CollisionRiskEngine? riskEngine,
    this.maxObservationLatency = const Duration(seconds: 2),
  }) : _genericDetector = genericDetector ?? GenericObstacleDetector(),
       _genericTracker = genericTracker ?? GenericObstacleTracker(),
       _riskEngine = riskEngine ?? CollisionRiskEngine(),
       _activeSessionGeneration = vm.cameraSession.generation;

  bool get providerReady => _providerReady;

  /// Invalidates every asynchronous result owned by an older physical camera
  /// session. An already-running provider call remains in flight so a second
  /// heavy inference cannot start concurrently; its eventual result is
  /// discarded before any scene state is touched.
  void beginSession(int generation) {
    assert(generation == vm.cameraSession.generation);
    _activeSessionGeneration = generation;
    _latestSubmittedFrameId = 0;
    _consecutiveLowConfidenceFrames = 0;
    _consecutivePlaneFitFailures = 0;
    _consecutiveAnalyzeFailures = 0;
    lastAcceptedPacket = null;
    lastAcceptedObservationHeader = null;
    lastGenericDetection = null;
    lastGenericTracks = const [];
    lastFrameRejectionReason = null;
    resetFusion();
  }

  void setProviderReady(bool value) {
    _providerReady = value;
    if (value) {
      // Safety audit 2026-06 fix: subscribe to NCNN session-disable so the
      // host gets an immediate TTS depth_degraded announcement instead of
      // waiting for _kDegradedFramesToAnnounce frames (or never, when the
      // provider flips to not-ready between analyze() calls).
      final dp = models.depthProvider;
      if (dp is NcnnDepthProvider) {
        dp.onSessionDisabled = onNcnnSessionDisabled;
      }
    }
  }

  /// Called when the underlying NCNN depth provider permanently disables its
  /// session (3 invalid outputs in 5 min — see NcnnDepthProvider safety
  /// inviolable). Surfaces the degradation to the host immediately via
  /// [onStatusChanged] so a blind user hears `depth_degraded` right away
  /// rather than after the consecutive-frame debounce.
  void onNcnnSessionDisabled() {
    _consecutiveLowConfidenceFrames = _kDegradedFramesToAnnounce;
    _consecutivePlaneFitFailures = 0;
    _consecutiveAnalyzeFailures = 0;
    _setStatus(DepthPipelineStatus.lowConfidence);
  }

  bool shouldRun(DateTime now) =>
      _providerReady && !_inFlight && now.difference(_lastRunAt) >= interval;

  void updateYoloTracks(
    List<Track> tracks, {
    required int imgW,
    DateTime? now,
  }) {
    _lastYoloAt = now ?? DateTime.now();
    _lastYoloTracks = List<Track>.from(tracks);
    _yoloHazardConfByZone.clear();
    if (imgW <= 0 || tracks.isEmpty) return;
    final zoneWidth = imgW / HazardZone.values.length;
    for (final t in tracks) {
      if (t.dist != 'very close' && t.dist != 'close') continue;

      double weight = 1.0;
      if (t.label == 'person') {
        weight = 1.0;
      } else if (isVehicle(t.label)) {
        weight = 1.1;
      } else {
        weight = 0.8;
      }
      final yoloConf = (t.avgConf > 0 ? t.avgConf : 0.0) * weight;
      final zoneIdx = (t.cx / zoneWidth).floor().clamp(
        0,
        HazardZone.values.length - 1,
      );
      final zone = HazardZone.values[zoneIdx];
      final prev = _yoloHazardConfByZone[zone] ?? 0.0;
      if (yoloConf > prev) {
        _yoloHazardConfByZone[zone] = yoloConf.clamp(0.0, 1.0);
      }
    }
  }

  @visibleForTesting
  Map<HazardZone, double> get yoloHazardConfByZoneForTesting =>
      Map<HazardZone, double>.unmodifiable(_yoloHazardConfByZone);

  Future<List<DepthHazardAlert>> analyze(
    CameraImage image,
    DateTime now,
  ) async {
    final packet = _buildPacket(image, now);
    _latestSubmittedFrameId = packet.frameId;

    // Never let an early-returning or superseded provider replay decisions
    // from an older frame into the assistive alert path.
    lastGenericDecisions = const [];
    lastGenericDetection = null;
    lastGenericTracks = const [];
    lastAcceptedPacket = null;
    lastAcceptedObservationHeader = null;
    lastFrameRejectionReason = null;
    if (_inFlight) {
      lastFrameRejectionReason = 'provider_busy_latest_frame_wins';
      onFrameRejected?.call('provider_busy_latest_frame_wins', 0);
      return const <DepthHazardAlert>[];
    }
    _inFlight = true;
    _lastRunAt = now;
    final provider = models.depthProvider;
    if (provider == null || !provider.isReady) {
      // Safety audit 2026-06 fix: provider unavailable (e.g. NCNN session
      // auto-disabled after 3 invalid outputs in 5 min) must not silently
      // pass. Count it as a degraded frame so the host gets a TTS
      // depth_degraded announcement after _kDegradedFramesToAnnounce
      // consecutive frames — otherwise a blind user walks toward stairs
      // with no depth backup and no spoken notice.
      _inFlight = false;
      _consecutiveLowConfidenceFrames++;
      _consecutivePlaneFitFailures = 0;
      lastFrameRejectionReason = 'provider_unavailable';
      onFrameRejected?.call('provider_unavailable', 0);
      if (_consecutiveLowConfidenceFrames >= _kDegradedFramesToAnnounce) {
        _setStatus(DepthPipelineStatus.lowConfidence);
      }
      return const <DepthHazardAlert>[];
    }

    _consecutiveLowConfidenceFrames = 0;
    final inferenceTimer = Stopwatch()..start();
    try {
      final userStationary =
          vm.fallDetector.motionState == MotionState.stationary;
      final detailed = await provider.analyzeDetailed(
        image,
        cropTopFrac: packet.cropTopFraction,
        userStationary: userStationary,
        weatherDegraded: vm.weatherGate.degraded,
        winterMode: vm.winterMode.active,
        sourceTimestampUs: packet.cameraTimestampUs,
        rotationDegrees: packet.sensorRotationDeg,
        mirrored: packet.mirrored,
      );
      inferenceTimer.stop();

      final identity = _identityFor(provider, detailed);
      final observation = PerceptionObservation<DepthAnalysisResult>(
        header: ObservationHeader.fromPacket(
          packet: packet,
          providerId: identity.providerId,
          modelId: identity.modelId,
          modelHash: identity.modelHash,
          preprocessId: identity.preprocessId,
          producedAtUs:
              packet.receivedAtUs + inferenceTimer.elapsedMicroseconds,
          confidence: detailed.health.components.combined,
          health: _observationHealth(detailed.health.capability),
        ),
        payload: detailed,
      );

      final ownershipRejection = _ownershipRejection(
        packet,
        observation.header,
      );
      if (ownershipRejection != null) {
        _inFlight = false;
        lastFrameRejectionReason = ownershipRejection;
        onFrameRejected?.call(
          ownershipRejection,
          observation.header.confidence,
        );
        if (ownershipRejection == 'stale_observation_latency' ||
            ownershipRejection == 'observation_header_mismatch') {
          _setStatus(DepthPipelineStatus.unalignedStale);
        }
        return const <DepthHazardAlert>[];
      }

      final alignmentRejection = _alignmentRejection(packet, detailed);
      if (alignmentRejection != null) {
        _inFlight = false;
        lastFrameRejectionReason = alignmentRejection;
        onFrameRejected?.call(
          alignmentRejection,
          observation.header.confidence,
        );
        _setStatus(DepthPipelineStatus.unalignedStale);
        return const <DepthHazardAlert>[];
      }

      lastAcceptedPacket = packet;
      lastAcceptedObservationHeader = observation.header;
      lastHealth = detailed.health;
      final hazards = detailed.legacyHazards;
      final genericReject = _runGenericStack(
        image: image,
        detailed: detailed,
        now: now,
      );
      _inFlight = false;

      // Safety audit 2026-06 fix: analyze() returned without throwing, so the
      // provider is healthy again. Clear the consecutive-exception counter so
      // a single transient error does not keep accumulating toward a false
      // degradation announcement. (Mirrors the _consecutiveLowConfidenceFrames
      // reset above — the pipeline is back in a confident state.)
      _consecutiveAnalyzeFailures = 0;

      _applyHealthStatus(
        detailed.health,
        detailed.planeFitQuality?.accepted ?? provider.lastPlaneFitOk,
        genericReject: genericReject,
      );

      if (hazards.isEmpty) return const <DepthHazardAlert>[];
      final rollExcessive = vm.orientation.isRollExcessive;
      final filteredHazards = hazards.where((h) {
        if (h.type == DepthHazardType.deadZone && h.midasScore < 0.65) {
          return false;
        }
        if (h.type == DepthHazardType.slippery && h.midasScore < 0.55) {
          return false;
        }
        return true;
      });
      final winterMode = vm.winterMode.active;
      final out = <DepthHazardAlert>[];
      for (final h in filteredHazards) {
        bool isCritical = _isHazardCritical(
          h,
          rollExcessive: rollExcessive,
          userStationary: userStationary,
          winterMode: winterMode,
        );

        if (!isCritical && !rollExcessive) {
          final yoloConf = _yoloHazardConfByZone[h.zone] ?? 0.0;
          final yoloAge = now.difference(_lastYoloAt);
          final fused = _fusion.evaluate(
            hazard: h,
            yoloHazardConf: yoloConf,
            now: now,
            yoloAge: yoloAge,
          );
          if (fused != null && fused.level == AlertLevel.critical) {
            isCritical = true;
          }
        }

        out.add(DepthHazardAlert(hazard: h, isCritical: isCritical));
      }
      return out;
    } catch (e) {
      if (inferenceTimer.isRunning) inferenceTimer.stop();
      _inFlight = false;
      debugPrint('Depth analysis error: $e');
      if (!_requestIsCurrent(packet)) {
        lastFrameRejectionReason = 'late_error_discarded';
        onFrameRejected?.call('late_error_discarded', 0);
        return const <DepthHazardAlert>[];
      }
      lastFrameRejectionReason = 'provider_analyze_exception';
      // Safety audit 2026-06 fix: a permanently throwing provider (e.g. a
      // recurring platform/NCNN exception that never reaches the
      // onSessionDisabled path) used to leave the pipeline silently "ok".
      // Count consecutive exceptions and degrade to lowConfidence after
      // _kAnalyzeFailuresToAnnounce so the host speaks `depth_degraded` and a
      // blind user is not walking toward hazards with depth detection off and
      // no spoken notice.
      _consecutiveAnalyzeFailures++;
      _consecutiveLowConfidenceFrames = 0;
      _consecutivePlaneFitFailures = 0;
      if (_consecutiveAnalyzeFailures >= _kAnalyzeFailuresToAnnounce) {
        _setStatus(DepthPipelineStatus.lowConfidence);
      }
      return const <DepthHazardAlert>[];
    }
  }

  FramePacket _buildPacket(CameraImage image, DateTime now) {
    final cropTop = OrientationService.cropTopFracForPitch(
      vm.orientation.pitch,
    );
    final transform = FrameTransform.forSensor(
      sensorRotationDeg: vm.cameraSensorRotationDeg,
      mirrored: vm.cameraMirrored,
      sourceSize: FrameSize(image.width, image.height),
      crop: CropTransform(topFraction: cropTop),
    );
    return FramePacket(
      sessionGeneration: vm.cameraSession.generation,
      frameId: vm.cameraSession.nextFrameId(),
      cameraTimestampUs: now.microsecondsSinceEpoch,
      receivedAtUs: now.microsecondsSinceEpoch,
      transform: transform,
      pitchDeg: vm.orientation.pitch,
      rollDeg: vm.orientation.roll,
      angularVelocity: AngularVelocity.unknown,
      motionState: switch (vm.fallDetector.motionState) {
        MotionState.stationary => FrameMotionState.stationary,
        MotionState.walking => FrameMotionState.walking,
        MotionState.running => FrameMotionState.running,
        MotionState.unstable => FrameMotionState.unstable,
      },
    );
  }

  String? _ownershipRejection(FramePacket packet, ObservationHeader header) {
    if (!header.matchesPacket(packet)) return 'observation_header_mismatch';
    if (packet.sessionGeneration != _activeSessionGeneration ||
        !vm.cameraSession.acceptsObservation(
          header,
          latestFrameId: _latestSubmittedFrameId,
        )) {
      return header.sessionGeneration != vm.cameraSession.generation
          ? 'stale_session_generation'
          : 'superseded_frame';
    }
    if (header.exceedsLatency(maxObservationLatency)) {
      return 'stale_observation_latency';
    }
    return null;
  }

  bool _requestIsCurrent(FramePacket packet) =>
      packet.sessionGeneration == _activeSessionGeneration &&
      packet.sessionGeneration == vm.cameraSession.generation &&
      packet.frameId == _latestSubmittedFrameId;

  String? _alignmentRejection(
    FramePacket packet,
    DepthAnalysisResult detailed,
  ) {
    final frame = detailed.frame;
    if (frame == null) return null;
    if (!CameraSession.timestampsAligned(
      imageTimestampUs: packet.cameraTimestampUs,
      depthTimestampUs: frame.timestampUs,
    )) {
      return 'depth_timestamp_mismatch';
    }
    if (FrameTransform.normalizeRotation(frame.rotationDegrees) !=
            packet.sensorRotationDeg ||
        frame.mirrored != packet.mirrored ||
        (frame.cropTopFraction - packet.cropTopFraction).abs() > 0.000001) {
      return 'depth_transform_mismatch';
    }
    if (!frame.alignedToImage) return 'depth_not_image_aligned';
    return null;
  }

  static ObservationHealth _observationHealth(DepthCapability capability) =>
      switch (capability) {
        DepthCapability.healthyMetric ||
        DepthCapability.healthyRelative => ObservationHealth.healthy,
        DepthCapability.providerUnavailable => ObservationHealth.unavailable,
        DepthCapability.temporarilyLowConfidence ||
        DepthCapability.unalignedOrStale ||
        DepthCapability.legacyOnlyDegraded => ObservationHealth.degraded,
      };

  static _ObservationIdentity _identityFor(
    Object provider,
    DepthAnalysisResult detailed,
  ) {
    final providerKind = detailed.health.provider;
    final frame = detailed.frame;
    if (frame != null) {
      final providerId = switch (frame.provider) {
        DepthProviderKind.ncnnRelative => 'ncnn-depth',
        DepthProviderKind.arcoreMetric => 'arcore-raw-depth',
        DepthProviderKind.unavailable => provider.runtimeType.toString(),
      };
      return _ObservationIdentity(
        providerId: providerId,
        modelId: frame.modelId,
        modelHash: frame.modelHash,
        preprocessId: frame.preprocessId,
      );
    }
    if (providerKind == DepthProviderKind.ncnnRelative ||
        provider is NcnnDepthProvider) {
      return const _ObservationIdentity(
        providerId: 'ncnn-depth',
        modelId: NcnnDepthContract.modelId,
        modelHash: NcnnDepthContract.modelHash,
        preprocessId: NcnnDepthContract.preprocessId,
      );
    }
    if (providerKind == DepthProviderKind.arcoreMetric) {
      return const _ObservationIdentity(
        providerId: 'arcore-raw-depth',
        modelId: 'arcore-raw-depth-platform',
        modelHash: 'platform-managed:arcore-raw-depth',
        preprocessId: 'arcore-depth-alignment-v1',
      );
    }
    final runtimeId = provider.runtimeType.toString();
    return _ObservationIdentity(
      providerId: runtimeId,
      modelId: 'legacy-adapter:$runtimeId',
      modelHash: 'unversioned:$runtimeId',
      preprocessId: 'legacy-depth-adapter-v1',
    );
  }

  void resetFusion() {
    _fusion.reset();
    _yoloHazardConfByZone.clear();
    _genericTracker.reset();
    lastGenericDecisions = const [];
    lastGenericDetection = null;
    lastGenericTracks = const [];
    lastGenericRejectReason = ObstacleRejectReason.detectorOff;
    lastFrameRejectionReason = null;
    lastHealth = null;
    lastAcceptedPacket = null;
    lastAcceptedObservationHeader = null;
  }

  void _applyHealthStatus(
    DepthHealth health,
    bool planeFitOk, {
    ObstacleRejectReason genericReject = ObstacleRejectReason.none,
  }) {
    if (health.isHealthyGeometry) {
      if (genericReject == ObstacleRejectReason.stale ||
          genericReject == ObstacleRejectReason.unaligned) {
        _setStatus(DepthPipelineStatus.unalignedStale);
        return;
      }
      if (genericReject == ObstacleRejectReason.lowConfidence ||
          genericReject == ObstacleRejectReason.lowCoverage ||
          genericReject == ObstacleRejectReason.planeUnreliable) {
        _setStatus(DepthPipelineStatus.lowConfidence);
        return;
      }
    }
    switch (health.capability) {
      case DepthCapability.healthyMetric:
        _consecutivePlaneFitFailures = 0;
        _setStatus(DepthPipelineStatus.healthyMetric);
        return;
      case DepthCapability.healthyRelative:
        _consecutivePlaneFitFailures = 0;
        _setStatus(DepthPipelineStatus.healthyRelative);
        return;
      case DepthCapability.unalignedOrStale:
        _setStatus(DepthPipelineStatus.unalignedStale);
        return;
      case DepthCapability.providerUnavailable:
        _setStatus(DepthPipelineStatus.providerUnavailable);
        return;
      case DepthCapability.temporarilyLowConfidence:
        _setStatus(DepthPipelineStatus.lowConfidence);
        return;
      case DepthCapability.legacyOnlyDegraded:
        if (health.rejectionReason == 'genericObstacleUnavailable') {
          _setStatus(DepthPipelineStatus.legacyOnlyDegraded);
          return;
        }
        if (planeFitOk) {
          _consecutivePlaneFitFailures = 0;
          if (_status != DepthPipelineStatus.lowConfidence) {
            _setStatus(DepthPipelineStatus.ok);
          }
        } else {
          _consecutivePlaneFitFailures++;
          if (_consecutivePlaneFitFailures >= _kDegradedFramesToAnnounce) {
            _setStatus(DepthPipelineStatus.planeFitFailed);
          }
        }
        return;
    }
  }

  ObstacleRejectReason _runGenericStack({
    required CameraImage image,
    required DepthAnalysisResult detailed,
    required DateTime now,
  }) {
    lastGenericDecisions = const [];
    final mode = Settings.instance.genericObstacleMode;
    if (mode == GenericObstacleMode.off) {
      lastGenericDetection = const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.detectorOff,
        detectorQuality: 0,
        groundConfidence: 0,
      );
      lastGenericTracks = const [];
      lastGenericRejectReason = ObstacleRejectReason.detectorOff;
      return lastGenericRejectReason;
    }

    final planeFitQuality = detailed.planeFitQuality;
    if (planeFitQuality != null && !planeFitQuality.accepted) {
      lastGenericDetection = const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.planeUnreliable,
        detectorQuality: 0,
        groundConfidence: 0,
      );
      lastGenericTracks = const [];
      lastGenericDecisions = const [];
      lastGenericRejectReason = ObstacleRejectReason.planeUnreliable;
      FieldLogger.instance.log('generic_obstacle_frame', {
        'reject': ObstacleRejectReason.planeUnreliable.name,
        'planeFitReason': planeFitQuality.rejectionReason.name,
        'planeFitQuality': planeFitQuality.toDiagnosticMap(),
        'provider': detailed.health.provider.name,
        'health': detailed.health.capability.name,
        'mode': mode.name,
      });
      return lastGenericRejectReason;
    }

    final detected = _genericDetector.detect(
      frame: detailed.health.genericObstacleAvailable ? detailed.frame : null,
      pitchDeg: vm.orientation.pitch,
      rollDeg: vm.orientation.roll,
      motion: vm.fallDetector.motionState,
      imageTimestampUs: now.microsecondsSinceEpoch,
      lumaMap: detailed.alignedLuma,
    );
    lastGenericDetection = detected;
    lastGenericRejectReason = detected.rejectReason;
    FieldLogger.instance.log('generic_obstacle_frame', {
      'reject': detected.rejectReason.name,
      'detectorQuality': detected.detectorQuality,
      'groundConfidence': detected.groundConfidence,
      'components': detected.observations.length,
      'provider': detailed.health.provider.name,
      'health': detailed.health.capability.name,
      'mode': mode.name,
    });

    final relative =
        detailed.frame?.semantics == DepthValueSemantics.relativeProximity;
    final tracks = _genericTracker.update(
      observations: detected.observations,
      timestampUs: detailed.frame?.timestampUs ?? now.microsecondsSinceEpoch,
      relative: relative,
    );
    lastGenericTracks = List<GenericObstacleTrack>.unmodifiable(tracks);

    final decisions = <CollisionRiskDecision>[];
    for (final track in tracks) {
      if (!track.confirmed) continue;
      final semantic = _semanticFor(
        track.last,
        image.width,
        image.height,
        detailed.frame,
        now,
      );
      final decision = _riskEngine.evaluate(
        track: track,
        health: detailed.health,
        motion: vm.fallDetector.motionState,
        mode: mode,
        relative: relative,
        semantic: semantic,
      );
      decisions.add(decision);
      FieldLogger.instance.log('generic_obstacle', {
        'rule': decision.ruleId,
        'level': decision.level?.name,
        'track': track.id,
        'geom': track.last.geometry.name,
        'zone': track.last.zone.name,
        'prox': (track.last.relativeProximity * 100).round(),
        'overlap': (track.last.corridorOverlap * 100).round(),
        'semantic': semantic?.label ?? 'none',
        'emit': decision.emitUserAlert,
        'mode': mode.name,
        'reject': detected.rejectReason.name,
      });
    }
    lastGenericDecisions = decisions;
    return detected.rejectReason;
  }

  SemanticMatch? _semanticFor(
    GenericObstacleObservation obs,
    int imgW,
    int imgH,
    DepthFrame? frame,
    DateTime now,
  ) {
    if (imgW <= 0 || imgH <= 0 || frame == null) return null;
    const config = GenericObstacleConfig.engineeringDefaults;
    if (_lastYoloAt.millisecondsSinceEpoch == 0 ||
        now.microsecondsSinceEpoch - _lastYoloAt.microsecondsSinceEpoch >
            config.semanticMaxAgeUs) {
      return null;
    }
    Track? best;
    var bestIou = 0.0;
    final transform = FrameTransform.forSensor(
      sensorRotationDeg: frame.rotationDegrees,
      mirrored: frame.mirrored,
      sourceSize: FrameSize(imgW, imgH),
      crop: CropTransform(topFraction: frame.cropTopFraction),
    );
    for (final t in _lastYoloTracks) {
      if (t.dist != 'very close' && t.dist != 'close') continue;
      if (t.avgConf < config.semanticMinConf) continue;
      final raw = Rect.fromLTRB(
        t.x1 / imgW,
        t.y1 / imgH,
        t.x2 / imgW,
        t.y2 / imgH,
      );
      // Generic observations are expanded back to full upright coordinates,
      // so semantic boxes use the same transform but intentionally stop
      // before the depth crop.
      final upright = transform.mapSourceRectToUpright(raw);
      final iou = _rectIou(obs.normalizedBounds, upright);
      if (iou >= config.semanticMatchIou && iou > bestIou) {
        best = t;
        bestIou = iou;
      }
    }
    if (best == null) return null;
    return SemanticMatch(
      yoloTrackId: best.id,
      label: best.label,
      confidence: best.avgConf,
    );
  }

  double _rectIou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final interArea = intersection.width * intersection.height;
    final unionArea = a.width * a.height + b.width * b.height - interArea;
    return unionArea <= 0 ? 0.0 : interArea / unionArea;
  }

  @visibleForTesting
  SemanticMatch? debugSemanticFor({
    required GenericObstacleObservation observation,
    required int imageWidth,
    required int imageHeight,
    required DepthFrame frame,
    required DateTime now,
  }) => _semanticFor(observation, imageWidth, imageHeight, frame, now);

  List<Track> _lastYoloTracks = const [];

  void _setStatus(DepthPipelineStatus next) {
    if (_status == next) return;
    final from = _status;
    _status = next;
    onStatusChanged?.call(from, next);
  }

  @visibleForTesting
  void debugSetStatus(DepthPipelineStatus next) => _setStatus(next);

  static String hazardKeyFor(DepthHazardType type) {
    return switch (type.name) {
      'stepDown' => 'hazard_step_down',
      'stepUp' => 'hazard_step_up',
      'pothole' => 'hazard_pothole',
      'curb' => 'hazard_curb',
      'lowCurb' => 'hazard_low_curb',
      'deadZone' => 'hazard_dead_zone',
      'stairsDown' => 'hazard_stairs_down',
      'overhead' => 'hazard_overhead',
      'glassDoor' => 'hazard_glass_door',
      'slippery' => 'hazard_slippery',
      'nearFieldIntrusion' => 'hazard_near_field',
      _ => 'hazard_unknown',
    };
  }

  static const double _kCriticalCenterScore = 0.65;
  static const double _kCriticalNearFieldScore = 0.55;
  static const double _kCriticalSlipperyScore = 0.50;

  static bool isHazardCriticalForTesting(
    DepthHazard hazard, {
    required bool rollExcessive,
    bool userStationary = false,
    bool winterMode = false,
  }) => _isHazardCritical(
    hazard,
    rollExcessive: rollExcessive,
    userStationary: userStationary,
    winterMode: winterMode,
  );

  static bool _isHazardCritical(
    DepthHazard hazard, {
    required bool rollExcessive,
    bool userStationary = false,
    bool winterMode = false,
  }) {
    switch (hazard.type) {
      case DepthHazardType.stairsDown:
      case DepthHazardType.overhead:
        return true;

      case DepthHazardType.pothole:
      case DepthHazardType.stepDown:
        if (rollExcessive) return false;
        return _isCenterZone(hazard.zone) &&
            hazard.midasScore >= _kCriticalCenterScore;

      case DepthHazardType.glassDoor:
        return _isCenterZone(hazard.zone) &&
            hazard.midasScore >= _kCriticalCenterScore;

      case DepthHazardType.nearFieldIntrusion:
        return hazard.midasScore >= _kCriticalNearFieldScore;

      case DepthHazardType.slippery:
        if (winterMode) {
          return !userStationary &&
              hazard.midasScore >= _kCriticalSlipperyScore;
        }
        return !userStationary &&
            _isCenterZone(hazard.zone) &&
            hazard.midasScore >= _kCriticalSlipperyScore;

      case DepthHazardType.stepUp:
      case DepthHazardType.curb:
      case DepthHazardType.lowCurb:
      case DepthHazardType.deadZone:
      case DepthHazardType.escalatorRiding:
      case DepthHazardType.unknown:
        return false;
    }
  }

  static bool _isCenterZone(HazardZone zone) =>
      zone == HazardZone.center ||
      zone == HazardZone.centerLeft ||
      zone == HazardZone.centerRight;
}
