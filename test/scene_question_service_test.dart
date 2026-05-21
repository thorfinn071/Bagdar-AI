import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/scene_question_service.dart';
import 'package:bagdar/utils/performance_throttler.dart';
import 'package:bagdar/services/thermal_monitor.dart';

void main() {
  group('SceneQuestionService', () {
    late SceneQuestionService service;

    setUp(() {
      service = SceneQuestionService.instance;
      service.resetForTesting();
    });

    test('initial state is idle', () {
      expect(service.state, VlmState.idle);
      expect(service.isModelLoaded, false);
    });

    test('canRun requires charging', () {
      expect(
        service.canRun(
          charging: false,
          batteryPct: 80,
          thermal: ThermalSeverity.normal,
          memory: MemoryPressureLevel.normal,
        ),
        false,
      );
    });

    test('canRun requires battery > 40', () {
      expect(
        service.canRun(
          charging: true,
          batteryPct: 30,
          thermal: ThermalSeverity.normal,
          memory: MemoryPressureLevel.normal,
        ),
        false,
      );
    });

    test('canRun rejects hot thermal', () {
      expect(
        service.canRun(
          charging: true,
          batteryPct: 80,
          thermal: ThermalSeverity.hot,
          memory: MemoryPressureLevel.normal,
        ),
        false,
      );
    });

    test('canRun rejects critical memory', () {
      expect(
        service.canRun(
          charging: true,
          batteryPct: 80,
          thermal: ThermalSeverity.normal,
          memory: MemoryPressureLevel.critical,
        ),
        false,
      );
    });

    test('canRun passes with all gates', () {
      expect(
        service.canRun(
          charging: true,
          batteryPct: 80,
          thermal: ThermalSeverity.normal,
          memory: MemoryPressureLevel.normal,
        ),
        true,
      );
    });

    test('canRun passes with warm thermal', () {
      expect(
        service.canRun(
          charging: true,
          batteryPct: 50,
          thermal: ThermalSeverity.warm,
          memory: MemoryPressureLevel.low,
        ),
        true,
      );
    });

    test('resetForTesting resets to idle', () {
      service.resetForTesting();
      expect(service.state, VlmState.idle);
      expect(service.isModelLoaded, false);
    });
  });
}
