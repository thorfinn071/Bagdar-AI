import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:crypto/crypto.dart';

/// Separate desktop timing, run serially after functional replay. No decisions
/// or calibration are fitted. Measurements are deliberately outside --check.
void main() {
  const root = 'test/fixtures/spatial_safety/camera-temporal-passage-v1';
  final manifest =
      jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map;
  final ncnn =
      jsonDecode(File('$root/ncnn/manifest.json').readAsStringSync()) as Map;
  final frameKeys = <String>{
    for (final layout in manifest['layouts'] as List)
      for (final id in layout['decisionFrameIds'] as List)
        '${layout['id']}:$id',
  };
  final maps = <String, Float32List>{};
  for (final item in ncnn['frames'] as List) {
    final key = '${item['layoutId']}:${item['frameId']}';
    if (!frameKeys.contains(key)) continue;
    final bytes = File('$root/ncnn/${item['path']}').readAsBytesSync();
    if (sha256.convert(bytes).toString() != item['sha256']) {
      throw StateError('NN identity changed');
    }
    final data = ByteData.sublistView(Uint8List.fromList(gzip.decode(bytes)));
    maps[key] = Float32List.fromList(
      List.generate(
        data.lengthInBytes ~/ 4,
        (i) => data.getFloat32(i * 4, Endian.little),
      ),
    );
  }
  for (var i = 0; i < 10; i++) {
    DepthMapOps.normalizeRelativeProximity(maps.values.first);
  }
  final frames = <Map<String, Object?>>[];
  for (final item in maps.entries) {
    final times = <double>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      final result = DepthMapOps.normalizeRelativeProximity(item.value);
      watch.stop();
      if (result.length != 65536) throw StateError('Invalid output size');
      times.add(watch.elapsedMicroseconds / 1000);
    }
    times.sort();
    final parts = item.key.split(':');
    frames.add({
      'layoutId': parts.first,
      'frameId': int.parse(parts.last),
      'normalizationMs': times[2],
      'samplesMs': times,
    });
  }
  File(
    'docs/_baseline_logs/camera_temporal_normalization_timing.json',
  ).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'scope': 'desktop Dart JIT, serial separate stage estimate, warmed 10 calls; per-frame median of five; excludes loading', 'sourceSha256': sha256.convert(File.fromUri(Platform.script).readAsBytesSync()).toString(), 'normalizationSourceSha256': sha256.convert(File('lib/utils/depth_map_ops.dart').readAsBytesSync()).toString(), 'frames': frames})}\n',
  );
  stdout.writeln(
    'Normalization timing recorded for ${frames.length} actual decision inputs',
  );
}
