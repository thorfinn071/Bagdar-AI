import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'harness/ego_motion_experiment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'new original-capture ego-motion replay preserves unknown and risk',
    () {
      final report = runEgoMotionExperiment(),
          summary = report['summary'] as Map;
      expect(summary['captures'], 42);
      expect(report['promotionAllowed'], false);
      expect(report['bodyCoverageEstablished'], false);
      for (final mode in ['legacy', 'frameStable']) {
        final outcomes = summary['runtime'] as Map;
        final control = outcomes['$mode/additiveControl'] as Map;
        final candidate = outcomes['$mode/additiveShadow'] as Map;
        expect(
          candidate['hazardMisses'],
          lessThanOrEqualTo(control['hazardMisses'] as int),
        );
        expect(
          (candidate['hazardStops'] as int) +
              (candidate['hazardMisses'] as int),
          summary['physicalHazardFrames'],
        );
      }
      for (final c in (report['cases'] as List).cast<Map>()) {
        expect((c['frames'] as List).length, 7);
        for (final row in (c['frames'] as List).cast<Map>()) {
          final motion = row['egoMotion'] as Map;
          expect(motion['relativeHypothesisResolved'], false);
          expect(motion['freeSpaceCertified'], false);
          expect(motion['poseAccepted'], true);
          for (final arm in (row['arms'] as Map).values.cast<Map>()) {
            final runtime = arm['runtime'] as Map;
            final control = runtime['additiveControl'] as Map,
                candidate = runtime['additiveShadow'] as Map;
            if (control['action'] == 'stopNow') {
              expect(candidate['action'], 'stopNow');
            }
            expect(
              candidate['unknown'],
              greaterThanOrEqualTo(control['unknown'] as double),
            );
            expect(
              candidate['observedFraction'],
              lessThanOrEqualTo(control['observedFraction'] as double),
            );
            for (final r in runtime.values.cast<Map>()) {
              expect(r['delivery'], 'shadow');
              expect(r['arbiterActive'], false);
            }
          }
        }
      }
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$egoRoot/replay.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_EGO')) {
        expect(file.existsSync(), false, reason: 'Immutable replay receipt');
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_EGO')) {
        expect(file.readAsStringSync(), text);
      }
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: !const bool.fromEnvironment('BAGDAR_EGO'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
