import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'harness/ego_volume_repair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same-capture volume authority repairs relative hypotheses and keeps physical stops',
    () {
      final report = runEgoVolumeRepair(), summary = report['summary'] as Map;
      expect(summary['captures'], 42);
      expect(summary['physicalHazardFrames'], 25);
      expect(summary['passableFrames'], 17);
      for (final mode in ['legacy', 'frameStable']) {
        for (final lane in ['fixedSingleView', 'fixedRig']) {
          expect(summary['runtime']['$mode/$lane']['hazardStops'], 25);
          expect(summary['runtime']['$mode/$lane']['hazardMisses'], 0);
        }
        expect(summary['runtime']['$mode/fixedSingleView']['falseStops'], 17);
        expect(summary['runtime']['$mode/sameRigControl']['falseStops'], 8);
        expect(summary['runtime']['$mode/fixedRig']['falseStops'], 3);
      }
      for (final c in (report['cases'] as List).cast<Map>()) {
        for (final row in (c['frames'] as List).cast<Map>()) {
          for (final arm in (row['arms'] as Map).values.cast<Map>()) {
            final fixed = arm['runtime']['fixedRig'] as Map;
            if (fixed['action'] == 'continueForward') {
              expect(row['volume']['status'], 'measuredClear');
              expect(row['volume']['coversCameraRecoveryVolume'], true);
              expect(row['bodyMotion']['addsMotionRisk'], false);
            }
            if (row['bodyMotion']['addsMotionRisk'] == true) {
              expect(fixed['action'], 'stopNow');
            }
            if (c['layoutId'] == 'ego-camera-yaw') {
              expect(fixed['action'], 'continueForward');
            }
          }
        }
      }
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$repairRoot/ego-repair-replay.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_VOLUME_FIX')) {
        expect(file.existsSync(), false, reason: 'Immutable replay receipt');
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_VOLUME_FIX')) {
        expect(file.readAsStringSync(), text);
      }
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: !const bool.fromEnvironment('BAGDAR_VOLUME_FIX'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
