import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/runtime/volume_authority_spatial_runtime.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';

import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart';
import 'harness/ego_motion_experiment.dart' show egoCorpus;
import 'harness/ego_volume_fixture.dart';
import 'harness/sequence_first_return_replay.dart'
    show sequenceAssociationInput;

class _Replay {
  final VisibleFixture original;
  final EgoVolumeFixture volume;
  final VolumeAuthoritySpatialRuntime engine;
  final tracker = GenericObstacleTracker();
  final List<CameraVisibleDepthFrame> frames;
  _Replay(this.original, this.volume)
    : frames = original.frames(
        (original.manifest['layouts'] as List)
            .cast<Map<String, dynamic>>()
            .first,
      ),
      engine = VolumeAuthoritySpatialRuntime(
        healthCoordinator: CoreHealthCoordinator(),
        shadowPassage: PassageClearanceShadowConfiguration(
          calibration: volume.calibration(),
          request: visibleRequest,
          policy: pairedBodyPolicy,
          requireCameraEvidence: true,
          associateCameraTracks: true,
          cameraTrackModelHash: original.ncnn['modelBinSha256'],
        ),
      ) {
    engine.beginSession(
      1,
      now: DateTime.fromMicrosecondsSinceEpoch(visibleStamp - 1000),
    );
  }

  SpatialRuntimeResult at(int index, {String? fault, bool moving = true}) {
    final f = frames[index], stamp = frames[index].capturedAtUs;
    final b = volume.batch('ego-camera-forward', f.frameId);
    final obs = [
      GenericObstacleObservation(
        geometry: ObstacleGeometry.broadSurface,
        zone: HazardZone.center,
        normalizedBounds: const Rect.fromLTRB(.29, .18, .71, .64),
        corridorOverlap: .8,
        confidence: .95,
        relativeProximity: .8,
        source: DepthProviderKind.ncnnRelative,
        pixelCount: 8196,
        semantic: fault == 'semantic'
            ? const SemanticMatch(
                yoloTrackId: 42,
                label: 'person',
                confidence: 1,
              )
            : null,
      ),
    ];
    final tracks = tracker.update(
      observations: obs,
      timestampUs: stamp,
      relative: true,
    );
    final header = ObservationHeader(
      providerId: 'desktop-midas',
      modelId: 'midas-small-ncnn',
      modelHash: original.ncnn['modelBinSha256'],
      preprocessId: 'rgb01-chw-256-nearest-stretch-no-crop-v1',
      sessionGeneration: 1,
      frameId: f.frameId,
      sourceTimestampUs: stamp,
      producedAtUs: stamp + 1000,
      transformId: f.transformId,
      confidence: 1,
      health: ObservationHealth.healthy,
    );
    var primary = copyVisibleFrame(f, modelHash: volume.hash);
    if (fault == 'blocker') {
      final i = (f.height ~/ 2) * f.width + f.width ~/ 2;
      final ranges = List<double>.from(primary.rangeM)..[i] = 1;
      final lo = List<double>.from(primary.freeZLowerM)..[i] = .99;
      final hi = List<double>.from(primary.surfaceZUpperM)..[i] = 1.01;
      primary = copyVisibleFrame(primary, range: ranges, lower: lo, upper: hi);
    }
    final channels = volume.frames(b);
    final source = volume.source(
      b,
      fault == 'partial' ? channels.take(11).toList() : channels,
      stamp + (fault == 'future' ? 3000 : 1000),
    );
    final proof = source.observationFor(volume.context(b, stamp + 2000));
    final invalidMotion = fault == 'foreignMotion'
        ? FastMetricMotionResult(
            reason: 'test foreign',
            sessionGeneration: 2,
            frameId: f.frameId,
            capturedAtUs: stamp,
            oldestEvidenceTimestampUs: stamp,
            validUntilUs: stamp + 100000,
            transformId: f.transformId,
            candidates: 0,
            unknownPatches: 0,
            patches: const [],
          )
        : null;
    return engine.ingestGenericGeometry(
      header: header,
      detection: GenericObstacleDetectResult(
        observations: obs,
        rejectReason: ObstacleRejectReason.none,
        detectorQuality: 1,
        groundConfidence: 1,
        surfaceEvidence: const CorridorSurfaceEvidence(
          observedFraction: 1,
          continuity: 1,
          confidence: 1,
        ),
        corridorCoverage: const CorridorDepthCoverage(
          upperObservedFraction: 1,
          lowerObservedFraction: 1,
        ),
      ),
      tracks: tracks,
      now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
      orientationValid: true,
      userMoving: moving,
      poseQuality: 1,
      passageObservation: fault == 'missing' ? null : proof,
      cameraTrackInput: sequenceAssociationInput(header, primary, f),
      bodyMotion: invalidMotion,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VisibleFixture original;
  late EgoVolumeFixture volume;
  setUpAll(() {
    original = VisibleFixture(root: egoCorpus);
    volume = EgoVolumeFixture();
  });
  test(
    'complete body/floor proof resolves current relative hypotheses without mutating tracks',
    () {
      final replay = _Replay(original, volume);
      for (var i = 0; i < 3; i++) {
        final r = replay.at(i);
        expect(r.decision!.action.kind.name, 'continueForward');
        expect(replay.tracker.tracks.single.last.confidence, .95);
        expect(replay.tracker.tracks.single.hits, i + 1);
        expect(r.submittedAction!.delivery.name, 'shadow');
        expect(replay.engine.arbiter.active, isNull);
      }
    },
  );
  for (final fault in [
    'missing',
    'partial',
    'future',
    'foreignMotion',
    'semantic',
    'blocker',
  ]) {
    test(
      '$fault vetoes current resolution and fresh proof cannot erase moving stop history',
      () {
        final replay = _Replay(original, volume);
        final first = replay.at(0, fault: fault);
        expect(first.decision!.action.kind.name, 'stopNow');
        if (fault == 'blocker') {
          expect(
            first.snapshot.polarSectors
                .singleWhere((s) => s.id == 'forward')
                .occupancyProbability,
            1,
          );
        }
        for (var i = 1; i < 4; i++) {
          final next = replay.at(i);
          expect(next.decision!.action.kind.name, 'stopNow');
          expect(next.snapshot.revision, greaterThan(first.snapshot.revision));
        }
      },
    );
  }
  test(
    'loss after a clear frame stops and preserves the same session recovery latch',
    () {
      final replay = _Replay(original, volume);
      expect(replay.at(0).decision!.action.kind.name, 'continueForward');
      expect(
        replay.at(1, fault: 'missing').decision!.action.kind.name,
        'stopNow',
      );
      expect(replay.at(2).decision!.action.kind.name, 'stopNow');
      final stationary = replay.at(3, moving: false);
      expect(stationary.decision!.action.kind.name, isNot('continueForward'));
      for (var i = 4; i < 7; i++) {
        expect(
          replay.at(i, moving: false).decision!.action.kind.name,
          isNot('continueForward'),
        );
      }
    },
  );
}
