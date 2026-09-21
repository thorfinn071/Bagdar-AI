import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/import_spatial_recording.dart' as importer;

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
}
