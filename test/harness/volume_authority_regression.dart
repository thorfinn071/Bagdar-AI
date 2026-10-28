import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/camera_track_motion_coverage.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/coverage_aware_stop_guidance.dart';
import 'package:bagdar/safety/runtime/volume_authority_spatial_runtime.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/frame_stable_generic_obstacle_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import '../../tool/model_benchmark/fast_camera_motion_fixture.dart';
import 'blender_visible_body_fixture.dart';
import 'blender_synchronized_rig_fixture.dart' show rigCopyFrame;
import 'camera_visible_passage_fixture.dart';
import 'sequence_first_return_fixture.dart';
import 'sequence_first_return_replay.dart' show sequenceAssociationInput;
import 'track_first_return_fixture.dart' show firstReturnCopy;

const wholeTrackRoot = 'scratch/whole-track-evidence-2026-10-10';
const authorityFixRoot = 'scratch/evidence-authority-fix-2026-10-10';
const _priorRoot = 'scratch/motion-origin-2026-10-10';
String _digest(Object? v) =>
    sha256.convert(utf8.encode(jsonEncode(v))).toString();

class _Detector {
  final bool stable;
  final old = GenericObstacleDetector(
    collectCameraSupport: true,
    collectOpeningDiagnostics: true,
  );
  final candidate = FrameStableGenericObstacleDetector(
    collectCameraSupport: true,
    collectOpeningDiagnostics: true,
  );
  _Detector(this.stable);
  GenericObstacleDetectResult detect(DepthFrame f, double pitch, int stamp) =>
      stable
      ? candidate.detect(
          frame: f,
          pitchDeg: pitch,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: stamp,
        )
      : old.detect(
          frame: f,
          pitchDeg: pitch,
          rollDeg: 0,
          motion: MotionState.walking,
          imageTimestampUs: stamp,
        );
}

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
      'supportSha256': _digest(t.last.cameraSupport?.indices),
    },
];

ObservationHeader _header(
  DepthFrame f,
  double quality,
  int frame,
  String transform,
) => ObservationHeader(
  providerId: 'desktop-midas',
  modelId: f.modelId,
  modelHash: f.modelHash,
  preprocessId: f.preprocessId,
  sessionGeneration: 1,
  frameId: frame,
  sourceTimestampUs: f.timestampUs,
  producedAtUs: f.timestampUs + 1000,
  transformId: transform,
  confidence: quality.clamp(0, 1),
  health: ObservationHealth.healthy,
);

