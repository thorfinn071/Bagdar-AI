import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';

import '../../../tool/model_benchmark/synthetic_passage_source.dart';

const oracleGeometryPath =
    'test/fixtures/passage_clearance_contract/blender_geometry.json';
const oraclePolicy = PassageClearancePolicy(
  maximumAgeUs: 400000,
  maximumPairSkewUs: 50000,
  maximumProcessingLatencyUs: 100000,
  minimumConfidence: 0.99,
);
const oracleRequest = PassageClearanceRequest(
  referenceFrameId: 'synthetic-camera-xy-world-z-v1',
  lateralCenterM: 0,
  widthM: 0.9,
  headroomM: 1.8,
  forwardStartM: 0.2,
  forwardEndM: 3.5,
  maximumFloorRiseM: 0.05,
  maximumFloorDropM: 0.05,
);

Map<String, dynamic> loadOracleGeometry() {
  final root =
      jsonDecode(File(oracleGeometryPath).readAsStringSync())
          as Map<String, dynamic>;
  if (root['schemaVersion'] != 1 ||
      root['scope'] != 'synthetic_full_scene_geometry_not_camera_visibility') {
    throw const FormatException('Not a full-scene synthetic geometry oracle');
  }
  for (final (key, path) in [
    (
      'sceneSha256',
      'test/fixtures/spatial_safety/blender-context-v3/scene.blend',
    ),
    (
      'corpusManifestSha256',
      'test/fixtures/spatial_safety/blender-context-v3/corpus-manifest.json',
    ),
    ('exporterSha256', 'tool/blender/export_passage_geometry.py'),
  ]) {
    if (root[key] != sha256.convert(File(path).readAsBytesSync()).toString()) {
      throw FormatException('Oracle source drift: $key');
    }
  }
  return root;
}

PassageClearanceShadowConfiguration oracleConfiguration({
  String transform = 'synthetic-rig-v1',
}) => PassageClearanceShadowConfiguration(
  calibration: PassageCalibration(
    id: 'synthetic-mesh-oracle-calibration-v1',
    providerId: 'synthetic-complete-mesh-oracle',
    modelId: 'conservative-mesh-bounds-v1',
    modelHash: sha256
        .convert(File(oracleGeometryPath).readAsBytesSync())
        .toString(),
    preprocessId: 'blender-xyz-to-walking-xzy-interval-bounds-v1',
    referenceFrameId: oracleRequest.referenceFrameId,
    transformId: transform,
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  ),
  request: oracleRequest,
  policy: oraclePolicy,
);

SyntheticPassageSource oracleSource({
  required Map<String, dynamic> geometry,
  required PassageClearanceShadowConfiguration configuration,
  required int capturedAtUs,
  int frameId = 1,
  int session = 1,
}) => SyntheticPassageSource(
  geometry: geometry,
  calibration: configuration.calibration,
  frameId: frameId,
  sessionGeneration: session,
  capturedAtUs: capturedAtUs,
  producedAtUs: capturedAtUs + 1000,
  lateralCenterM: configuration.request.lateralCenterM,
);
