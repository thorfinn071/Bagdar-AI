import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/evaluate_spatial_recording.dart' as evaluator;

Map<String, Object?> _pair(int index, {bool depthMissing = false}) =>
    <String, Object?>{
      'frameIndex': index,
      'sessionGeneration': 1,
      'frameId': index + 1,
      'rgbTimestampUs': 1000000 + index * 100000,
      'rgbSha256': 'a' * 64,
      'rgbTransformId': 'upright-r0',
      'depthStatus': depthMissing ? 'missing' : 'aligned',
      'depthTimestampUs': depthMissing ? null : 990000 + index * 100000,
      'depthSha256': depthMissing ? null : 'b' * 64,
      'depthTransformId': depthMissing ? null : 'upright-r0',
    };

Map<String, Object?> _decision(
  int index,
  String action, {
  int? decisionTimestampUs,
  String delivery = 'shadow',
  String modelId = 'model-control',
}) => <String, Object?>{
  'frameIndex': index,
  'sessionGeneration': 1,
  'frameId': index + 1,
  'decisionTimestampUs': decisionTimestampUs ?? 1030000 + index * 100000,
  'action': action,
  'delivery': delivery,
  'runId': 'control-run-1',
  'modelId': modelId,
  'modelHash': 'sha256:control',
  'preprocessId': 'preprocess-v1',
};

Map<String, Object?> _event(String id, int start, int end, int deadlineUs) =>
    <String, Object?>{
      'hazardId': id,
      'hazardClass': 'low-obstacle',
      'startFrameIndex': start,
      'endFrameIndex': end,
      'latestStopTimestampUs': deadlineUs,
    };

Map<String, Object?> _annotations({
  required List<Map<String, Object?>> events,
  required List<Map<String, Object?>> passable,
}) => <String, Object?>{
  'schemaVersion': 1,
  'annotationRevision': 'review-draft-1',
  'criticalEvents': events,
  'passableIntervals': passable,
};

File _fixture(
  Directory directory, {
  required List<Map<String, Object?>> pairs,
  required Map<String, Object?> annotations,
  required List<Map<String, Object?>> decisions,
}) {
  final pairsFile = File('${directory.path}/pairs.jsonl')
    ..writeAsStringSync('${pairs.map(jsonEncode).join('\n')}\n');
  final annotationsFile = File('${directory.path}/annotations.json')
    ..writeAsStringSync(jsonEncode(annotations));
  final decisionsFile = File('${directory.path}/decisions.jsonl')
    ..writeAsStringSync('${decisions.map(jsonEncode).join('\n')}\n');
  Map<String, Object?> artifact(String kind, File file) => <String, Object?>{
    'kind': kind,
    'path': file.uri.pathSegments.last,
    'sha256': sha256.convert(file.readAsBytesSync()).toString(),
  };
  return File('${directory.path}/manifest.json')..writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'recordingId': 'synthetic-contract-test',
      'source': 'recorded',
      'handling': 'private',
      'license': 'test-only',
      'consent': <String, Object?>{'class': 'explicit', 'confirmed': true},
      'retention': <String, Object?>{
        'rawMediaInGit': false,
        'rawMediaPolicy': 'external',
      },
      'capture': <String, Object?>{
        'deviceModel': 'synthetic-test',
        'androidVersion': 'test-only',
        'cameraMountId': 'test-mount',
        'rgbCameraId': 'test-camera',
        'depthProviderId': 'test-depth',
        'depthModelId': 'test-model',
        'depthModelHash': 'sha256:test',
        'preprocessId': 'test-preprocess',
        'depthSemantics': 'relativeProximity',
        'timestampDomain': 'elapsedRealtimeUs',
        'maxPairSkewUs': 50000,
      },
      'rawArtifacts': <Object?>[
        <String, Object?>{
          'kind': 'test-source',
          'sha256': 'c' * 64,
          'retainedAt': 'external://synthetic-test',
        },
      ],
      'derivedArtifacts': <Object?>[
        artifact('frame-pairs', pairsFile),
        artifact('event-annotations', annotationsFile),
        artifact('shadow-decisions', decisionsFile),
      ],
    }),
  );
}