DepthFrame _relative(List<double> raw, int stamp, String hash) {
  final v = DepthMapOps.normalizeRelativeProximity(Float32List.fromList(raw));
  return DepthFrame(
    values: v,
    confidence01: Float32List.fromList(List.filled(v.length, 1)),
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

Map<String, Object?> runVolumeAuthorityRegression() {
  final fixture = SequenceReturnFixture(), base = fixture.base;
  final prior = bodyJson('$_priorRoot/replay.json');
  final proof = bodyJson('$wholeTrackRoot/optical/manifest.json');
  final hash = bodySha('$wholeTrackRoot/optical/manifest.json');
  if (proof['priorOpticalManifestSha256'] != base.modelHash ||
      proof['priorValidationSha256'] !=
          bodySha('$_priorRoot/validation.json') ||
      proof['selectionSha256'] !=
          bodySha('$wholeTrackRoot/optical/selection.json') ||
      proof['promotionAllowed'] != false ||
      proof['ordinaryCameraWired'] != false) {
    throw StateError('Supplement identity changed');
  }
  for (final e in (proof['sources'] as Map).entries) {
    if (bodySha(e.key as String) != e.value) throw StateError('Exporter drift');
  }
  PassageCalibration calibration(Map b) {
    final c = base.calibration(b, 'rig');
    return PassageCalibration(
      id: '${c.id}-whole-track',
      providerId: c.providerId,
      modelId: c.modelId,
      modelHash: hash,
      preprocessId: c.preprocessId,
      referenceFrameId: c.referenceFrameId,
      transformId: c.transformId,
      timestampDomain: c.timestampDomain,
      metricScaleValidated: true,
      alignmentValidated: true,
      floorReferenceValidated: true,
    );
  }

  final optical = <String, List<Map<String, Object?>>>{};
  final faults = <Map<String, Object?>>[];
  List<Map<String, Object?>> replay(bool stable, {String? fault}) {
    final detector = _Detector(stable), tracker = GenericObstacleTracker();
    final mode = stable ? 'frameStable' : 'legacy';
    final engine =
        VolumeAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          planner: CoverageAwareStopGuidance(),
          shadowPassage: PassageClearanceShadowConfiguration(
            calibration: calibration(fixture.captures.first.batch),
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
    for (var i = 0; i < fixture.captures.length; i++) {
      final c = fixture.captures[i],
          b = c.batch,
          stamp = c.original.capturedAtUs;
      final rec = (proof['records'] as List).cast<Map>().singleWhere(
        (r) => r['frameId'] == i + 1,
      );
      if (rec['capturedAtUs'] != stamp ||
          rec['id'] != b['id'] ||
          rec['sceneStateSha256'] != b['sceneStateSha256']) {
        throw StateError('Retimed supplement');
      }
      var packet = firstReturnCopy(
        c.supplemental,
        modelHash: hash,
        upper: bodyFloats(
          bodyAsset('$wholeTrackRoot/optical', rec['surfaceZUpper'] as Map),
        ),
      );
      final channels = [
        for (final ch in c.channels) rigCopyFrame(ch, modelHash: hash),
      ];
      final rigSource = CameraSynchronizedEnvelopeSource(
        channels: base.channels(b),
        batchFrameId: b['frameId'] as int,
        sessionGeneration: b['sessionGeneration'] as int,
        capturedAtUs: stamp,
        stationarySyntheticScene: b['stationarySyntheticScene'] as bool,
        calibration: calibration(b),
        request: pairedBodyRequest,
        frames: channels,
        producedAtUs: stamp + 1000,
      );
      final rig = rigSource.observationFor(base.context(b, stamp + 2000));
      final detection = detector.detect(c.relative, 12, stamp);
      var tracks = tracker.update(
        observations: detection.observations,
        timestampUs: stamp,
        relative: true,
      );
      var age = 2000;
      if (fault != null) {
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
          case 'foreignModel':
            packet = firstReturnCopy(packet, modelHash: 'foreign');
          case 'foreignTransform':
            packet = firstReturnCopy(packet, transformId: 'foreign');
          case 'foreignPose':
            packet = firstReturnCopy(
              packet,
              rotation: c.channels.first.depth.rotation,
            );
          case 'staleCapture':
            age = 100001;
          case 'semantic' || 'ttc' || 'metricApproach':
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
                  confirmed: tr.confirmed,
                  proximityHist: List.from(tr.proximityHist),
                  metricHist: List.from(tr.metricHist),
                  timestampUsHist: List.from(tr.timestampUsHist),
                  hitWindow: List.from(tr.hitWindow),
                ),
            ];
        }
      }
      final h = _header(
        c.relative,
        detection.detectorQuality,
        i + 1,
        base.transform(b),
      );
      final input = sequenceAssociationInput(h, packet, c.original);
      final revision = engine.sceneModel.revision;
      final r = engine.ingestGenericGeometry(
        header: h,
        detection: detection,
        tracks: tracks,
        now: DateTime.fromMicrosecondsSinceEpoch(stamp + age),
        orientationValid: true,
        userMoving: true,
        poseQuality: 1,
        passageObservation: fault == 'missingRig' ? null : rig,
        cameraTrackInput: input,
      );
      if (!r.accepted ||
          r.submittedAction?.delivery.name != 'shadow' ||
          engine.arbiter.active != null ||
          r.snapshot.revision <= revision) {
        throw StateError('Unexpected authority');
      }
      final associator = CameraTrackAssociator(
        input: input,
        header: h,
        calibration: calibration(b),
        request: pairedBodyRequest,
        nowUs: stamp + age,
        relativeModelHash: fixture.pinned.relativeHash,
      );
      final geometric = [
        for (final tr in tracks)
          {
            'trackId': tr.id,
            ...associator
                .associate(
                  normalizedBounds: [
                    tr.last.normalizedBounds.left,
                    tr.last.normalizedBounds.top,
                    tr.last.normalizedBounds.right,
                    tr.last.normalizedBounds.bottom,
                  ],
                  trackTimestampUs: tr.timestampUsHist.last,
                  currentlyObserved: tr.misses == 0,
                  motionOrSemanticRisk: false,
                  support: tr.last.cameraSupport,
                  expectedPixelCount: tr.last.pixelCount,
                )
                .toDiagnosticMap(),
          },
      ];
      final trace = _tracks(tracks);
      if (fault == null &&
          jsonEncode(trace) !=
              jsonEncode((prior['sequence'][mode] as List)[i]['tracks'])) {
        throw StateError('Detector/tracker changed instead of optical support');
      }
      rows.add({
        'frameId': i + 1,
        'capturedAtUs': stamp,
        'nowUs': stamp + age,
        'sessionStarts': 1,
        'previousRevision': revision,
        'revision': r.snapshot.revision,
        'userMoving': true,
        'action': r.decision!.action.kind.name,
        'rule': r.decision!.action.ruleId,
        'delivery': 'shadow',
        'arbiterActive': false,
        'passageApplied': r.passageClearanceApplied,
        'bodyUnknown': rigSource.unknownBodyBoxes,
        'tracks': trace,
        'associations': [
          for (final e in engine.cameraTrackAssociations.entries)
            {'trackId': e.key, ...e.value.toDiagnosticMap()},
        ],
        'geometryOnlyQueries': geometric,
        if (fault != null) 'injectedFault': fault,
      });
      if (fault != null) break;
    }
    return rows;
  }

  for (final stable in [false, true]) {
    final mode = stable ? 'frameStable' : 'legacy';
    optical[mode] = replay(stable);
    for (final f in [
      'lostUpper',
      'invalidReturn',
      'relativeUnits',
      'foreignModel',
      'foreignTransform',
      'foreignPose',
      'staleCapture',
      'missingRig',
      'semantic',
      'ttc',
      'metricApproach',
    ]) {
      faults.add({
        'mode': mode,
        'fault': f,
        'frame': replay(stable, fault: f).single,
      });
    }
  }
  final motion = _auditMotion(prior);
  return {
    'schemaVersion': 1,
    'promotionAllowed': false,
    'ordinaryCameraWired': false,
    'newIndependentHoldout': false,
    'newNeuralInference': false,
    'captureToCommandMeasured': false,
    'maximumAgeUs': 100000,
    'opticalManifestSha256': hash,
    'priorReplaySha256': bodySha('$_priorRoot/replay.json'),
    'optical': optical,
    'initialClearFaultControls': faults,
    'motionCases': motion,
    'summary': {
      for (final e in optical.entries)
        e.key: {
          'frames': e.value.length,
          'stops': e.value.where((f) => f['action'] == 'stopNow').length,
          'continues': e.value
              .where((f) => f['action'] == 'continueForward')
              .length,
          'geometryUnknownPixels': [
            for (final f in e.value)
              (f['geometryOnlyQueries'] as List).cast<Map>().fold<int>(
                0,
                (n, a) => n + (a['unknownPixels'] as int),
              ),
          ],
        },
      'initialFaultTrials': faults.length,
      'initialFaultStops': faults
          .where((f) => (f['frame'] as Map)['action'] == 'stopNow')
          .length,
      'motionSequences': motion.length,
      'diagnosticTrackSamples': motion.fold<int>(
        0,
        (n, s) =>
            n +
            (s['frames'] as List).cast<Map>().fold<int>(
              0,
              (m, f) =>
                  m +
                  (f['relative'] as Map).values.cast<Map>().fold<int>(
                    0,
                    (k, v) => k + (v['coverage'] as List).length,
                  ),
            ),
      ),
    },
  };
}

