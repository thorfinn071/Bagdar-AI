import 'dart:io';

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_visible_body_fixture.dart';

const scanCoverageRoot =
    'test/fixtures/spatial_safety/blender-scan-coverage-v1';

class ScanCoverageFixture {
  final prior = PairedBodyFixture();
  final manifest = bodyJson('$scanCoverageRoot/manifest.json');
  final modelHash = bodySha('$scanCoverageRoot/manifest.json');

  ScanCoverageFixture() {
    if (manifest['promotionAllowed'] != false ||
        manifest['priorVisibleManifestSha256'] != prior.modelHash ||
        manifest['sourceCorpusSha256'] !=
            bodySha('$pairedRgbRoot/corpus-manifest.json')) {
      throw StateError('Invalid scan coverage provenance');
    }
    for (final entry in (manifest['sources'] as Map).entries) {
      if (bodySha(entry.key as String) != entry.value) {
        throw StateError('Changed scan source ${entry.key}');
      }
    }
  }

  PassageCalibration calibration(String id) => PassageCalibration(
    id: 'paired-synthetic-scan-coverage-v1',
    providerId: 'paired-synthetic-visible-scan',
    modelId: 'first-return-surface-envelope-v1',
    modelHash: modelHash,
    preprocessId: 'opaque-first-return-pixel-partition-v1',
    referenceFrameId: pairedBodyRequest.referenceFrameId,
    transformId: prior.transform(id),
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  CameraVisibleDepthFrame packet(
    Map p,
    String id, {
    bool legacy = false,
  }) => CameraVisibleDepthFrame(
    width: p['width'] as int,
    height: p['height'] as int,
    frameId: p['frameId'] as int,
    capturedAtUs: pairedBodyStamp + (p['capturedOffsetMs'] as int) * 1000,
    sessionGeneration: 1,
    fx: (p['fx'] as num).toDouble(),
    fy: (p['fy'] as num).toDouble(),
    cx: (p['cx'] as num).toDouble(),
    cy: (p['cy'] as num).toDouble(),
    errorM: 0,
    poseQuality: 1,
    cameraId: 'paired-one-camera',
    modelHash: modelHash,
    transformId: prior.transform(id),
    referenceFrameId: pairedBodyRequest.referenceFrameId,
    units: PassageUnits.metricMeters,
    providerHealthy: true,
    rotation: (p['cameraToWalkingRotation'] as List)
        .map((v) => (v as num).toDouble())
        .toList(),
    originM: (p['cameraOriginM'] as List)
        .map((v) => (v as num).toDouble())
        .toList(),
    rangeM: bodyFloats(
      bodyAsset(legacy ? pairedBodyRoot : scanCoverageRoot, p['depth'] as Map),
    ),
    freeZLowerM: bodyFloats(
      bodyAsset(
        legacy ? pairedBodyRoot : scanCoverageRoot,
        p['freeZLower'] as Map,
      ),
    ),
    surfaceZUpperM: bodyFloats(
      bodyAsset(
        legacy ? pairedBodyRoot : scanCoverageRoot,
        p['surfaceZUpper'] as Map,
      ),
    ),
    valid: gzip
        .decode(
          bodyAsset(
            legacy ? pairedBodyRoot : scanCoverageRoot,
            p['validity'] as Map,
          ),
        )
        .map((v) => v == 1)
        .toList(),
  );

  List<CameraVisibleDepthFrame> frames(Map layout, String mode) {
    final id = layout['sceneId'] as String;
    final legacy = mode == 'old-views-old-bounds';
    final records = legacy
        ? (prior.manifest['sequences'] as List).cast<Map>().singleWhere(
                (s) => s['sceneId'] == id,
              )['staticScan']
              as List
        : layout[mode == 'old-views-new-bounds'
                  ? 'sameViewsNewBounds'
                  : 'coverageViewsNewBounds']
              as List;
    return records
        .cast<Map>()
        .map((p) => packet(p, id, legacy: legacy))
        .toList();
  }
}

CameraVisibleDepthFrame scanFrameCopy(
  CameraVisibleDepthFrame f, {
  List<double>? upper,
  List<bool>? valid,
  List<double>? origin,
  PassageUnits? units,
  int? session,
}) => CameraVisibleDepthFrame(
  width: f.width,
  height: f.height,
  frameId: f.frameId,
  capturedAtUs: f.capturedAtUs,
  sessionGeneration: session ?? f.sessionGeneration,
  fx: f.fx,
  fy: f.fy,
  cx: f.cx,
  cy: f.cy,
  errorM: f.errorM,
  poseQuality: f.poseQuality,
  cameraId: f.cameraId,
  modelHash: f.modelHash,
  transformId: f.transformId,
  referenceFrameId: f.referenceFrameId,
  units: units ?? f.units,
  providerHealthy: f.providerHealthy,
  rotation: f.rotation,
  originM: origin ?? f.originM,
  rangeM: f.rangeM,
  freeZLowerM: f.freeZLowerM,
  surfaceZUpperM: upper ?? f.surfaceZUpperM,
  valid: valid ?? f.valid,
);
