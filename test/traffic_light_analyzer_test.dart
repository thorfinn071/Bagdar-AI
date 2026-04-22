import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/nav_models.dart';
import 'package:bagdar/services/traffic_light_analyzer.dart';

void main() {
  group('TrafficLightAnalyzer dominant color selection', () {
    test('clear red winner is selected', () {
      expect(
        TrafficLightAnalyzer.pickDominantColor(
          redScore: 0.31,
          yellowScore: 0.14,
          greenScore: 0.10,
        ),
        TrafficLightColor.red,
      );
    });

    test('close scores stay unknown', () {
      expect(
        TrafficLightAnalyzer.pickDominantColor(
          redScore: 0.18,
          yellowScore: 0.17,
          greenScore: 0.09,
        ),
        TrafficLightColor.unknown,
      );
    });

    test('shape penalty tightens the boundary for wide boxes', () {
      final penalty = TrafficLightAnalyzer.shapePenaltyForAspectRatio(2.2);

      expect(
        TrafficLightAnalyzer.pickDominantColor(
          redScore: 0.20,
          yellowScore: 0.12,
          greenScore: 0.10,
          minScore: 0.15 + penalty * 0.5,
          dominanceMargin: 0.08 + penalty * 0.5,
        ),
        TrafficLightColor.unknown,
      );
    });

    test('compact boxes do not receive a shape penalty', () {
      expect(TrafficLightAnalyzer.shapePenaltyForAspectRatio(1.0), 0.0);
    });

    test('high confidence reduces confirmation frames', () {
      expect(
        TrafficLightAnalyzer.stableFramesRequiredForBox(
          bboxWidth: 50,
          bboxHeight: 60,
          confidence: 0.85,
        ),
        2,
      );
    });

    test('low confidence keeps confirmation conservative', () {
      expect(
        TrafficLightAnalyzer.stableFramesRequiredForBox(
          bboxWidth: 50,
          bboxHeight: 60,
          confidence: 0.2,
        ),
        4,
      );
    });
  });

  group('TrafficLightAnalyzer.classifyKindByAspect', () {
    test('2-section pedestrian ratio is classified as pedestrian', () {
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(30, 60),
        TrafficLightKind.pedestrian,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(40, 90),
        TrafficLightKind.pedestrian,
      );
    });

    test('3-section vehicle ratio is classified as vehicle', () {
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(30, 100),
        TrafficLightKind.vehicle,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(25, 85),
        TrafficLightKind.vehicle,
      );
    });

    test('boxy or horizontal shapes are unknown', () {
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(50, 50),
        TrafficLightKind.unknown,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(80, 40),
        TrafficLightKind.unknown,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(20, 100),
        TrafficLightKind.unknown,
      );
    });

    test('degenerate inputs return unknown without crashing', () {
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(0, 60),
        TrafficLightKind.unknown,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(30, 0),
        TrafficLightKind.unknown,
      );
      expect(
        TrafficLightAnalyzer.classifyKindByAspect(-5, -5),
        TrafficLightKind.unknown,
      );
    });
  });
}
