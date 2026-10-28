import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_visible_body_fixture.dart';

const synchronizedRigRoot =
    'test/fixtures/spatial_safety/blender-synchronized-rig-v2';

const synchronizedRigRequest = PassageClearanceRequest(
  referenceFrameId: 'synthetic-rig-walking-v1',
  lateralCenterM: 0,
  widthM: .9,
  headroomM: 1.85,
  forwardStartM: .2,
  forwardEndM: 3.5,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);

PassageClearanceResult rigDecision(
  PassageCalibration calibration,
  PassageEvaluationContext context,
  PassageClearanceObservation observation,
) => const PassageClearanceEvaluator(policy: pairedBodyPolicy).evaluate(
  request: synchronizedRigRequest,
  context: context,
  calibration: calibration,
  observation: observation,
);

class SynchronizedRigFixture {
  final manifest = bodyJson('$synchronizedRigRoot/manifest.json');
  final modelHash = bodySha('$synchronizedRigRoot/manifest.json');

  SynchronizedRigFixture() {
    if (manifest['schemaVersion'] != 1 ||
        manifest['corpusId'] != 'blender-synchronized-rig-v2' ||
        manifest['promotionAllowed'] != false ||
        manifest['runtimeWired'] != false ||
        manifest['timestampDomain'] != 'utcEpochMicroseconds') {
      throw StateError('Invalid synthetic rig scope');
    }
    for (final entry in (manifest['sources'] as Map).entries) {
      if (bodySha(entry.key as String) != entry.value) {
        throw StateError('Changed rig export source ${entry.key}');
      }
    }
  }

  List<Map> get batches => (manifest['batches'] as List).cast<Map>();

  String transform(Map batch, String mode) => '${batch['id']}/rig-$mode-v1';

  PassageCalibration calibration(Map batch, String mode) => PassageCalibration(
    id: 'synthetic-rig-visible-envelope-v1',
    providerId: 'synthetic-synchronized-rig-v1',
    modelId: 'synthetic-first-return-complete-envelope-v1',
    modelHash: modelHash,
    preprocessId: 'visible-whole-pixel-exact-height-v1',
    referenceFrameId: manifest['referenceFrameId'] as String,
    transformId: transform(batch, mode),
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: true,
    alignmentValidated: true,
    floorReferenceValidated: true,
  );

  List<Map> packets(Map batch, String mode) {
    final all = (batch['channels'] as List).cast<Map>();
    return mode == 'batch' ? all : [all[manifest['singleChannelIndex'] as int]];
  }

