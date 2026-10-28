import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_visible_body_fixture.dart';

const synchronizedPassageRoot =
    'scratch/synchronized-passage-2026-10-09/optical-v2';

/// Optical packets only. Labels are consulted after perception, for scoring.
class SynchronizedPassageFixture {
  final String root;
  final Map<String, dynamic> manifest;
  final String modelHash;

  SynchronizedPassageFixture({
    this.root = synchronizedPassageRoot,
    bool pilot = false,
  }) : manifest = bodyJson('$root/${pilot ? 'pilot' : 'manifest'}.json'),
       modelHash = bodySha('$root/${pilot ? 'pilot' : 'manifest'}.json') {
    if (manifest['promotionAllowed'] != false ||
        manifest['runtimeWired'] != false ||
        manifest['referenceFrameId'] != pairedBodyRequest.referenceFrameId ||
        manifest['pilotOnly'] != pilot) {
      throw StateError('Invalid synchronized passage scope');
    }
    for (final e in (manifest['sources'] as Map).entries) {
      if (bodySha(e.key as String) != e.value) {
        throw StateError('Changed exporter ${e.key}');
      }
    }
  }

  List<Map> get batches => (manifest['batches'] as List).cast<Map>();
  String transform(Map batch) =>
      'synchronized-${batch['sceneId']}-${batch['contrast'] ?? 'base'}-256x256';

  PassageCalibration calibration(Map batch, String mode) => PassageCalibration(
    id: 'synchronized-paired-$mode-v1',
    providerId: 'synthetic-synchronized-rig-paired-$mode',
    modelId: mode == 'rig'
        ? 'synthetic-first-return-complete-envelope-v1'
        : 'first-return-whole-pixel-v1',
    modelHash: modelHash,
    preprocessId: mode == 'rig'
        ? 'visible-whole-pixel-coherent-height-v1'
        : 'opaque-first-return-whole-pixel-v1',
    referenceFrameId: pairedBodyRequest.referenceFrameId,
    transformId: transform(batch),
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  CameraVisibleDepthFrame depth(Map batch, Map p, {bool primary = false}) {
    if (p['sceneStateSha256'] != batch['sceneStateSha256'] ||
        p['capturedAtUs'] != batch['capturedAtUs'] ||
        p['frameId'] != batch['frameId'] ||
        p['sessionGeneration'] != batch['sessionGeneration']) {
      throw StateError('Mixed scene state or capture');
    }
    return CameraVisibleDepthFrame(
      width: p['width'] as int,
      height: p['height'] as int,
      frameId: p['frameId'] as int,
      capturedAtUs: p['capturedAtUs'] as int,
      sessionGeneration: p['sessionGeneration'] as int,
      fx: (p['fx'] as num).toDouble(),
      fy: (p['fy'] as num).toDouble(),
      cx: (p['cx'] as num).toDouble(),
      cy: (p['cy'] as num).toDouble(),
      errorM: 0,
      poseQuality: 1,
      cameraId: p['cameraId'] as String,
      modelHash: modelHash,
      // The primary is explicitly bound to the aggregate RGB coordinate
      // namespace. Its intrinsics, pose, pixels, capture and frame never change.
      transformId: primary
          ? transform(batch)
          : '${transform(batch)}/${p['cameraId']}',
      referenceFrameId: pairedBodyRequest.referenceFrameId,
      units: PassageUnits.metricMeters,
      providerHealthy: true,
      rotation: (p['cameraToWalkingRotation'] as List)
          .cast<num>()
          .map((v) => v.toDouble())
          .toList(),
      originM: (p['cameraOriginM'] as List)
          .cast<num>()
          .map((v) => v.toDouble())
          .toList(),
      rangeM: bodyFloats(bodyAsset(root, p['depth'] as Map)),
      freeZLowerM: bodyFloats(bodyAsset(root, p['freeZLower'] as Map)),
      surfaceZUpperM: bodyFloats(bodyAsset(root, p['surfaceZUpper'] as Map)),
      valid: gzip
          .decode(bodyAsset(root, p['validity'] as Map))
          .map((v) => v == 1)
          .toList(),
    );
  }

  CameraVisibleDepthFrame primary(Map batch) =>
      depth(batch, batch['primary'] as Map, primary: true);

  List<CameraHeightEnvelopeFrame> frames(Map batch) => [
    for (final p in (batch['channels'] as List).cast<Map>())
      CameraHeightEnvelopeFrame(
        depth: depth(batch, p),
        heightLowerM: bodyFloats(bodyAsset(root, p['heightLower'] as Map)),
        heightUpperM: bodyFloats(bodyAsset(root, p['heightUpper'] as Map)),
        firstZLowerM: bodyFloats(bodyAsset(root, p['firstZLower'] as Map)),
      ),
  ];

  List<SyntheticRigChannel> channels(Map batch) => [
    for (final p in (batch['channels'] as List).cast<Map>())
      SyntheticRigChannel(
        cameraId: p['cameraId'] as String,
        transformId: '${transform(batch)}/${p['cameraId']}',
        width: p['width'] as int,
        height: p['height'] as int,
        fx: (p['fx'] as num).toDouble(),
        fy: (p['fy'] as num).toDouble(),
        cx: (p['cx'] as num).toDouble(),
        cy: (p['cy'] as num).toDouble(),
        rotation: (p['cameraToWalkingRotation'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
        originM: (p['cameraOriginM'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
      ),
  ];

  CameraSynchronizedEnvelopeSource source(
    Map batch,
    List<CameraHeightEnvelopeFrame> input,
    int producedAtUs, {
    bool? staticScene,
  }) => CameraSynchronizedEnvelopeSource(
    channels: channels(batch),
    batchFrameId: batch['frameId'] as int,
    sessionGeneration: batch['sessionGeneration'] as int,
    capturedAtUs: batch['capturedAtUs'] as int,
    stationarySyntheticScene:
        staticScene ?? batch['stationarySyntheticScene'] as bool,
    calibration: calibration(batch, 'rig'),
    request: pairedBodyRequest,
    frames: input,
    producedAtUs: producedAtUs,
  );

  PassageEvaluationContext context(Map batch, int nowUs) =>
      PassageEvaluationContext(
        nowUs: nowUs,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: batch['sessionGeneration'] as int,
        frameId: batch['frameId'] as int,
        rgbTimestampUs: batch['capturedAtUs'] as int,
        transformId: transform(batch),
      );
}
