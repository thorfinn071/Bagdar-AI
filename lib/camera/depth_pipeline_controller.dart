import '../core/performance/perception_performance.dart';
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
  int _yoloImageWidth = 0;
  int? _yoloImageHeight, _yoloRotationDegrees;
  bool? _yoloMirrored;
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
    int? imgH,
    int? rotationDegrees,
    bool? mirrored,
    DateTime? now,
  }) {
    _yoloImageWidth = imgW;
    _yoloImageHeight = imgH;
    _yoloRotationDegrees = rotationDegrees;
    _yoloMirrored = mirrored;
    _lastYoloAt = now ?? DateTime.now();
    _lastYoloTracks = List<_YoloTrackSample>.unmodifiable(
      tracks.map(_YoloTrackSample.new),
    );
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

  void Function(DepthPerformanceSample sample)? onPerformanceSample;

  Future<List<DepthHazardAlert>> analyze(
    CameraImage image,
    DateTime now, {
    CallbackFrameTiming? timing,
  }) async {
    final clock = timing ?? CallbackFrameTiming(now.microsecondsSinceEpoch);
    final measurement = _DepthMeasurement(vm.cameraSession.generation);
    try {
      if (clock.callbackTimestampUs != now.microsecondsSinceEpoch ||
          clock.ageUs < 0) {
        lastFrameRejectionReason = 'callback_clock_mismatch';
        measurement.rejectionReason = lastFrameRejectionReason;
        lastGenericDetection = null;
        lastGenericTracks = const [];
        lastGenericDecisions = const [];
        lastAcceptedPacket = null;
        lastAcceptedObservationHeader = null;
        onFrameRejected?.call('callback_clock_mismatch', 0);
        _setStatus(DepthPipelineStatus.unalignedStale);
        return const [];
      }
      return await _analyze(image, now, clock, measurement);
    } finally {
      final sample = DepthPerformanceSample(
        sessionGeneration: measurement.generation,
        frameId: measurement.frameId,
        sourceTimestampUs: now.microsecondsSinceEpoch,
        providerRoundTripUs: measurement.providerUs,
        callbackToDecisionUs: clock.ageUs,
        providerCalled: measurement.providerCalled,
        accepted: measurement.accepted,
        rejectionReason: measurement.rejectionReason,
      );
      // Diagnostics must never change safety decisions when a sink fails.
      try {
        onPerformanceSample?.call(sample);
      } catch (_) {}
    }
  }

  Future<List<DepthHazardAlert>> _analyze(
    CameraImage image,
    DateTime now,
    CallbackFrameTiming clock,
    _DepthMeasurement measurement,
  ) async {
    final packet = _buildPacket(image, now);
    measurement.frameId = packet.frameId;
    _latestSubmittedFrameId = packet.frameId;

    // Never let an early-returning or superseded provider replay decisions
    // from an older frame into the assistive alert path.
    lastGenericDecisions = const [];
    lastGenericDetection = null;
    lastGenericTracks = const [];
    lastAcceptedPacket = null;
    lastAcceptedObservationHeader = null;
    lastFrameRejectionReason = null;
    measurement.rejectionReason = lastFrameRejectionReason;
    if (_inFlight) {
      lastFrameRejectionReason = 'provider_busy_latest_frame_wins';
      measurement.rejectionReason = lastFrameRejectionReason;
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
      measurement.rejectionReason = lastFrameRejectionReason;
      onFrameRejected?.call('provider_unavailable', 0);
      if (_consecutiveLowConfidenceFrames >= _kDegradedFramesToAnnounce) {
        _setStatus(DepthPipelineStatus.lowConfidence);
      }
      return const <DepthHazardAlert>[];
    }

    _consecutiveLowConfidenceFrames = 0;
    // YOLO and sensor callbacks may advance while background inference runs.
    // Keep scalar context from submission with this frame, not the next frame.
    final yoloAligned = _yoloMatchesFrame(
      at: now,
      width: image.width,
      height: image.height,
      rotationDegrees: packet.sensorRotationDeg,
      mirrored: packet.mirrored,
    );
    final context = _DepthFrameContext(
      yoloTracks: yoloAligned ? _lastYoloTracks : const [],
      yoloAt: yoloAligned
          ? _lastYoloAt
          : DateTime.fromMillisecondsSinceEpoch(0),
      yoloHazardConf: yoloAligned
          ? Map<HazardZone, double>.unmodifiable(_yoloHazardConfByZone)
          : const {},
      pitch: vm.orientation.pitch,
      roll: vm.orientation.roll,
      rollExcessive: vm.orientation.isRollExcessive,
      motion: vm.fallDetector.motionState,
      winterMode: vm.winterMode.active,
    );
    final inferenceTimer = Stopwatch()..start();
    try {
      final userStationary = context.motion == MotionState.stationary;
      measurement.providerCalled = true;
      final detailed = await provider.analyzeDetailed(
        image,
        cropTopFrac: packet.cropTopFraction,
        userStationary: userStationary,
        weatherDegraded: vm.weatherGate.degraded,
        winterMode: context.winterMode,
        sourceTimestampUs: packet.cameraTimestampUs,
        rotationDegrees: packet.sensorRotationDeg,
        mirrored: packet.mirrored,
      );
      inferenceTimer.stop();
      measurement.providerUs = inferenceTimer.elapsedMicroseconds;

      final identity = _identityFor(provider, detailed);
      var observation = PerceptionObservation<DepthAnalysisResult>(
        header: ObservationHeader.fromPacket(
          packet: packet,
          providerId: identity.providerId,
          modelId: identity.modelId,
          modelHash: identity.modelHash,
          preprocessId: identity.preprocessId,
          producedAtUs: clock.producedAtUs,
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
        measurement.rejectionReason = lastFrameRejectionReason;
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
        measurement.rejectionReason = lastFrameRejectionReason;
        onFrameRejected?.call(
          alignmentRejection,
          observation.header.confidence,
        );
        _setStatus(DepthPipelineStatus.unalignedStale);
        return const <DepthHazardAlert>[];
      }

      final hazards = detailed.legacyHazards;
      final genericReject = _runGenericStack(
        image: image,
        detailed: detailed,
        now: now,
        context: context,
      );
      observation = PerceptionObservation<DepthAnalysisResult>(
        header: ObservationHeader.fromPacket(
          packet: packet,
          providerId: identity.providerId,
          modelId: identity.modelId,
          modelHash: identity.modelHash,
          preprocessId: identity.preprocessId,
          producedAtUs: clock.producedAtUs,
          confidence: detailed.health.components.combined,
          health: _observationHealth(detailed.health.capability),
        ),
        payload: detailed,
      );
      final releaseRejection = _ownershipRejection(packet, observation.header);
      if (releaseRejection != null) {
        _inFlight = false;
        lastFrameRejectionReason = releaseRejection;
        measurement.rejectionReason = lastFrameRejectionReason;
        lastGenericDetection = null;
        lastGenericTracks = const [];
        lastGenericDecisions = const [];
        onFrameRejected?.call(releaseRejection, observation.header.confidence);
        _setStatus(DepthPipelineStatus.unalignedStale);
        return const [];
      }
      lastAcceptedPacket = packet;
      lastAcceptedObservationHeader = observation.header;
      lastHealth = detailed.health;
      measurement.accepted = detailed.frame != null;
      if (!measurement.accepted) {
        measurement.rejectionReason = detailed.health.rejectionReason;
      }
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
      final rollExcessive = context.rollExcessive;
      final filteredHazards = hazards.where((h) {
        if (h.type == DepthHazardType.deadZone && h.midasScore < 0.65) {
          return false;
        }
        if (h.type == DepthHazardType.slippery && h.midasScore < 0.55) {
          return false;
        }
        return true;
      });
      final winterMode = context.winterMode;
      final out = <DepthHazardAlert>[];
      for (final h in filteredHazards) {
        bool isCritical = _isHazardCritical(
          h,
          rollExcessive: rollExcessive,
          userStationary: userStationary,
          winterMode: winterMode,
        );

        if (!isCritical && !rollExcessive) {
          final yoloConf = context.yoloHazardConf[h.zone] ?? 0.0;
          final yoloAge = now.difference(context.yoloAt);
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
      measurement.providerUs = inferenceTimer.elapsedMicroseconds;
      _inFlight = false;
      debugPrint('Depth analysis error: $e');
      if (!_requestIsCurrent(packet)) {
        lastFrameRejectionReason = 'late_error_discarded';
        measurement.rejectionReason = lastFrameRejectionReason;
        onFrameRejected?.call('late_error_discarded', 0);
        return const <DepthHazardAlert>[];
      }
      lastFrameRejectionReason = 'provider_analyze_exception';
      measurement.rejectionReason = lastFrameRejectionReason;
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
    if (FrameTransform.normalizeRotation(vm.cameraSensorRotationDeg) !=
            packet.sensorRotationDeg ||
        vm.cameraMirrored != packet.mirrored) {
      return 'active_camera_transform_mismatch';
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
    _lastYoloTracks = const [];
    _lastYoloAt = DateTime.fromMillisecondsSinceEpoch(0);
    _yoloImageWidth = 0;
    _yoloImageHeight = null;
    _yoloRotationDegrees = null;
    _yoloMirrored = null;
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
    required _DepthFrameContext context,
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
      pitchDeg: context.pitch,
      rollDeg: context.roll,
      motion: context.motion,
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

    final decisions = <CollisionRiskDecision>[];
    for (final track in tracks) {
      if (!track.confirmed) continue;
      final semantic = _attachSemanticToTrack(
        track: track,
        imageWidth: image.width,
        imageHeight: image.height,
        frame: detailed.frame,
        now: now,
        context: context,
      );
      final decision = _riskEngine.evaluate(
        track: track,
        health: detailed.health,
        motion: context.motion,
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
    lastGenericTracks = List<GenericObstacleTrack>.unmodifiable(tracks);
    lastGenericDecisions = decisions;
    return detected.rejectReason;
  }

  SemanticMatch? _attachSemanticToTrack({
    required GenericObstacleTrack track,
    required int imageWidth,
    required int imageHeight,
    required DepthFrame? frame,
    required DateTime now,
    _DepthFrameContext? context,
  }) {
    final semantic = _semanticFor(
      track.last,
      imageWidth,
      imageHeight,
      frame,
      now,
      context: context,
    );
    // The scene adapter consumes the track snapshot. Keep the current match
    // on that same observation, and explicitly clear an older match when the
    // latest frame no longer has one. Risk evaluation and spatial fusion must
    // not see different versions of one confirmed track.
    track.last = track.last.copyWith(
      semantic: semantic,
      clearSemantic: semantic == null,
    );
    return semantic;
  }

  SemanticMatch? _semanticFor(
    GenericObstacleObservation obs,
    int imgW,
    int imgH,
    DepthFrame? frame,
    DateTime now, {
    _DepthFrameContext? context,
  }) {
    if (imgW <= 0 || imgH <= 0 || frame == null) return null;
    if (context == null &&
        !_yoloMatchesFrame(
          at: DateTime.fromMicrosecondsSinceEpoch(frame.timestampUs),
          width: imgW,
          height: imgH,
          rotationDegrees: frame.rotationDegrees,
          mirrored: frame.mirrored,
        )) {
      return null;
    }
    const config = GenericObstacleConfig.engineeringDefaults;
    final yoloAt = context?.yoloAt ?? _lastYoloAt;
    if (yoloAt.millisecondsSinceEpoch == 0 ||
        now.isBefore(yoloAt) ||
        now.microsecondsSinceEpoch - yoloAt.microsecondsSinceEpoch >
            config.semanticMaxAgeUs) {
      return null;
    }
    _YoloTrackSample? best;
    var bestIou = 0.0;
    final transform = FrameTransform.forSensor(
      sensorRotationDeg: frame.rotationDegrees,
      mirrored: frame.mirrored,
      sourceSize: FrameSize(imgW, imgH),
      crop: CropTransform(topFraction: frame.cropTopFraction),
    );
    for (final t in context?.yoloTracks ?? _lastYoloTracks) {
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

  bool _yoloMatchesFrame({
    required DateTime at,
    required int width,
    required int height,
    required int rotationDegrees,
    required bool mirrored,
  }) {
    final ageUs =
        at.microsecondsSinceEpoch - _lastYoloAt.microsecondsSinceEpoch;
    return _lastYoloAt.millisecondsSinceEpoch != 0 &&
        ageUs >= 0 &&
        ageUs <= CameraSession.maxImageDepthDelta.inMicroseconds &&
        _yoloImageWidth == width &&
        (_yoloImageHeight == null || _yoloImageHeight == height) &&
        (_yoloRotationDegrees == null ||
            _yoloRotationDegrees == rotationDegrees) &&
        (_yoloMirrored == null || _yoloMirrored == mirrored);
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

  @visibleForTesting
  SemanticMatch? debugAttachSemanticToTrack({
    required GenericObstacleTrack track,
    required int imageWidth,
    required int imageHeight,
    required DepthFrame frame,
    required DateTime now,
  }) => _attachSemanticToTrack(
    track: track,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    frame: frame,
    now: now,
  );

  List<_YoloTrackSample> _lastYoloTracks = const [];

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

class _DepthMeasurement {
  final int generation;
  int frameId = 0;
  int providerUs = 0;
  bool providerCalled = false;
  bool accepted = false;
  String? rejectionReason;
  _DepthMeasurement(this.generation);
}

class _YoloTrackSample {
  final int id;
  final String label;
  final String dist;
  final double avgConf;
  final double x1, y1, x2, y2;

  _YoloTrackSample(Track track)
    : id = track.id,
      label = track.label,
      dist = track.dist,
      avgConf = track.avgConf,
      x1 = track.x1,
      y1 = track.y1,
      x2 = track.x2,
      y2 = track.y2;
}

class _DepthFrameContext {
  final List<_YoloTrackSample> yoloTracks;
  final DateTime yoloAt;
  final Map<HazardZone, double> yoloHazardConf;
  final double pitch, roll;
  final bool rollExcessive, winterMode;
  final MotionState motion;

  const _DepthFrameContext({
    required this.yoloTracks,
    required this.yoloAt,
    required this.yoloHazardConf,
    required this.pitch,
    required this.roll,
    required this.rollExcessive,
    required this.motion,
    required this.winterMode,
  });
}
