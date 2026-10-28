import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/utils/blur_detector.dart';
import 'package:crypto/crypto.dart';

/// Fast desktop evaluation using the exact application blur check.
/// It does not bypass the check or substitute model inference.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass a runtime manifest path');
  final manifest = File(args.single);
  final root = await manifest.parent.resolveSymbolicLinks();
  final rows = <Map<String, Object?>>[];
  final map = jsonDecode(await manifest.readAsString()) as Map;
  for (final sequence in map['sequences'] as List) {
    final width = sequence['width'] as int;
    final height = sequence['height'] as int;
    var blurred = 0;
    final scores = <double>[];
    for (final frame in sequence['frames'] as List) {
      final asset = frame['yuv'] as Map;
      final relative = asset['path'] as String;
      if (relative.contains('..') ||
          relative.contains('\\') ||
          relative.startsWith('/') ||
          relative.contains(':')) {
        throw const FormatException('Unsafe YUV path');
      }
      final path = File('$root/$relative');
      final real = await path.resolveSymbolicLinks();
      if (!real.startsWith('$root${Platform.pathSeparator}')) {
        throw const FormatException('YUV path escaped');
      }
      final raw = await path.readAsBytes();
      if (raw.length != width * height * 3 ~/ 2 ||
          sha256.convert(raw).toString() != asset['sha256']) {
        throw const FormatException('YUV bytes/hash mismatch');
      }
      final score = BlurDetector.sharpnessScore(
        Uint8List.sublistView(raw, 0, width * height),
        width: width,
        height: height,
        rowStride: width,
        stride: 8,
      );
      scores.add(score);
      if (BlurDetector.isBlurry(score)) blurred++;
    }
    scores.sort();
    rows.add({
      'sequenceId': sequence['id'],
      'frames': scores.length,
      'blurSkipped': blurred,
      'minimum': scores.first,
      'median': scores[scores.length ~/ 2],
      'maximum': scores.last,
    });
  }
  final result = {
    'scope':
        'exact production blur check on synthetic luma; no model inference',
    'threshold': BlurDetector.kBlurThreshold,
    'sequences': rows,
  };
  final file = File('${manifest.parent.parent.path}/quality-report.json');
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  final frames = rows.fold<int>(0, (sum, row) => sum + (row['frames'] as int));
  final skipped = rows.fold<int>(
    0,
    (sum, row) => sum + (row['blurSkipped'] as int),
  );
  stdout.writeln(
    'Production blur gate: $skipped/$frames frames skipped; ${frames - skipped} eligible. ${file.path}',
  );
}
