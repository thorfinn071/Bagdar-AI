import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/sequence_first_return_fixture.dart';
import 'harness/sequence_first_return_replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'eleven moving frames retain tracker, planner, scene and arbiter history',
    () {
      final report = runSequenceFirstReturnReplay(),
          summary = report['summary'] as Map;
      expect(summary['frames'], 11);
      expect(summary['completePassages'], 11);
      expect((summary['single-original'] as Map)['stops'], 11);
      expect((summary['rig-original'] as Map)['stops'], 11);
      expect((summary['rig-supplemental'] as Map)['stops'], 10);
      expect((summary['rig-supplemental'] as Map)['continues'], 1);
      for (final rows in (report['continuous'] as Map).values.cast<List>()) {
        expect(rows.length, 11);
        expect((rows.last as Map)['sessionStarts'], 1);
        for (var i = 1; i < rows.length; i++) {
          expect(
            (rows[i] as Map)['previousRevision'],
            (rows[i - 1] as Map)['revision'],
          );
        }
      }
      expect(summary['faultTrials'], 18);
      expect(summary['faultStops'], 18);
      expect(summary['afterFaultMovingContinues'], 0);
      final file = File('$sequenceReturnRoot/replay.json');
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (const bool.fromEnvironment('BAGDAR_WRITE_SEQUENCE_RETURN')) {
        expect(
          file.existsSync(),
          false,
          reason: 'Sequence receipt is immutable',
        );
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_SEQUENCE_RETURN')) {
        expect(file.readAsStringSync(), text);
      }
    },
    skip: !const bool.fromEnvironment('BAGDAR_SEQUENCE_RETURN'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
