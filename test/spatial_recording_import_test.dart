import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/import_spatial_recording.dart' as importer;

Map<String, Object?> _pair(
  int index, {
  int generation = 1,
  int? frameId,
  int? rgbTimestampUs,
  int? depthTimestampUs,
  String depthStatus = 'aligned',
  String rgbTransformId = 'upright-r0',
  String depthTransformId = 'upright-r0',
}) => <String, Object?>{
  'frameIndex': index,
  'sessionGeneration': generation,
  'frameId': frameId ?? index + 1,
  'rgbTimestampUs': rgbTimestampUs ?? 1000000 + index * 100000,
  'rgbSha256': 'a' * 64,
  'rgbTransformId': rgbTransformId,
  'depthStatus': depthStatus,
  'depthTimestampUs': depthStatus == 'missing'
      ? null
      : (depthTimestampUs ?? 990000 + index * 100000),
  'depthSha256': depthStatus == 'missing' ? null : 'b' * 64,
  'depthTransformId': depthStatus == 'missing' ? null : depthTransformId,
};

File _writeV2(
  Directory directory,
  List<Map<String, Object?>> pairs, {
  Map<String, Object?> captureOverrides = const {},
}) {
  final frames = File('${directory.path}/pairs.jsonl')
    ..writeAsStringSync('${pairs.map(jsonEncode).join('\n')}\n');
  final capture = <String, Object?>{
    'deviceModel': 'test-android',
    'androidVersion': 'test-version',
    'cameraMountId': 'chest-v1',
    'rgbCameraId': 'back-0',
    'depthProviderId': 'test-depth',
    'depthModelId': 'test-model',
    'depthModelHash': 'sha256:test-artifact',
    'preprocessId': 'test-preprocess-v1',
    'depthSemantics': 'relativeProximity',
    'timestampDomain': 'elapsedRealtimeUs',
    'maxPairSkewUs': 50000,
    ...captureOverrides,
  };
  return File('${directory.path}/manifest.json')..writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'recordingId': 'controlled-002',
      'source': 'recorded',
      'handling': 'private',
      'license': 'participant-consent-restricted',
      'consent': <String, Object?>{'class': 'explicit', 'confirmed': true},
      'retention': <String, Object?>{
        'rawMediaInGit': false,
        'rawMediaPolicy': 'external',
      },
      'capture': capture,
      'rawArtifacts': <Object?>[
        <String, Object?>{
          'kind': 'rgb-video',
          'sha256': 'c' * 64,
          'retainedAt': 'external://consent-vault/capture-002',
        },
      ],
      'derivedArtifacts': <Object?>[
        <String, Object?>{
          'kind': 'frame-pairs',
          'path': 'pairs.jsonl',
          'sha256': sha256.convert(frames.readAsBytesSync()).toString(),
        },
      ],
    }),
  );
}

