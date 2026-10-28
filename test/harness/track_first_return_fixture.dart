import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_synchronized_envelope_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_synchronized_rig_fixture.dart' show rigCopyFrame;
import 'blender_visible_body_fixture.dart';
import 'synchronized_passage_fixture.dart';

const firstReturnRoot = 'scratch/track-first-return-2026-10-09';

CameraVisibleDepthFrame firstReturnCopy(
  CameraVisibleDepthFrame f, {
  List<double>? upper,
  List<double>? range,
  List<bool>? valid,
  String? modelHash,
  String? transformId,
  int? capturedAtUs,
  PassageUnits? units,
  List<double>? rotation,
}) => rigCopyFrame(
  CameraHeightEnvelopeFrame(
    depth: f,
    heightLowerM: const [],
    heightUpperM: const [],
    firstZLowerM: const [],
  ),
  surfaceZUpperM: upper,
  rangeM: range,
  valid: valid,
  modelHash: modelHash,
  transformId: transformId,
  capturedAtUs: capturedAtUs,
  units: units,
  rotation: rotation,
).depth;

/// New calibration identity binds old and supplemental optical payloads together.
class FirstReturnFixture {
  final base = SynchronizedPassageFixture();
  final Map<String, dynamic> proof;
  final String modelHash;
  final bool pilot;

  FirstReturnFixture({this.pilot = false})
    : proof = bodyJson(
        '$firstReturnRoot/optical/${pilot ? 'pilot' : 'manifest'}.json',
      ),
      modelHash = bodySha(
        '$firstReturnRoot/optical/${pilot ? 'pilot' : 'manifest'}.json',
      ) {
    if ((proof['pilotOnly'] == true) != pilot) {
      throw StateError('Pilot/full scope mismatch');
    }
    if (proof['promotionAllowed'] != false ||
        proof['ordinaryCameraWired'] != false ||
        proof['priorManifestSha256'] != base.modelHash ||
        proof['priorNeuralSha256'] != bodySha('${base.root}/neural.json')) {
      throw StateError('Supplemental optical identity drift');
    }
    for (final e in (proof['sources'] as Map).entries) {
      if (bodySha(e.key as String) != e.value) {
        throw StateError('Changed exact exporter');
      }
    }
  }

  String get root => base.root;
  List<Map> get batches => base.batches
      .where(
        (b) => (proof['records'] as List).cast<Map>().any(
          (r) => r['id'] == b['id'],
        ),
      )
      .toList();
  String transform(Map b) => base.transform(b);
  Map record(Map b) => (proof['records'] as List).cast<Map>().singleWhere(
    (r) => r['id'] == b['id'],
  );
  CameraVisibleDepthFrame primary(Map b) =>
      firstReturnCopy(base.primary(b), modelHash: modelHash);
  CameraVisibleDepthFrame supplementedPrimary(Map b) {
    final r = record(b), p = b['primary'] as Map;
    for (final key in [
      'frameId',
      'sessionGeneration',
      'capturedAtUs',
      'sceneStateSha256',
    ]) {
      if (r[key] != p[key]) throw StateError('Foreign supplemental packet');
    }
    return firstReturnCopy(
      primary(b),
      upper: bodyFloats(
        bodyAsset('$firstReturnRoot/optical', r['surfaceZUpper'] as Map),
      ),
    );
  }

  PassageCalibration calibration(Map b, String mode) {
    final old = base.calibration(b, mode);
    return PassageCalibration(
      id: 'primary-first-return-$mode-v1',
      providerId: old.providerId,
      modelId: old.modelId,
      modelHash: modelHash,
      preprocessId: old.preprocessId,
      referenceFrameId: old.referenceFrameId,
      transformId: old.transformId,
      timestampDomain: old.timestampDomain,
      metricScaleValidated: old.metricScaleValidated,
      alignmentValidated: old.alignmentValidated,
      floorReferenceValidated: old.floorReferenceValidated,
    );
  }

  List<CameraHeightEnvelopeFrame> frames(Map b) => [
    for (final f in base.frames(b)) rigCopyFrame(f, modelHash: modelHash),
  ];

  CameraSynchronizedEnvelopeSource source(
    Map b,
    List<CameraHeightEnvelopeFrame> frames,
    int producedAtUs, {
    bool? staticScene,
  }) => CameraSynchronizedEnvelopeSource(
    channels: base.channels(b),
    batchFrameId: b['frameId'] as int,
    sessionGeneration: b['sessionGeneration'] as int,
    capturedAtUs: b['capturedAtUs'] as int,
    stationarySyntheticScene:
        staticScene ?? b['stationarySyntheticScene'] as bool,
    calibration: calibration(b, 'rig'),
    request: pairedBodyRequest,
    frames: frames,
    producedAtUs: producedAtUs,
  );

  PassageEvaluationContext context(Map b, int nowUs) => base.context(b, nowUs);
}
