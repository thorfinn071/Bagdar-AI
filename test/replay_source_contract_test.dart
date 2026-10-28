import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/replay_source_contract.dart';

void main() {
  late Directory root;
  const contractPath = 'contract.json';
  const files = {
    'test/replay.dart': "import 'package:bagdar/algorithm.dart';",
    'lib/algorithm.dart': "export 'inner.dart';",
    'lib/inner.dart': 'const value = 42;',
    'fixtures/expected.json': '{"value":42}',
  };

  File file(String path) => File.fromUri(root.uri.resolve(path));
  void seal({Map<String, String> extraSources = const {}}) {
    file(contractPath).writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'entrypoints': ['test/replay.dart'],
        'sources': {
          for (final name in files.keys)
            name: sha256.convert(file(name).readAsBytesSync()).toString(),
          ...extraSources,
        },
      }),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('bagdar-replay-contract-');
    for (final entry in files.entries) {
      file(entry.key).parent.createSync(recursive: true);
      file(entry.key).writeAsStringSync(entry.value);
    }
    seal();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('pins transitive computation and expected fixture data', () {
    verifyReplaySourceContract(contractPath, root: root);
  });

  test('unrelated application changes do not change replay inputs', () {
    file('lib/onboarding.dart').writeAsStringSync('const page = 2;');
    verifyReplaySourceContract(contractPath, root: root);
  });

  for (final name in ['lib/inner.dart', 'fixtures/expected.json']) {
    test('changed $name is rejected', () {
      file(name).writeAsStringSync('changed');
      expect(
        () => verifyReplaySourceContract(contractPath, root: root),
        throwsStateError,
      );
    });
  }

  test('a new transitive dependency needs its own pinned hash', () {
    file('lib/inner.dart').writeAsStringSync("export 'additional.dart';");
    file('lib/additional.dart').writeAsStringSync('const extra = 1;');
    seal();
    expect(
      () => verifyReplaySourceContract(contractPath, root: root),
      throwsStateError,
    );
  });

  test('missing expected fixture is rejected', () {
    file('fixtures/expected.json').deleteSync();
    expect(
      () => verifyReplaySourceContract(contractPath, root: root),
      throwsStateError,
    );
  });

  test('source paths cannot escape the repository', () {
    seal(extraSources: {'../outside.dart': List.filled(64, '0').join()});
    expect(
      () => verifyReplaySourceContract(contractPath, root: root),
      throwsFormatException,
    );
  });

  test('unrelated Dart files cannot enter the computation contract', () {
    file('lib/onboarding.dart').writeAsStringSync('const page = 2;');
    seal(
      extraSources: {
        'lib/onboarding.dart': sha256
            .convert(file('lib/onboarding.dart').readAsBytesSync())
            .toString(),
      },
    );
    expect(
      () => verifyReplaySourceContract(contractPath, root: root),
      throwsStateError,
    );
  });
}