void main() {
  test('validates hash-only raw evidence and derived fixtures', () {
    final temp = Directory.systemTemp.createTempSync('bagdar-recording-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final derived = File('${temp.path}/frames.jsonl')
      ..writeAsStringSync('{}\n');
    final hash = sha256.convert(derived.readAsBytesSync()).toString();
    final manifest = File('${temp.path}/manifest.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'recordingId': 'controlled-001',
          'source': 'recorded',
          'handling': 'private',
          'license': 'participant-consent-restricted',
          'consent': <String, Object?>{'class': 'explicit', 'confirmed': true},
          'retention': <String, Object?>{
            'rawMediaInGit': false,
            'rawMediaPolicy': 'external',
          },
          'rawArtifacts': <Object?>[
            <String, Object?>{
              'kind': 'rgb-video',
              'sha256': List<String>.filled(64, 'a').join(),
              'retainedAt': 'external://consent-vault/capture-001',
            },
          ],
          'derivedArtifacts': <Object?>[
            <String, Object?>{
              'kind': 'replay-frames',
              'path': 'frames.jsonl',
              'sha256': hash,
            },
          ],
        }),
      );

    final receipt = importer.validateSpatialRecordingManifest(manifest.path);
    expect(receipt['status'], 'validated');
    expect(receipt['rawMediaImported'], isFalse);
  });

  test('rejects absent consent and raw media paths', () {
    final temp = Directory.systemTemp.createTempSync('bagdar-recording-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final manifest = File('${temp.path}/manifest.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'recordingId': 'bad',
          'source': 'recorded',
          'handling': 'private',
          'license': 'unknown',
          'consent': <String, Object?>{'class': 'implicit', 'confirmed': false},
          'retention': <String, Object?>{
            'rawMediaInGit': true,
            'rawMediaPolicy': 'git',
          },
          'rawArtifacts': const <Object?>[],
          'derivedArtifacts': const <Object?>[],
        }),
      );

    expect(
      () => importer.validateSpatialRecordingManifest(manifest.path),
      throwsFormatException,
    );
  });

  test(
    'v2 validates paired and explicitly missing depth without accuracy claim',
    () {
      final temp = Directory.systemTemp.createTempSync('bagdar-recording-v2-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final manifest = _writeV2(temp, <Map<String, Object?>>[
        _pair(0),
        _pair(1, depthStatus: 'missing'),
        _pair(2, generation: 2, frameId: 1),
      ]);

      final receipt = importer.validateSpatialRecordingManifest(manifest.path);
      expect(receipt['schemaVersion'], 2);
      expect(receipt['rawMediaImported'], isFalse);
      expect(jsonEncode(receipt), isNot(contains('consent-vault')));
      expect(receipt['framePairs'], <String, Object>{
        'frameCount': 3,
        'alignedCount': 2,
        'missingCount': 1,
        'maxObservedSkewUs': 10000,
        'accuracyMetricsReady': false,
      });
    },
  );

  test('v2 rejects reused, skewed, or transform-mismatched depth', () {
    final invalidSecondPairs = <Map<String, Object?>>[
      _pair(1, depthTimestampUs: 990000),
      _pair(1, depthTimestampUs: 1000000),
      _pair(1, depthTransformId: 'mirrored-r0'),
    ];
    for (final second in invalidSecondPairs) {
      final temp = Directory.systemTemp.createTempSync('bagdar-recording-v2-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final manifest = _writeV2(temp, <Map<String, Object?>>[_pair(0), second]);
      expect(
        () => importer.validateSpatialRecordingManifest(manifest.path),
        throwsFormatException,
      );
    }
  });

  test('v2 rejects out-of-order frames and undeclared raw fields', () {
    for (final second in <Map<String, Object?>>[
      _pair(2),
      _pair(1, frameId: 1),
      <String, Object?>{..._pair(1), 'rgbPath': 'private/photo.png'},
    ]) {
      final temp = Directory.systemTemp.createTempSync('bagdar-recording-v2-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final manifest = _writeV2(temp, <Map<String, Object?>>[_pair(0), second]);
      expect(
        () => importer.validateSpatialRecordingManifest(manifest.path),
        throwsFormatException,
      );
    }
  });

  test(
    'v2 rejects missing depth with hidden payload and incompatible clock',
    () {
      final temp = Directory.systemTemp.createTempSync('bagdar-recording-v2-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final malformed = <String, Object?>{
        ..._pair(0, depthStatus: 'missing'),
        'depthSha256': 'b' * 64,
      };
      final manifest = _writeV2(temp, <Map<String, Object?>>[malformed]);
      expect(
        () => importer.validateSpatialRecordingManifest(manifest.path),
        throwsFormatException,
      );

      final incompatible = _writeV2(
        temp,
        <Map<String, Object?>>[_pair(0)],
        captureOverrides: <String, Object?>{'timestampDomain': 'wallClockUs'},
      );
      expect(
        () => importer.validateSpatialRecordingManifest(incompatible.path),
        throwsFormatException,
      );
    },
  );

  test('v2 rejects raw media embedded in manifest metadata', () {
    final temp = Directory.systemTemp.createTempSync('bagdar-recording-v2-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final manifest = _writeV2(temp, <Map<String, Object?>>[_pair(0)]);
    final decoded =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final raw = decoded['rawArtifacts'] as List<dynamic>;
    (raw.first as Map<String, dynamic>)['rgbBase64'] = 'not-allowed';
    manifest.writeAsStringSync(jsonEncode(decoded));

    expect(
      () => importer.validateSpatialRecordingManifest(manifest.path),
      throwsFormatException,
    );
  });
}
