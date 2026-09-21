import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _predictionsPath = 'test/fixtures/model_predictions/predictions.json';
const _outputRoot = 'test/fixtures/model_predictions/replay';

void main(List<String> arguments) {
  final checkOnly = arguments.contains('--check');
  final predictions = File(_predictionsPath);
  if (!predictions.existsSync()) {
    stderr.writeln('Missing real prediction fixture: $_predictionsPath');
    exitCode = 1;
    return;
  }
  final generated = _generate(predictions);
  final mismatches = <String>[];
  for (final entry in generated.entries) {
    final file = File(entry.key);
    if (checkOnly) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        mismatches.add(entry.key);
      }
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }
  if (mismatches.isNotEmpty) {
    stderr.writeln('Model replay drift:\n${mismatches.join('\n')}');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    checkOnly
        ? 'Model prediction replay matches (${generated.length} files).'
        : 'Generated model prediction replay (${generated.length} files).',
  );
}

Map<String, String> _generate(File predictionsFile) {
  final root =
      (jsonDecode(predictionsFile.readAsStringSync()) as Map<String, dynamic>);
  if (root['schemaVersion'] != 1 || root['promotionAllowed'] != false) {
    throw const FormatException('Unsupported or promotable prediction input.');
  }
  final predictionHash = _fileHash(predictionsFile);
  final files = <String, String>{};
  for (final rawModel in root['models'] as List<dynamic>) {
    final model = (rawModel as Map).cast<String, dynamic>();
    final modelId = model['modelId'] as String;
    final artifactHash = model['artifactSha256'] as String;
    final preprocessId = model['preprocessId'] as String;
    final sceneEntries = <Map<String, Object?>>[];
    for (final rawPrediction in model['predictions'] as List<dynamic>) {
      final prediction = (rawPrediction as Map).cast<String, dynamic>();
      final sourceId = prediction['sourceId'] as String;
      final sceneId = '${_slug(modelId)}-${_slug(sourceId)}';
      final framesRelative = 'scenes/$sceneId/frames.jsonl';
      final annotationsRelative = 'scenes/$sceneId/annotations.json';
      final sectors = _sectors(prediction['detections'] as List<dynamic>);
      final frames =
          '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'sceneId': sceneId, 'frameIndex': 0, 'capturedOffsetMs': 0, 'evaluateOffsetMs': 0, 'validUntilOffsetMs': 900, 'sessionGeneration': 1, 'frameId': 1, 'modelId': modelId, 'modelHash': artifactHash, 'preprocessId': preprocessId, 'orientationValid': true, 'sensingHealthy': true, 'userMoving': true, 'sectors': sectors})}\n';
      final annotations = _pretty(<String, Object?>{
        'schemaVersion': 1,
        'sceneId': sceneId,
        'annotationRevision': 1,
        'initialFeedback': 'none',
        'timeline': <Object?>[
          <String, Object?>{
            'startOffsetMs': 0,
            'endOffsetMs': 100,
            'expectedActions': const <String>['stopNow'],
            'forbiddenActions': const <String>[
              'continueForward',
              'adjustLeft',
              'adjustRight',
            ],
            'expectedHealth': const <String>['healthy'],
            'expectedAlertEvents': const <String>['emitted'],
            'expectedShadowDirections': const <String>['none'],
            'interruptCurrent': false,
          },
        ],
        'sourceImageSha256': prediction['sourceSha256'],
        'predictionsSha256': predictionHash,
      });
      final base = '$_outputRoot/${_slug(modelId)}';
      files['$base/$framesRelative'] = frames;
      files['$base/$annotationsRelative'] = annotations;
      sceneEntries.add(<String, Object?>{
        'id': sceneId,
        'kind': 'real-model-output',
        'frames': framesRelative,
        'annotations': annotationsRelative,
        'sha256': <String, Object?>{
          'frames': _stringHash(frames),
          'annotations': _stringHash(annotations),
        },
        'tags': <String>['real-output', sourceId, 'derived-no-rgb'],
        'annotationRevision': 1,
        'requiredForRc': true,
        'coverage': 'complete',
      });
      files['$base/manifest.json'] = _pretty(<String, Object?>{
        'schemaVersion': 1,
        'corpusId': 'bagdar-model-replay-${_slug(modelId)}-v1',
        'seed': 20260921,
        'generatorId': 'bagdar-real-model-output-adapter-v1',
        'timelineOriginUtc': '2026-09-21T00:00:00.000Z',
        'source': <String, Object?>{
          'type': 'derived-real-model-output',
          'license': 'blocked_pending_asset_provenance_review',
          'consentClass': 'not_applicable',
        },
        'handling': 'derived-only',
        'camera': <String, Object?>{
          'mount': 'installed-package-fixture',
          'parameters': 'source-image-coordinate-space',
          'coordinateMode': 'relative',
        },
        'modelContract': <String, Object?>{
          'modelId': modelId,
          'modelHash': artifactHash,
          'preprocessId': preprocessId,
        },
        'scenes': sceneEntries,
        'externalCorpora': const <Object?>[],
        'predictionsSha256': predictionHash,
      });
    }
  }
  return files;
}

Map<String, Object?> _sectors(List<dynamic> detections) {
  final bySector = <String, List<Map<String, dynamic>>>{
    'left': <Map<String, dynamic>>[],
    'forward': <Map<String, dynamic>>[],
    'right': <Map<String, dynamic>>[],
  };
  for (final raw in detections) {
    final detection = (raw as Map).cast<String, dynamic>();
    bySector[detection['sector'] as String]!.add(detection);
  }
  return bySector.map((sector, values) {
    if (values.isEmpty) {
      return MapEntry(sector, <String, Object?>{
        'observedFraction': 0.0,
        'occupancyProbability': 0.0,
        'traversabilityProbability': 0.0,
        'dropProbability': 0.0,
        'movingThreatRisk': 0.0,
        'unknownProbability': 1.0,
        'confidence': 0.0,
        'sourceMask': const <String>['semantic'],
        'hazardIds': const <String>[],
        'lastObservedOffsetMs': 0,
      });
    }
    final strongest = values.reduce(
      (a, b) => (a['score'] as num).toDouble() >= (b['score'] as num).toDouble()
          ? a
          : b,
    );
    final score = (strongest['score'] as num).toDouble();
    return MapEntry(sector, <String, Object?>{
      'observedFraction': 0.8,
      'occupancyProbability': score.clamp(0.7, 0.98),
      'traversabilityProbability': 0.0,
      'dropProbability': 0.0,
      'movingThreatRisk': 0.0,
      'unknownProbability': 0.2,
      'confidence': score,
      'sourceMask': const <String>['semantic'],
      'hazardIds': <String>[
        'model:${strongest['classId']}:${strongest['sector']}',
      ],
      'lastObservedOffsetMs': 0,
    });
  });
}

String _slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

String _pretty(Object value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

String _fileHash(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();
String _stringHash(String value) =>
    sha256.convert(utf8.encode(value)).toString();
