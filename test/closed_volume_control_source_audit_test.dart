// Versioned diagnostic harness derived from test/volume_holdout_source_audit_test.dart.
// Frozen predecessors stay unchanged; only corpus identity and declared scope differ.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart';
import 'harness/closed_volume_control_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'producer precondition before inference and runtime',
    () {
      final volume = ClosedVolumeFixture();
      final rows = <Map<String, Object?>>[];
      for (final b in (volume.manifest['batches'] as List).cast<Map>()) {
        final now = (b['capturedAtUs'] as int) + 2000;
        final source = volume.source(b, volume.frames(b), now - 1000);
        final observation = source.observationFor(volume.context(b, now))!;
        final proof = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
            .evaluate(
              request: visibleRequest,
              context: volume.context(b, now),
              calibration: volume.calibration(),
              observation: observation,
            );
        rows.add({
          'layoutId': b['layoutId'],
          'frameId': b['frameId'],
          'providerHealthy': observation.providerHealthy,
          'proofStatus': proof.status.name,
          'proofReasons': proof.reasons.map((v) => v.name).toList(),
          'certifiedBodyBoxes': source.certifiedBodyBoxes,
          'unknownBodyBoxes': source.unknownBodyBoxes,
          'unobservedBodyCellCenters': source.unobservedBodyCellCenters,
          'sourceDiagnostics': source.diagnostics,
          'sections': [
            for (final s in observation.sections)
              {
                'forwardStartM': s.forwardStartM,
                'forwardEndM': s.forwardEndM,
                'state': s.state.name,
                'bodyObservedFraction': s.bodyObservedFraction,
                'floorObservedFraction': s.floorObservedFraction,
              },
          ],
        });
      }
      expect(rows.length, 21);
      final positive = rows
          .where((r) => (r['layoutId'] as String).startsWith('closed-clear-'))
          .toList();
      expect(positive.length, 14);
      expect(
        positive.every(
          (r) =>
              r['proofStatus'] == 'measuredClear' && r['unknownBodyBoxes'] == 0,
        ),
        true,
        reason: 'Full producer precondition before inference/runtime',
      );
      final value = {
        'scope':
            'producer precondition before neural inference/runtime; unchanged thresholds and source',
        'promotionAllowed': false,
        'rows': rows,
      };
      final encoded = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
      final file = File(
        'scratch/closed-volume-control-2026-10-11/source-audit.json',
      );
      if (const bool.fromEnvironment('BAGDAR_WRITE_CLOSED_AUDIT')) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(encoded);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_CLOSED_AUDIT')) {
        expect(file.readAsStringSync(), encoded);
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          'captures': rows.length,
          'healthy': rows.where((v) => v['providerHealthy'] == true).length,
          'measuredClear': rows
              .where((v) => v['proofStatus'] == 'measuredClear')
              .length,
        }),
      );
    },
    skip: !const bool.fromEnvironment('BAGDAR_CLOSED_AUDIT'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
