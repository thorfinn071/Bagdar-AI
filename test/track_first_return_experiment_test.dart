import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/track_first_return_fixture.dart';
import 'harness/track_first_return_replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'exact primary first-return bounds preserve shadow hazards and unknown inputs',
    () {
      const pilot = bool.fromEnvironment('BAGDAR_FIRST_RETURN_PILOT');
      final report = runTrackFirstReturnReplay(pilot: pilot),
          summary = report['summary'] as Map;
      expect(summary['passableSnapshots'], 2);
      expect(summary['completePassages'], 2);
      expect(summary['controlStops'], 2);
      expect(summary['supplementalStops'], 0);
      expect(summary['supplementalContinues'], 2);
      expect(summary['singleCameraStops'], 2);
      expect(summary['hazardSnapshots'], pilot ? 0 : 5);
      expect(summary['hazardStops'], pilot ? 0 : 5);
      expect(summary['hazardUnsafeContinues'], 0);
      expect(summary['faultChecks'], 38);
      expect(summary['faultStops'], 36);
      expect(summary['priorityUnknowns'], 2);
      final file = File(
        '$firstReturnRoot/${pilot ? 'pilot-replay' : 'replay'}.json',
      );
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (const bool.fromEnvironment('BAGDAR_CHECK_FIRST_RETURN')) {
        expect(file.readAsStringSync(), rendered);
      }
      if (const bool.fromEnvironment('BAGDAR_WRITE_FIRST_RETURN')) {
        expect(file.existsSync(), false, reason: 'First replay is immutable');
        file.writeAsStringSync(rendered);
      }
    },
    skip: !const bool.fromEnvironment('BAGDAR_FIRST_RETURN'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
