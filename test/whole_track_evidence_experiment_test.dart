import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'harness/whole_track_evidence_experiment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'whole visible support audit preserves motion and stop authority',
    () {
      final report = runWholeTrackEvidenceExperiment();
      final summary = report['summary'] as Map;
      expect(report['promotionAllowed'], false);
      expect(summary['initialFaultTrials'], 22);
      expect(summary['initialFaultStops'], 22);
      expect(summary['motionSequences'], 9);
      for (final mode in ['legacy', 'frameStable']) {
        expect((summary[mode] as Map)['stops'], 10);
        expect((summary[mode] as Map)['continues'], 1);
        expect((summary[mode] as Map)['geometryUnknownPixels'], [
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
      }
      for (final rows in (report['optical'] as Map).values.cast<List>()) {
        expect(rows.length, 11);
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i] as Map;
          expect(r['sessionStarts'], 1);
          expect(r['userMoving'], true);
          expect(r['delivery'], 'shadow');
          expect(r['arbiterActive'], false);
          expect(r['bodyUnknown'], 0);
          if (i > 0) {
            expect(r['previousRevision'], (rows[i - 1] as Map)['revision']);
          }
        }
      }
      var hazards = 0;
      for (final c in (report['motionCases'] as List).cast<Map>()) {
        for (final f in (c['frames'] as List).cast<Map>()) {
          if ((f['scoringOnly'] as Map)['physicalHazard'] == true) hazards++;
          for (final mode in (f['relative'] as Map).values.cast<Map>()) {
            if ((f['scoringOnly'] as Map)['physicalHazard'] == true) {
              expect(mode['action'], 'stopNow');
            }
            for (final r in (mode['coverage'] as List).cast<Map>()) {
              expect(r['completeVisibleSupport'], false);
              expect(r['wholeObjectStationarityCertified'], false);
              expect(r['mayResolveMotionPriority'], false);
              expect(r['freeSpaceCertified'], false);
            }
          }
        }
      }
      expect(hazards, 60);
      final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final file = File('$wholeTrackRoot/replay.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_WHOLE_TRACK')) {
        expect(file.existsSync(), false, reason: 'Receipt is immutable');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_WHOLE_TRACK')) {
        expect(file.readAsStringSync(), text);
      }
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: !const bool.fromEnvironment('BAGDAR_WHOLE_TRACK'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
