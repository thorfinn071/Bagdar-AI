import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/path_clear_stop_diagnosis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object?> report;
  setUpAll(() => report = runPathClearStopDiagnosis());

  test(
    'actual path-clear/path-box inputs reproduce frozen behavior and preserve authority',
    () {
      expect(report['failures'], isEmpty);
      final summary = report['summary'] as Map;
      expect(summary['frames'], 22);
      expect(summary['baselineFalseStops'], 11);
      expect(summary['correctedFalseStops'], 11);
      expect(summary['hazardStops'], 11);
      expect(summary['hazardUnsafeContinues'], 0);
      expect(summary['reasonCorrections'], greaterThan(0));
      final rows = (report['frames'] as List).cast<Map>();
      final last = rows.singleWhere(
        (r) => r['sceneId'] == 'path-clear' && r['frameIndex'] == 10,
      );
      expect((last['baseline'] as Map)['rule'], 'SPATIAL-P0-AWAIT-STATIONARY');
      expect(
        (last['correctedCause'] as Map)['rule'],
        'SPATIAL-P0-DEGRADED-MOVING',
      );
      expect((last['input'] as Map)['unknownBodyBoxes'], greaterThan(0));
      expect(report['falseStopReductionEstablished'], false);
      expect(report['ordinaryCameraWired'], false);
      expect(report['promotionAllowed'], false);
      const write = bool.fromEnvironment('BAGDAR_WRITE_STOP_DIAGNOSIS');
      const check = bool.fromEnvironment('BAGDAR_CHECK_STOP_DIAGNOSIS');
      const output = String.fromEnvironment(
        'BAGDAR_STOP_DIAGNOSIS_PATH',
        defaultValue: 'scratch/path-clear-diagnosis-2026-10-07/replay.json',
      );
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (check) {
        expect(File(output).readAsStringSync(), rendered);
      }
      if (write) {
        final file = File(output);
        expect(
          file.existsSync(),
          false,
          reason: 'Keep the first diagnosis receipt',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(rendered);
      }
    },
  );
  test(
    'removing latch and all tracks cannot compensate for unseen body space',
    () {
      final summary = report['summary'] as Map;
      expect(summary['passableWithoutLatchStops'], 11);
      expect(summary['passableWithoutTracksMovingStops'], 11);
      expect(summary['passableWithoutTracksStationaryHolds'], 11);
      for (final row in (report['frames'] as List).cast<Map>().where(
        (r) => r['sceneId'] == 'path-clear',
      )) {
        final ablations = row['testOnlyAblations'] as Map;
        for (final mode in [
          'freshPlanner',
          'noTracksFreshMoving',
          'noTracksFreshStationary',
        ]) {
          final result = ablations[mode] as Map;
          expect(result['positiveCorridor'], false);
          expect(result['passageApplied'], false);
          expect(result['forwardUnknown'], greaterThanOrEqualTo(.65));
        }
      }
    },
  );
  test(
    'holes, relative depth and stale metric input remain unavailable and stopped',
    () {
      final first = (report['frames'] as List).cast<Map>().firstWhere(
        (r) => r['sceneId'] == 'path-clear',
      );
      final ablations = first['testOnlyAblations'] as Map;
      for (final fault in [
        'holes',
        'relativeUnits',
        'staleMetricObservation',
      ]) {
        final result = ablations[fault] as Map;
        expect(result['action'], 'stopNow', reason: fault);
        expect(result['positiveCorridor'], false, reason: fault);
        expect(result['passageApplied'], false, reason: fault);
        expect(
          (result['passage'] as Map)['status'],
          'unavailable',
          reason: fault,
        );
      }
    },
  );
}
