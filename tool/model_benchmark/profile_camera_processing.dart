import 'dart:convert';
import 'dart:io';
import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_cached_scale_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_scale_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import '../../test/harness/camera_visible_passage_fixture.dart';
import '../../test/harness/frozen_replay_sources.dart';

const processingCorpus = 'test/fixtures/spatial_safety/camera-scale-motion-v1';

CameraMetricMotionInput processingInput(
  VisibleFixture fixture,
  Map<String, dynamic> layout,
  CameraVisibleDepthFrame frame,
) {
  final pixels =
      (fixture.ncnn['frames'] as List).cast<Map<String, dynamic>>().singleWhere(
            (r) =>
                r['layoutId'] == layout['id'] && r['frameId'] == frame.frameId,
          )['rgbPixels']
          as Map;
  final path = '${fixture.root}/ncnn/${pixels['path']}';
  if (visibleSha(path) != pixels['sha256']) {
    throw StateError('RGB identity mismatch');
  }
  return CameraMetricMotionInput(
    camera: CameraTrackAssociationInput(
      rgbHeader: processingHeader(fixture, frame),
      depth: frame,
      imageGeometry: CameraTrackImageGeometry(
        cameraId: frame.cameraId,
        width: frame.width,
        height: frame.height,
        fx: frame.fx,
        fy: frame.fy,
        cx: frame.cx,
        cy: frame.cy,
        rotation: frame.rotation,
        originM: frame.originM,
      ),
    ),
    rgb: gzip.decode(File(path).readAsBytesSync()),
    positionErrorM: .0001,
    angularErrorRad: 0,
  );
}

ObservationHeader processingHeader(
  VisibleFixture fixture,
  CameraVisibleDepthFrame frame, {
  int? producedAtUs,
  double confidence = 1,
}) => ObservationHeader(
  providerId: 'desktop-ncnn-midas-depth',
  modelId: 'midas-small-ncnn',
  modelHash: fixture.ncnn['modelBinSha256'] as String,
  preprocessId: fixture.ncnn['preprocessId'] as String,
  sessionGeneration: frame.sessionGeneration,
  frameId: frame.frameId,
  sourceTimestampUs: frame.capturedAtUs,
  producedAtUs: producedAtUs ?? frame.capturedAtUs + 1000,
  transformId: frame.transformId,
  confidence: confidence,
  health: ObservationHealth.healthy,
);

Map<String, Object?> percentiles(Iterable<num> values) {
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  if (sorted.isEmpty) return {'count': 0, 'p50': null, 'p95': null};
  double at(double q) => sorted[(sorted.length * q).ceil() - 1];
  return {'count': sorted.length, 'p50': at(.5), 'p95': at(.95)};
}

