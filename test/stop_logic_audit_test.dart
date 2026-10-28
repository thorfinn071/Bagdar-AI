import 'dart:convert';
import 'dart:io';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_visible_body_fixture.dart';
import 'harness/stop_cause_replay.dart';

// All state resets below are diagnostic interventions, never recovery policy.
const _lanes = <String, ({bool calibrated, bool fresh, bool moving})>{
  'appContinuous': (calibrated: false, fresh: false, moving: true),
  'appFreshRuntime': (calibrated: false, fresh: true, moving: true),
  'appFreshStationary': (calibrated: false, fresh: true, moving: false),
  'calibratedContinuous': (calibrated: true, fresh: false, moving: true),
  'calibratedFreshRuntime': (calibrated: true, fresh: true, moving: true),
  'calibratedFreshStationary': (calibrated: true, fresh: true, moving: false),
};

String _digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

Map<String, Object?> _track(GenericObstacleTrack t) => {
  'id': t.id,
  'hits': t.hits,
  'misses': t.misses,
  'age': t.age,
  'confirmed': t.confirmed,
  'proximityHistory': List.of(t.proximityHist),
  'metricHistory': List.of(t.metricHist),
  'timestamps': List.of(t.timestampUsHist),
  'hitWindow': List.of(t.hitWindow),
  'observation': {
    'geometry': t.last.geometry.name,
    'zone': t.last.zone.name,
    'bounds': [
      t.last.normalizedBounds.left,
      t.last.normalizedBounds.top,
      t.last.normalizedBounds.right,
      t.last.normalizedBounds.bottom,
    ],
    'confidence': t.last.confidence,
    'overlap': t.last.corridorOverlap,
    'proximity': t.last.relativeProximity,
    'distanceM': t.last.nearestDistanceM,
    'approachRateMps': t.last.approachRateMps,
    'timeToCollisionS': t.last.timeToCollisionS,
    'source': t.last.source.name,
    'pixelCount': t.last.pixelCount,
    'edgeOnly': t.last.edgeOnly,
    'support': t.last.cameraSupport?.indices,
    'semantic': t.last.semantic == null
        ? null
        : {
            'label': t.last.semantic!.label,
            'confidence': t.last.semantic!.confidence,
            'id': t.last.semantic!.yoloTrackId,
          },
  },
};

Map<String, String> _fingerprint() => {
  for (final path in [
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path),
    'test/stop_logic_audit_test.dart',
    'test/harness/stop_cause_replay.dart',
    'test/harness/blender_visible_body_fixture.dart',
    '$pairedBodyRoot/manifest.json',
    '$pairedRgbRoot/corpus-manifest.json',
    'scratch/closed-volume-control-2026-10-11/replay.json',
    'scratch/volume-holdout-2026-10-10/replay.json',
  ]..sort())
    path.replaceAll('\\', '/'): bodySha(path),
};

