import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/spatial_replay_fixture.dart';
import 'harness/spatial_scenario_runner.dart';

const _predictionsPath = 'test/fixtures/model_predictions/predictions.json';
const _replayRoot = 'test/fixtures/model_predictions/replay';

void main() {
  final root =
      jsonDecode(File(_predictionsPath).readAsStringSync())
          as Map<String, dynamic>;

  test('fixture contains real finite outputs from every pinned candidate', () {
    expect(root['schemaVersion'], 1);
    expect(root['promotionAllowed'], isFalse);
    final models = root['models'] as List<dynamic>;
    expect(models, hasLength(3));
    for (final rawModel in models) {
      final model = rawModel as Map<String, dynamic>;
      expect(model['artifactSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(model['licenseStatus'], startsWith('blocked_'));
      final predictions = model['predictions'] as List<dynamic>;
      expect(predictions, hasLength(2));
      for (final rawPrediction in predictions) {
        final prediction = rawPrediction as Map<String, dynamic>;
        expect(prediction['sourceSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        final detections = prediction['detections'] as List<dynamic>;
        expect(
          detections,
          isNotEmpty,
          reason: prediction['sourceId'] as String,
        );
        for (final rawDetection in detections) {
          final detection = rawDetection as Map<String, dynamic>;
          expect((detection['score'] as num).toDouble().isFinite, isTrue);
          expect(
            detection['sector'],
            isIn(<String>['left', 'forward', 'right']),
          );
        }
      }
    }
  });

  test('real candidate predictions use the canonical spatial runner', () {
    final models = root['models'] as List<dynamic>;
    for (final rawModel in models) {
      final model = rawModel as Map<String, dynamic>;
      final modelId = model['modelId'] as String;
      final slug = modelId
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final fixture = SpatialReplayFixture.load(
        '$_replayRoot/$slug/manifest.json',
      );
      final report = SpatialScenarioRunner(
        fixture: fixture,
        mode: SpatialRunMode.releaseCandidate,
      ).runAll();
      expect(report.passed, isTrue, reason: modelId);
      expect(report.metrics.unsafeGuidanceCount, 0, reason: modelId);
      expect(report.metrics.guidanceIntoUnknownCount, 0, reason: modelId);
      expect(report.metrics.staleActionEmissionCount, 0, reason: modelId);
    }
  });
}
