import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';

import 'harness/blender_visible_body_fixture.dart';

const sequenceFirstReturnRoot = 'scratch/sequence-first-return-2026-10-09';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'prepare complete sequential component footprints without scene labels',
    () {
      final fixture = PairedBodyFixture();
      final seq = (fixture.corpus['sequences'] as List).cast<Map>().singleWhere(
        (s) => s['sceneId'] == 'path-clear',
      );
      final optics = (fixture.manifest['sequences'] as List)
          .cast<Map>()
          .singleWhere((s) => s['sceneId'] == 'path-clear');
      final detector = GenericObstacleDetector(
        collectCameraSupport: true,
        collectOpeningDiagnostics: true,
      );
      final tracker = GenericObstacleTracker();
      final frames = <Map<String, Object?>>[];
      for (final original in (seq['frames'] as List).cast<Map>()) {
        final index = original['frameIndex'] as int,
            p = (optics['single'] as List)[original['frameIndex']] as Map;
        final depth = fixture.visible(p, 'path-clear');
        final frame = fixture.relative(
          original,
          'path-clear',
          depth.capturedAtUs,
          canonicalPreprocess: true,
        );
        final detection = detector.detect(
          frame: frame,
          pitchDeg: 12,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: depth.capturedAtUs,
        );
        final tracks = tracker.update(
          observations: detection.observations,
          timestampUs: depth.capturedAtUs,
          relative: true,
        );
        final pixels = <int>{};
        for (final track in tracks) {
          final support = track.last.cameraSupport!;
          for (final i in support.indices) {
            final x = i % 256, y = i ~/ 256;
            final x0 = math.max(
              0,
              (math.max(0, (x - 1) / 256) * depth.width).floor(),
            );
            final x1 = math.min(
              depth.width - 1,
              (math.min(1, (x + 2) / 256) * depth.width).ceil() - 1,
            );
            final y0 = math.max(
              0,
              (math.max(0, (y - 1) / 256) * depth.height).floor(),
            );
            final y1 = math.min(
              depth.height - 1,
              (math.min(1, (y + 2) / 256) * depth.height).ceil() - 1,
            );
            for (var yy = y0; yy <= y1; yy++) {
              for (var xx = x0; xx <= x1; xx++) {
                pixels.add(yy * depth.width + xx);
              }
            }
          }
        }
        final raw = (fixture.ncnn['frames'] as List).cast<Map>().singleWhere(
          (r) => r['sceneId'] == 'path-clear' && r['frameIndex'] == index,
        );
        frames.add({
          'id': 'clear-${index.toString().padLeft(2, '0')}',
          'frameIndex': index,
          'frameId': p['frameId'],
          'capturedAtUs': depth.capturedAtUs,
          'original': original,
          'primary': p,
          'neural': raw,
          'supportPixels': pixels.toList()..sort(),
          'tracks': [
            for (final t in tracks)
              {
                'id': t.id,
                'hits': t.hits,
                'age': t.age,
                'misses': t.misses,
                'confirmed': t.confirmed,
                'approachTrend': t.approachTrend(),
                'timestamps': List<int>.from(t.timestampUsHist),
                'componentSupport': List<int>.from(
                  t.last.cameraSupport!.indices,
                ),
              },
          ],
        });
      }
      expect(frames.length, 11);
      final result = {
        'schemaVersion': 1,
        'promotionAllowed': false,
        'newNeuralInference': false,
        'scope':
            'complete sequential detector/tracker footprints; no labels or runtime authority',
        'corpusManifestSha256': bodySha('$pairedRgbRoot/corpus-manifest.json'),
        'visibleManifestSha256': fixture.modelHash,
        'neuralReceiptSha256': bodySha(
          'docs/_baseline_logs/blender_paired_ncnn.json',
        ),
        'sources': {
          for (final p in [
            'test/prepare_sequence_first_return_test.dart',
            'docs/sequence-first-return-protocol-2026-10-09.md',
            'test/harness/blender_visible_body_fixture.dart',
            'lib/services/generic_obstacle_detector.dart',
            'lib/tracker/generic_obstacle_tracker.dart',
          ])
            p: bodySha(p),
        },
        'frames': frames,
      };
      final file = File('$sequenceFirstReturnRoot/selection.json');
      final text = '${const JsonEncoder.withIndent('  ').convert(result)}\n';
      if (const bool.fromEnvironment('BAGDAR_WRITE_SEQUENCE_SELECTION')) {
        expect(file.existsSync(), false, reason: 'Selection is immutable');
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_SEQUENCE_SELECTION')) {
        expect(file.readAsStringSync(), text);
      }
    },
    skip: !const bool.fromEnvironment('BAGDAR_SEQUENCE_SELECTION'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
