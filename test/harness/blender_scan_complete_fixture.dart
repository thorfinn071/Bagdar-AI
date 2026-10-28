import 'dart:convert';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_scan_coverage_fixture.dart';
import 'blender_visible_body_fixture.dart';

const scanCompleteRoot =
    'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1';
const scanWatertightRoot =
    'test/fixtures/spatial_safety/blender-scan-watertight-height-v1';
const scanExactRoot =
    'test/fixtures/spatial_safety/blender-scan-exact-height-v1';

class ScanCompleteFixture {
  final prior = ScanCoverageFixture();
  final manifest = bodyJson('$scanCompleteRoot/manifest.json');
  final supplement = bodyJson('$scanWatertightRoot/manifest.json');
  final exact = bodyJson('$scanExactRoot/manifest.json');
  final modelHash = bodySha('$scanExactRoot/manifest.json');

  ScanCompleteFixture() {
    if (manifest['promotionAllowed'] != false ||
        manifest['priorManifestSha256'] != prior.modelHash) {
      throw StateError('Unbound complete optical envelope');
    }
    if (supplement['promotionAllowed'] != false ||
        supplement['priorManifestSha256'] !=
            bodySha('$scanCompleteRoot/manifest.json')) {
      throw StateError('Unbound canonical height supplement');
    }
    if (exact['promotionAllowed'] != false ||
        exact['priorManifestSha256'] !=
            bodySha('$scanWatertightRoot/manifest.json')) {
      throw StateError('Unbound exact height supplement');
    }
    for (final data in [manifest, supplement, exact]) {
      for (final entry in (data['sources'] as Map).entries) {
        if (bodySha(entry.key as String) != entry.value) {
          throw StateError('Changed complete envelope source ${entry.key}');
        }
      }
    }
  }

  PassageCalibration calibration(String id) => PassageCalibration(
    id: 'paired-synthetic-complete-exact-envelope-v1',
    providerId: 'paired-synthetic-complete-envelope',
    modelId: 'first-return-complete-envelope-v1',
    modelHash: modelHash,
    preprocessId: 'opaque-visible-pixel-partition-v1',
    referenceFrameId: pairedBodyRequest.referenceFrameId,
    transformId: prior.prior.transform(id),
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  List<CameraHeightEnvelopeFrame> frames(Map layout) {
    final id = layout['sceneId'] as String;
    final previous = (prior.manifest['layouts'] as List)
        .cast<Map>()
        .singleWhere((l) => l['sceneId'] == id);
    final records = (layout['frames'] as List).cast<Map>().toList();
    final canonical = (supplement['layouts'] as List).cast<Map>().singleWhere(
      (l) => l['sceneId'] == id,
    );
    final exactLayout = (exact['layouts'] as List).cast<Map>().singleWhere(
      (l) => l['sceneId'] == id,
    );
    return [
      for (var i = 0; i < records.length; i++)
        _frame(
          records[i],
          id,
          (previous['coverageViewsNewBounds'] as List)[i] as Map,
          (canonical['frames'] as List)[i] as Map,
          (exactLayout['frames'] as List)[i] as Map,
        ),
    ];
  }

  List<CameraHeightEnvelopeFrame> originalHeightFrames(Map layout) {
    final current = frames(layout);
    final records = (layout['frames'] as List).cast<Map>();
    return [
      for (var i = 0; i < current.length; i++)
        completeFrameCopy(
          current[i],
          heightLower: bodyFloats(
            bodyAsset(
              scanCompleteRoot,
              records.elementAt(i)['heightLower'] as Map,
            ),
          ),
          heightUpper: bodyFloats(
            bodyAsset(
              scanCompleteRoot,
              records.elementAt(i)['heightUpper'] as Map,
            ),
          ),
        ),
    ];
  }

  CameraHeightEnvelopeFrame _frame(
    Map record,
    String id,
    Map expected,
    Map canonical,
    Map exactPacket,
  ) {
    if (record['fourArraysExact'] != true ||
        jsonEncode(record['axisPacket']) != jsonEncode(expected)) {
      throw StateError('Changed optical packet correspondence');
    }
    if (jsonEncode(canonical['priorPacket']) != jsonEncode(record)) {
      throw StateError('Changed canonical packet correspondence');
    }
    if (jsonEncode(exactPacket['priorPacket']) != jsonEncode(canonical)) {
      throw StateError('Changed exact packet correspondence');
    }
    final f = prior.packet(record['axisPacket'] as Map, id);
    final depth = CameraVisibleDepthFrame(
      width: f.width,
      height: f.height,
      frameId: f.frameId,
      capturedAtUs: f.capturedAtUs,
      sessionGeneration: f.sessionGeneration,
      fx: f.fx,
      fy: f.fy,
      cx: f.cx,
      cy: f.cy,
      errorM: f.errorM,
      poseQuality: f.poseQuality,
      cameraId: f.cameraId,
      modelHash: modelHash,
      transformId: f.transformId,
      referenceFrameId: f.referenceFrameId,
      units: f.units,
      providerHealthy: f.providerHealthy,
      rotation: f.rotation,
      originM: f.originM,
      rangeM: f.rangeM,
      freeZLowerM: f.freeZLowerM,
      surfaceZUpperM: f.surfaceZUpperM,
      valid: f.valid,
    );
    final first = bodyFloats(
      bodyAsset(scanCompleteRoot, record['firstZLower'] as Map),
    );
    final lower = bodyFloats(
      bodyAsset(scanExactRoot, exactPacket['heightLower'] as Map),
    );
    final upper = bodyFloats(
      bodyAsset(scanExactRoot, exactPacket['heightUpper'] as Map),
    );
    // The independent height supplement cannot replace absent free-Z proof.
    // Such pixels remain wholly unknown under the combined input contract.
    for (var i = 0; i < first.length; i++) {
      if (first[i].isNaN) {
        lower[i] = double.nan;
        upper[i] = double.nan;
      }
    }
    return CameraHeightEnvelopeFrame(
      depth: depth,
      heightLowerM: lower,
      heightUpperM: upper,
      firstZLowerM: first,
    );
  }
}

CameraHeightEnvelopeFrame completeFrameCopy(
  CameraHeightEnvelopeFrame f, {
  CameraVisibleDepthFrame? depth,
  List<double>? heightLower,
  List<double>? heightUpper,
  List<double>? firstZLower,
}) => CameraHeightEnvelopeFrame(
  depth: depth ?? f.depth,
  heightLowerM: heightLower ?? f.heightLowerM,
  heightUpperM: heightUpper ?? f.heightUpperM,
  firstZLowerM: firstZLower ?? f.firstZLowerM,
);
