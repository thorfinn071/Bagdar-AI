import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_worker.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_shadow_adapter.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';
import '../../tool/model_benchmark/fast_camera_motion_fixture.dart';
import 'camera_visible_passage_fixture.dart';

Future<void> verifyFastMotionShadow({bool write = false}) async {
  final fixture = VisibleFixture(root: fastCorpus);
  final baseline = visibleJson('docs/_baseline_logs/camera_scale_motion.json');
  final sequences = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List)
          .cast<Map<String, dynamic>>()
          .where((l) => l['split'] == 'test')) {
    final id = layout['id'] as String;
    final previous = (baseline['sequences'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((s) => s['layoutId'] == id && s['mode'] == 'scale-motion');
    final expected = {
      for (final r
          in (previous['decisions'] as List).cast<Map<String, dynamic>>())
        r['frameId']: r,
    };
    final frames = fixture
        .frames(layout)
        .where((f) => (layout['decisionFrameIds'] as List).contains(f.frameId));
    final inputs = frames.map((f) => fastInput(fixture, layout, f)).toList();
    var now = inputs.first.camera.depth.capturedAtUs + 2000;
    final worker = await CameraFastMotionWorker.start(
      calibration: fixture.calibration(),
      rgbContract: fastRgbContract,
      clockUs: () => now,
    );
    worker.beginSession(1);
    final scene = CameraMetricMotionShadowScene();
    final runtime = SpatialSafetyRuntime(
      healthCoordinator: CoreHealthCoordinator(),
      sceneModel: scene,
      minimumTickInterval: Duration.zero,
      tickActionCooldown: Duration.zero,
    )..beginSession(1, now: DateTime.fromMicrosecondsSinceEpoch(now - 1));
    final rows = <Map<String, Object?>>[];
    try {
      for (final input in inputs) {
        final f = input.camera.depth;
        now = f.capturedAtUs + 2000;
        final outcome = await worker.offer(input);
        expect(outcome.admitted, true);
        expect(
          outcome.result!.toDiagnosticMap(),
          expected[f.frameId]!['scaleMotion'],
        );
        final risk = applyFastMotionShadow(worker, scene, outcome);
        final at = DateTime.fromMicrosecondsSinceEpoch(now);
        final update = scene.update(
          LocalSceneUpdate(
            coordinateMode: SceneCoordinateMode.relative,
            at: at,
            validUntil: DateTime.fromMicrosecondsSinceEpoch(
              f.capturedAtUs + 100000,
            ),
            poseQuality: 1,
            sensorHealth: SceneSensorHealth({
              'rgb-metric-motion': SceneSensorState.healthy,
              'relative-depth-nn': SceneSensorState.unavailable,
            }),
            useIndependentEvidenceClocks: true,
            evidence: [
              for (final element in ['left', 'forward', 'right'])
                SpatialEvidence(
                  elementId: element,
                  coordinateMode: SceneCoordinateMode.relative,
                  sourceId: 'unavailable-relative-depth',
                  source: SpatialEvidenceSource.depth,
                  observedAt: at,
                  validUntil: DateTime.fromMicrosecondsSinceEpoch(
                    f.capturedAtUs + 100000,
                  ),
                  observedFraction: 0,
                  confidence: 1,
                  unknownProbability: 1,
                ),
            ],
          ),
        );
        expect(update.accepted, true);
        final result = runtime.tick(
          now: at,
          userMoving: expected[f.frameId]!['userMoving'] as bool,
          orientationValid: true,
        );
        expect(result.submittedAction!.delivery.name, 'shadow');
        expect(runtime.arbiter.active, isNull);
        expect(result.decision!.action.kind.name, isNot('continueForward'));
        expect(result.passageClearanceApplied, false);
        final applied = result.snapshot.polarSectors.any(
          (s) => s.sourceMask.contains('visible-metric-motion:1:${f.frameId}'),
        );
        expect(applied, risk);
        rows.add({
          'frameId': f.frameId,
          'diagnosticParity': true,
          'motionRisk': risk,
          'motionApplied': applied,
          'ageAtApplyUs': now - f.capturedAtUs,
          'action': result.decision!.action.kind.name,
          'delivery': 'shadow',
          'physicalHazard': expected[f.frameId]!['physicalHazard'],
          'sufficientObservationLabel':
              expected[f.frameId]!['sufficientObservationLabel'],
          'passageApplied': false,
          'unknownRetained':
              result.snapshot.polarSectors
                  .firstWhere((s) => s.id == 'forward')
                  .unknownProbability >=
              .9,
        });
      }
      sequences.add({
        'layoutId': id,
        'frames': rows,
        'finalAction': rows.last['action'],
        'sufficientPassable':
            previous['physicalHazard'] != true &&
            (previous['final'] as Map)['sufficientObservationLabel'] == true,
      });
    } finally {
      worker.close();
    }
  }
  final rows = sequences
      .expand((s) => (s['frames'] as List).cast<Map<String, Object?>>())
      .toList();
  final passable = sequences
      .where((s) => s['sufficientPassable'] == true)
      .toList();
  final report = {
    'scope':
        'known 67-frame regression, independent motion in real shadow scene/planner/arbiter with NN unavailable; fixed clock, no clearance capability',
    'promotionAllowed': false,
    'newIndependentHoldout': false,
    'nnAwaited': false,
    'captureToCommandMeasured': false,
    'summary': {
      'frames': rows.length,
      'diagnosticMatches': rows.length,
      'freshMotionAppliedFrames': rows
          .where((r) => r['motionApplied'] == true)
          .length,
      'staleApplications': rows
          .where(
            (r) =>
                r['motionApplied'] == true &&
                (r['ageAtApplyUs'] as int) > 100000,
          )
          .length,
      'unsafeContinues': rows
          .where(
            (r) =>
                r['physicalHazard'] == true && r['action'] == 'continueForward',
          )
          .length,
      'clearances': rows.where((r) => r['passageApplied'] == true).length,
      'unknownRetainedFrames': rows
          .where((r) => r['unknownRetained'] == true)
          .length,
      'sufficientPassableSequences': passable.length,
      'falseStopSequences': passable
          .where((s) => s['finalAction'] == 'stopNow')
          .length,
      'falseHoldSequences': passable
          .where((s) => s['finalAction'] == 'holdAndScan')
          .length,
    },
    'sequences': sequences,
  };
  const path = 'docs/_baseline_logs/camera_fast_motion_shadow.json';
  if (write) {
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  } else {
    expect(jsonEncode(report), jsonEncode(visibleJson(path)));
  }
}
