import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import '../../test/harness/camera_visible_passage_fixture.dart';
import 'fast_camera_motion_fixture.dart';

Map<String, Object?> fastPercentiles(Iterable<num> values) {
  final a = values.map((x) => x.toDouble()).toList()..sort();
  return {
    'count': a.length,
    'p50': a.isEmpty ? null : a[(a.length * .5).ceil() - 1],
    'p95': a.isEmpty ? null : a[(a.length * .95).ceil() - 1],
  };
}

void main(List<String> args) {
  if (args.length != 2 || !['--check', '--measure'].contains(args.first)) {
    throw ArgumentError(
      'Usage: profile_fast_camera_motion --check|--measure output.json',
    );
  }
  final measure = args.first == '--measure';
  final fixture = VisibleFixture(root: fastCorpus);
  final expected = visibleJson(
    'docs/_baseline_logs/camera_processing_parity.json',
  );
  final inputs = <String, List<FastMetricMotionInput>>{};
  final preload = Stopwatch()..start();
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    inputs[layout['id'] as String] = fixture
        .frames(layout)
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId))
        .map((f) => fastInput(fixture, layout, f))
        .toList();
  }
  preload.stop();
  final timings = <Map<String, Object?>>[], parity = <Map<String, Object?>>[];
  for (var round = -1; round < (measure ? 3 : 1); round++) {
    for (final layout in inputs.entries) {
      final sources = {
        for (final optimized in [false, true])
          optimized: CameraFastMetricMotionSource(
            calibration: fixture.calibration(),
            rgbContract: fastRgbContract,
            optimizePixels: optimized,
            profileStages: true,
          ),
      };
      for (final input in layout.value) {
        final f = input.camera.depth;
        final results = <bool, FastMetricMotionResult>{};
        for (final optimized in round.isEven ? [false, true] : [true, false]) {
          final timer = Stopwatch()..start();
          results[optimized] = sources[optimized]!.observe(
            input,
            nowUs: f.capturedAtUs + 2000,
          );
          timer.stop();
          if (round >= 0) {
            timings.add({
              'round': round,
              'layoutId': layout.key,
              'frameId': f.frameId,
              'optimized': optimized,
              'computeMs': timer.elapsedMicroseconds / 1000,
              'stagesUs': sources[optimized]!.stageTimesUs,
            });
          }
        }
        final old = (expected['frames'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere(
              (r) => r['layoutId'] == layout.key && r['frameId'] == f.frameId,
            )['result'];
        for (final r in results.values) {
          if (jsonEncode(r.toDiagnosticMap()) != jsonEncode(old)) {
            throw StateError(
              'Full frozen parity drift ${layout.key}/${f.frameId}',
            );
          }
        }
        if (round == 0) {
          parity.add({
            'layoutId': layout.key,
            'frameId': f.frameId,
            'equal': true,
            'result': results[true]!.toDiagnosticMap(),
          });
        }
      }
    }
    stdout.writeln('Fast pure kernel round $round completed');
  }
  final report = {
    'scope':
        'known synthetic regression, pure independent RGB/metric-depth/pose kernel; no phone evidence',
    'promotionAllowed': false,
    'newIndependentHoldout': false,
    'nnAwaited': false,
    'frames': parity,
  };
  final output = File(args.last);
  output.parent.createSync(recursive: true);
  if (measure) {
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        ...report,
        'runtimeVersion': Platform.version,
        'executable': Platform.resolvedExecutable,
        'warmupTraversals': 1,
        'measuredRounds': 3,
        'alternatingOrder': true,
        'fixtureLoadMs': preload.elapsedMicroseconds / 1000,
        'summaries': {
          for (final mode in [false, true]) mode ? 'optimized' : 'baseline': fastPercentiles(timings.where((r) => r['optimized'] == mode).map((r) => r['computeMs'] as num)),
        },
        'timings': timings,
      })}\n',
    );
  } else {
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  stdout.writeln('Exact independent fast kernel parity: ${parity.length}/109');
}
