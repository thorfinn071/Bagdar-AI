import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/world/generic_geometry_scene_adapter.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

Track _yoloTrack({
  required int id,
  required String label,
  required Rect bounds,
  required double confidence,
}) => Track(
  id: id,
  label: label,
  cx: bounds.center.dx * 100,
  cy: bounds.center.dy * 100,
  x1: bounds.left * 100,
  y1: bounds.top * 100,
  x2: bounds.right * 100,
  y2: bounds.bottom * 100,
  dist: 'close',
  distM: 1.0,
  initialConf: confidence,
);

void main() {
  test('semantic fusion uses one fresh spatially matched YOLO track', () {
    final controller = DepthPipelineController(
      vm: CameraViewModel(),
      models: ModelService.instance,
    );
    final at = DateTime(2026, 1, 1);
    final unrelatedCar = _yoloTrack(
      id: 10,
      label: 'car',
      bounds: const Rect.fromLTWH(0.40, 0.30, 0.05, 0.30),
      confidence: 0.95,
    );
    final matchingPerson = _yoloTrack(
      id: 20,
      label: 'person',
      bounds: const Rect.fromLTWH(0.50, 0.30, 0.10, 0.30),
      confidence: 0.65,
    );
    controller.updateYoloTracks(
      <Track>[unrelatedCar, matchingPerson],
      imgW: 100,
      now: at,
    );
    final frame = DepthFrame(
      values: Float32List.fromList(<double>[0.8]),
      confidence01: Float32List.fromList(<double>[1.0]),
      width: 1,
      height: 1,
      timestampUs: at.microsecondsSinceEpoch,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: 'test-depth',
      modelHash: 'test-hash',
      preprocessId: 'test-preprocess',
      cropTopFraction: 0,
      frameQuality: 1,
      alignedToImage: true,
    );
    const observation = GenericObstacleObservation(
      geometry: ObstacleGeometry.unknown,
      zone: HazardZone.center,
      normalizedBounds: Rect.fromLTWH(0.50, 0.30, 0.10, 0.30),
      corridorOverlap: 0.5,
      confidence: 0.8,
      relativeProximity: 0.8,
      source: DepthProviderKind.ncnnRelative,
    );

    final match = controller.debugSemanticFor(
      observation: observation,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(milliseconds: 100)),
    );
    expect(match?.yoloTrackId, 20);
    expect(match?.label, 'person');
    expect(match?.confidence, 0.65);

    // Tracker objects are mutable. A later update must not rewrite an already
    // submitted frame's numeric/semantic snapshot.
    matchingPerson
      ..label = 'car'
      ..avgConf = 0.99
      ..x1 = 0
      ..x2 = 1;
    final unchanged = controller.debugSemanticFor(
      observation: observation,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(milliseconds: 100)),
    );
    expect(unchanged?.yoloTrackId, 20);
    expect(unchanged?.label, 'person');
    expect(unchanged?.confidence, 0.65);

    final stale = controller.debugSemanticFor(
      observation: observation,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(seconds: 2)),
    );
    expect(stale, isNull);
  });

  test('matched semantic reaches the spatial scene through the track', () {
    final controller = DepthPipelineController(
      vm: CameraViewModel(),
      models: ModelService.instance,
    );
    final at = DateTime.utc(2026, 1, 1);
    controller.updateYoloTracks(
      <Track>[
        _yoloTrack(
          id: 20,
          label: 'person',
          bounds: const Rect.fromLTWH(0.45, 0.25, 0.20, 0.50),
          confidence: 0.75,
        ),
      ],
      imgW: 100,
      now: at,
    );
    final frame = DepthFrame(
      values: Float32List.fromList(<double>[0.8]),
      confidence01: Float32List.fromList(<double>[1.0]),
      width: 1,
      height: 1,
      timestampUs: at.microsecondsSinceEpoch,
      provider: DepthProviderKind.ncnnRelative,
      semantics: DepthValueSemantics.relativeProximity,
      modelId: 'test-depth',
      modelHash: 'test-hash',
      preprocessId: 'test-preprocess',
      cropTopFraction: 0,
      frameQuality: 1,
      alignedToImage: true,
    );
    const observation = GenericObstacleObservation(
      geometry: ObstacleGeometry.broadSurface,
      zone: HazardZone.center,
      normalizedBounds: Rect.fromLTWH(0.45, 0.25, 0.20, 0.50),
      corridorOverlap: 0.8,
      confidence: 0.9,
      relativeProximity: 0.9,
      source: DepthProviderKind.ncnnRelative,
    );
    final track = GenericObstacleTrack(
      id: 7,
      last: observation.copyWith(trackId: 7),
      hits: 3,
      misses: 0,
      age: 3,
      proximityHist: <double>[0.7, 0.8, 0.9],
      metricHist: <double?>[null, null, null],
      timestampUsHist: <int>[1, 2, 3],
      confirmed: true,
    );

    final match = controller.debugAttachSemanticToTrack(
      track: track,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(milliseconds: 100)),
    );
    expect(match?.yoloTrackId, 20);
    expect(track.last.semantic?.label, 'person');

    final scene = LocalSceneModel.relative().ingestGenericGeometry(
      header: ObservationHeader(
        providerId: 'generic-depth',
        modelId: frame.modelId,
        modelHash: frame.modelHash,
        preprocessId: frame.preprocessId,
        sessionGeneration: 1,
        frameId: 1,
        sourceTimestampUs: at.microsecondsSinceEpoch,
        producedAtUs: at.microsecondsSinceEpoch + 1000,
        transformId: 'test-transform',
        confidence: 0.9,
        health: ObservationHealth.healthy,
      ),
      detection: const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[observation],
        rejectReason: ObstacleRejectReason.none,
        detectorQuality: 0.9,
        groundConfidence: 0.9,
      ),
      tracks: <GenericObstacleTrack>[track],
      at: at.add(const Duration(milliseconds: 100)),
      validUntil: at.add(const Duration(seconds: 1)),
      poseQuality: 0.9,
    );
    final forward = scene.snapshot.polarSectors.singleWhere(
      (element) => element.id == 'forward',
    );
    expect(scene.accepted, isTrue);
    expect(forward.sourceMask, contains('geometry:generic-depth'));
    expect(forward.sourceMask, contains('semantic:20'));

    controller.updateYoloTracks(const <Track>[], imgW: 100, now: at);
    final cleared = controller.debugAttachSemanticToTrack(
      track: track,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(milliseconds: 200)),
    );
    expect(cleared, isNull);
    expect(track.last.semantic, isNull);
  });
}