// A ceiling probe: even ideal RELATIVE inputs contain no physical clearance
// certificate. This is constructed input, not a camera or model measurement.
List<Map<String, Object?>> _relativeCeilingProbes() {
  final rows = <Map<String, Object?>>[];
  final stamp = DateTime.utc(2026, 10, 19).microsecondsSinceEpoch;
  for (final moving in [true, false]) {
    final runtime = ConfidenceAuthoritySpatialRuntime(
      healthCoordinator: CoreHealthCoordinator(),
    )..beginSession(1, now: DateTime.fromMicrosecondsSinceEpoch(stamp - 1000));
    const detection = GenericObstacleDetectResult(
      observations: [],
      rejectReason: ObstacleRejectReason.none,
      detectorQuality: 1,
      groundConfidence: 1,
      surfaceEvidence: CorridorSurfaceEvidence(
        observedFraction: 1,
        continuity: 1,
        confidence: 1,
      ),
      corridorCoverage: CorridorDepthCoverage(
        upperObservedFraction: 1,
        lowerObservedFraction: 1,
      ),
    );
    final header = ObservationHeader(
      providerId: 'constructed-relative-ceiling',
      modelId: 'constructed',
      modelHash: 'constructed',
      preprocessId: 'constructed',
      sessionGeneration: 1,
      frameId: 1,
      sourceTimestampUs: stamp,
      producedAtUs: stamp + 1000,
      transformId: 'constructed',
      confidence: 1,
      health: ObservationHealth.healthy,
    );
    final result = runtime.ingestGenericGeometry(
      header: header,
      detection: detection,
      tracks: const [],
      now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
      orientationValid: true,
      userMoving: moving,
      poseQuality: 1,
    );
    final forward = result.snapshot.polarSectors.singleWhere(
      (s) => s.id == 'forward',
    );
    expect(result.accepted, true);
    expect(result.submittedAction!.delivery.name, 'shadow');
    expect(runtime.arbiter.active, isNull);
    rows.add({
      'sampleKind': 'constructedRelativeCeiling',
      'moving': moving,
      'action': result.decision!.action.kind.name,
      'ruleId': result.decision!.action.ruleId,
      'unknown': forward.unknownProbability,
      'occupancy': forward.occupancyProbability,
      'drop': forward.dropProbability,
      'positiveCorridor': result.decision!.candidates
          .singleWhere((c) => c.direction.name == 'forward')
          .hasPositiveEvidence,
      'delivery': result.submittedAction!.delivery.name,
      'arbiterActive': false,
      'physicalMeasurement': false,
    });
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('relative input ceiling identifies absent clearance authority', () {
    final probes = _relativeCeilingProbes();
    for (final row in probes) {
      expect(row['unknown'], greaterThanOrEqualTo(.65));
      expect(row['occupancy'], 0);
      expect(row['drop'], 0);
      expect(row['positiveCorridor'], false);
    }
    expect(probes.first['action'], 'stopNow');
    expect(probes.last['action'], 'holdAndScan');
  });

  test(
    'same snapshots separate app configuration, fusion and planner history',
    () {
      const output = String.fromEnvironment('BAGDAR_STOP_LOGIC_OUTPUT');
      const baselinePath = String.fromEnvironment('BAGDAR_STOP_LOGIC_BASELINE');
      if (output.isEmpty || baselinePath.isEmpty) {
        fail('Explicit new output directory and baseline receipt required');
      }
      final target = File('$output/audit.json');
      expect(target.existsSync(), false, reason: 'Preserve previous audit');
      final before = _fingerprint();
      final baselineHash = bodySha(baselinePath);
      final baseline = (bodyJson(baselinePath)['frames'] as List)
          .cast<Map>()
          .where(
            (r) =>
                r['corpus'] == 'paired-visible-body-v1' &&
                r['sampleKind'] == 'knownSyntheticReplay',
          )
          .toList();
      expect(baseline.length, 132);
      final fixture = PairedBodyFixture();
      final rows = <Map<String, Object?>>[];
      var comparisons = 0;
      for (final seq in (fixture.corpus['sequences'] as List).cast<Map>()) {
        final id = seq['sceneId'] as String;
        final optics = (fixture.manifest['sequences'] as List)
            .cast<Map>()
            .singleWhere((s) => s['sceneId'] == id);
        final calibration = fixture.calibration(id);
        ConfidenceAuthoritySpatialRuntime engine(bool calibrated) =>
            ConfidenceAuthoritySpatialRuntime(
              healthCoordinator: CoreHealthCoordinator(),
              planner: calibrated ? CoverageAwareStopGuidance() : null,
              shadowPassage: calibrated
                  ? PassageClearanceShadowConfiguration(
                      calibration: calibration,
                      request: pairedBodyRequest,
                      policy: pairedBodyPolicy,
                      requireCameraEvidence: true,
                      associateCameraTracks: true,
                      cameraTrackModelHash: fixture.relativeHash,
                    )
                  : null,
            )..beginSession(
              1,
              now: DateTime.fromMicrosecondsSinceEpoch(pairedBodyStamp - 1000),
            );
        final continuous = {
          for (final lane in _lanes.entries.where((e) => !e.value.fresh))
            lane.key: engine(lane.value.calibrated),
        };
        final detector = GenericObstacleDetector(
          collectOpeningDiagnostics: true,
          collectCameraSupport: true,
        );
        final tracker = GenericObstacleTracker();
        for (final original in (seq['frames'] as List).cast<Map>()) {
          final index = original['frameIndex'] as int;
          final packet = (optics['single'] as List)[index] as Map;
          expect(packet['rgbSha256'], (original['rgb'] as Map)['sha256']);
          final depth = fixture.visible(packet, id);
          final stamp = depth.capturedAtUs, now = stamp + 2000;
          final relative = fixture.relative(
            original,
            id,
            stamp,
            canonicalPreprocess: true,
          );
          final detection = detector.detect(
            frame: relative,
            pitchDeg: ((original['cameraPose'] as Map)['pitchDownDeg'] as num)
                .toDouble(),
            rollDeg: 0,
            motion: MotionState.walking,
            imageTimestampUs: stamp,
          );
          final tracks = tracker.update(
            observations: detection.observations,
            timestampUs: stamp,
            relative: true,
          );
          final rawTracks = tracks.map(_track).toList();
          final tracksHash = _digest(rawTracks);
          final header = ObservationHeader(
            providerId: 'desktop-midas',
            modelId: relative.modelId,
            modelHash: relative.modelHash,
            preprocessId: relative.preprocessId,
            sessionGeneration: 1,
            frameId: index + 1,
            sourceTimestampUs: stamp,
            producedAtUs: stamp + 1000,
            transformId: fixture.transform(id),
            confidence: detection.detectorQuality.clamp(0, 1),
            health: ObservationHealth.healthy,
          );
          final headerHash = _digest(header.toDiagnosticMap());
          final source = CameraPassageClearanceSource(
            calibration: calibration,
            request: pairedBodyRequest,
            frames: [depth],
            producedAtUs: stamp + 1000,
          );
          final context = PassageEvaluationContext(
            nowUs: now,
            timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
            sessionGeneration: 1,
            frameId: index + 1,
            rgbTimestampUs: stamp,
            transformId: fixture.transform(id),
          );
          final observation = source.observationFor(context);
          final proof =
              const PassageClearanceEvaluator(
                policy: pairedBodyPolicy,
              ).evaluate(
                request: pairedBodyRequest,
                context: context,
                calibration: calibration,
                observation: observation,
              );
          for (final lane in _lanes.entries) {
            final options = lane.value;
            final runtime = options.fresh
                ? engine(options.calibrated)
                : continuous[lane.key]!;
            final result = runtime.ingestGenericGeometry(
              header: header,
              detection: detection,
              tracks: tracks,
              now: DateTime.fromMicrosecondsSinceEpoch(now),
              orientationValid: true,
              userMoving: options.moving,
              poseQuality: 1,
              passageObservation: options.calibrated ? observation : null,
              cameraTrackInput: options.calibrated
                  ? CameraTrackAssociationInput(
                      rgbHeader: header,
                      depth: depth,
                      imageGeometry: CameraTrackImageGeometry(
                        cameraId: depth.cameraId,
                        width: depth.width,
                        height: depth.height,
                        fx: depth.fx,
                        fy: depth.fy,
                        cx: depth.cx,
                        cy: depth.cy,
                        rotation: depth.rotation,
                        originM: depth.originM,
                      ),
                    )
                  : null,
            );
            expect(result.accepted, true);
            expect(result.submittedAction!.delivery.name, 'shadow');
            expect(runtime.arbiter.active, isNull);
            expect(_digest(tracks.map(_track).toList()), tracksHash);
            expect(_digest(header.toDiagnosticMap()), headerHash);
            final freshPlanner = options.calibrated
                ? CoverageAwareStopGuidance()
                : ConfidenceAuthorityGuidance();
            final replayedDecision = freshPlanner.evaluate(
              RelativePolarGrid.fromSnapshot(
                result.snapshot,
                orientationValid: true,
                userMoving: options.moving,
              ),
              now: DateTime.fromMicrosecondsSinceEpoch(now),
            );
            final forward = result.snapshot.polarSectors.singleWhere(
              (s) => s.id == 'forward',
            );
            final telemetry = captureStopTelemetry(
              result: result,
              header: header,
              detection: detection,
              corpus: 'paired-visible-body-v1',
              sceneId: id,
              variant: lane.key,
              sampleKind: options.fresh
                  ? 'diagnosticStateIntervention'
                  : 'knownSyntheticReplay',
              nowUs: now,
              moving: options.moving,
              producerProof: options.calibrated ? proof : null,
              observation: options.calibrated ? observation : null,
              source: options.calibrated ? source : null,
            );
            rows.add({
              ...telemetry,
              'runtimeHistoryReset': options.fresh,
              'calibratedSourceSupplied': options.calibrated,
              'trackerHistoryReset': false,
              'detectorMotionInput': 'walking_in_all_lanes',
              'rawTracksSha256': tracksHash,
              'headerSha256': headerHash,
              'tracks': rawTracks,
              'detectorObservationCount': detection.observations.length,
              'cameraTrackAssociations': {
                for (final entry in runtime.cameraTrackAssociations.entries)
                  entry.key.toString(): entry.value.toDiagnosticMap(),
              },
              'forwardHazardIds': [
                for (final hazard in result.snapshot.hazardTracks)
                  if (hazard.elementId == 'forward') hazard.id,
              ],
              'forwardSector': {
                'unknown': forward.unknownProbability,
                'occupancy': forward.occupancyProbability,
                'drop': forward.dropProbability,
                'movingThreat': forward.movingThreatRisk,
                'sources': forward.sourceMask.toList()..sort(),
              },
              'sameSnapshotFreshPlanner': {
                'action': replayedDecision.action.kind.name,
                'ruleId': replayedDecision.action.ruleId,
              },
            });
            if (lane.key == 'calibratedContinuous') {
              final old = baseline.singleWhere(
                (r) => r['sceneId'] == id && r['frameId'] == index + 1,
              );
              for (final field in [
                'action',
                'ruleId',
                'passageStatus',
                'passageApplied',
                'corridorRejections',
              ]) {
                expect(
                  telemetry[field],
                  old[field],
                  reason: '$id/${index + 1}/$field',
                );
              }
              comparisons++;
            }
          }
        }
      }
      // Scene labels are read only after all runtime and planner decisions.
      final labels = {
        for (final seq in (fixture.corpus['sequences'] as List).cast<Map>())
          seq['sceneId'] as String:
              jsonDecode(
                    utf8.decode(
                      bodyAsset(pairedRgbRoot, seq['annotations'] as Map),
                    ),
                  )
                  as Map,
      };
      final scored = [
        for (final row in rows)
          {
            ...row,
            'scoringOnly': {
              'referencePassable': labels[row['sceneId']]!['referencePassable'],
              'physicalHazard': labels[row['sceneId']]!['physicalHazard'],
            },
          },
      ];
      expect(comparisons, 132);
      expect(scored.length, 792);
      expect(_fingerprint(), before);
      expect(bodySha(baselinePath), baselineHash);
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'scope': 'known synthetic replay and diagnostic state interventions',
          'appConfigurationParity':
              'runtime constructor and absent passage inputs only; not full Android pipeline',
          'poseQuality':
              'fixed ideal 1.0 in every lane; not measured phone pose',
          'clockMode': 'fixed_replay_capture_plus_2000us',
          'captureToDecisionMs': null,
          'namedDeviceRuntime': 'not_run',
          'controlledWalking': 'not_run',
          'ordinaryCameraWired': false,
          'promotionAllowed': false,
          'falseStopReductionEstablished': false,
          'newHoldout': false,
          'newNeuralInference': false,
          'freshnessPolicyUs': 100000,
          'baselineSha256': baselineHash,
          'baselineComparisons': comparisons,
          'preservedSourceHashes': before,
          'relativeCeilingProbes': _relativeCeilingProbes(),
          'frames': scored,
        }),
      );
    },
    skip: !const bool.fromEnvironment('BAGDAR_STOP_LOGIC_REPLAY'),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
