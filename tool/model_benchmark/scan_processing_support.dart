import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_indexed_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import '../../test/harness/blender_scan_complete_fixture.dart';
import '../../test/harness/blender_visible_body_fixture.dart';

PassageEvaluationContext scanContext(CameraHeightEnvelopeFrame f, int nowUs) =>
    PassageEvaluationContext(
      nowUs: nowUs,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: f.depth.sessionGeneration,
      frameId: f.depth.frameId,
      rgbTimestampUs: f.depth.capturedAtUs,
      transformId: f.depth.transformId,
    );

PassageClearanceEvidenceSource scanSource(
  String implementation,
  PassageCalibration calibration,
  List<CameraHeightEnvelopeFrame> frames,
  int producedAtUs,
) => switch (implementation) {
  'frozen' => CameraHeightEnvelopePassageSource(
    calibration: calibration,
    request: pairedBodyRequest,
    frames: frames,
    producedAtUs: producedAtUs,
  ),
  'indexed' => CameraIndexedHeightEnvelopePassageSource(
    calibration: calibration,
    request: pairedBodyRequest,
    frames: frames,
    producedAtUs: producedAtUs,
  ),
  _ => throw ArgumentError.value(implementation, 'implementation'),
};

Map<String, Object?> scanObservationRecord(PassageClearanceObservation o) => {
  'providerId': o.providerId,
  'modelId': o.modelId,
  'modelHash': o.modelHash,
  'preprocessId': o.preprocessId,
  'calibrationId': o.calibrationId,
  'referenceFrameId': o.referenceFrameId,
  'rgbTransformId': o.rgbTransformId,
  'depthTransformId': o.depthTransformId,
  'timestampDomain': o.timestampDomain.name,
  'units': o.units.name,
  'sessionGeneration': o.sessionGeneration,
  'frameId': o.frameId,
  'rgbTimestampUs': o.rgbTimestampUs,
  'depthTimestampUs': o.depthTimestampUs,
  'oldestEvidenceTimestampUs': o.oldestEvidenceTimestampUs,
  'producedAtUs': o.producedAtUs,
  'providerHealthy': o.providerHealthy,
  'sections': [
    for (final s in o.sections)
      {
        'forwardStartM': s.forwardStartM,
        'forwardEndM': s.forwardEndM,
        'state': s.state.name,
        'bodyObservedFraction': s.bodyObservedFraction,
        'floorObservedFraction': s.floorObservedFraction,
        'confidence': s.confidence,
        'leftBoundaryUpperM': s.leftBoundaryUpperM,
        'rightBoundaryLowerM': s.rightBoundaryLowerM,
        'headroomLowerBoundM': s.headroomLowerBoundM,
        'floorRiseUpperBoundM': s.floorRiseUpperBoundM,
        'floorDropUpperBoundM': s.floorDropUpperBoundM,
      },
  ],
};

PassageClearanceObservation scanCompletedAt(
  PassageClearanceObservation o,
  int atUs,
) => PassageClearanceObservation(
  providerId: o.providerId,
  modelId: o.modelId,
  modelHash: o.modelHash,
  preprocessId: o.preprocessId,
  calibrationId: o.calibrationId,
  referenceFrameId: o.referenceFrameId,
  rgbTransformId: o.rgbTransformId,
  depthTransformId: o.depthTransformId,
  timestampDomain: o.timestampDomain,
  units: o.units,
  sessionGeneration: o.sessionGeneration,
  frameId: o.frameId,
  rgbTimestampUs: o.rgbTimestampUs,
  depthTimestampUs: o.depthTimestampUs,
  oldestEvidenceTimestampUs: o.oldestEvidenceTimestampUs,
  producedAtUs: atUs,
  providerHealthy: o.providerHealthy,
  sections: o.sections,
);

PassageClearanceResult scanDecision(
  PassageCalibration calibration,
  PassageEvaluationContext context,
  PassageClearanceObservation observation, {
  bool strict = true,
}) =>
    PassageClearanceEvaluator(
      policy: strict ? pairedBodyPolicy : pairedBodyScanDiagnosticPolicy,
    ).evaluate(
      request: pairedBodyRequest,
      context: context,
      calibration: calibration,
      observation: observation,
    );

/// Only the scoring harness reads labels, after consumers have run.
bool scanHazard(ScanCompleteFixture fixture, String id) {
  final sequence = (fixture.prior.prior.corpus['sequences'] as List)
      .cast<Map>()
      .singleWhere((s) => s['sceneId'] == id);
  final annotation = sequence['annotations'] as Map;
  bodyAsset(pairedRgbRoot, annotation);
  return bodyJson('$pairedRgbRoot/${annotation['path']}')['physicalHazard']
      as bool;
}

Map<String, Object?> scanPercentiles(Iterable<int> samples) {
  final values = samples.toList()..sort();
  if (values.isEmpty) return {'samples': 0, 'p50Ms': null, 'p95Ms': null};
  double percentile(double p) {
    final index = (values.length - 1) * p;
    final lo = index.floor(), hi = index.ceil();
    return (values[lo] + (values[hi] - values[lo]) * (index - lo)) / 1000;
  }

  return {
    'samples': values.length,
    'p50Ms': percentile(.5),
    'p95Ms': percentile(.95),
    'maximumMs': values.last / 1000,
  };
}

void writeScanReceipt(String path, Map<String, Object?> value) {
  final file = File(path);
  if (file.existsSync()) throw StateError('Scan receipt is write-once: $path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
