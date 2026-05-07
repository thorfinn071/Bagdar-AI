import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/models/app_mode.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/models/nav_models.dart';
import 'package:bagdar/services/traffic_light_analyzer.dart';
import 'package:bagdar/services/scene_narrator.dart';

void main() {
  setUp(() {
    AppStrings.setLanguage(AppLanguage.en);
  });

  group('SceneNarrator', () {
    late SceneNarrator narrator;

    setUp(() {
      narrator = SceneNarrator();
    });

    test('narrates empty scene', () {
      final snapshot = SceneSnapshot(
        objects: [],
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, 'Nothing detected. Path appears clear.');
    });

    test('narrates single object', () {
      final snapshot = SceneSnapshot(
        objects: [
          SceneObject(
            label: 'person',
            direction: 'ahead',
            distance: 'close',
            distM: 2.5,
            approaching: false,
            threatScore: 1.0,
          ),
        ],
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('I see one object.'));
      expect(result, contains('person ahead, approximately 2.5.'));
    });

    test('narrates multiple objects sorted by threat', () {
      final snapshot = SceneSnapshot(
        objects: [
          SceneObject(
            label: 'dog',
            direction: 'at 9 o\'clock',
            distance: 'far',
            distM: 10.0,
            approaching: false,
            threatScore: 0.5,
          ),
          SceneObject(
            label: 'car',
            direction: 'ahead',
            distance: 'close',
            distM: 3.0,
            approaching: true,
            threatScore: 2.0,
          ),
        ],
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('I see 2 objects.'));
      
      final carIdx = result.indexOf('car');
      final dogIdx = result.indexOf('dog');
      expect(carIdx < dogIdx, isTrue);
      expect(result, contains('car ahead, approximately 3, approaching.'));
    });

    test('respects max objects cap', () {
      final objects = List.generate(
        10,
        (i) => SceneObject(
          label: 'person',
          direction: 'ahead',
          distance: 'far',
          distM: 10.0,
          approaching: false,
          threatScore: 1.0,
        ),
      );

      final snapshot = SceneSnapshot(
        objects: objects,
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      
      final count = '\n'.allMatches(result).length;
      expect(count, lessThanOrEqualTo(7)); 
    });

    test('narrates hazards', () {
      final snapshot = SceneSnapshot(
        objects: [],
        hazards: [
          DepthHazard(
            midasScore: 0.8,
            type: DepthHazardType.stepDown,
            zone: HazardZone.center,
            coverage: 0.5,
          ),
        ],
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('On the ground:'));
      expect(result, contains('Step down forward.'));
    });

    test('narrates traffic light', () {
      final snapshot = SceneSnapshot(
        objects: [],
        hazards: [],
        trafficLight: TrafficLightColor.red,
        trafficLightKind: TrafficLightKind.vehicle,
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('Traffic light red.'));
    });

    test('narrates OCR text', () {
      final snapshot = SceneSnapshot(
        objects: [],
        hazards: [],
        ocrText: 'Pharmacy',
        isIndoor: false,
        mode: AppMode.street,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('Sign reads: Pharmacy.'));
    });

    test('respects verbosity settings', () {
      final snapshot = SceneSnapshot(
        objects: [
          SceneObject(
            label: 'person',
            direction: 'ahead',
            distance: 'close',
            distM: 2.5,
            approaching: false,
            threatScore: 1.0,
          ),
        ],
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
      );

      final minimal = narrator.narrate(snapshot, Verbosity.minimal);
      expect(minimal, isNot(contains('approximately')));
      expect(minimal, contains('person ahead.'));

      final detailed = narrator.narrate(snapshot, Verbosity.detailed);
      expect(detailed, contains('person ahead, approximately 2.5.'));
    });

    test('filters left objects correctly', () {
      final snapshot = SceneSnapshot(
        objects: [
          SceneObject(
            label: 'person',
            direction: 'at 9 o\'clock',
            distance: 'close',
            threatScore: 1.0,
            approaching: false,
          ),
          SceneObject(
            label: 'car',
            direction: 'at 3 o\'clock',
            distance: 'close',
            threatScore: 1.0,
            approaching: false,
          ),
        ],
        hazards: [],
        isIndoor: false,
        mode: AppMode.street,
        filter: SceneFilter.left,
      );

      final result = narrator.narrate(snapshot, Verbosity.normal);
      expect(result, contains('On the left:'));
      expect(result, contains('person'));
      expect(result, isNot(contains('car')));
    });
  });
}
