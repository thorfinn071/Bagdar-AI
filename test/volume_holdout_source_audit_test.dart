import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'harness/blender_visible_body_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart';
import 'harness/volume_holdout_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'read-only producer attribution after frozen holdout outcome',
    () {
      final volume = HoldoutVolumeFixture();
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
      expect(rows.length, 84);
      final value = {
        'scope':
            'read-only producer diagnosis after frozen runtime outcomes; no threshold/source/data edits',
        'promotionAllowed': false,
        'rows': rows,
      };
      final encoded = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
      final file = File('scratch/volume-holdout-2026-10-10/source-audit.json');
      if (const bool.fromEnvironment('BAGDAR_WRITE_HOLDOUT_AUDIT')) {
        expect(file.existsSync(), false);
        file.writeAsStringSync(encoded);
      }
      if (const bool.fromEnvironment('BAGDAR_CHECK_HOLDOUT_AUDIT')) {
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
    skip: !const bool.fromEnvironment('BAGDAR_HOLDOUT_AUDIT'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
