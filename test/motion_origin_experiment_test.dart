import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/motion_origin_experiment.dart';
import 'harness/camera_visible_passage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'continuous motion origin experiment preserves safety authority',
    () {
      final report = runMotionOriginExperiment();
      final stationary = (report['stationaryCounterfactual'] as List)
          .cast<Map>();
      expect(stationary.first['positiveRelativeFrames'], greaterThan(0));
      expect(stationary.last['positiveRelativeFrames'], 0);
      expect(stationary.last['uniqueSegmentations'], 1);
      final sampling = (report['fixedInputSampling'] as List).cast<Map>();
      expect(
        sampling
            .where((r) => r['mode'] == 'frameStable')
            .every((r) => r['uniqueSegmentations'] == 1),
        true,
      );
      final summary = report['summary'] as Map;
      expect((summary['legacy'] as Map)['stops'], 10);
      expect((summary['frameStable'] as Map)['stops'], 10);
      expect(summary['initialFaultTrials'], 22);
      expect(summary['initialFaultStops'], 22);
      for (final rows in (report['sequence'] as Map).values.cast<List>()) {
        expect(rows.length, 11);
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i] as Map;
          expect(r['sessionStarts'], 1);
          expect(r['userMoving'], true);
          expect(r['delivery'], 'shadow');
          expect(r['arbiterActive'], false);
          if (i > 0) {
            expect(r['previousRevision'], (rows[i - 1] as Map)['revision']);
          }
        }
      }
      final frozenMotion = visibleJson(
        'docs/_baseline_logs/camera_scale_motion.json',
      );
      final cases = (report['motionCases'] as List).cast<Map>();
      expect(cases.length, 9);
      var hazardFrames = 0;
      for (final trial in cases) {
        hazardFrames += (trial['summary'] as Map)['hazardFrames'] as int;
        final prior = (frozenMotion['sequences'] as List)
            .cast<Map>()
            .singleWhere(
              (s) =>
                  s['layoutId'] == trial['layoutId'] &&
                  s['mode'] == 'scale-motion',
            );
        for (final unsafe
            in ((trial['summary'] as Map)['unsafeContinues'] as Map).values) {
          expect(unsafe, 0, reason: trial['layoutId'].toString());
        }
        for (final frame in (trial['frames'] as List).cast<Map>()) {
          final previous = (prior['decisions'] as List).cast<Map>().singleWhere(
            (r) => r['frameId'] == frame['frameId'],
          );
          expect(
            frame['metricMotion'],
            previous['scaleMotion'],
            reason:
                'Unchanged pose-compensated source must reproduce frozen motion',
          );
          expect(frame['objectStationarityCertified'], false);
          expect(frame['motionSuppressed'], false);
          expect(frame['freeSpaceCertified'], false);
        }
      }
      expect(hazardFrames, 60);
      const write = bool.fromEnvironment('BAGDAR_WRITE_MOTION_ORIGIN');
      const check = bool.fromEnvironment('BAGDAR_CHECK_MOTION_ORIGIN');
      final file = File('$motionOriginRoot/replay.json');
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (write) {
        expect(file.existsSync(), false, reason: 'Receipt is immutable');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }
      if (check) expect(file.readAsStringSync(), text);
      // A compact result is useful during development without freezing outputs.
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: !const bool.fromEnvironment('BAGDAR_MOTION_ORIGIN'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
