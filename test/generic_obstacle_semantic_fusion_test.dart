import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

Track _track({
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
    final unrelatedCar = _track(
      id: 10,
      label: 'car',
      bounds: const Rect.fromLTWH(0.40, 0.30, 0.05, 0.30),
      confidence: 0.95,
    );
    final matchingPerson = _track(
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

    final stale = controller.debugSemanticFor(
      observation: observation,
      imageWidth: 100,
      imageHeight: 100,
      frame: frame,
      now: at.add(const Duration(seconds: 2)),
    );
    expect(stale, isNull);
  });
}
