import 'dart:typed_data';
import 'dart:ui';

import 'package:bagdar/camera/camera_session.dart';
import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _SemanticContext implements CameraViewModel {
  @override
  final CameraSession cameraSession = CameraSession();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected UI access: ${invocation.memberName}');
}

void main() {
  final at = DateTime.utc(2026, 10, 5);
  final frame = DepthFrame(
    values: Float32List.fromList([0.8]),
    confidence01: Float32List.fromList([1]),
    width: 1,
    height: 1,
    timestampUs: at.microsecondsSinceEpoch,
    provider: DepthProviderKind.ncnnRelative,
    semantics: DepthValueSemantics.relativeProximity,
    modelId: 'test',
    modelHash: 'test',
    preprocessId: 'test',
    cropTopFraction: 0,
    frameQuality: 1,
    alignedToImage: true,
  );
  const observation = GenericObstacleObservation(
    geometry: ObstacleGeometry.unknown,
    zone: HazardZone.center,
    normalizedBounds: Rect.fromLTWH(0.4, 0.2, 0.2, 0.5),
    corridorOverlap: 0.5,
    confidence: 0.8,
    relativeProximity: 0.8,
    source: DepthProviderKind.ncnnRelative,
  );
  final track = Track(
    id: 1,
    label: 'person',
    cx: 50,
    cy: 45,
    x1: 40,
    x2: 60,
    y1: 20,
    y2: 70,
    dist: 'close',
    distM: -1,
    initialConf: 0.8,
  );

  for (final sample in [
    (
      name: 'same image',
      offsetUs: 0,
      width: 100,
      height: 100,
      rotation: 0,
      mirrored: false,
      matches: true,
    ),
    (
      name: '150 ms source boundary',
      offsetUs: -150000,
      width: 100,
      height: 100,
      rotation: 0,
      mirrored: false,
      matches: true,
    ),
    (
      name: 'future image',
      offsetUs: 1,
      width: 100,
      height: 100,
      rotation: 0,
      mirrored: false,
      matches: false,
    ),
    (
      name: 'source mismatch beyond 150 ms',
      offsetUs: -150001,
      width: 100,
      height: 100,
      rotation: 0,
      mirrored: false,
      matches: false,
    ),
    (
      name: 'width',
      offsetUs: 0,
      width: 200,
      height: 100,
      rotation: 0,
      mirrored: false,
      matches: false,
    ),
    (
      name: 'height',
      offsetUs: 0,
      width: 100,
      height: 200,
      rotation: 0,
      mirrored: false,
      matches: false,
    ),
    (
      name: 'rotation',
      offsetUs: 0,
      width: 100,
      height: 100,
      rotation: 90,
      mirrored: false,
      matches: false,
    ),
    (
      name: 'mirror',
      offsetUs: 0,
      width: 100,
      height: 100,
      rotation: 0,
      mirrored: true,
      matches: false,
    ),
  ]) {
    test('semantic admission checks ${sample.name}', () {
      final controller = DepthPipelineController(
        vm: _SemanticContext(),
        models: ModelService.instance,
      );
      controller.updateYoloTracks(
        [track],
        imgW: sample.width,
        imgH: sample.height,
        rotationDegrees: sample.rotation,
        mirrored: sample.mirrored,
        now: at.add(Duration(microseconds: sample.offsetUs)),
      );
      final result = controller.debugSemanticFor(
        observation: observation,
        imageWidth: 100,
        imageHeight: 100,
        frame: frame,
        now: at,
      );
      expect(result?.label, sample.matches ? 'person' : isNull);
    });
  }
  test(
    'a new camera session clears old semantic and hazard confidence caches',
    () {
      final vm = _SemanticContext();
      final controller = DepthPipelineController(
        vm: vm,
        models: ModelService.instance,
      );
      controller.updateYoloTracks(
        [track],
        imgW: 100,
        imgH: 100,
        rotationDegrees: 0,
        mirrored: false,
        now: at,
      );
      expect(controller.yoloHazardConfByZoneForTesting, isNotEmpty);
      controller.beginSession(vm.cameraSession.beginNewSession());
      expect(controller.yoloHazardConfByZoneForTesting, isEmpty);
      expect(
        controller.debugSemanticFor(
          observation: observation,
          imageWidth: 100,
          imageHeight: 100,
          frame: frame,
          now: at,
        ),
        isNull,
      );
    },
  );
}
