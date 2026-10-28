import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_visible_body_fixture.dart';
import 'camera_visible_passage_fixture.dart';

const holdoutCorpus = 'scratch/volume-holdout-2026-10-10/corpus';

const holdoutVolumeRoot = 'scratch/volume-holdout-2026-10-10/optical';

/// New preregistered captures, plus simultaneous visible first-return channels.
/// A batch is one instantaneous state, never an inter-frame motion certificate.
class HoldoutVolumeFixture {
  final manifest = bodyJson('$holdoutVolumeRoot/manifest.json');
  final hash = bodySha('$holdoutVolumeRoot/manifest.json');
  HoldoutVolumeFixture() {
    if (manifest['promotionAllowed'] != false ||
        manifest['ordinaryCameraWired'] != false ||
        manifest['priorCorpusSha256'] !=
            bodySha('$holdoutCorpus/manifest.json') ||
        (manifest['batches'] as List).length != 84) {
      throw StateError('Changed original corpus/scope');
    }
    for (final e in (manifest['sources'] as Map).entries) {
      if (bodySha(e.key as String) != e.value) {
        throw StateError('Changed optical exporter ${e.key}');
      }
    }
  }

  Map batch(String layout, int frame) => (manifest['batches'] as List)
      .cast<Map>()
      .singleWhere((b) => b['layoutId'] == layout && b['frameId'] == frame);

  PassageCalibration calibration() => PassageCalibration(
    id: 'synthetic-holdout-volume-v1',
    providerId: 'synthetic-synchronized-rig-current-volume',
    modelId: 'visible-first-return',
    modelHash: hash,
    preprocessId: 'visible-whole-pixel-coherent-height-v1',
    referenceFrameId: visibleRequest.referenceFrameId,
    transformId: 'synthetic-optical-centre-fixed-v1',
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  CameraVisibleDepthFrame depth(Map b, Map p) {
    if (p['sceneStateSha256'] != b['sceneStateSha256'] ||
        p['capturedAtUs'] != b['capturedAtUs'] ||
        p['frameId'] != b['frameId'] ||
        p['sessionGeneration'] != b['sessionGeneration'] ||
        b['primaryArraysReproduced'] != true ||
        b['zeroSkewUs'] != 0) {
      throw StateError('Mixed capture/scene state');
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
      modelHash: hash,
      transformId: '${calibration().transformId}/${p['cameraId']}',
      referenceFrameId: visibleRequest.referenceFrameId,
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
      rangeM: bodyFloats(bodyAsset(holdoutVolumeRoot, p['depth'] as Map)),
      freeZLowerM: bodyFloats(
        bodyAsset(holdoutVolumeRoot, p['freeZLower'] as Map),
      ),
      surfaceZUpperM: bodyFloats(
        bodyAsset(holdoutVolumeRoot, p['surfaceZUpper'] as Map),
      ),
      valid: gzip
          .decode(bodyAsset(holdoutVolumeRoot, p['validity'] as Map))
          .map((v) => v == 1)
          .toList(),
    );
  }

  List<CameraHeightEnvelopeFrame> frames(Map b) => [
    for (final p in (b['channels'] as List).cast<Map>())
      CameraHeightEnvelopeFrame(
        depth: depth(b, p),
        heightLowerM: bodyFloats(
          bodyAsset(holdoutVolumeRoot, p['heightLower'] as Map),
        ),
        heightUpperM: bodyFloats(
          bodyAsset(holdoutVolumeRoot, p['heightUpper'] as Map),
        ),
        firstZLowerM: bodyFloats(
          bodyAsset(holdoutVolumeRoot, p['firstZLower'] as Map),
        ),
      ),
  ];

  List<SyntheticRigChannel> channels(Map b) => [
    for (final p in (b['channels'] as List).cast<Map>())
      SyntheticRigChannel(
        cameraId: p['cameraId'] as String,
        transformId: '${calibration().transformId}/${p['cameraId']}',
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

  PassageEvaluationContext context(Map b, int nowUs) =>
      PassageEvaluationContext(
        nowUs: nowUs,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: b['sessionGeneration'] as int,
        frameId: b['frameId'] as int,
        rgbTimestampUs: b['capturedAtUs'] as int,
        transformId: calibration().transformId,
      );

  CameraSynchronizedEnvelopeSource source(
    Map b,
    List<CameraHeightEnvelopeFrame> input,
    int producedAtUs,
  ) => CameraSynchronizedEnvelopeSource(
    channels: channels(b),
    batchFrameId: b['frameId'] as int,
    sessionGeneration: b['sessionGeneration'] as int,
    capturedAtUs: b['capturedAtUs'] as int,
    stationarySyntheticScene: b['stationarySyntheticScene'] as bool,
    calibration: calibration(),
    request: visibleRequest,
    frames: input,
    producedAtUs: producedAtUs,
  );
}
