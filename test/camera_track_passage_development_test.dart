import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'camera_visible_passage_replay_test.dart'
    show runVisiblePassageBenchmark;
import 'harness/camera_visible_passage_fixture.dart';

void main() {
  test(
    'predeclared association development scenes only',
    () {
      runVisiblePassageBenchmark(
        inputFixture: VisibleFixture(
          root: 'test/fixtures/spatial_safety/camera-track-passage-v1',
        ),
        reportPath: 'scratch/camera-track-development.json',
        developmentOnly: true,
        associationExperiment: true,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'previously inspected recovery cases are diagnostic regressions',
    () {
      final report = runVisiblePassageBenchmark(
        inputFixture: VisibleFixture(
          root:
              'test/fixtures/spatial_safety/camera-visible-passage-recovery-v1',
        ),
        associationExperiment: true,
      );
      // This set was inspected in the previous stage; never call it a holdout.
      final json = const JsonEncoder.withIndent('  ').convert(report);
      File(
        'scratch/camera-track-known-regressions.json',
      ).writeAsStringSync('$json\n');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
