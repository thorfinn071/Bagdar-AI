import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

import 'fixtures/passage_clearance_contract/blender_oracle.dart';

const _reportPath = 'docs/_baseline_logs/synthetic_passage_shadow_replay.json';
const _write = bool.fromEnvironment('BAGDAR_WRITE_PASSAGE_REPORT');
const _check = bool.fromEnvironment('BAGDAR_CHECK_PASSAGE_REPORT');
const _root = 'test/fixtures/spatial_safety/blender-context-ncnn-depth-v1';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test(
    'same NCNN replay with and without independent mesh-oracle passage evidence',
    () {
      final oracle = loadOracleGeometry();
      final depthManifest = _json('$_root/manifest.json');
      final context = _json(
        'test/fixtures/spatial_safety/blender-context-v3/corpus-manifest.json',
      );
      expect(
        depthManifest['sourceCorpusManifestSha256'],
        sha256
            .convert(
              File(
                'test/fixtures/spatial_safety/blender-context-v3/corpus-manifest.json',
              ).readAsBytesSync(),
            )
            .toString(),
      );
      final frames = <String, Map<String, dynamic>>{
        for (final item in depthManifest['frames'] as List)
          '${item['sceneId']}/${item['frameIndex']}':
              item as Map<String, dynamic>,
      };
      final profile = <String, Map<String, dynamic>>{
        for (final item in oracle['frames'] as List)
          '${item['sceneId']}/${item['frameIndex']}':
              item as Map<String, dynamic>,
      };
      final origin = DateTime.utc(2026, 9, 22);
      final runs = <Map<String, Object?>>[];
      for (final augmented in [false, true]) {
        var falseStops = 0,
            safeFrames = 0,
            hazardFrames = 0,
            hazardStops = 0,
            unsafeContinues = 0,
            applied = 0;
        final rows = <Map<String, Object?>>[];
        for (final asset in context['assets'] as List) {
          final sceneId = asset['sceneId'] as String;
          final detector = GenericObstacleDetector();
          final tracker = GenericObstacleTracker();
          const transform = 'upright-rgb-depth-256x256-pitch-8.000';
          final configuration = oracleConfiguration(transform: transform);
          final runtime =
              SpatialSafetyRuntime(
                healthCoordinator: CoreHealthCoordinator(),
                shadowPassage: augmented ? configuration : null,
              )..beginSession(
                1,
                now: origin.subtract(const Duration(milliseconds: 1)),
              );
          final replayFrames =
              File(
                    'test/fixtures/spatial_safety/blender-context-v3/scenes/$sceneId/frames.jsonl',
                  )
                  .readAsLinesSync()
                  .map((line) => jsonDecode(line) as Map<String, dynamic>)
                  .toList();
          for (final frame in asset['frames'] as List) {
            final index = frame['frameIndex'] as int;
            final stamp = origin
                .add(Duration(milliseconds: frame['capturedOffsetMs'] as int))
                .microsecondsSinceEpoch;
            final map = frames['$sceneId/$index']!;
            final geometryFrame = profile['$sceneId/$index']!;
            expect(map['rgbSha256'], frame['rgb']['sha256']);
            expect(geometryFrame['rgbSha256'], frame['rgb']['sha256']);
            final bytes = File('$_root/${map['mapPath']}').readAsBytesSync();
            expect(sha256.convert(bytes).toString(), map['mapSha256']);
            expect(bytes.length, 256 * 256 * 4);
            final data = ByteData.sublistView(bytes);
            final raw = Float32List.fromList([
              for (var i = 0; i < 256 * 256; i++)
                data.getFloat32(i * 4, Endian.little),
            ]);
            final relative = DepthMapOps.normalizeRelativeProximity(raw);
            final depth = DepthFrame(
              values: relative,
              confidence01: Float32List.fromList(
                List.filled(relative.length, 1),
              ),
              width: 256,
              height: 256,
              timestampUs: stamp,
              provider: DepthProviderKind.ncnnRelative,
              semantics: DepthValueSemantics.relativeProximity,
              modelId: depthManifest['modelId'] as String,
              modelHash: 'pinned-ncnn-replay',
              preprocessId: depthManifest['preprocessId'] as String,
              cropTopFraction: 0,
              frameQuality: 1,
              alignedToImage: true,
            );
            final detection = detector.detect(
              frame: depth,
              pitchDeg: 8,
              rollDeg: 0,
              motion: MotionState.walking,
              imageTimestampUs: stamp,
            );
            final tracks = tracker.update(
              observations: detection.observations,
              timestampUs: stamp,
              relative: true,
            );
            final now = DateTime.fromMicrosecondsSinceEpoch(stamp + 2000);
            final header = ObservationHeader(
              providerId: 'desktop-ncnn-midas-depth',
              modelId: depth.modelId,
              modelHash: depth.modelHash,
              preprocessId: depth.preprocessId,
              sessionGeneration: 1,
              frameId: index + 1,
              sourceTimestampUs: stamp,
              producedAtUs: stamp + 1000,
              transformId: transform,
              confidence: detection.detectorQuality,
              health: ObservationHealth.healthy,
            );
            final aperture = detection.unknownReasons.contains(
              ObstacleUnknownReason.unverifiedAperture,
            );
            // The decision to request geometry uses the detector hypothesis,
            // NEVER the scene ID, state or ground-truth action.
            final observation = augmented && aperture
                ? oracleSource(
                    geometry: geometryFrame['geometry'] as Map<String, dynamic>,
                    configuration: configuration,
                    capturedAtUs: stamp,
                    frameId: index + 1,
                  ).observationFor(
                    PassageEvaluationContext(
                      nowUs: stamp + 2000,
                      timestampDomain:
                          PassageTimestampDomain.utcEpochMicroseconds,
                      sessionGeneration: 1,
                      frameId: index + 1,
                      rgbTimestampUs: stamp,
                      transformId: transform,
                    ),
                  )
                : null;
            final result = runtime.ingestGenericGeometry(
              header: header,
              detection: detection,
              tracks: tracks,
              now: now,
              orientationValid: true,
              userMoving: true,
              poseQuality: 1,
              passageObservation: observation,
            );
            expect(result.accepted, isTrue);
            expect(
              result.submittedAction!.delivery,
              SafetyActionDelivery.shadow,
            );
            expect(runtime.arbiter.active, isNull);
            final action = result.decision!.action.kind;
            final expected =
                (replayFrames[index]['sectors']['forward']['occupancyProbability']
                        as num) >=
                    0.65 ||
                (replayFrames[index]['sectors']['forward']['movingThreatRisk']
                        as num) >=
                    0.55;
            // Labels are used only HERE, after producer/runtime/planner decisions.
            if (expected) {
              hazardFrames++;
              if (action == SafetyActionKind.stopNow) hazardStops++;
              if (action == SafetyActionKind.continueForward) unsafeContinues++;
            } else {
              safeFrames++;
              if (action == SafetyActionKind.stopNow) falseStops++;
            }
            if (result.passageClearanceApplied) applied++;
            rows.add({
              'sceneId': sceneId,
              'frameIndex': index,
              'expectedHazard': expected,
              'action': action.name,
              'ruleId': result.decision!.action.ruleId,
              'delivery': result.submittedAction!.delivery.name,
              'apertureHypothesis': aperture,
              'passageApplied': result.passageClearanceApplied,
              'passage': result.passageClearance?.toDiagnosticMap(),
            });
          }
        }
        expect(hazardFrames, 12);
        expect(hazardStops, 12);
        expect(unsafeContinues, 0);
        expect(safeFrames, 6);
        expect(falseStops, augmented ? 0 : 3);
        expect(applied, augmented ? 3 : 0);
        runs.add({
          'mode': augmented
              ? 'ncnn-plus-full-scene-geometry-oracle'
              : 'ncnn-control',
          'hazardFrames': hazardFrames,
          'hazardStops': hazardStops,
          'unsafeContinues': unsafeContinues,
          'traversableFrames': safeFrames,
          'falseStops': falseStops,
          'passageApplications': applied,
          'frames': rows,
        });
      }
      final report = {
        'schemaVersion': 1,
        'benchmarkId': 'synthetic-passage-shadow-augmentation-v1',
        'scope':
            'NCNN relative geometry plus optional omniscient Blender mesh oracle; not camera-only clearance or phone evidence',
        'sourceSha256': {
          for (final path in [
            'lib/safety/perception/passage_clearance.dart',
            'test/fixtures/spatial_safety/blender-context-v3/corpus-manifest.json',
            'test/fixtures/spatial_safety/blender-context-ncnn-depth-v1/manifest.json',
            oracleGeometryPath,
            'tool/blender/export_passage_geometry.py',
            'tool/model_benchmark/synthetic_passage_source.dart',
            'test/fixtures/passage_clearance_contract/blender_oracle.dart',
            'test/synthetic_passage_shadow_replay_test.dart',
            'test/passage_clearance_shadow_test.dart',
            'lib/safety/runtime/passage_clearance_shadow.dart',
            'lib/safety/runtime/spatial_safety_runtime.dart',
            'lib/safety/world/generic_geometry_scene_adapter.dart',
            'lib/safety/world/local_scene_model.dart',
          ])
            path: sha256.convert(File(path).readAsBytesSync()).toString(),
        },
        'runs': runs,
        'promotionAllowed': false,
        'cameraOnlyModelImprovementEstablished': false,
        'deviceCalibrationEstablished': false,
      };
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (_check) expect(File(_reportPath).readAsStringSync(), rendered);
      if (_write) File(_reportPath).writeAsStringSync(rendered);
    },
  );
}
