import 'dart:io';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
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

import 'blender_synchronized_rig_fixture.dart' show rigCopyFrame;
import 'blender_visible_body_fixture.dart';
import 'sequence_first_return_fixture.dart';
import 'track_first_return_fixture.dart' show firstReturnCopy;
import 'track_first_return_pixel_audit.dart';

CameraTrackAssociationInput sequenceAssociationInput(
  ObservationHeader header,
  CameraVisibleDepthFrame packet,
  CameraVisibleDepthFrame original,
) => CameraTrackAssociationInput(
  rgbHeader: header,
  depth: packet,
  imageGeometry: CameraTrackImageGeometry(
    cameraId: original.cameraId,
    width: original.width,
    height: original.height,
    fx: original.fx,
    fy: original.fy,
    cx: original.cx,
    cy: original.cy,
    rotation: original.rotation,
    originM: original.originM,
  ),
);

Map<String, Object?> runSequenceFirstReturnReplay() {
  final fixture = SequenceReturnFixture(), base = fixture.base;
  ConfidenceAuthoritySpatialRuntime runtime(String mode) =>
      ConfidenceAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        planner: CoverageAwareStopGuidance(),
        shadowPassage: PassageClearanceShadowConfiguration(
          calibration: base.calibration(
            fixture.captures.first.batch,
            mode == 'single-original' ? 'single' : 'rig',
          ),
          request: pairedBodyRequest,
          policy: pairedBodyPolicy,
          requireCameraEvidence: true,
          associateCameraTracks: true,
          cameraTrackModelHash: fixture.pinned.relativeHash,
        ),
      );

  final faultAt = fixture.captures[5], at = faultAt.original.capturedAtUs;
  final input = faultAt.channels;
  final badSources = <String, PassageClearanceObservation?>{};
  final channelFaults = <String, List<CameraHeightEnvelopeFrame>>{
    'missingChannel': input.take(11).toList(),
    'reorderedChannels': input.reversed.toList(),
    'captureSkew1us': [
      rigCopyFrame(input.first, capturedAtUs: at + 1),
      ...input.skip(1),
    ],
    'relativeUnits': [
      rigCopyFrame(input.first, units: PassageUnits.relativeProximity),
      ...input.skip(1),
    ],
    'foreignPose': [
      rigCopyFrame(input.first, rotation: input.last.depth.rotation),
      ...input.skip(1),
    ],
    'incompleteFirstZ': [
      rigCopyFrame(input.first, firstZLowerM: []),
      ...input.skip(1),
    ],
    'providerFailed': [
      rigCopyFrame(input.first, providerHealthy: false),
      ...input.skip(1),
    ],
    'noReturns': [
      for (final f in input)
        rigCopyFrame(
          f,
          valid: List.filled(f.depth.valid.length, false),
          rangeM: List.filled(f.depth.valid.length, double.nan),
          freeZLowerM: List.filled(f.depth.valid.length, double.nan),
          surfaceZUpperM: List.filled(f.depth.valid.length, double.nan),
          heightLowerM: List.filled(f.depth.valid.length, double.nan),
          heightUpperM: List.filled(f.depth.valid.length, double.nan),
          firstZLowerM: List.filled(f.depth.valid.length, double.nan),
        ),
    ],
  };
  for (final e in channelFaults.entries) {
    badSources[e.key] = base
        .source(faultAt.batch, e.value, at + 1000)
        .observationFor(base.context(faultAt.batch, at + 2000));
  }
  badSources['unestablishedMotion'] = base
      .source(faultAt.batch, input, at + 1000, staticScene: false)
      .observationFor(base.context(faultAt.batch, at + 2000));
  // A previously missing, now certified pixel in the actual full support.
  final repaired = bodyAsset(
    base.root,
    (faultAt.batch['primary'] as Map)['repairMask'] as Map,
  );
  final repairMask = gzip.decode(repaired);
  final repairIndex = (faultAt.selection['supportPixels'] as List)
      .cast<int>()
      .firstWhere((i) => repairMask[i] == 1);
  final badUpper = List<double>.from(faultAt.supplemental.surfaceZUpperM)
    ..[repairIndex] = double.nan;
  final badRange = List<double>.from(faultAt.supplemental.rangeM)
    ..[repairIndex] = double.nan;
  final badValid = List<bool>.from(faultAt.supplemental.valid)
    ..[repairIndex] = false;
  final primaryFaults = <String, CameraVisibleDepthFrame>{
    'primaryLostUpper': firstReturnCopy(faultAt.supplemental, upper: badUpper),
    'primaryInvalidRange': firstReturnCopy(
      faultAt.supplemental,
      range: badRange,
    ),
    'primaryInvalidReturn': firstReturnCopy(
      faultAt.supplemental,
      valid: badValid,
    ),
    'primaryRelativeUnits': firstReturnCopy(
      faultAt.supplemental,
      units: PassageUnits.relativeProximity,
    ),
    'primaryForeignPose': firstReturnCopy(
      faultAt.supplemental,
      rotation: input.first.depth.rotation,
    ),
    'primaryForeignModel': firstReturnCopy(
      faultAt.supplemental,
      modelHash: 'foreign-model',
    ),
    'primaryForeignTransform': firstReturnCopy(
      faultAt.supplemental,
      transformId: 'foreign-transform',
    ),
    'primaryOldCapture': firstReturnCopy(
      faultAt.supplemental,
      capturedAtUs: at - 100001,
    ),
  };

  List<Map<String, Object?>> run(
    String mode, {
    String? fault,
    bool freshRuntime = false,
    bool freshAll = false,
    bool geometryAudit = false,
  }) {
    var detector = GenericObstacleDetector(
      collectCameraSupport: true,
      collectOpeningDiagnostics: true,
    );
    var tracker = GenericObstacleTracker();
    var engine = runtime(mode), sessions = 0;
    final rows = <Map<String, Object?>>[];
    for (var index = 0; index < fixture.captures.length; index++) {
      final c = fixture.captures[index], t = c.original.capturedAtUs;
      if (index == 0 || freshRuntime || freshAll) {
        engine = runtime(mode);
        engine.beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(t - 1000),
        );
        sessions++;
      }
      if (freshAll) {
        detector = GenericObstacleDetector(
          collectCameraSupport: true,
          collectOpeningDiagnostics: true,
        );
        tracker = GenericObstacleTracker();
      }
      final detection = detector.detect(
        frame: c.relative,
        pitchDeg: 12,
        rollDeg: 0,
        motion: MotionState.walking,
        imageTimestampUs: t,
      );
      final tracks = tracker.update(
        observations: detection.observations,
        timestampUs: t,
        relative: true,
      );
      final recordedTracks = <Map<String, Object?>>[
        for (final tr in tracks)
          {
            'id': tr.id,
            'hits': tr.hits,
            'age': tr.age,
            'misses': tr.misses,
            'confirmed': tr.confirmed,
            'approachTrend': tr.approachTrend(),
            'timestamps': List<int>.from(tr.timestampUsHist),
            'componentSupport': List<int>.from(tr.last.cameraSupport!.indices),
          },
      ];
      if (!freshAll) {
        final expected = (c.selection['tracks'] as List).cast<Map>();
        if (recordedTracks.length != expected.length) {
          throw StateError('Tracker count drift');
        }
        for (var j = 0; j < expected.length; j++) {
          for (final key in [
            'id',
            'hits',
            'age',
            'misses',
            'confirmed',
            'approachTrend',
          ]) {
            if (recordedTracks[j][key] != expected[j][key]) {
              throw StateError('Tracker history drift $index/$key');
            }
          }
          for (final key in ['timestamps', 'componentSupport']) {
            final a = recordedTracks[j][key] as List,
                b = expected[j][key] as List;
            if (a.length != b.length ||
                List.generate(a.length, (k) => a[k] == b[k]).contains(false)) {
              throw StateError('Track support or history drift');
            }
          }
        }
      }
      final header = ObservationHeader(
        providerId: 'desktop-midas',
        modelId: c.relative.modelId,
        modelHash: c.relative.modelHash,
        preprocessId: c.relative.preprocessId,
        sessionGeneration: 1,
        frameId: c.original.frameId,
        sourceTimestampUs: t,
        producedAtUs: t + 1000,
        transformId: base.transform(c.batch),
        confidence: detection.detectorQuality.clamp(0, 1),
        health: ObservationHealth.healthy,
      );
      var packet = mode == 'rig-supplemental' ? c.supplemental : c.original;
      PassageClearanceObservation? observation = mode == 'single-original'
          ? c.single
          : c.rig;
      var age = 2000;
      if (fault != null && index == 5) {
        if (badSources.containsKey(fault)) observation = badSources[fault];
        if (primaryFaults.containsKey(fault)) packet = primaryFaults[fault]!;
        if (fault == 'staleOriginalCapture') age = 100001;
      }
      final previousRevision = engine.sceneModel.revision;
      final result = engine.ingestGenericGeometry(
        header: header,
        detection: detection,
        tracks: tracks,
        now: DateTime.fromMicrosecondsSinceEpoch(t + age),
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
        passageObservation: observation,
        cameraTrackInput: sequenceAssociationInput(header, packet, c.original),
      );
      if (!result.accepted ||
          result.submittedAction?.delivery.name != 'shadow' ||
          engine.arbiter.active != null ||
          engine.lastFrameId != index + 1 ||
          engine.sceneModel.revision <= previousRevision ||
          (!freshRuntime && !freshAll && sessions != 1)) {
        throw StateError(
          'Unexpected runtime authority, reset or rejected frame',
        );
      }
      final forward = RelativePolarGrid.fromSnapshot(
        result.snapshot,
        orientationValid: true,
        userMoving: true,
      ).sector(RelativeSectorDirection.forward);
      final candidate = result.decision!.candidates.singleWhere(
        (v) => v.direction.name == 'forward',
      );
      final geometric = <Map<String, Object?>>[];
      if (geometryAudit) {
        // Diagnostic query only: motion priority remains enabled in the runtime above.
        for (final item in {
          'original': c.original,
          'supplemental': c.supplemental,
        }.entries) {
          final associator = CameraTrackAssociator(
            input: sequenceAssociationInput(header, item.value, c.original),
            header: header,
            calibration: base.calibration(c.batch, 'rig'),
            request: pairedBodyRequest,
            nowUs: t + 2000,
            relativeModelHash: fixture.pinned.relativeHash,
          );
          for (final tr in tracks) {
            final b = tr.last.normalizedBounds;
            final association = associator.associate(
              normalizedBounds: [b.left, b.top, b.right, b.bottom],
              trackTimestampUs: tr.timestampUsHist.last,
              currentlyObserved: tr.misses == 0,
              motionOrSemanticRisk: false,
              support: tr.last.cameraSupport,
              expectedPixelCount: tr.last.pixelCount,
            );
            geometric.add({
              'bounds': item.key,
              'trackId': tr.id,
              ...association.toDiagnosticMap(),
              if (item.key == 'supplemental' && association.unknownPixels > 0)
                'pixelAudit': firstReturnPixelAudit(
                  item.value,
                  tr.last.cameraSupport!,
                  association,
                ),
            });
          }
        }
      }
      rows.add({
        'id': c.batch['id'],
        'index': index,
        'frameId': header.frameId,
        'capturedAtUs': t,
        'nowUs': t + age,
        'userMoving': true,
        'sessionStarts': sessions,
        'previousRevision': previousRevision,
        'revision': result.snapshot.revision,
        'lastFrameId': engine.lastFrameId,
        'action': result.decision!.action.kind.name,
        'rule': result.decision!.action.ruleId,
        'cause': result.decision!.action.cause,
        'previousState': result.decision!.previousState.name,
        'state': result.decision!.state.name,
        'delivery': result.submittedAction!.delivery.name,
        'arbiterActive': false,
        'passageApplied': result.passageClearanceApplied,
        'passage': result.passageClearance?.toDiagnosticMap(),
        'forwardUnknown': forward.unknownProbability,
        'forwardOccupancy': forward.occupancyProbability,
        'forwardMovingThreat': forward.movingThreatRisk,
        'hazardIds': forward.hazardIds,
        'forwardPositiveEvidence': candidate.hasPositiveEvidence,
        'forwardRejections': [
          for (final r in candidate.rejectionReasons) r.name,
        ],
        'hazardHistory': [
          for (final h in result.snapshot.hazardTracks)
            {
              'id': h.id,
              'elementId': h.elementId,
              'risk': h.risk,
              'lastObservedAtUs': h.lastObservedAt.microsecondsSinceEpoch,
            },
        ],
        'tracks': fault != null || freshRuntime || freshAll
            ? [
                for (final tr in recordedTracks)
                  {
                    for (final e in tr.entries)
                      if (e.key != 'componentSupport') e.key: e.value,
                    'componentSupportCount':
                        (tr['componentSupport'] as List).length,
                  },
              ]
            : recordedTracks,
        'trackEvidence': [
          for (final tr in tracks)
            {
              'id': tr.id,
              'zone': tr.last.zone.name,
              'corridorOverlap': tr.last.corridorOverlap,
              'confidence': tr.last.confidence,
              'relativeProximity': tr.last.relativeProximity,
              'proximityHistory': List<double>.from(tr.proximityHist),
              'semanticPresent': tr.last.semantic != null,
              'timeToCollisionS': tr.last.timeToCollisionS,
              'approachRateMps': tr.last.approachRateMps,
            },
        ],
        'associations': [
          for (final e in engine.cameraTrackAssociations.entries)
            {'trackId': e.key, ...e.value.toDiagnosticMap()},
        ],
        if (geometryAudit) 'geometryOnlyQueries': geometric,
        if (fault != null && index == 5) 'injectedFault': fault,
      });
    }
    return rows;
  }

  final modes = <String, List<Map<String, Object?>>>{
    for (final mode in ['single-original', 'rig-original', 'rig-supplemental'])
      mode: run(mode, geometryAudit: mode == 'rig-supplemental'),
  };
  final faults = <Map<String, Object?>>[];
  for (final fault in [
    ...badSources.keys,
    'staleOriginalCapture',
    ...primaryFaults.keys,
  ]) {
    final rows = run('rig-supplemental', fault: fault);
    if (rows[5]['action'] != 'stopNow' ||
        rows.skip(6).any((r) => r['action'] == 'continueForward')) {
      throw StateError('Fault or moving recovery gained continue: $fault');
    }
    faults.add({
      'fault': fault,
      'injectedIndex': 5,
      'frames': rows,
      'injectionStop': true,
      'laterMovingContinues': 0,
    });
  }
  return {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'captureToCommandMeasured': false,
    'namedDeviceValidated': false,
    'maximumAgeUs': 100000,
    'newNeuralInference': false,
    'manifestSha256': base.modelHash,
    'selectionSha256': bodySha('$sequenceReturnRoot/selection.json'),
    'priorHazardReplaySha256': bodySha(
      'scratch/track-first-return-2026-10-09/replay.json',
    ),
    'scope':
        'eleven pinned moving camera frames at original 200 ms intervals; static ideal 12-channel rig; fixed +2 ms functional clock',
    'sourceFrames': [
      for (final c in fixture.captures)
        {
          'id': c.batch['id'],
          'bodyUnknown': c.bodyUnknown,
          'passage': c.sourceDecision,
        },
    ],
    'continuous': modes,
    'diagnosticAblations': {
      'freshRuntimeRetainedTracker': run(
        'rig-supplemental',
        freshRuntime: true,
      ),
      'freshDetectorTrackerRuntime': run('rig-supplemental', freshAll: true),
    },
    'freshAllScope':
        'Fresh detector state changes component footprints; sparse proof is selected for the continuous run. This ablation cannot isolate tracker history or establish snapshot clearance.',
    'faultTrials': faults,
    'summary': {
      'frames': fixture.captures.length,
      'completePassages': fixture.captures
          .where((c) => c.sourceDecision['status'] == 'measuredClear')
          .length,
      for (final e in modes.entries)
        e.key: {
          'stops': e.value.where((r) => r['action'] == 'stopNow').length,
          'continues': e.value
              .where((r) => r['action'] == 'continueForward')
              .length,
          'sessionStarts': e.value.last['sessionStarts'],
        },
      'faultTrials': faults.length,
      'faultStops': faults.length,
      'afterFaultMovingContinues': 0,
    },
  };
}
