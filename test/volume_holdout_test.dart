import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'harness/volume_holdout_replay.dart';
import 'harness/volume_holdout_faults.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'preregistered frozen runtime holdout and measurement faults',
    () {
      final faultControls = runHoldoutFaults();
      final report = runVolumeHoldout();
      report['faultControls'] = faultControls;
      final summary = report['summary'] as Map;
      final runtime = summary['runtime'] as Map;
      final faults = (report['faultControls'] as Map)['summary'] as Map;
      final gates = <String, bool>{
        'zeroHazardMisses': ['legacy', 'frameStable'].every(
          (m) => [
            'fixedSingleView',
            'fixedRig',
          ].every((a) => runtime['$m/$a']['hazardMisses'] == 0),
        ),
        'allFaultsStop': faults['faultStops'] == 48,
        'allMovingRecoveriesStop': faults['movingRecoveryStops'] == 48,
        'afterClearPreconditions': faults['clearPreconditionsPassed'] == 24,
        'noSingleViewOptimism': [
          'legacy',
          'frameStable',
        ].every((m) => runtime['$m/fixedSingleView']['passableContinues'] == 0),
        'aggregateSameRigFalseStopsReduced':
            ['legacy', 'frameStable'].fold<int>(
              0,
              (n, m) => n + runtime['$m/fixedRig']['falseStops'] as int,
            ) <
            ['legacy', 'frameStable'].fold<int>(
              0,
              (n, m) => n + runtime['$m/sameRigControl']['falseStops'] as int,
            ),
      };
      var allContinuesProved = true;
      for (final c in (report['cases'] as List).cast<Map>()) {
        for (final r in (c['frames'] as List).cast<Map>()) {
          for (final a in (r['arms'] as Map).values.cast<Map>()) {
            if (a['runtime']['fixedRig']['action'] == 'continueForward') {
              allContinuesProved &=
                  r['volume']['status'] == 'measuredClear' &&
                  r['volume']['coversCameraRecoveryVolume'] == true &&
                  r['bodyMotion']['addsMotionRisk'] == false &&
                  (r['volume']['validUntilUs'] as int) >= (r['nowUs'] as int);
            }
          }
        }
      }
      gates['allContinuesHaveCurrentProof'] = allContinuesProved;
      report['gates'] = gates;
      report['syntheticHoldoutGatePassed'] = gates.values.every((v) => v);
      expect(summary['captures'], 84);
      expect(
        (summary['physicalHazardFrames'] as int) +
            (summary['passableFrames'] as int),
        84,
      );
      expect(faults['trials'], 48);
      // Persist all predeclared outcomes, including failed gates, without tuning.
      final encoded = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$holdoutRoot/replay.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_HOLDOUT')) {
        expect(file.existsSync(), false, reason: 'Immutable holdout receipt');
        file.writeAsStringSync(encoded);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_HOLDOUT')) {
        expect(file.readAsStringSync(), encoded);
      }
      // ignore: avoid_print
      print(jsonEncode({'summary': summary, 'faults': faults, 'gates': gates}));
      // Reproducibility and gate outcome are separate; failures remain in receipt.
    },
    skip: !const bool.fromEnvironment('BAGDAR_VOLUME_HOLDOUT'),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
