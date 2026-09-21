import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/spatial_replay_fixture.dart';
import 'harness/spatial_scenario_runner.dart';

const _manifestPath = 'test/fixtures/spatial_safety/manifest.json';

void main() {
  group('spatial replay manifest', () {
    test('loads versioned corpus and verifies every fixture hash', () {
      final fixture = SpatialReplayFixture.load(_manifestPath);

      expect(fixture.manifest.schemaVersion, spatialReplaySchemaVersion);
      expect(fixture.manifest.seed, 20260919);
      expect(fixture.manifest.scenes, hasLength(9));
      for (final scene in fixture.manifest.scenes) {
        expect(fixture.validateSceneFiles(scene), isEmpty, reason: scene.id);
      }
    });

    test('rejects paths that could escape the corpus root', () {
      final json = _manifestJson();
      final first =
          (json['scenes']! as List<dynamic>).first as Map<String, dynamic>;
      first['frames'] = '../outside.jsonl';

      expect(
        () => SpatialReplayManifest.fromJson(json, manifestPath: _manifestPath),
        throwsFormatException,
      );
    });

    test('rejects frame identity that differs from the model contract', () {
      final json = _manifestJson();
      final contract = json['modelContract']! as Map<String, dynamic>;
      contract['modelHash'] = List<String>.filled(64, '1').join();
      final report = _run(json, SpatialRunMode.developer);

      expect(report.passed, isFalse);
      expect(
        report.scenarios.every(
          (scenario) => scenario.status == SpatialScenarioStatus.fail,
        ),
        isTrue,
      );
      expect(
        report.scenarios.first.violations.single,
        contains('model/preprocess identity mismatch'),
      );
    });
  });

  group('spatial scenario runner', () {
    test(
      'procedural and integrity-pinned Blender corpora pass RC',
      () {
        final fixture = SpatialReplayFixture.load(_manifestPath);
        final developer = SpatialScenarioRunner(
          fixture: fixture,
          mode: SpatialRunMode.developer,
        ).runAll();
        final rc = SpatialScenarioRunner(
          fixture: fixture,
          mode: SpatialRunMode.releaseCandidate,
        ).runAll();

        expect(developer.passed, isTrue);
        expect(rc.passed, isTrue);
        expect(rc.blockingReasons, isEmpty);
        expect(
          developer.scenarios.every(
            (scenario) => scenario.status == SpatialScenarioStatus.pass,
          ),
          isTrue,
        );
        expect(developer.metrics.unsafeGuidanceCount, 0);
        expect(developer.metrics.guidanceIntoUnknownCount, 0);
        expect(developer.metrics.staleActionEmissionCount, 0);
        expect(developer.metrics.expectedActionMismatchCount, 0);
        expect(developer.metrics.healthMismatchCount, 0);
        expect(developer.metrics.alertMismatchCount, 0);
        expect(developer.missingExternalCorpora, isEmpty);
        expect(developer.missingPrivateCorpora, ['controlled-camera-v1']);
        expect(developer.invalidExternalCorpora, isEmpty);
      },
    );

    test('available external corpus fails closed on manifest hash drift', () {
      final json = _manifestJson();
      final external = (json['externalCorpora']! as List<dynamic>).first
          as Map<String, dynamic>;
      external['manifestSha256'] = List<String>.filled(64, '0').join();

      final report = _run(json, SpatialRunMode.releaseCandidate);

      expect(report.passed, isFalse);
      expect(
        report.blockingReasons.single,
        contains('external_manifest_hash_mismatch'),
      );
    });

    test('report is deterministic and independent of manifest scene order', () {
      final normalJson = _manifestJson();
      final reversedJson = _manifestJson();
      final reversedScenes = reversedJson['scenes']! as List<dynamic>;
      reversedJson['scenes'] = reversedScenes.reversed.toList();

      final normal = _run(normalJson, SpatialRunMode.releaseCandidate);
      final reversed = _run(reversedJson, SpatialRunMode.releaseCandidate);

      expect(jsonEncode(reversed.toJson()), jsonEncode(normal.toJson()));
    });

    test('partial required coverage is non-blocking in dev and fails RC', () {
      final json = _manifestJson();
      final first =
          (json['scenes']! as List<dynamic>).first as Map<String, dynamic>;
      first['coverage'] = 'partial';

      final developer = _run(json, SpatialRunMode.developer);
      final rc = _run(json, SpatialRunMode.releaseCandidate);

      expect(developer.passed, isTrue);
      expect(
        developer.scenarios
            .singleWhere((scenario) => scenario.sceneId == first['id'])
            .status,
        SpatialScenarioStatus.partial,
      );
      expect(rc.passed, isFalse);
      expect(rc.blockingReasons, contains('${first['id']}:partial'));
    });

    test('missing required fixture is explicit and fails RC', () {
      final json = _manifestJson();
      final first =
          (json['scenes']! as List<dynamic>).first as Map<String, dynamic>;
      first['frames'] = 'scenes/missing/frames.jsonl';

      final developer = _run(json, SpatialRunMode.developer);
      final rc = _run(json, SpatialRunMode.releaseCandidate);

      expect(developer.passed, isTrue);
      expect(
        developer.scenarios
            .singleWhere((scenario) => scenario.sceneId == first['id'])
            .status,
        SpatialScenarioStatus.missing,
      );
      expect(rc.passed, isFalse);
      expect(rc.blockingReasons, contains('${first['id']}:missing'));
    });

    test('timeline checks expected and forbidden actions for every frame', () {
      final fixture = SpatialReplayFixture.load(_manifestPath);
      final report = SpatialScenarioRunner(
        fixture: fixture,
        mode: SpatialRunMode.releaseCandidate,
      ).runAll();
      final temporal = report.scenarios.singleWhere(
        (scenario) => scenario.sceneId == 'hazard-emerges-during-guidance',
      );

      expect(temporal.frames.map((frame) => frame.action), [
        'continueForward',
        'stopNow',
      ]);
      expect(temporal.frames.map((frame) => frame.alertEvent), [
        'suppressed',
        'emitted',
      ]);
      expect(temporal.frames.expand((frame) => frame.violations), isEmpty);
    });

    test('critical action preempts informational feedback on the timeline', () {
      final fixture = SpatialReplayFixture.load(_manifestPath);
      final report = SpatialScenarioRunner(
        fixture: fixture,
        mode: SpatialRunMode.releaseCandidate,
      ).runAll();
      final preemption = report.scenarios.singleWhere(
        (scenario) => scenario.sceneId == 'critical-during-information',
      );

      expect(preemption.frames.single.action, 'stopNow');
      expect(preemption.frames.single.alertEvent, 'emitted');
      expect(preemption.frames.single.interruptCurrent, isTrue);
    });

    test('shadow correction requires three stable scene revisions', () {
      final fixture = SpatialReplayFixture.load(_manifestPath);
      final report = SpatialScenarioRunner(
        fixture: fixture,
        mode: SpatialRunMode.releaseCandidate,
      ).runAll();
      final hysteresis = report.scenarios.singleWhere(
        (scenario) => scenario.sceneId == 'stable-left-shadow-correction',
      );

      expect(hysteresis.frames.map((frame) => frame.shadowDirection), [
        'none',
        'none',
        'left',
      ]);
      expect(hysteresis.frames.expand((frame) => frame.violations), isEmpty);
    });
  });
}

Map<String, dynamic> _manifestJson() =>
    jsonDecode(File(_manifestPath).readAsStringSync()) as Map<String, dynamic>;

SpatialReplayReport _run(Map<String, dynamic> json, SpatialRunMode mode) {
  final manifest = SpatialReplayManifest.fromJson(
    json,
    manifestPath: _manifestPath,
  );
  return SpatialScenarioRunner(
    fixture: SpatialReplayFixture(manifest),
    mode: mode,
  ).runAll();
}
