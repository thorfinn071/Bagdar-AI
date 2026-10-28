import 'dart:convert';
import 'dart:io';

import 'package:bagdar/research/image_quality_observer.dart';
import 'package:crypto/crypto.dart';

import 'quality_benchmark.dart' as production;

Future<String> validateFrozenObserver(Directory root, File source) async {
  final manifest =
      jsonDecode(await File('${root.path}/manifest.json').readAsString())
          as Map;
  final sourceHash = sha256.convert(await source.readAsBytes()).toString();
  final frozen = await File(
    '${root.path}/candidate-frozen.dart.txt',
  ).readAsBytes();
  if (sourceHash != manifest['candidateSourceSha256'] ||
      sha256.convert(frozen).toString() != sourceHash) {
    throw const FormatException('Candidate changed after experiment freeze');
  }
  return sourceHash;
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Pass a new observer corpus directory');
  }
  final root = Directory(await Directory(args.single).resolveSymbolicLinks());
  final target = File('${root.path}/observer.json');
  if (await target.exists()) {
    throw StateError('Preserve existing observer results');
  }
  final raw = await File('${root.path}/manifest.json').readAsBytes();
  final manifest = jsonDecode(utf8.decode(raw)) as Map;
  final source = File.fromUri(
    Platform.script.resolve('../../lib/research/image_quality_observer.dart'),
  );
  final sourceHash = await validateFrozenObserver(root, source);
  // This verifies protocol, paths, IDs and every pixel hash, then measures the
  // unchanged filter. Existing baselines are deliberately never overwritten.
  await production.main(args);
  final baselineRaw = await File('${root.path}/baseline.json').readAsBytes();
  final baseline = jsonDecode(utf8.decode(baselineRaw)) as Map;
  final rows = <Map<String, Object?>>[];
  for (final item in baseline['images'] as List) {
    final row = item as Map;
    final asset = row['asset'] as Map;
    final bytes = await File('${root.path}/${asset['path']}').readAsBytes();
    if (sha256.convert(bytes).toString() != asset['sha256']) {
      throw const FormatException('Pixels changed during observer evaluation');
    }
    final watch = Stopwatch()..start();
    final observation = const ImageQualityObserver().observe(
      bytes,
      width: row['width'] as int,
      height: row['height'] as int,
      rowStride: row['rowStride'] as int,
    );
    watch.stop();
    rows.add({
      ...Map<String, Object?>.from(row),
      'observer': observation.toJson(),
      'observerElapsedUs': watch.elapsedMicroseconds,
    });
  }
  final result = {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'version': ImageQualityObserver.version,
    'candidateSourceSha256': sourceHash,
    'corpusManifestSha256': sha256.convert(raw).toString(),
    'baselineSha256': sha256.convert(baselineRaw).toString(),
    'protocolSha256': manifest['protocolSha256'],
    'scorerSourceSha256': sha256
        .convert(await File.fromUri(Platform.script).readAsBytes())
        .toString(),
    'timingScope':
        'One desktop Dart/JIT observation per image; includes allocation, excludes IO. Cold/JIT effects included. Not Android latency.',
    'runtime': Platform.version,
    'images': rows,
  };
  await target.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln('OBSERVER_RESULT ${rows.length} images; $target');
}
