import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:bagdar/utils/blur_detector.dart';

/// Calls the unchanged app implementation. Dense sampling is diagnostic only.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Pass a diagnostic corpus directory');
  }
  final root = Directory(await Directory(args.single).resolveSymbolicLinks());
  final target = File('${root.path}/baseline.json');
  if (await target.exists()) throw StateError('Preserve the existing baseline');
  final rawManifest = await File('${root.path}/manifest.json').readAsBytes();
  final manifest = jsonDecode(utf8.decode(rawManifest)) as Map;
  final protocol = await File('${root.path}/protocol.json').readAsBytes();
  if (manifest['schemaVersion'] != 1 ||
      manifest['promotionAllowed'] != false ||
      sha256.convert(protocol).toString() != manifest['protocolSha256']) {
    throw const FormatException('Invalid diagnostic manifest/protocol');
  }
  final rows = <Map<String, Object?>>[];
  final ids = <String>{};
  final elapsed = <int>[];
  for (final item in manifest['images'] as List) {
    final row = item as Map;
    final id = row['id'] as String;
    final width = row['width'] as int;
    final height = row['height'] as int;
    final rowStride = row['rowStride'] as int;
    final asset = row['asset'] as Map;
    final relative = asset['path'] as String;
    if (!ids.add(id) ||
        width < 16 ||
        width > 1280 ||
        height < 16 ||
        height > 1280 ||
        rowStride < width ||
        rowStride > 2048 ||
        relative.contains('..') ||
        relative.contains('\\') ||
        relative.contains(':') ||
        relative.startsWith('/')) {
      throw FormatException('Invalid diagnostic image: $id');
    }
    final file = File('${root.path}/$relative');
    final resolved = await file.resolveSymbolicLinks();
    if (!resolved.startsWith('${root.path}${Platform.pathSeparator}')) {
      throw const FormatException('Diagnostic path escaped corpus');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != rowStride * height ||
        sha256.convert(bytes).toString() != asset['sha256']) {
      throw FormatException('Changed diagnostic pixels: $id');
    }
    final timer = Stopwatch()..start();
    final score = BlurDetector.sharpnessScore(
      bytes,
      width: width,
      height: height,
      rowStride: rowStride,
      stride: 8,
    );
    timer.stop();
    elapsed.add(timer.elapsedMicroseconds);
    final dense = BlurDetector.sharpnessScore(
      bytes,
      width: width,
      height: height,
      rowStride: rowStride,
      stride: 1,
    );
    rows.add({
      ...Map<String, Object?>.from(row),
      'score': score,
      'rejected': BlurDetector.isBlurry(score),
      'denseScore': dense,
      'denseRejected': BlurDetector.isBlurry(dense),
    });
  }
  elapsed.sort();
  final source = File.fromUri(
    Platform.script.resolve('../../lib/utils/blur_detector.dart'),
  );
  final result = {
    'schemaVersion': 1,
    'scope':
        'Unchanged production blur check on independent diagnostic luma; no model inference',
    'promotionAllowed': false,
    'corpusManifestSha256': sha256.convert(rawManifest).toString(),
    'protocolSha256': manifest['protocolSha256'],
    'productionSourceSha256': sha256
        .convert(await source.readAsBytes())
        .toString(),
    'scorerSourceSha256': sha256
        .convert(await File.fromUri(Platform.script).readAsBytes())
        .toString(),
    'threshold': BlurDetector.kBlurThreshold,
    'runtime': Platform.version,
    'timingScope':
        'Desktop Dart/JIT score only, excludes IO and dense comparator; not Android latency',
    'stride8TimingUs': {
      'samples': elapsed.length,
      'p50': elapsed[(elapsed.length * 50 + 99) ~/ 100 - 1],
      'p95': elapsed[(elapsed.length * 95 + 99) ~/ 100 - 1],
      'maximum': elapsed.last,
    },
    'images': rows,
  };
  await target.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln('QUALITY_BASELINE ${rows.length} checked images; $target');
}