class _SupportSample {
  final CameraComponentSupport? support;
  final int count;
  final bool observed;
  _SupportSample(GenericObstacleTrack t)
    : support = t.last.cameraSupport,
      count = t.last.pixelCount,
      observed = t.misses == 0;
}

List<Map<String, Object?>> _auditMotion(Map prior) {
  final fixture = VisibleFixture(root: fastCorpus),
      cases = <Map<String, Object?>>[];
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
    final samples = [<int, _SupportSample>{}, <int, _SupportSample>{}];
    final engines = [
      for (var j = 0; j < 2; j++)
        VolumeAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
          planner: CoverageAwareStopGuidance(),
        )..beginSession(
          1,
          now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1),
        ),
    ];
    final old = (prior['motionCases'] as List).cast<Map>().singleWhere(
      (c) => c['layoutId'] == layout['id'],
    );
    FastMetricMotionInput? previous;
    final rows = <Map<String, Object?>>[];
    for (final f in fixture.frames(layout)) {
      final t = f.capturedAtUs, input = fastInput(fixture, layout, f);
      final measured = source.observe(input, nowUs: t + 2000);
      final frozen = (old['frames'] as List).cast<Map>().singleWhere(
        (r) => r['frameId'] == f.frameId,
      );
      if (jsonEncode(measured.toDiagnosticMap()) !=
          jsonEncode(frozen['metricMotion'])) {
        throw StateError('Frozen metric producer changed');
      }
      final meta = (layout['frames'] as List).cast<Map>().singleWhere(
        (r) => r['frameId'] == f.frameId,
      );
      final relative = _relative(
        fixture.raw(layout, f.frameId),
        t,
        fixture.ncnn['modelBinSha256'] as String,
      );
      final modes = <String, Object?>{};
      for (var j = 0; j < 2; j++) {
        final mode = j == 0 ? 'legacy' : 'frameStable';
        final detection = detectors[j].detect(
          relative,
          (meta['pitchDeg'] as num).toDouble(),
          t,
        );
        final tracks = trackers[j].update(
          observations: detection.observations,
          timestampUs: t,
          relative: true,
        );
        final trace = _tracks(tracks);
        if (jsonEncode(trace) !=
            jsonEncode(frozen['relative'][mode]['tracks'])) {
          throw StateError('Frozen track drift');
        }
        final r = engines[j].ingestGenericGeometry(
          header: _header(
            relative,
            detection.detectorQuality,
            f.frameId,
            f.transformId,
          ),
          detection: detection,
          tracks: tracks,
          now: DateTime.fromMicrosecondsSinceEpoch(t + 2000),
          orientationValid: true,
          userMoving: true,
          poseQuality: 1,
        );
        if (!r.accepted ||
            r.submittedAction?.delivery.name != 'shadow' ||
            engines[j].arbiter.active != null ||
            r.decision!.action.kind.name !=
                frozen['relative'][mode]['action'] ||
            r.decision!.action.ruleId != frozen['relative'][mode]['rule']) {
          throw StateError('Motion runtime drift');
        }
        final coverage = <Map<String, Object?>>[];
        for (final tr in tracks) {
          final p = samples[j][tr.id];
          if (previous == null || p == null) {
            coverage.add({
              'trackId': tr.id,
              'available': false,
              'reason': 'no_previous_observed_track_sample',
              'completeVisibleSupport': false,
              'mayResolveMotionPriority': false,
              'wholeObjectStationarityCertified': false,
              'freeSpaceCertified': false,
            });
          } else {
            coverage.add({
              'trackId': tr.id,
              ...CameraTrackMotionCoverage.evaluate(
                trackId: tr.id,
                previousTrackId: tr.id,
                currentlyObserved: tr.misses == 0,
                previouslyObserved: p.observed,
                currentSupport: tr.last.cameraSupport,
                previousSupport: p.support,
                currentPixelCount: tr.last.pixelCount,
                previousPixelCount: p.count,
                current: input,
                previous: previous,
                motion: measured,
                calibration: fixture.calibration(),
                rgbContract: fastRgbContract,
                nowUs: t + 2000,
              ).toDiagnosticMap(),
            });
          }
        }
        samples[j] = {for (final tr in tracks) tr.id: _SupportSample(tr)};
        modes[mode] = {
          'action': r.decision!.action.kind.name,
          'rule': r.decision!.action.ruleId,
          'delivery': 'shadow',
          'tracks': trace,
          'coverage': coverage,
        };
      }
      rows.add({
        'frameId': f.frameId,
        'capturedAtUs': t,
        'metricMotion': measured.toDiagnosticMap(),
        'relative': modes,
      });
      previous = input;
    }
    // Scoring annotations are copied only after the unchanged runtime decisions.
    for (final r in rows) {
      r['scoringOnly'] = (old['frames'] as List).cast<Map>().singleWhere(
        (o) => o['frameId'] == r['frameId'],
      )['scoringOnly'];
    }
    cases.add({
      'layoutId': layout['id'],
      'knownRegression': true,
      'frames': rows,
    });
  }
  return cases;
}