void main(List<String> args) {
  final knownCorpusRegression = args.contains('--known-corpus-regression');
  final modes = args
      .where((arg) => arg != '--known-corpus-regression')
      .toList();
  if (modes.length != 1 ||
      !['--write', '--check'].contains(modes.single) ||
      args.length != modes.length + (knownCorpusRegression ? 1 : 0)) {
    throw ArgumentError(
      'Usage: profile_camera_processing.dart --write|--check '
      '[--known-corpus-regression]',
    );
  }
  final check = modes.single == '--check';
  if (knownCorpusRegression && !check) {
    throw ArgumentError('Known-corpus replay cannot replace frozen reports.');
  }
  final fixture = VisibleFixture(root: processingCorpus);
  final freeze = visibleJson(
    'docs/_baseline_logs/camera_scale_motion_development_freeze.json',
  );
  verifyFrozenReplaySources(
    freeze['sourceSha256'] as Map<String, dynamic>,
    allowHistoricalSources: knownCorpusRegression,
  );
  final inputs = <String, List<CameraMetricMotionInput>>{};
  final loads = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    final timer = Stopwatch()..start();
    final frames = fixture
        .frames(layout)
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId));
    inputs[layout['id'] as String] = frames
        .map((f) => processingInput(fixture, layout, f))
        .toList();
    loads.add({
      'layoutId': layout['id'],
      'frames': inputs[layout['id']]!.length,
      'fixtureLoadMs': timer.elapsedMicroseconds / 1000,
    });
  }
  final parity = <Map<String, Object?>>[], timings = <Map<String, Object?>>[];
  // One unmeasured warm-up traversal, then alternating mode order per round.
  for (var round = -1; round < (check ? 1 : 3); round++) {
    for (final entry in inputs.entries) {
      final frozen = CameraScaleMetricMotionSource(
        calibration: fixture.calibration(),
        relativeModelHash: fixture.ncnn['modelBinSha256'] as String,
      );
      final cached = CameraCachedScaleMetricMotionSource(
        calibration: fixture.calibration(),
        relativeModelHash: fixture.ncnn['modelBinSha256'] as String,
      );
      for (final input in entry.value) {
        final results = <String, CameraMetricMotionResult>{};
        for (final mode
            in round.isEven ? ['frozen', 'cached'] : ['cached', 'frozen']) {
          final timer = Stopwatch()..start();
          results[mode] = mode == 'frozen'
              ? frozen.observe(
                  input,
                  nowUs: input.camera.depth.capturedAtUs + 2000,
                )
              : cached.observe(
                  input,
                  nowUs: input.camera.depth.capturedAtUs + 2000,
                );
          timer.stop();
          if (round >= 0) {
            timings.add({
              'round': round,
              'layoutId': entry.key,
              'frameId': input.camera.depth.frameId,
              'mode': mode,
              'computeMs': timer.elapsedMicroseconds / 1000,
            });
          }
        }
        final a = jsonEncode(results['frozen']!.toDiagnosticMap());
        final b = jsonEncode(results['cached']!.toDiagnosticMap());
        if (a != b) {
          throw StateError(
            'Matcher output changed: ${entry.key}/${input.camera.depth.frameId}',
          );
        }
        if (round == 0) {
          parity.add({
            'layoutId': entry.key,
            'frameId': input.camera.depth.frameId,
            'equal': true,
            'addsMotionRisk': results['cached']!.addsMotionRisk,
            'result': results['cached']!.toDiagnosticMap(),
          });
        }
      }
    }
    stdout.writeln('Processing profile round $round completed');
  }
  final report = {
    if (knownCorpusRegression) 'evaluationScope': 'knownCorpusRegression',
    'scope':
        'known synthetic regression, exact matcher parity; no fresh holdout',
    'promotionAllowed': false,
    'frames': parity,
    'sourceSha256': {
      'lib/safety/perception/camera_cached_scale_metric_motion.dart':
          visibleSha(
            'lib/safety/perception/camera_cached_scale_metric_motion.dart',
          ),
      'tool/model_benchmark/profile_camera_processing.dart': visibleSha(
        'tool/model_benchmark/profile_camera_processing.dart',
      ),
    },
    'oldFreezeSha256': visibleSha(
      'docs/_baseline_logs/camera_scale_motion_development_freeze.json',
    ),
  };
  const path = 'docs/_baseline_logs/camera_processing_parity.json';
  if (check) {
    final expected = visibleJson(path);
    if (knownCorpusRegression) {
      verifyFrozenReplaySources(
        expected['sourceSha256'] as Map<String, dynamic>,
        allowHistoricalSources: true,
      );
      final expectedData = Map<String, dynamic>.of(expected)
        ..remove('sourceSha256');
      final currentData = Map<String, Object?>.of(report)
        ..remove('sourceSha256')
        ..remove('evaluationScope');
      if (jsonEncode(expectedData) != jsonEncode(currentData)) {
        throw StateError('Processing parity report drift');
      }
    } else if (jsonEncode(expected) != jsonEncode(report)) {
      throw StateError('Processing parity report drift');
    }
  } else {
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    final summary = {
      for (final mode in ['frozen', 'cached'])
        mode: percentiles(
          timings
              .where((r) => r['mode'] == mode)
              .map((r) => r['computeMs'] as num),
        ),
    };
    File(
      'docs/_baseline_logs/camera_processing_motion_profile.json',
    ).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'scope': 'warmed preloaded Dart matcher; excludes input IO/construction and NN/runtime', 'dartVersion': Platform.version, 'executable': Platform.resolvedExecutable, 'warmupTraversals': 1, 'measuredRounds': 3, 'alternatingOrder': true, 'fixtureLoads': loads, 'summaries': summary, 'frames': timings})}\n',
    );
    stdout.writeln(jsonEncode(summary));
  }
  stdout.writeln('Exact frozen/cached parity: ${parity.length} input frames');
}
