import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../services/fall_detector.dart' show MotionState;
import '../services/model_service.dart';
import '../services/orientation_service.dart';
import '../utils/depth_hazard.dart';
import '../viewmodels/camera_view_model.dart';

class DepthHazardAlert {
  final DepthHazard hazard;
  final bool isCritical;

  const DepthHazardAlert({required this.hazard, required this.isCritical});
}

class DepthPipelineController {
  final CameraViewModel vm;
  final ModelService models;

  DateTime _lastRunAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration interval = const Duration(milliseconds: 400);
  bool _providerReady = false;

  DepthPipelineController({required this.vm, required this.models});

  bool get providerReady => _providerReady;

  void setProviderReady(bool value) {
    _providerReady = value;
  }

  bool shouldRun(DateTime now) =>
      _providerReady && now.difference(_lastRunAt) >= interval;

  Future<List<DepthHazardAlert>> analyze(
    CameraImage image,
    DateTime now,
  ) async {
    _lastRunAt = now;
    final provider = models.depthProvider;
    if (provider == null || !provider.isReady) {
      return const <DepthHazardAlert>[];
    }
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
      if (hazards.isEmpty) return const <DepthHazardAlert>[];
      final rollExcessive = vm.orientation.isRollExcessive;
      return [
        for (final h in hazards)
          DepthHazardAlert(
            hazard: h,
            isCritical: (h.type == DepthHazardType.stairsDown ||
                    h.type == DepthHazardType.overhead) &&
                !rollExcessive,
          ),
      ];
    } catch (e) {
      debugPrint('Depth analysis error: $e');
      return const <DepthHazardAlert>[];
    }
  }

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
}
