import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/simulation/quality_observer_benchmark.dart' as benchmark;

void main() {
  test(
    'candidate and frozen source must both match the declared identity',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bagdar-observer-freeze-',
      );
      try {
        final source = File('${root.path}/candidate.dart');
        final frozen = File('${root.path}/candidate-frozen.dart.txt');
        await source.writeAsString('fixed pixel-only candidate');
        await frozen.writeAsBytes(await source.readAsBytes());
        final hash = sha256.convert(await source.readAsBytes()).toString();
        await File(
          '${root.path}/manifest.json',
        ).writeAsString(jsonEncode({'candidateSourceSha256': hash}));
        expect(await benchmark.validateFrozenObserver(root, source), hash);
        await source.writeAsString('changed candidate');
        await expectLater(
          benchmark.validateFrozenObserver(root, source),
          throwsFormatException,
        );
        await source.writeAsBytes(await frozen.readAsBytes());
        await frozen.writeAsString('changed frozen bytes');
        await expectLater(
          benchmark.validateFrozenObserver(root, source),
          throwsFormatException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'existing candidate results are preserved before any new scoring',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bagdar-observer-preserve-',
      );
      try {
        final result = File('${root.path}/observer.json');
        await result.writeAsString('original receipt');
        await expectLater(benchmark.main([root.path]), throwsStateError);
        expect(await result.readAsString(), 'original receipt');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
