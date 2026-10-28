import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/camera/camera_session.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/experimental_relative_depth_replay_provider.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _required = bool.fromEnvironment('BAGDAR_DEPTH_BAKEOFF_REQUIRED');
const _write = bool.fromEnvironment('BAGDAR_WRITE_DEPTH_BAKEOFF');
const _admissionRequired = bool.fromEnvironment(
  'BAGDAR_DEPTH_CANDIDATE_ADMISSION_REQUIRED',
);
const _root = String.fromEnvironment(
  'BAGDAR_DEPTH_BAKEOFF_ROOT',
  defaultValue: 'scratch/depth-anything-v2-bakeoff-2026-10-05',
);
const _corpus = 'test/fixtures/spatial_safety/blender-context-v3';
const _yoloPath =
    'docs/_baseline_logs/blender_context_detector_diagnostic.json';

// Semantic attachment only needs session identity. Do not construct or start
// the complete camera/audio/navigation UI in this camera-free diagnostic.
class _ReplayCameraContext implements CameraViewModel {
  @override
  final CameraSession cameraSession = CameraSession();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'unexpected replay UI access: ${invocation.memberName}',
  );
}

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
String _sha(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Uint8List _checked(String root, String relative, String digest) {
  if (relative.startsWith('/') ||
      relative.contains('..') ||
      relative.contains('\\') ||
      relative.contains(':')) {
    throw const FormatException('unsafe experiment asset path');
  }
  final resolvedRoot = Directory(root).resolveSymbolicLinksSync();
  final file = File('$root/$relative');
  if (!file.resolveSymbolicLinksSync().startsWith(
    '$resolvedRoot${Platform.pathSeparator}',
  )) {
    throw const FormatException('experiment asset escaped its root');
  }
  final bytes = file.readAsBytesSync();
  if (sha256.convert(bytes).toString() != digest) {
    throw const FormatException('experiment asset hash mismatch');
  }
  return bytes;
}

List<Track> _semanticTracks(Map<String, dynamic> frame) => [
  for (final (i, raw) in (frame['detections'] as List<dynamic>).indexed)
    (() {
      final detection = raw as Map<String, dynamic>;
      final box = (detection['boxNormalized'] as List<dynamic>).cast<num>();
      return Track(
        id: i + 1,
        label: 'class-${detection['classId']}',
        cx: (box[0] + box[2]).toDouble() * 128,
        cy: (box[1] + box[3]).toDouble() * 128,
        x1: box[0].toDouble() * 256,
        y1: box[1].toDouble() * 256,
        x2: box[2].toDouble() * 256,
        y2: box[3].toDouble() * 256,
        dist: 'close',
        distM: -1,
        initialConf: (detection['score'] as num).toDouble(),
      );
    })(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = File('$_root/inference-report.json').existsSync();
  test(
    'real MiDaS and DA-V2 NCNN maps traverse unchanged Bagdar shadow runtime',
    () {
      if (!available) {
        fail('required DA-V2 artifacts missing; run the documented bakeoff');
      }
      final inference = _json('$_root/inference-report.json');
      final corpus = _json('$_corpus/corpus-manifest.json');
      final diagnostic = _json(_yoloPath);
      expect(inference['promotionAllowed'], isFalse);
      expect(inference['failedVariant'], isNull);
      expect(inference['allConversionParityPassed'], isTrue);
      expect(
        inference['corpusManifestSha256'],
        _sha('$_corpus/corpus-manifest.json'),
      );
      expect(
        diagnostic['corpusManifestSha256'],
        inference['corpusManifestSha256'],
      );
      expect(
        inference['sourceManifestSha256'],
        _sha('model_export/depth_anything_v2/source-manifest.json'),
      );
      expect(
        inference['exportManifestSha256'],
        _sha('model_export/depth_anything_v2/export-manifest.json'),
      );
      expect(
        inference['scriptSha256'],
        _sha('tool/model_benchmark/run_depth_anything_bakeoff.py'),
      );
      expect(
        inference['helperSha256'],
        _sha('tool/model_benchmark/depth_candidate_common.py'),
      );
      final yolo = (diagnostic['models'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((m) => m['modelId'] == 'yolov8n-int8-control-416');
      expect(yolo['artifactSha256'], _sha('assets/yolov8n_int8.tflite'));
      final yoloFrames = <String, Map<String, dynamic>>{
        for (final sequence
            in (yolo['sequences'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          for (final frame
              in (sequence['frames'] as List<dynamic>)
                  .cast<Map<String, dynamic>>())
            '${sequence['sceneId']}/${frame['frameIndex']}': frame,
      };
      final sourceFrames = <String, Map<String, dynamic>>{};
      for (final scene
          in (corpus['assets'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        for (final frame
            in (scene['frames'] as List<dynamic>)
                .cast<Map<String, dynamic>>()) {
          final key = '${scene['sceneId']}/${frame['frameIndex']}';
          expect(sourceFrames.containsKey(key), isFalse);
          sourceFrames[key] = {
            ...frame,
            'sceneId': scene['sceneId'],
            'state': scene['state'],
          };
        }
      }
      expect(sourceFrames, hasLength(18));
      expect(yoloFrames.keys.toSet(), sourceFrames.keys.toSet());
      final origin = DateTime.utc(2026, 10, 5);
      final variants = <Map<String, Object?>>[];
      final neuralVariants = (inference['variants'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(
            (v) =>
                v['backend'] == 'midas' ||
                (v['backend'] as String).startsWith('ncnn-'),
          );
      expect(neuralVariants, hasLength(5));
      for (final variant in neuralVariants) {
        final adapter = ExperimentalRelativeDepthReplayProvider(
          modelId: variant['modelId'] as String,
          modelHash: variant['modelHash'] as String,
          preprocessId: variant['preprocessId'] as String,
        );
        final byScene = <String, List<Map<String, dynamic>>>{};
        final seen = <String>{};
        for (final row
            in (variant['frames'] as List<dynamic>)
                .cast<Map<String, dynamic>>()) {
          final key = '${row['sceneId']}/${row['frameIndex']}';
          expect(seen.add(key), isTrue);
          byScene.putIfAbsent(row['sceneId'] as String, () => []).add(row);
        }
        expect(seen, sourceFrames.keys.toSet());
        final rows = <Map<String, Object?>>[];
        var hazards = 0, stopped = 0, unsafe = 0, passable = 0, falseStops = 0;
        for (final entry in byScene.entries) {
          final detector = GenericObstacleDetector(
            collectOpeningDiagnostics: true,
          );
          final tracker = GenericObstacleTracker();
          final controller = DepthPipelineController(
            vm: _ReplayCameraContext(),
            models: ModelService.instance,
          );
          final runtime =
              SpatialSafetyRuntime(healthCoordinator: CoreHealthCoordinator())
                ..beginSession(
                  1,
                  now: origin.subtract(const Duration(milliseconds: 1)),
                );
          for (final row in entry.value) {
            final key = '${row['sceneId']}/${row['frameIndex']}';
            final source = sourceFrames[key]!;
            final rgb = source['rgb'] as Map<String, dynamic>;
            _checked(_corpus, rgb['path'] as String, rgb['sha256'] as String);
            final yoloFrame = yoloFrames[key]!;
            expect(yoloFrame['rgbSha256'], rgb['sha256']);
            expect(row['rgbSha256'], rgb['sha256']);
            expect(row['capturedOffsetMs'], source['capturedOffsetMs']);
            final expected = source['state'] == 'safe'
                ? 'continueForward'
                : 'stopNow';
            expect(row['expectedAction'], expected);
            final now = origin.add(
              Duration(milliseconds: source['capturedOffsetMs'] as int),
            );
            final frame = adapter.frameForReplay(
              bytes: _checked(
                _root,
                row['mapPath'] as String,
                row['mapSha256'] as String,
              ),
              mapSha256: row['mapSha256'] as String,
              sourceRgbSha256: row['rgbSha256'] as String,
              expectedRgbSha256: rgb['sha256'] as String,
              sourceTimestampUs: now.microsecondsSinceEpoch,
              evaluatedAtUs: now.microsecondsSinceEpoch + 2000,
              diagnosticFrameQuality: 1,
            );
            final rotation =
                ((source['cameraPose']
                            as Map<String, dynamic>)['rotationEulerRadians']
                        as List<dynamic>)
                    .cast<num>();
            final pitch = 90 - rotation[0].toDouble() * 180 / math.pi;
            final detection = detector.detect(
              frame: frame,
              pitchDeg: pitch,
              rollDeg: 0,
              motion: MotionState.walking,
              imageTimestampUs: frame.timestampUs,
            );
            final tracks = tracker.update(
              observations: detection.observations,
              timestampUs: frame.timestampUs,
              relative: true,
            );
            controller.updateYoloTracks(
              _semanticTracks(yoloFrame),
              imgW: 256,
              now: now,
            );
            var matches = 0;
            for (final track in tracks) {
              final match = controller.debugAttachSemanticToTrack(
                track: track,
                imageWidth: 256,
                imageHeight: 256,
                frame: frame,
                now: now,
              );
              if (match != null) matches++;
            }
            final header = ObservationHeader(
              providerId: 'desktop-depth-experiment:${variant['variantId']}',
              modelId: frame.modelId,
              modelHash: frame.modelHash,
              preprocessId: frame.preprocessId,
              sessionGeneration: 1,
              frameId: (source['frameIndex'] as int) + 1,
              sourceTimestampUs: frame.timestampUs,
              producedAtUs: frame.timestampUs + 1000,
              transformId: 'full-fov-upright-256x256',
              confidence: detection.detectorQuality.clamp(0, 1),
              health: ObservationHealth.healthy,
            );
            final result = runtime.ingestGenericGeometry(
              header: header,
              detection: detection,
              tracks: tracks,
              now: now.add(const Duration(milliseconds: 2)),
              orientationValid: true,
              userMoving: true,
              poseQuality: 1,
            );
            expect(result.accepted, isTrue);
            expect(
              result.submittedAction?.delivery,
              SafetyActionDelivery.shadow,
            );
            expect(runtime.arbiter.active, isNull);
            final action = result.decision!.action.kind;
            if (expected == 'stopNow') {
              hazards++;
              if (action == SafetyActionKind.stopNow) stopped++;
              if (action == SafetyActionKind.continueForward) unsafe++;
            } else {
              passable++;
              if (action == SafetyActionKind.stopNow) falseStops++;
            }
            final forward = RelativePolarGrid.fromSnapshot(
              result.snapshot,
              orientationValid: true,
              userMoving: true,
            ).sector(RelativeSectorDirection.forward);
            rows.add({
              'sceneId': entry.key,
              'frameIndex': source['frameIndex'],
              'expectedAction': expected,
              'plannedAction': action.name,
              'ruleId': result.decision!.action.ruleId,
              'geometryReject': detection.rejectReason.name,
              'groundConfidence': detection.groundConfidence,
              'geometryObservationCount': detection.observations.length,
              'semanticMatches': matches,
              'forwardUnknown': forward.unknownProbability,
              'delivery': result.submittedAction!.delivery.name,
            });
          }
        }
        variants.add({
          'variantId': variant['variantId'],
          'frames': rows,
          'summary': {
            'hazardFrames': hazards,
            'hazardFramesWithStop': stopped,
            'hazardFramesWithoutStop': hazards - stopped,
            'unsafeContinueFrames': unsafe,
            'passableFrames': passable,
            'falseStopFrames': falseStops,
          },
        });
      }
      final control =
          variants.singleWhere(
                (v) => v['variantId'] == 'midas_ncnn_control',
              )['summary']!
              as Map<String, int>;
      for (final variant in variants) {
        final summary = variant['summary']! as Map<String, int>;
        final reasons = <String>[
          if (summary['unsafeContinueFrames']! > 0) 'unsafe-continue-on-hazard',
          if (summary['hazardFramesWithStop']! <
              control['hazardFramesWithStop']!)
            'hazard-stop-regression',
          if (summary['falseStopFrames']! > control['falseStopFrames']!)
            'false-stop-regression',
        ];
        variant['qualityAdmission'] = {
          'passed': reasons.isEmpty,
          'rejectionReasons': reasons,
          'policy':
              'zero unsafe continue, hazard stops >= control, false stops <= control',
        };
      }
      final report = {
        'schemaVersion': 1,
        'experimentId': 'dav2-vs-midas-context-shadow-runtime-v1',
        'inferenceReportSha256': _sha('$_root/inference-report.json'),
        'testSha256': _sha('test/depth_anything_shadow_bakeoff_test.dart'),
        'adapterSha256': _sha(
          'lib/services/experimental_relative_depth_replay_provider.dart',
        ),
        'corpusManifestSha256': inference['corpusManifestSha256'],
        'yoloDiagnosticSha256': _sha(_yoloPath),
        'yoloModelId': yolo['modelId'],
        'variants': variants,
        'promotionAllowed': false,
        'scope':
            'real desktop neural maps -> detector/tracker/semantic attachment -> unchanged shadow runtime',
        'timing':
            'functional fixed-clock replay at capture+2ms; not measured latency or on-time hazard evidence',
        'quality':
            'forced diagnostic quality=1; actual provider health and Android alignment not tested',
        'semanticAssumption':
            'same pinned YOLOv8 boxes for every depth variant, all close (upper bound)',
      };
      if (_write) {
        File('$_root/shadow-runtime-report.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      }
      expect(variants, hasLength(5));
      // The diagnostic can successfully measure a rejected model. Only the
      // explicit admission run requires candidates to meet the unchanged gates.
      expect(control['unsafeContinueFrames'], 0);
      for (final variant in variants) {
        final summary = variant['summary']! as Map<String, int>;
        expect(summary['hazardFrames'], 12);
        expect(summary['passableFrames'], 6);
        if (_admissionRequired) {
          expect(
            (variant['qualityAdmission']! as Map<String, Object>)['passed'],
            isTrue,
            reason: '${variant['variantId']}: ${variant['qualityAdmission']}',
          );
        }
      }
    },
    skip: !available && !_required
        ? 'optional real DA-V2 experiment artifacts not prepared'
        : false,
  );
}
