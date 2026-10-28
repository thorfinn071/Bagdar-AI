import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'harness/volume_authority_regression.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'current body/floor proof resolves relative hypotheses without history reset',
    () {
      final report = runVolumeAuthorityRegression();
      final summary = report['summary'] as Map;
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
      for (final mode in ['legacy', 'frameStable']) {
        expect((summary[mode] as Map)['stops'], 0);
        expect((summary[mode] as Map)['continues'], 11);
      }
      expect(summary['initialFaultStops'], 22);
      var hazards = 0;
      for (final c in (report['motionCases'] as List).cast<Map>()) {
        for (final f in (c['frames'] as List).cast<Map>()) {
          if ((f['scoringOnly'] as Map)['physicalHazard'] == true) {
            hazards++;
            for (final arm in (f['relative'] as Map).values.cast<Map>()) {
              expect(arm['action'], 'stopNow');
            }
          }
        }
      }
      expect(hazards, 60);
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$authorityFixRoot/known-replay.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_VOLUME_FIX')) {
        expect(file.existsSync(), false);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_VOLUME_FIX')) {
        expect(file.readAsStringSync(), text);
      }
    },
    skip: !const bool.fromEnvironment('BAGDAR_VOLUME_FIX'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
