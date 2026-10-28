import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_visible_body_fixture.dart';
import 'harness/stop_cause_replay.dart';
import 'harness/unknown_volume_diagnostics.dart';

Map<String, String> _fingerprint() => {
  for (final root in ['lib', 'test', 'tool'])
    for (final file
        in (Directory(root)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path))))
      file.path.replaceAll('\\', '/'): bodySha(file.path),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all known paired frames have complete producer-matched unknown maps',
    () {
      const output = String.fromEnvironment('BAGDAR_UNKNOWN_VOLUME_OUTPUT');
      if (output.isNotEmpty && File('$output/maps.jsonl').existsSync()) {
        fail('Preserve existing unknown-volume maps');
      }
      const priorPath =
          'scratch/stop-causes-20261017/final-verification/diagnosis.json';
      final priorHash = bodySha(priorPath);
      final sources = _fingerprint();
      final prior = bodyJson(priorPath);
      final previous = (prior['frames'] as List)
          .cast<Map>()
          .where(
            (r) =>
                r['corpus'] == 'paired-visible-body-v1' &&
                r['sampleKind'] == 'knownSyntheticReplay',
          )
          .toList();
      final fixture = PairedBodyFixture();
      final rows = <Map<String, Object?>>[];
      for (final seq in (fixture.manifest['sequences'] as List).cast<Map>()) {
        final id = seq['sceneId'] as String;
        for (final packet in (seq['single'] as List).cast<Map>()) {
          final frame = fixture.visible(packet, id);
          final context = PassageEvaluationContext(
            nowUs: frame.capturedAtUs + 2000,
            timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
            sessionGeneration: 1,
            frameId: frame.frameId,
            rgbTimestampUs: frame.capturedAtUs,
            transformId: frame.transformId,
          );
          final source = CameraPassageClearanceSource(
            calibration: fixture.calibration(id),
            request: pairedBodyRequest,
            frames: [frame],
            producedAtUs: frame.capturedAtUs + 1000,
          );
          final observation = source.observationFor(context)!;
          final map = UnknownVolumeDiagnostics(
            frame: frame,
            request: pairedBodyRequest,
          ).inspect(source: source, observation: observation, context: context);
          final old = previous.singleWhere(
            (r) => r['sceneId'] == id && r['frameId'] == frame.frameId,
          );
          expect(map['certifiedBodyBoxes'], old['observedBodyCells']);
          expect(map['unknownBodyBoxes'], old['unknownBodyCells']);
          expect(
            (map['bodyCells'] as List).length,
            (map['nx'] as int) * (map['ny'] as int) * (map['nz'] as int),
          );
          expect(
            (map['floorCells'] as List).length,
            (map['nx'] as int) * (map['ny'] as int),
          );
          expect(map['canAuthorizeMovement'], false);
          rows.add({
            'sceneId': id,
            'frameId': frame.frameId,
            'sourceTimestampUs': frame.capturedAtUs,
            'fixedReplayAgeUs': 2000,
            'scope': 'current source inspection; known synthetic inputs',
            'opticalManifestSha256': bodySha('$pairedBodyRoot/manifest.json'),
            'map': map,
          });
        }
        // ignore: avoid_print
        print('Unknown-volume maps complete: $id');
      }
      expect(rows.length, 132);
      // A fresh decision replay, rather than attaching archived actions to new maps.
      final freshDecisions = replayPairedStopCauses();
      for (final row in rows) {
        final fresh = freshDecisions.singleWhere(
          (r) =>
              r['sceneId'] == row['sceneId'] &&
              r['frameId'] == row['frameId'] &&
              r['sampleKind'] == 'knownSyntheticReplay',
        );
        final old = previous.singleWhere(
          (r) =>
              r['sceneId'] == row['sceneId'] && r['frameId'] == row['frameId'],
        );
        for (final key in [
          'action',
          'ruleId',
          'passageApplied',
          'delivery',
          'unknownBodyCells',
          'minimumFloorObservedFraction',
          'outcome',
        ]) {
          expect(
            fresh[key],
            old[key],
            reason: '${row['sceneId']}/${row['frameId']}/$key',
          );
        }
        row['runtime'] = {
          for (final key in [
            'action',
            'ruleId',
            'passageApplied',
            'delivery',
            'outcome',
          ])
            key: fresh[key],
        };
        row['scoringOnly'] = fresh['scoringOnly'];
      }
      expect(_fingerprint(), sources);
      expect(bodySha(priorPath), priorHash);
      final report = {
        'schemaVersion': 1,
        'scope': 'complete cell maps on 132 already-known synthetic frames',
        'promotionAllowed': false,
        'ordinaryCameraWired': false,
        'falseStopReductionEstablished': false,
        'newHoldout': false,
        'captureToDecisionMs': null,
        'namedDeviceRuntime': 'not_run',
        'controlledWalking': 'not_run',
        'maximumAgeUs': 100000,
        'priorDiagnosticSha256': priorHash,
        'opticalManifestSha256': fixture.modelHash,
        'rgbCorpusManifestSha256': bodySha(
          '$pairedRgbRoot/corpus-manifest.json',
        ),
        'sourceFingerprint': sources,
        'frames': rows.length,
        'runtimeDecisionsCompared': rows.length,
        'bodyCells': rows.fold<int>(
          0,
          (n, r) => n + ((r['map'] as Map)['bodyCells'] as List).length,
        ),
        'floorCells': rows.fold<int>(
          0,
          (n, r) => n + ((r['map'] as Map)['floorCells'] as List).length,
        ),
      };
      if (output.isNotEmpty) {
        Directory(output).createSync(recursive: true);
        File(
          '$output/maps.jsonl',
        ).writeAsStringSync('${rows.map(jsonEncode).join('\n')}\n');
        File('$output/experiment.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          ...report,
          'sourceFingerprint': '${sources.length} immutable sources',
        }),
      );
    },
    skip: !const bool.fromEnvironment('BAGDAR_UNKNOWN_VOLUME_REPLAY'),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
