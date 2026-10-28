import 'dart:io';

import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import '../../test/harness/camera_visible_passage_fixture.dart';

const fastCorpus = 'test/fixtures/spatial_safety/camera-scale-motion-v1';
const fastRgbContract = FastRgbContract(
  providerId: 'synthetic-rgb-capture',
  revision: 'predecoded-u8-v1',
  preprocessId: 'rgb-u8-256-nearest-stretch-no-crop-v1',
);

FastMetricMotionInput fastInput(
  VisibleFixture fixture,
  Map<String, dynamic> layout,
  CameraVisibleDepthFrame f,
) {
  final record = (fixture.ncnn['frames'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere(
        (r) => r['layoutId'] == layout['id'] && r['frameId'] == f.frameId,
      );
  final asset = record['rgbPixels'] as Map;
  final path = '${fixture.root}/ncnn/${asset['path']}';
  if (visibleSha(path) != asset['sha256']) {
    throw StateError('RGB capture asset drift');
  }
  // This is a direct, preloaded RGB capture fixture. No inference is awaited
  // and no NN-produced timestamp or confidence is used in this packet.
  return fastInputWithPixels(f, gzip.decode(File(path).readAsBytesSync()));
}

FastMetricMotionInput fastInputWithPixels(
  CameraVisibleDepthFrame f,
  List<int> rgb,
) => FastMetricMotionInput(
  camera: FastCameraInput(
    rgbHeader: FastRgbHeader(
      providerId: fastRgbContract.providerId,
      revision: fastRgbContract.revision,
      preprocessId: fastRgbContract.preprocessId,
      transformId: f.transformId,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      sourceTimestampUs: f.capturedAtUs,
      producedAtUs: f.capturedAtUs + 1000,
      healthy: true,
      confidence: 1,
    ),
    depth: f,
    imageGeometry: FastRgbGeometry(
      cameraId: f.cameraId,
      width: f.width,
      height: f.height,
      fx: f.fx,
      fy: f.fy,
      cx: f.cx,
      cy: f.cy,
      rotation: f.rotation,
      originM: f.originM,
    ),
  ),
  rgb: rgb,
  positionErrorM: .0001,
  angularErrorRad: 0,
);
