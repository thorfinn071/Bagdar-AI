import '../models/strings.dart';
import '../models/a11y_prefs.dart';
import '../models/app_mode.dart';
import '../utils/depth_hazard.dart';
import '../models/nav_models.dart';
import 'traffic_light_analyzer.dart';

enum SceneFilter { all, left, right, forward }

class SceneObject {
  final String label;
  final String direction;
  final String distance;
  final double? distM;
  final bool approaching;
  final double threatScore;

  const SceneObject({
    required this.label,
    required this.direction,
    required this.distance,
    this.distM,
    required this.approaching,
    required this.threatScore,
  });
}

class SceneSnapshot {
  final List<SceneObject> objects;
  final List<DepthHazard> hazards;
  final TrafficLightColor? trafficLight;
  final TrafficLightKind? trafficLightKind;
  final String? ocrText;
  final bool isIndoor;
  final AppMode mode;
  final SceneFilter filter;

  const SceneSnapshot({
    required this.objects,
    required this.hazards,
    this.trafficLight,
    this.trafficLightKind,
    this.ocrText,
    required this.isIndoor,
    required this.mode,
    this.filter = SceneFilter.all,
  });
}

class SceneNarrator {
  static const int _maxObjects = 5;

  String narrate(SceneSnapshot snapshot, Verbosity verbosity) {
    final buffer = StringBuffer();

    var objects = _filterObjects(snapshot.objects, snapshot.filter);
    objects.sort((a, b) => b.threatScore.compareTo(a.threatScore));
    if (objects.length > _maxObjects) {
      objects = objects.take(_maxObjects).toList();
    }

    final hazards = _filterHazards(snapshot.hazards, snapshot.filter);

    if (objects.isEmpty &&
        hazards.isEmpty &&
        (snapshot.trafficLight == null || snapshot.trafficLight == TrafficLightColor.unknown) &&
        (snapshot.ocrText == null || snapshot.ocrText!.isEmpty)) {
      return S.get('scene_see_none');
    }

    if (snapshot.filter != SceneFilter.all) {
      if (snapshot.filter == SceneFilter.left) {
        buffer.writeln(S.get('scene_left_only'));
      } else if (snapshot.filter == SceneFilter.right) {
        buffer.writeln(S.get('scene_right_only'));
      } else if (snapshot.filter == SceneFilter.forward) {
        buffer.writeln(S.get('scene_ahead_only'));
      }
    } else {
      if (objects.length == 1) {
        buffer.writeln(S.get('scene_see_one'));
      } else if (objects.length > 1) {
        buffer.writeln(
            S.get('scene_see_count').replaceAll('{count}', objects.length.toString()));
      }
    }

    for (final obj in objects) {
      final entry = S.get('scene_object_entry')
          .replaceAll('{label}', S.label(obj.label))
          .replaceAll('{direction}', obj.direction);
      buffer.write(entry);

      if (verbosity != Verbosity.minimal) {
        if (obj.distM != null && obj.distM! > 0) {
          String distStr = obj.distM!.toStringAsFixed(1);
          if (distStr.endsWith('.0')) {
            distStr = distStr.substring(0, distStr.length - 2);
          }
          buffer.write(S.get('scene_object_dist').replaceAll('{dist}', distStr));
        } else if (verbosity == Verbosity.detailed) {
          buffer.write(', ${S.get(obj.distance)}');
        }
      }

      if (obj.approaching) {
        buffer.write(S.get('scene_object_approaching'));
      }
      buffer.writeln('.');
    }

    if (hazards.isNotEmpty) {
      buffer.writeln(S.get('scene_hazard_intro'));
      final uniqueHazards = <String>{};
      for (final h in hazards) {
        final loc = _zoneToDir(h.zone);
        final name = S.get(_hazardTypeToKey(h.type));
        uniqueHazards.add('$name $loc.');
      }
      for (final u in uniqueHazards) {
        buffer.writeln(u);
      }
    }

    if (snapshot.trafficLight != null &&
        snapshot.trafficLight != TrafficLightColor.unknown) {
      final colorStr = _trafficLightColorStr(snapshot.trafficLight!);
      buffer.writeln(
          S.get('scene_traffic_light').replaceAll('{color}', colorStr));
    }

    if (snapshot.ocrText != null && snapshot.ocrText!.isNotEmpty) {
      buffer.writeln(
          S.get('scene_ocr_read').replaceAll('{text}', snapshot.ocrText!));
    }

    return buffer.toString().trim();
  }

  List<SceneObject> _filterObjects(
      List<SceneObject> objects, SceneFilter filter) {
    if (filter == SceneFilter.all) return List.of(objects);
    return objects.where((o) {
      if (filter == SceneFilter.left) {
        return o.direction == S.dir('9') ||
            o.direction == S.dir('10') ||
            o.direction == S.dir('11');
      }
      if (filter == SceneFilter.right) {
        return o.direction == S.dir('1') ||
            o.direction == S.dir('2') ||
            o.direction == S.dir('3');
      }
      return o.direction == S.dir('forward');
    }).toList();
  }

  List<DepthHazard> _filterHazards(
      List<DepthHazard> hazards, SceneFilter filter) {
    if (filter == SceneFilter.all) return List.of(hazards);
    return hazards.where((h) {
      if (filter == SceneFilter.left) {
        return h.zone == HazardZone.left || h.zone == HazardZone.centerLeft;
      }
      if (filter == SceneFilter.right) {
        return h.zone == HazardZone.right || h.zone == HazardZone.centerRight;
      }
      return h.zone == HazardZone.center;
    }).toList();
  }

  String _zoneToDir(HazardZone zone) {
    switch (zone) {
      case HazardZone.left:
      case HazardZone.centerLeft:
        return S.get('left');
      case HazardZone.center:
        return S.get('forward_loc');
      case HazardZone.right:
      case HazardZone.centerRight:
        return S.get('right');
    }
  }

  String _hazardTypeToKey(DepthHazardType type) {
    switch (type) {
      case DepthHazardType.deadZone:
        return 'hazard_dead_zone';
      case DepthHazardType.stepDown:
        return 'hazard_step_down';
      case DepthHazardType.stepUp:
        return 'hazard_step_up';
      case DepthHazardType.pothole:
        return 'hazard_pothole';
      case DepthHazardType.curb:
        return 'hazard_curb';
      case DepthHazardType.lowCurb:
        return 'hazard_low_curb';
      case DepthHazardType.stairsDown:
        return 'hazard_stairs_down';
      case DepthHazardType.overhead:
        return 'hazard_overhead';
      case DepthHazardType.glassDoor:
        return 'hazard_glass_door';
      case DepthHazardType.slippery:
        return 'hazard_slippery';
      case DepthHazardType.nearFieldIntrusion:
        return 'hazard_near_field';
      case DepthHazardType.unknown:
      case DepthHazardType.escalatorRiding:
        return 'hazard_unknown';
    }
  }

  String _trafficLightColorStr(TrafficLightColor color) {
    switch (color) {
      case TrafficLightColor.red:
        return S.get('scene_color_red');
      case TrafficLightColor.yellow:
        return S.get('scene_color_yellow');
      case TrafficLightColor.green:
        return S.get('scene_color_green');
      case TrafficLightColor.unknown:
        return '';
    }
  }
}