  List<SyntheticRigChannel> channels(Map batch, String mode) => [
    for (final p in packets(batch, mode))
      SyntheticRigChannel(
        cameraId: p['cameraId'] as String,
        transformId: '${transform(batch, mode)}/${p['cameraId']}',
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

  List<CameraHeightEnvelopeFrame> frames(Map batch, String mode) => [
    for (final p in packets(batch, mode)) _frame(batch, p, mode),
  ];

  CameraHeightEnvelopeFrame _frame(Map batch, Map p, String mode) {
    if (p['sceneStateSha256'] != batch['sceneStateSha256'] ||
        p['capturedAtUs'] != batch['capturedAtUs'] ||
        p['frameId'] != batch['frameId'] ||
        p['sessionGeneration'] != batch['sessionGeneration']) {
      throw StateError('Channels do not share one scene state/capture');
    }
    List<double> floats(String key) =>
        bodyFloats(bodyAsset(synchronizedRigRoot, p[key] as Map));
    return CameraHeightEnvelopeFrame(
      depth: CameraVisibleDepthFrame(
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
        transformId: '${transform(batch, mode)}/${p['cameraId']}',
        referenceFrameId: manifest['referenceFrameId'] as String,
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
        rangeM: floats('depth'),
        freeZLowerM: floats('freeZLower'),
        surfaceZUpperM: floats('surfaceZUpper'),
        valid: gzip
            .decode(bodyAsset(synchronizedRigRoot, p['validity'] as Map))
            .map((v) => v == 1)
            .toList(),
      ),
      heightLowerM: floats('heightLower'),
      heightUpperM: floats('heightUpper'),
      firstZLowerM: floats('firstZLower'),
    );
  }

  CameraSynchronizedEnvelopeSource source(
    Map batch,
    String mode,
    List<CameraHeightEnvelopeFrame> frames,
    int producedAtUs,
  ) => CameraSynchronizedEnvelopeSource(
    channels: channels(batch, mode),
    batchFrameId: batch['frameId'] as int,
    sessionGeneration: batch['sessionGeneration'] as int,
    capturedAtUs: batch['capturedAtUs'] as int,
    stationarySyntheticScene: batch['stationarySyntheticScene'] as bool,
    calibration: calibration(batch, mode),
    request: synchronizedRigRequest,
    frames: frames,
    producedAtUs: producedAtUs,
  );

  PassageEvaluationContext context(Map batch, String mode, int nowUs) =>
      PassageEvaluationContext(
        nowUs: nowUs,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: batch['sessionGeneration'] as int,
        frameId: batch['frameId'] as int,
        rgbTimestampUs: batch['capturedAtUs'] as int,
        transformId: transform(batch, mode),
      );

  /// Scoring only. This method is called after the perception result exists.
  Map label(String id) {
    final asset = manifest['labels'] as Map;
    bodyAsset(synchronizedRigRoot, asset);
    return (bodyJson('$synchronizedRigRoot/${asset['path']}')['labels'] as List)
        .cast<Map>()
        .singleWhere((l) => l['id'] == id);
  }
}

CameraHeightEnvelopeFrame rigCopyFrame(
  CameraHeightEnvelopeFrame e, {
  int? capturedAtUs,
  int? frameId,
  int? sessionGeneration,
  String? cameraId,
  String? modelHash,
  String? transformId,
  String? referenceFrameId,
  PassageUnits? units,
  List<double>? rotation,
  List<double>? originM,
  double? fx,
  double? poseQuality,
  bool? providerHealthy,
  List<bool>? valid,
  List<double>? firstZLowerM,
  List<double>? heightLowerM,
  List<double>? heightUpperM,
  List<double>? rangeM,
  List<double>? freeZLowerM,
  List<double>? surfaceZUpperM,
}) {
  final f = e.depth;
  return CameraHeightEnvelopeFrame(
    depth: CameraVisibleDepthFrame(
      width: f.width,
      height: f.height,
      frameId: frameId ?? f.frameId,
      capturedAtUs: capturedAtUs ?? f.capturedAtUs,
      sessionGeneration: sessionGeneration ?? f.sessionGeneration,
      fx: fx ?? f.fx,
      fy: f.fy,
      cx: f.cx,
      cy: f.cy,
      errorM: f.errorM,
      poseQuality: poseQuality ?? f.poseQuality,
      cameraId: cameraId ?? f.cameraId,
      modelHash: modelHash ?? f.modelHash,
      transformId: transformId ?? f.transformId,
      referenceFrameId: referenceFrameId ?? f.referenceFrameId,
      units: units ?? f.units,
      providerHealthy: providerHealthy ?? f.providerHealthy,
      rotation: rotation ?? f.rotation,
      originM: originM ?? f.originM,
      rangeM: rangeM ?? f.rangeM,
      freeZLowerM: freeZLowerM ?? f.freeZLowerM,
      surfaceZUpperM: surfaceZUpperM ?? f.surfaceZUpperM,
      valid: valid ?? f.valid,
    ),
    heightLowerM: heightLowerM ?? e.heightLowerM,
    heightUpperM: heightUpperM ?? e.heightUpperM,
    firstZLowerM: firstZLowerM ?? e.firstZLowerM,
  );
}
