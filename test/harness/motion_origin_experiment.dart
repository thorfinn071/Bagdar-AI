import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

import '../../tool/model_benchmark/fast_camera_motion_fixture.dart';
import 'blender_visible_body_fixture.dart';
import 'camera_visible_passage_fixture.dart';
import 'sequence_first_return_fixture.dart';
import 'sequence_first_return_replay.dart' show sequenceAssociationInput;
import 'track_first_return_fixture.dart' show firstReturnCopy;

const motionOriginRoot = 'scratch/motion-origin-2026-10-10';

class _Detector {
  final bool stable;
  final legacy = GenericObstacleDetector(
    collectCameraSupport: true,
    collectOpeningDiagnostics: true,
  );
  final candidate = FrameStableGenericObstacleDetector(
    collectCameraSupport: true,
    collectOpeningDiagnostics: true,
  );
  _Detector(this.stable);

  GenericObstacleDetectResult detect(
    DepthFrame frame,
    double pitch,
    int stamp,
  ) => stable
      ? candidate.detect(
          frame: frame,
          pitchDeg: pitch,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: stamp,
        )
      : legacy.detect(
          frame: frame,
          pitchDeg: pitch,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: stamp,
        );
}

String _signature(GenericObstacleDetectResult result) => jsonEncode({
  'reject': result.rejectReason.name,
  'quality': result.detectorQuality,
  'ground': result.groundConfidence,
  'unknown': result.unknownReasons.map((v) => v.name).toList(),
  'observations': [
    for (final o in result.observations)
      {
        'geometry': o.geometry.name,
        'zone': o.zone.name,
        'bounds': [
          o.normalizedBounds.left,
          o.normalizedBounds.top,
          o.normalizedBounds.right,
          o.normalizedBounds.bottom,
        ],
        'confidence': o.confidence,
        'proximity': o.relativeProximity,
        'support': o.cameraSupport?.indices,
      },
  ],
});

List<Map<String, Object?>> _tracks(List<GenericObstacleTrack> tracks) => [
  for (final t in tracks)
    {
      'id': t.id,
      'hits': t.hits,
      'misses': t.misses,
      'age': t.age,
      'confirmed': t.confirmed,
      'approachTrend': t.approachTrend(),
      'proximityHistory': List<double>.from(t.proximityHist),
      'timestamps': List<int>.from(t.timestampUsHist),
      'supportCount': t.last.cameraSupport?.indices.length,
      'supportSha256': _digest(jsonEncode(t.last.cameraSupport?.indices)),
    },
];

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

DepthFrame _relative(List<double> raw, int stamp, String hash) {
  final values = DepthMapOps.normalizeRelativeProximity(
    Float32List.fromList(raw),
  );
  return DepthFrame(
    values: values,
    confidence01: Float32List.fromList(List.filled(values.length, 1)),
    width: 256,
    height: 256,
    timestampUs: stamp,
    provider: DepthProviderKind.ncnnRelative,
    semantics: DepthValueSemantics.relativeProximity,
    modelId: 'midas-small-ncnn',
    modelHash: hash,
    preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
    cropTopFraction: 0,
    frameQuality: 1,
    alignedToImage: true,
  );
}