Directory _temp() {
  final directory = Directory.systemTemp.createTempSync('bagdar-metrics-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

void main() {
  test('counts on-time, late, missed, false stop and latency separately', () {
    final directory = _temp();
    final manifest = _fixture(
      directory,
      pairs: <Map<String, Object?>>[
        _pair(0),
        _pair(1),
        _pair(2, depthMissing: true),
        _pair(3),
        _pair(4),
        _pair(5),
      ],
      annotations: _annotations(
        events: <Map<String, Object?>>[
          _event('hazard-a', 0, 1, 1150000),
          _event('hazard-b', 4, 4, 1430000),
          _event('hazard-c', 5, 5, 1520000),
        ],
        passable: <Map<String, Object?>>[
          <String, Object?>{'startFrameIndex': 2, 'endFrameIndex': 3},
        ],
      ),
      decisions: <Map<String, Object?>>[
        _decision(0, 'none'),
        _decision(1, 'stopNow'),
        _decision(2, 'stopNow'),
        _decision(3, 'continueForward'),
        _decision(4, 'continueForward'),
        _decision(5, 'stopNow', decisionTimestampUs: 1560000),
      ],
    );

    final report = evaluator.evaluateSpatialRecording(manifest.path);
    final metrics = report['metrics'] as Map<String, Object?>;
    expect(metrics['criticalEvents'], 3);
    expect(metrics['onTimeStops'], 1);
    expect(metrics['lateStops'], 1);
    expect(metrics['missedStops'], 1);
    expect(metrics['detectedCriticalRecall'], closeTo(2 / 3, 0.000001));
    expect(metrics['onTimeCriticalRecall'], closeTo(1 / 3, 0.000001));
    expect(metrics['passableFrames'], 2);
    expect(metrics['falseStopFrames'], 1);
    expect(metrics['falseStopRate'], 0.5);
    expect(metrics['degradedFalseStopFrames'], 1);
    expect(metrics['unsafeContinueFrames'], 1);
    expect(metrics['alertLatencyP50Us'], 60000);
    expect(metrics['alertLatencyP90Us'], 130000);
    expect((report['evidence'] as Map)['userAlertsEnabled'], isFalse);
  });

  test('empty metric denominators are null rather than perfect scores', () {
    final directory = _temp();
    final manifest = _fixture(
      directory,
      pairs: <Map<String, Object?>>[_pair(0)],
      annotations: _annotations(
        events: const <Map<String, Object?>>[],
        passable: <Map<String, Object?>>[
          <String, Object?>{'startFrameIndex': 0, 'endFrameIndex': 0},
        ],
      ),
      decisions: <Map<String, Object?>>[_decision(0, 'continueForward')],
    );
    final metrics =
        evaluator.evaluateSpatialRecording(manifest.path)['metrics']
            as Map<String, Object?>;
    expect(metrics['detectedCriticalRecall'], isNull);
    expect(metrics['onTimeCriticalRecall'], isNull);
    expect(metrics['alertLatencyP50Us'], isNull);
    expect(metrics['falseStopRate'], 0.0);
  });

  test('zero passable frames does not report a zero false-stop rate', () {
    final directory = _temp();
    final manifest = _fixture(
      directory,
      pairs: <Map<String, Object?>>[_pair(0)],
      annotations: _annotations(
        events: <Map<String, Object?>>[_event('h1', 0, 0, 1050000)],
        passable: const <Map<String, Object?>>[],
      ),
      decisions: <Map<String, Object?>>[_decision(0, 'stopNow')],
    );
    final metrics =
        evaluator.evaluateSpatialRecording(manifest.path)['metrics']
            as Map<String, Object?>;
    expect(metrics['falseStopRate'], isNull);
    expect(metrics['onTimeCriticalRecall'], 1.0);
  });

  test('overlapping passable and critical annotations fail closed', () {
    final directory = _temp();
    final manifest = _fixture(
      directory,
      pairs: <Map<String, Object?>>[_pair(0)],
      annotations: _annotations(
        events: <Map<String, Object?>>[_event('h1', 0, 0, 1050000)],
        passable: <Map<String, Object?>>[
          <String, Object?>{'startFrameIndex': 0, 'endFrameIndex': 0},
        ],
      ),
      decisions: <Map<String, Object?>>[_decision(0, 'stopNow')],
    );
    expect(
      () => evaluator.evaluateSpatialRecording(manifest.path),
      throwsFormatException,
    );
  });

  test('missing, non-shadow and mixed-identity decisions are rejected', () {
    for (final decisions in <List<Map<String, Object?>>>[
      <Map<String, Object?>>[_decision(0, 'none')],
      <Map<String, Object?>>[
        _decision(0, 'none'),
        _decision(1, 'stopNow', delivery: 'assistive'),
      ],
      <Map<String, Object?>>[
        _decision(0, 'none'),
        _decision(1, 'stopNow', modelId: 'mixed-model'),
      ],
    ]) {
      final directory = _temp();
      final manifest = _fixture(
        directory,
        pairs: <Map<String, Object?>>[_pair(0), _pair(1)],
        annotations: _annotations(
          events: <Map<String, Object?>>[_event('h1', 0, 1, 1150000)],
          passable: const <Map<String, Object?>>[],
        ),
        decisions: decisions,
      );
      expect(
        () => evaluator.evaluateSpatialRecording(manifest.path),
        throwsFormatException,
      );
    }
  });

  test('tampered annotations are rejected by the import hash gate', () {
    final directory = _temp();
    final manifest = _fixture(
      directory,
      pairs: <Map<String, Object?>>[_pair(0)],
      annotations: _annotations(
        events: <Map<String, Object?>>[_event('h1', 0, 0, 1050000)],
        passable: const <Map<String, Object?>>[],
      ),
      decisions: <Map<String, Object?>>[_decision(0, 'stopNow')],
    );
    File('${directory.path}/annotations.json').writeAsStringSync('{}');
    expect(
      () => evaluator.evaluateSpatialRecording(manifest.path),
      throwsFormatException,
    );
  });
}
