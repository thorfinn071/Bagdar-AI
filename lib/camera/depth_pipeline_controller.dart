import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../services/fall_detector.dart' show MotionState;
import '../services/model_service.dart';
import '../services/orientation_service.dart';
import '../tracker/track.dart';
import '../tracker/tracker.dart' show isVehicle;
import '../utils/depth_hazard.dart';
import '../utils/fusion_engine.dart';
import '../viewmodels/camera_view_model.dart';

class DepthHazardAlert {
  final DepthHazard hazard;
  final bool isCritical;

  const DepthHazardAlert({required this.hazard, required this.isCritical});
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

  /// MiDaS / hardware confidence has been below the rejection floor for
  /// several consecutive frames — depth-based hazards are not running.
  lowConfidence,

  /// RANSAC plane-fit has failed for several consecutive frames — only
  /// plane-independent hazards (foot zone, stairs, near-field, glass)
  /// are running; pothole / curb / lowCurb detection is OFF.
  planeFitFailed,
}

class DepthPipelineController {
  final CameraViewModel vm;
  final ModelService models;

  DateTime _lastRunAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration interval = const Duration(milliseconds: 800);
  bool _providerReady = false;
  bool _inFlight = false;

  
  
  
  
  
  
  
  
  
  
  
  final FusionEngine _fusion = FusionEngine();
  final Map<HazardZone, double> _yoloHazardConfByZone = {};

  
  
  
  
  
  
  
  
  
  
  
  
  static const int _kDegradedFramesToAnnounce = 3;

  int _consecutiveLowConfidenceFrames = 0;
  int _consecutivePlaneFitFailures = 0;
  DepthPipelineStatus _status = DepthPipelineStatus.ok;

  /// Called once per status transition so the host (camera_screen) can
  /// announce a single TTS message + earcon when depth health changes.
  void Function(DepthPipelineStatus from, DepthPipelineStatus to)?
      onStatusChanged;

  void Function(String reason, double confidence)? onFrameRejected;

  DepthPipelineStatus get status => _status;

  DepthPipelineController({required this.vm, required this.models});

  bool get providerReady => _providerReady;

  void setProviderReady(bool value) {
    _providerReady = value;
  }

  bool shouldRun(DateTime now) =>
      _providerReady &&
      !_inFlight &&
      now.difference(_lastRunAt) >= interval;

  
  
  
  
  
  
  
  
  
  void updateYoloTracks(List<Track> tracks, {required int imgW}) {
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
      final zoneIdx = (t.cx / zoneWidth)
          .floor()
          .clamp(0, HazardZone.values.length - 1);
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
    if (_inFlight) return const <DepthHazardAlert>[];
    _inFlight = true;
    _lastRunAt = now;
    final provider = models.depthProvider;
    if (provider == null || !provider.isReady) {
      _inFlight = false;
      return const <DepthHazardAlert>[];
    }
    
    
    
    if (provider.lastConfidenceScore > 0 &&
        provider.lastConfidenceScore < 0.4) {
      _inFlight = false;
      _consecutiveLowConfidenceFrames++;
      _consecutivePlaneFitFailures = 0;
      onFrameRejected?.call(
        'low_confidence',
        provider.lastConfidenceScore,
      );
      if (_consecutiveLowConfidenceFrames >= _kDegradedFramesToAnnounce) {
        _setStatus(DepthPipelineStatus.lowConfidence);
      }
      return const <DepthHazardAlert>[];
    }
    
    
    _consecutiveLowConfidenceFrames = 0;
    try {
      final cropTopFrac = OrientationService.cropTopFracForPitch(
        vm.orientation.pitch,
      );
      final userStationary =
          vm.fallDetector.motionState == MotionState.stationary;
      final hazards = await provider.analyze(
        image,
        cropTopFrac: cropTopFrac,
        userStationary: userStationary,
        weatherDegraded: vm.weatherGate.degraded,
      );
      _inFlight = false;

      
      
      
      
      
      if (provider.lastPlaneFitOk) {
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

      if (hazards.isEmpty) return const <DepthHazardAlert>[];
      final rollExcessive = vm.orientation.isRollExcessive;
      final filteredHazards = hazards.where((h) {
        if (h.type == DepthHazardType.deadZone && h.midasScore < 0.65) return false;
        if (h.type == DepthHazardType.slippery && h.midasScore < 0.55) return false;
        return true;
      });
      final out = <DepthHazardAlert>[];
      for (final h in filteredHazards) {
        bool isCritical = _isHazardCritical(
          h,
          rollExcessive: rollExcessive,
          userStationary: userStationary,
        );

        
        
        
        
        if (!isCritical && !rollExcessive) {
          final yoloConf = _yoloHazardConfByZone[h.zone] ?? 0.0;
          final fused = _fusion.evaluate(
            hazard: h,
            yoloHazardConf: yoloConf,
            now: now,
          );
          if (fused != null && fused.level == AlertLevel.critical) {
            isCritical = true;
          }
        }

        out.add(DepthHazardAlert(hazard: h, isCritical: isCritical));
      }
      return out;
    } catch (e) {
      _inFlight = false;
      debugPrint('Depth analysis error: $e');
      return const <DepthHazardAlert>[];
    }
  }

  void resetFusion() {
    _fusion.reset();
    _yoloHazardConfByZone.clear();
  }

  
  
  
  
  
  
  
  
  
  
  
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
  }) =>
      _isHazardCritical(
        hazard,
        rollExcessive: rollExcessive,
        userStationary: userStationary,
      );

  static bool _isHazardCritical(
    DepthHazard hazard, {
    required bool rollExcessive,
    bool userStationary = false,
  }) {
    if (rollExcessive) return false;

    switch (hazard.type) {
      case DepthHazardType.stairsDown:
      case DepthHazardType.overhead:
        return true;

      case DepthHazardType.pothole:
      case DepthHazardType.stepDown:
      case DepthHazardType.glassDoor:
        return _isCenterZone(hazard.zone) &&
            hazard.midasScore >= _kCriticalCenterScore;

      case DepthHazardType.nearFieldIntrusion:
        return hazard.midasScore >= _kCriticalNearFieldScore;

      case DepthHazardType.slippery:
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
