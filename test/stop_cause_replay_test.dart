import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/stop_cause_diagnostics.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/closed_volume_control_replay.dart';
import 'harness/stop_cause_replay.dart';

Map<String, String> _sourceFingerprint() => {
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

const _oldReceipts = [
  'scratch/closed-volume-control-2026-10-11/replay.json',
  'scratch/volume-holdout-2026-10-10/replay.json',
  'scratch/path-clear-diagnosis-2026-10-07/replay.json',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'current known-scene replay explains stops without changing decisions',
    () {
      const output = String.fromEnvironment('BAGDAR_STOP_CAUSES_OUTPUT');
      if (output.isNotEmpty &&
          Directory(output).existsSync() &&
          Directory(output).listSync().any(
            (f) => [
              'diagnosis.json',
              'frames.jsonl',
              'report.md',
            ].any((n) => f.path.endsWith('${Platform.pathSeparator}$n')),
          )) {
        fail('Existing diagnostic artifacts must not be overwritten');
      }
      final sourcesBefore = _sourceFingerprint();
      final receiptsBefore = {for (final p in _oldReceipts) p: bodySha(p)};
      final paired = replayPairedStopCauses();
      expect(paired.length, 140); // 132 frames + 8 separately unscored probes.
      final normal = paired
          .where((r) => r['sampleKind'] == 'knownSyntheticReplay')
          .toList();
      expect(normal.map((r) => r['sceneId']).toSet().length, 12);
      expect(normal.length, 132);
      final priorPath = bodyJson(_oldReceipts.last);
      var pathComparisons = 0;
      for (final old in (priorPath['frames'] as List).cast<Map>()) {
        final fresh = normal.singleWhere(
          (r) =>
              r['sceneId'] == old['sceneId'] &&
              r['frameId'] == (old['frameIndex'] as int) + 1,
        );
        expect(fresh['action'], old['correctedCause']['action']);
        expect(fresh['ruleId'], old['correctedCause']['rule']);
        pathComparisons++;
      }
      expect(pathComparisons, 22);
      for (final row in normal.where((r) => r['sceneId'] == 'path-clear')) {
        expect(row['unknownBodyCells'], greaterThan(0));
        expect(row['minimumFloorObservedFraction'], 0);
        expect(
          row['categories'],
          containsAll(['bodyCoverage', 'floorCoverage']),
        );
      }
      final faults = paired
          .where((r) => r['sampleKind'] == 'syntheticFaultControl')
          .toList();
      expect(faults.length, stopDiagnosticFaults.length);
      for (final row in faults) {
        expect(row['outcome'], 'unscored');
        // Stationarity alone cannot resolve the retained, unverified forward
        // track. The normal tracks are preserved even in this stationary probe.
        expect(row['action'], 'stopNow', reason: row['variant'] as String);
        expect(row['passageApplied'], false);
      }
      final stale = faults.singleWhere((r) => r['variant'] == 'staleMetric');
      expect(stale['replayAgeUs'], 100001);
      expect(stale['categories'], contains('freshness'));
      for (final variant in ['relativeDepth', 'foreignModel']) {
        final row = faults.singleWhere((r) => r['variant'] == variant);
        expect(row['unknownBodyCells'], isNull);
        expect(row['observedBodyCells'], isNull);
        expect(row['unknownBodyCellCentersSampleM'], isNull);
      }
      expect(
        faults.singleWhere((r) => r['variant'] == 'foreignModel')['categories'],
        contains('identity'),
      );
      expect(
        faults.singleWhere(
          (r) => r['variant'] == 'relativeDepth',
        )['categories'],
        contains('metricCalibration'),
      );
      expect(
        faults.singleWhere(
          (r) => r['variant'] == 'invalidOrientation',
        )['categories'],
        contains('orientation'),
      );
      expect(
        faults.singleWhere(
          (r) => r['variant'] == 'providerUnavailable',
        )['categories'],
        contains('sensingUnavailable'),
      );

      final closed = runClosedVolumeControl();
      final priorClosed = bodyJson(_oldReceipts.first);
      var controlComparisons = 0;
      for (final c in (closed['cases'] as List).cast<Map>()) {
        final oldCase = (priorClosed['cases'] as List).cast<Map>().singleWhere(
          (v) => v['layoutId'] == c['layoutId'],
        );
        for (final f in (c['frames'] as List).cast<Map>()) {
          final old = (oldCase['frames'] as List).cast<Map>().singleWhere(
            (v) => v['frameId'] == f['frameId'],
          );
          // All eight original lanes, not only the four displayed in diagnosis.
          for (final arm in (f['arms'] as Map).entries) {
            expect(arm.value['runtime'], old['arms'][arm.key]['runtime']);
            controlComparisons += (arm.value['runtime'] as Map).length;
          }
        }
      }
      expect(controlComparisons, 168);
      final closedRows = closedControlStopRows(closed);
      final rows = [...paired, ...closedRows];
      for (final row in rows) {
        expect(row['delivery'], 'shadow');
        expect(row['captureToDecisionMs'], isNull);
      }
      final summary = summarizeStopDiagnostics(rows);
      for (final group in (summary['groups'] as List).cast<Map>().where(
        (g) => (g['variant'] as String).endsWith('/fixedRig'),
      )) {
        expect(group['falseStops'], 0);
        expect(group['passableFrames'], 14);
        expect(group['hazardStops'], 7);
        expect(group['hazardContinues'], 0);
      }
      expect(_sourceFingerprint(), sourcesBefore);
      expect({for (final p in _oldReceipts) p: bodySha(p)}, receiptsBefore);
      final gitHead = Process.runSync('git', ['rev-parse', 'HEAD']);
      final gitStatus = Process.runSync('git', ['status', '--porcelain']);
      expect(gitHead.exitCode, 0);
      expect(gitStatus.exitCode, 0);
      final report = <String, Object?>{
        'schemaVersion': 1,
        'scope': 'current implementation on already-known synthetic corpora',
        'ordinaryCameraWired': false,
        'promotionAllowed': false,
        'falseStopReductionEstablished': false,
        'newHoldout': false,
        'newNeuralInference': false,
        'namedDeviceRuntime': 'not_run',
        'controlledWalking': 'not_run',
        'captureToDecisionMs': null,
        'freshnessPolicyUs': 100000,
        'gitCommit': (gitHead.stdout as String).trim(),
        'gitDirty': (gitStatus.stdout as String).trim().isNotEmpty,
        'sourceFingerprint': sourcesBefore,
        'preservedReceipts': receiptsBefore,
        'corpusManifestHashes': {
          '$pairedBodyRoot/manifest.json': bodySha(
            '$pairedBodyRoot/manifest.json',
          ),
          '$pairedRgbRoot/corpus-manifest.json': bodySha(
            '$pairedRgbRoot/corpus-manifest.json',
          ),
          'scratch/closed-volume-control-2026-10-11/corpus/manifest.json':
              bodySha(
                'scratch/closed-volume-control-2026-10-11/corpus/manifest.json',
              ),
        },
        'checks': {
          'unchangedSources': sourcesBefore.length,
          'unchangedHistoricalReceipts': receiptsBefore.length,
          'pathDecisionComparisons': pathComparisons,
          'closedControlDecisionComparisons': controlComparisons,
          'protectiveFaultProbes': faults.length,
        },
        'summary': summary,
        'frames': rows,
      };
      // No artifacts are written by a default test run.
      if (output.isNotEmpty) {
        final dir = Directory(output)..createSync(recursive: true);
        File('${dir.path}/diagnosis.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
        File(
          '${dir.path}/frames.jsonl',
        ).writeAsStringSync('${rows.map(jsonEncode).join('\n')}\n');
        File(
          '${dir.path}/report.md',
        ).writeAsStringSync(stopDiagnosticsMarkdown(report));
      }
      // ignore: avoid_print
      print(jsonEncode({'summary': summary, 'checks': report['checks']}));
    },
    skip: !const bool.fromEnvironment('BAGDAR_STOP_CAUSES_REPLAY'),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