Map<String, Object?> runMotionOriginExperiment() {
  final fixture = SequenceReturnFixture(), base = fixture.base;
  final prior = bodyJson('$sequenceReturnRoot/replay.json');
  final sequence = <String, List<Map<String, Object?>>>{};
  final faults = <Map<String, Object?>>[];
  final controls = [
    'lostUpper',
    'invalidReturn',
    'relativeUnits',
    'foreignPose',
    'foreignModel',
    'foreignTransform',
    'staleCapture',
    'semantic',
    'ttc',
    'metricApproach',
    'missingRig',
  ];

  List<Map<String, Object?>> replay(bool stable, {String? fault}) {
    final detector = _Detector(stable), tracker = GenericObstacleTracker();
    final engine =
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          planner: CoverageAwareStopGuidance(),
          shadowPassage: PassageClearanceShadowConfiguration(
            calibration: base.calibration(fixture.captures.first.batch, 'rig'),
            request: pairedBodyRequest,
            policy: pairedBodyPolicy,
            requireCameraEvidence: true,
            associateCameraTracks: true,
            cameraTrackModelHash: fixture.pinned.relativeHash,
          ),
        )..beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(
            fixture.captures.first.original.capturedAtUs - 1000,
          ),
        );
    final rows = <Map<String, Object?>>[];
    for (var index = 0; index < fixture.captures.length; index++) {
      final c = fixture.captures[index], stamp = c.original.capturedAtUs;
      final detection = detector.detect(c.relative, 12, stamp);
      var tracks = tracker.update(
        observations: detection.observations,
        timestampUs: stamp,
        relative: true,
      );
      final header = ObservationHeader(
        providerId: 'desktop-midas',
        modelId: c.relative.modelId,
        modelHash: c.relative.modelHash,
        preprocessId: c.relative.preprocessId,
        sessionGeneration: 1,
        frameId: c.original.frameId,
        sourceTimestampUs: stamp,
        producedAtUs: stamp + 1000,
        transformId: base.transform(c.batch),
        confidence: detection.detectorQuality.clamp(0, 1),
        health: ObservationHealth.healthy,
      );
      var packet = c.supplemental, age = 2000;
      if (fault != null && index == 0) {
        switch (fault) {
          case 'lostUpper':
            packet = firstReturnCopy(
              packet,
              upper: List.filled(packet.rangeM.length, double.nan),
            );
          case 'invalidReturn':
            packet = firstReturnCopy(
              packet,
              valid: List.filled(packet.rangeM.length, false),
            );
          case 'relativeUnits':
            packet = firstReturnCopy(
              packet,
              units: PassageUnits.relativeProximity,
            );
          case 'foreignPose':
            packet = firstReturnCopy(
              packet,
              rotation: c.channels.first.depth.rotation,
            );
          case 'foreignModel':
            packet = firstReturnCopy(packet, modelHash: 'foreign');
          case 'foreignTransform':
            packet = firstReturnCopy(packet, transformId: 'foreign');
          case 'staleCapture':
            age = 100001;
          case 'semantic' || 'ttc' || 'metricApproach':
            // Independent explicit-risk control. Do not mutate tracker history.
            tracks = [
              for (final tr in tracks)
                GenericObstacleTrack(
                  id: tr.id,
                  last: tr.last.copyWith(
                    semantic: fault == 'semantic'
                        ? const SemanticMatch(
                            yoloTrackId: 99,
                            label: 'person',
                            confidence: .99,
                          )
                        : null,
                    timeToCollisionS: fault == 'ttc' ? .5 : null,
                    approachRateMps: fault == 'metricApproach' ? 2 : null,
                  ),
                  hits: tr.hits,
                  misses: tr.misses,
                  age: tr.age,
                  proximityHist: List.from(tr.proximityHist),
                  metricHist: List.from(tr.metricHist),
                  timestampUsHist: List.from(tr.timestampUsHist),
                  confirmed: tr.confirmed,
                  hitWindow: List.from(tr.hitWindow),
                ),
            ];
        }
      }
      final before = engine.sceneModel.revision;
      final result = engine.ingestGenericGeometry(
        header: header,
        detection: detection,
        tracks: tracks,
        now: DateTime.fromMicrosecondsSinceEpoch(stamp + age),
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
        passageObservation: fault == 'missingRig' && index == 0 ? null : c.rig,
        cameraTrackInput: sequenceAssociationInput(header, packet, c.original),
      );
      if (!result.accepted ||
          result.submittedAction?.delivery.name != 'shadow' ||
          engine.arbiter.active != null ||
          engine.sceneModel.revision <= before) {
        throw StateError('Unexpected runtime admission or authority');
      }
      final geometric = <Map<String, Object?>>[];
      final associator = CameraTrackAssociator(
        input: sequenceAssociationInput(header, packet, c.original),
        header: header,
        calibration: base.calibration(c.batch, 'rig'),
        request: pairedBodyRequest,
        nowUs: stamp + age,
        relativeModelHash: fixture.pinned.relativeHash,
      );
      final selected = (c.selection['supportPixels'] as List)
          .cast<int>()
          .toSet();
      var newSupport = 0;
      final allPixels = <int>{};
      for (final tr in tracks) {
        final b = tr.last.normalizedBounds;
        final a = associator.associate(
          normalizedBounds: [b.left, b.top, b.right, b.bottom],
          trackTimestampUs: tr.timestampUsHist.last,
          currentlyObserved: tr.misses == 0,
          motionOrSemanticRisk: false,
          support: tr.last.cameraSupport,
          expectedPixelCount: tr.last.pixelCount,
        );
        geometric.add({'trackId': tr.id, ...a.toDiagnosticMap()});
        for (final i in tr.last.cameraSupport!.indices) {
          final x = i % 256, y = i ~/ 256;
          final x0 = math.max(
            0,
            (math.max(0, (x - 1) / 256) * packet.width).floor(),
          );
          final x1 = math.min(
            packet.width - 1,
            (math.min(1, (x + 2) / 256) * packet.width).ceil() - 1,
          );
          final y0 = math.max(
            0,
            (math.max(0, (y - 1) / 256) * packet.height).floor(),
          );
          final y1 = math.min(
            packet.height - 1,
            (math.min(1, (y + 2) / 256) * packet.height).ceil() - 1,
          );
          for (var yy = y0; yy <= y1; yy++) {
            for (var xx = x0; xx <= x1; xx++) {
              allPixels.add(yy * packet.width + xx);
            }
          }
        }
      }
      newSupport = allPixels.difference(selected).length;
      final associations = [
        for (final e in engine.cameraTrackAssociations.entries)
          {'trackId': e.key, ...e.value.toDiagnosticMap()},
      ];
      final action = result.decision!.action.kind.name;
      if (!stable && fault == null) {
        final old =
            (prior['continuous']['rig-supplemental'] as List)[index] as Map;
        if (action != old['action'] ||
            result.decision!.action.ruleId != old['rule'] ||
            jsonEncode(associations) != jsonEncode(old['associations'])) {
          throw StateError('Frozen legacy action/association drift at $index');
        }
        for (var j = 0; j < tracks.length; j++) {
          final oldTrack = (old['tracks'] as List)[j] as Map, tr = tracks[j];
          if (tr.id != oldTrack['id'] ||
              tr.hits != oldTrack['hits'] ||
              tr.age != oldTrack['age'] ||
              tr.misses != oldTrack['misses'] ||
              tr.confirmed != oldTrack['confirmed'] ||
              tr.approachTrend() != oldTrack['approachTrend'] ||
              jsonEncode(tr.last.cameraSupport!.indices) !=
                  jsonEncode(oldTrack['componentSupport'])) {
            throw StateError('Frozen legacy tracker drift');
          }
        }
      }
      rows.add({
        'index': index,
        'frameId': header.frameId,
        'capturedAtUs': stamp,
        'nowUs': stamp + age,
        'sessionStarts': 1,
        'userMoving': true,
        'previousRevision': before,
        'revision': result.snapshot.revision,
        'action': action,
        'rule': result.decision!.action.ruleId,
        'delivery': result.submittedAction!.delivery.name,
        'arbiterActive': false,
        'passageApplied': result.passageClearanceApplied,
        'passageStatus': result.passageClearance?.status.name,
        'tracks': _tracks(tracks),
        'associations': associations,
        'geometryOnlyQueries': geometric,
        'pixelsOutsidePriorSelection': newSupport,
        'allSupportPixels': allPixels.toList()..sort(),
        'positiveRelativeTracks': tracks
            .where((t) => t.approachTrend() > 0)
            .length,
        if (fault != null && index == 0) 'injectedFault': fault,
      });
      if (fault != null) break; // Initial-clear control, not a recovery claim.
    }
    return rows;
  }

  for (final stable in [false, true]) {
    final mode = stable ? 'frameStable' : 'legacy';
    sequence[mode] = replay(stable);
    for (final fault in controls) {
      faults.add({
        'mode': mode,
        'fault': fault,
        'frame': replay(stable, fault: fault).single,
      });
    }
  }

  final stationary = <Map<String, Object?>>[];
  final knownFixture = VisibleFixture(
    root: 'test/fixtures/spatial_safety/camera-track-passage-v1',
  );
  final knownLayout = (knownFixture.manifest['layouts'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((l) => l['id'] == 'test-association-wide-08');
  final known = knownFixture.raw(knownLayout, 1);
  for (final stable in [false, true]) {
    final detector = _Detector(stable), tracker = GenericObstacleTracker();
    final signatures = <String>{};
    var positiveFrames = 0, maxTrend = 0.0;
    for (var i = 0; i < 11; i++) {
      // Counterfactual detector-only repeat. No runtime/capture evidence created.
      final t = 1000000 + i * 200000;
      final result = detector.detect(
        _relative(known, t, 'counterfactual'),
        3,
        t,
      );
      signatures.add(_digest(_signature(result)));
      final tracks = tracker.update(
        observations: result.observations,
        timestampUs: t,
        relative: true,
      );
      if (tracks.any((t) => t.approachTrend() > 0)) positiveFrames++;
      for (final t in tracks) {
        maxTrend = math.max(maxTrend, t.approachTrend());
      }
    }
    stationary.add({
      'mode': stable ? 'frameStable' : 'legacy',
      'calls': 11,
      'uniqueSegmentations': signatures.length,
      'positiveRelativeFrames': positiveFrames,
      'maximumRelativeTrend': maxTrend,
      'runtimeUsed': false,
    });
  }

  // Actual path-clear input at fixed capture, after different sampling histories.
  final sampling = <Map<String, Object?>>[];
  for (final stable in [false, true]) {
    final detector = _Detector(stable);
    for (final c in fixture.captures) {
      final signatures = <String>{};
      for (var j = 0; j < 3; j++) {
        signatures.add(
          _digest(
            _signature(
              detector.detect(c.relative, 12, c.original.capturedAtUs),
            ),
          ),
        );
      }
      sampling.add({
        'mode': stable ? 'frameStable' : 'legacy',
        'frameId': c.original.frameId,
        'uniqueSegmentations': signatures.length,
      });
    }
  }

  final motion = _motionCases();
  return {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'newIndependentHoldout': false,
    'newNeuralInference': false,
    'captureToCommandMeasured': false,
    'maximumAgeUs': 100000,
    'priorReplaySha256': bodySha('$sequenceReturnRoot/replay.json'),
    'priorValidationSha256': bodySha('$sequenceReturnRoot/validation.json'),
    'stationaryCounterfactual': stationary,
    'fixedInputSampling': sampling,
    'sequence': sequence,
    'initialClearFaultControls': faults,
    'motionCases': motion,
    'summary': {
      for (final e in sequence.entries)
        e.key: {
          'frames': e.value.length,
          'stops': e.value.where((r) => r['action'] == 'stopNow').length,
          'continues': e.value
              .where((r) => r['action'] == 'continueForward')
              .length,
          'positiveRelativeFrames': e.value
              .where((r) => (r['positiveRelativeTracks'] as int) > 0)
              .length,
          'motionPriorityFrames': e.value
              .where(
                (r) => (r['associations'] as List).cast<Map>().any(
                  (a) => a['reason'] == 'motion_or_semantic_priority',
                ),
              )
              .length,
          'framesWithNewSupport': e.value
              .where((r) => (r['pixelsOutsidePriorSelection'] as int) > 0)
              .length,
        },
      'initialFaultTrials': faults.length,
      'initialFaultStops': faults
          .where((r) => (r['frame'] as Map)['action'] == 'stopNow')
          .length,
      'motionRegressionSequences': motion.length,
    },
  };
}

List<Map<String, Object?>> _motionCases() {
  final fixture = VisibleFixture(root: fastCorpus),
      rows = <Map<String, Object?>>[];
  for (final layout
      in (fixture.manifest['layouts'] as List).cast<Map<String, dynamic>>()) {
    if (layout['split'] != 'test' || layout['staticSyntheticScan'] == true) {
      continue;
    }
    final source = CameraFastMetricMotionSource(
      calibration: fixture.calibration(),
      rgbContract: fastRgbContract,
    );
    final detectors = [_Detector(false), _Detector(true)],
        trackers = [GenericObstacleTracker(), GenericObstacleTracker()];
    final engines = [
      for (var j = 0; j < 2; j++)
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          planner: CoverageAwareStopGuidance(),
        )..beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1),
        ),
    ];
    final frames = <Map<String, Object?>>[];
    final observations = fixture.frames(layout);
    for (var i = 0; i < observations.length; i++) {
      final f = observations[i], t = f.capturedAtUs;
      final input = fastInput(fixture, layout, f);
      final measured = source.observe(input, nowUs: t + 2000);
      final metadata = (layout['frames'] as List).cast<Map>().singleWhere(
        (r) => r['frameId'] == f.frameId,
      );
      final relative = _relative(
        fixture.raw(layout, f.frameId),
        t,
        fixture.ncnn['modelBinSha256'] as String,
      );
      final modes = <String, Object?>{};
      for (var j = 0; j < 2; j++) {
        final detection = detectors[j].detect(
          relative,
          (metadata['pitchDeg'] as num).toDouble(),
          t,
        );
        final tracks = trackers[j].update(
          observations: detection.observations,
          timestampUs: t,
          relative: true,
        );
        final header = ObservationHeader(
          providerId: 'desktop-midas',
          modelId: relative.modelId,
          modelHash: relative.modelHash,
          preprocessId: relative.preprocessId,
          sessionGeneration: 1,
          frameId: f.frameId,
          sourceTimestampUs: t,
          producedAtUs: t + 1000,
          transformId: f.transformId,
          confidence: detection.detectorQuality.clamp(0, 1),
          health: ObservationHealth.healthy,
        );
        final r = engines[j].ingestGenericGeometry(
          header: header,
          detection: detection,
          tracks: tracks,
          now: DateTime.fromMicrosecondsSinceEpoch(t + 2000),
          orientationValid: true,
          userMoving: true,
          poseQuality: 1,
        );
        if (!r.accepted ||
            r.submittedAction?.delivery.name != 'shadow' ||
            engines[j].arbiter.active != null) {
          throw StateError('Motion control gained active authority');
        }
        modes[j == 0 ? 'legacy' : 'frameStable'] = {
          'action': r.decision!.action.kind.name,
          'rule': r.decision!.action.ruleId,
          'delivery': 'shadow',
          'positiveRelativeTracks': tracks
              .where((t) => t.approachTrend() > 0)
              .length,
          'tracks': _tracks(tracks),
        };
      }
      frames.add({
        'frameId': f.frameId,
        'capturedAtUs': t,
        'cameraOriginM': f.originM,
        'cameraRotation': f.rotation,
        'metricMotion': measured.toDiagnosticMap(),
        'relative': modes,
        'objectStationarityCertified': false,
        'motionSuppressed': false,
        'freeSpaceCertified': false,
      });
    }
    // Scoring starts only after every perception/runtime decision is complete.
    final labels =
        (visibleJson('$fastCorpus/annotations.json')['layouts'] as List)
            .cast<Map>()
            .singleWhere((l) => l['layoutId'] == layout['id']);
    final annotations = (labels['frames'] as List).cast<Map>();
    var hazardFrames = 0;
    final unsafe = {'legacy': 0, 'frameStable': 0},
        stops = {'legacy': 0, 'frameStable': 0};
    for (final frame in frames) {
      final annotation = annotations.singleWhere(
        (r) => r['frameId'] == frame['frameId'],
      );
      frame['scoringOnly'] = annotation;
      if (annotation['physicalHazard'] == true) {
        hazardFrames++;
        for (final mode in unsafe.keys) {
          final action = ((frame['relative'] as Map)[mode] as Map)['action'];
          if (action == 'continueForward') unsafe[mode] = unsafe[mode]! + 1;
          if (action == 'stopNow') stops[mode] = stops[mode]! + 1;
        }
      }
    }
    rows.add({
      'layoutId': layout['id'],
      'knownRegression': true,
      'frames': frames,
      'summary': {
        'hazardFrames': hazardFrames,
        'hazardStops': stops,
        'unsafeContinues': unsafe,
        'positiveLocalMotionFrames': frames
            .where(
              (r) => ((r['metricMotion'] as Map)['patches'] as List)
                  .cast<Map>()
                  .any(
                    (p) => ![
                      'consistentWithStationary',
                      'uncertain',
                    ].contains(p['classification']),
                  ),
            )
            .length,
        'riskAddingLocalMotionFrames': frames
            .where((r) => (r['metricMotion'] as Map)['addsMotionRisk'] == true)
            .length,
      },
    });
  }
  return rows;
}
