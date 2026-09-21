import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'depth_map_ops.dart';

/// Debug-only dump of **normalized depth metadata** (not camera pixels).
///
/// Off unless **both** [kDebugMode] is true **and** a developer has set
/// [consentGranted] plus [outputDir]. Never writes YUV/RGB.
class NcnnDepthDebugDump {
  NcnnDepthDebugDump._();

  static bool consentGranted = false;
  static String? outputDir;

  static bool get enabled =>
      kDebugMode &&
      consentGranted &&
      outputDir != null &&
      outputDir!.isNotEmpty;

  static void dump({
    required Float32List depth,
    required int width,
    required int height,
    required String provider,
    required int timestampUs,
    int? nativeOutW,
    int? nativeOutH,
    double? frameQuality,
  }) {
    if (!enabled) return;
    try {
      final dir = Directory(outputDir!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      var valid = 0;
      var nan = 0;
      double sum = 0;
      var minV = double.infinity;
      var maxV = double.negativeInfinity;
      for (final v in depth) {
        if (!DepthMapOps.isValid(v)) {
          nan++;
          continue;
        }
        valid++;
        sum += v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      final meta = <String, Object?>{
        'tsUs': timestampUs,
        'provider': provider,
        'width': width,
        'height': height,
        'nativeOutW': nativeOutW,
        'nativeOutH': nativeOutH,
        'valid': valid,
        'nan': nan,
        'min': minV.isFinite ? minV : null,
        'max': maxV.isFinite ? maxV : null,
        'mean': valid > 0 ? sum / valid : null,
        'frameQuality': frameQuality,
      };
      final name = 'depth_$timestampUs.json';
      File('${dir.path}/$name').writeAsStringSync(jsonEncode(meta));
    } catch (e) {
      debugPrint('NcnnDepthDebugDump: failed ($e)');
    }
  }
}
