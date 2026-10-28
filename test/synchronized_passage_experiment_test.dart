import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/synchronized_passage_replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'simultaneous paired passage preserves actual shadow runtime and faults',
    () {
      final report = runSynchronizedPassageReplay();
      final summary = report['summary'] as Map;
      expect(summary['passableSnapshots'], 2);
      expect(summary['completePassages'], 2);
      expect(summary['controlStops'], 2);
      expect(summary['hazardStops'], 5);
      expect(summary['hazardUnsafeContinues'], 0);
      expect(summary['faultStops'], 20);
      final file = File('scratch/synchronized-passage-2026-10-09/replay.json');
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (const bool.fromEnvironment('BAGDAR_CHECK_SYNC_PASSAGE')) {
        expect(file.readAsStringSync(), rendered);
      }
      if (const bool.fromEnvironment('BAGDAR_WRITE_SYNC_PASSAGE')) {
        expect(file.existsSync(), false, reason: 'First replay is immutable');
        file.writeAsStringSync(rendered);
      }
    },
    skip: !const bool.fromEnvironment('BAGDAR_SYNC_PASSAGE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
