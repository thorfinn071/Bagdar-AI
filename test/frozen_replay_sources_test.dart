import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/profile_camera_processing.dart' as profile;
import 'camera_visible_passage_replay_test.dart'
    show runVisiblePassageBenchmark;
import 'harness/camera_metric_motion_benchmark.dart'
    show runMetricMotionBenchmark;
import 'harness/camera_scale_motion_benchmark.dart'
    show runScaleMotionBenchmark;
import 'harness/camera_temporal_passage_benchmark.dart'
    show runTemporalPassageBenchmark;
import 'harness/frozen_replay_sources.dart';

void main() {
  late Directory root;
  const source = 'lib/algorithm.dart';
  const original = 'const value = 1;';
  final digest = sha256.convert(original.codeUnits).toString();
  File file(String path) => File.fromUri(root.uri.resolve(path));
  void write(String path, String value) {
    file(path).parent.createSync(recursive: true);
    file(path).writeAsStringSync(value);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('bagdar-frozen-replay-');
    write(source, original);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('original holdout accepts the current frozen implementation', () {
    verifyFrozenReplaySources({source: digest}, root: root);
  });

  test('archived sources require explicit known-corpus opt-in', () {
    write('$historicalReplaySourceRoot/$source.snapshot', original);
    write(source, 'const value = 2;');
    expect(
      () => verifyFrozenReplaySources({source: digest}, root: root),
      throwsStateError,
    );
    verifyFrozenReplaySources(
      {source: digest},
      root: root,
      allowHistoricalSources: true,
    );
  });

  test('a changed historical snapshot is rejected', () {
    write('$historicalReplaySourceRoot/$source.snapshot', 'changed archive');
    write(source, 'changed current');
    expect(
      () => verifyFrozenReplaySources(
        {source: digest},
        root: root,
        allowHistoricalSources: true,
      ),
      throwsStateError,
    );
  });

  test(
    'models and corpus data must match live files even in regression mode',
    () {
      const data = 'fixtures/input.bin';
      write(data, 'changed data');
      write('$historicalReplaySourceRoot/$data.snapshot', original);
      expect(
        () => verifyFrozenReplaySources(
          {data: digest},
          root: root,
          allowHistoricalSources: true,
        ),
        throwsStateError,
      );
    },
  );

  test('missing snapshots do not authorize source drift', () {
    write(source, 'changed current');
    expect(
      () => verifyFrozenReplaySources(
        {source: digest},
        root: root,
        allowHistoricalSources: true,
      ),
      throwsStateError,
    );
  });

  test('empty source recipes are rejected', () {
    expect(
      () => verifyFrozenReplaySources({}, root: root),
      throwsFormatException,
    );
  });

  test('source paths cannot escape the repository', () {
    expect(
      () => verifyFrozenReplaySources({'../outside.dart': digest}, root: root),
      throwsFormatException,
    );
  });

  final reportWriters = <String, Future<void> Function()>{
    'metric motion': () async {
      await runMetricMotionBenchmark(knownCorpusRegression: true, write: true);
    },
    'scale motion': () async {
      await runScaleMotionBenchmark(knownCorpusRegression: true, write: true);
    },
    'temporal passage': () async {
      await runTemporalPassageBenchmark(
        knownCorpusRegression: true,
        write: true,
      );
    },
    'track passage': () async {
      runVisiblePassageBenchmark(knownCorpusRegression: true, write: true);
    },
    'processing profile': () async {
      profile.main(['--write', '--known-corpus-regression']);
    },
  };
  for (final entry in reportWriters.entries) {
    test(
      '${entry.key} regression cannot overwrite historical reports',
      () async {
        await expectLater(entry.value(), throwsArgumentError);
      },
    );
  }
}
