import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_scan_coverage_fixture.dart';
import 'harness/blender_visible_body_fixture.dart';

const _path = 'docs/_baseline_logs/blender_scan_coverage_replay_v1.json';
const _write = bool.fromEnvironment('BAGDAR_WRITE_SCAN_COVERAGE');
const _check = bool.fromEnvironment('BAGDAR_CHECK_SCAN_COVERAGE');

PassageEvaluationContext _context(CameraVisibleDepthFrame last) =>
    PassageEvaluationContext(
      nowUs: last.capturedAtUs + 2000,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: last.sessionGeneration,
      frameId: last.frameId,
      rgbTimestampUs: last.capturedAtUs,
      transformId: last.transformId,
    );

CameraPassageClearanceSource _source(
  PassageCalibration calibration,
  List<CameraVisibleDepthFrame> frames,
) => CameraPassageClearanceSource(
  calibration: calibration,
  request: pairedBodyRequest,
  frames: frames,
  producedAtUs: frames.last.capturedAtUs + 1000,
  allowStaticSyntheticScan: true,
);

PassageClearanceResult _evaluate(
  CameraPassageClearanceSource source, {
  bool strict = false,
}) {
  final context = _context(source.frames.last);
  return PassageClearanceEvaluator(
    policy: strict ? pairedBodyPolicy : pairedBodyScanDiagnosticPolicy,
  ).evaluate(
    request: pairedBodyRequest,
    context: context,
    calibration: source.calibration,
    observation: source.observationFor(context),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'scan surface bounds and optical coverage remain separate from freshness',
    () {
      final fixture = ScanCoverageFixture();
      final priorReport = bodyJson(
        'docs/_baseline_logs/blender_visible_body_shadow_v2.json',
      );
      final modes = <Map<String, Object?>>[];
      final timings = <Map<String, Object?>>[];
      for (final mode in [
        'old-views-old-bounds',
        'old-views-new-bounds',
        'coverage-views-new-bounds',
      ]) {
        final scans = <Map<String, Object?>>[];
        for (final layout
            in (fixture.manifest['layouts'] as List).cast<Map>()) {
          final id = layout['sceneId'] as String;
          final timer = Stopwatch()..start();
          final frames = fixture.frames(layout, mode);
          final source = _source(fixture.calibration(id), frames);
          final result = _evaluate(source);
          final strict = _evaluate(source, strict: true);
          timer.stop();
          timings.add({
            'mode': mode,
            'sceneId': id,
            'computeUs': timer.elapsedMicroseconds,
          });
          final observation = source.observationFor(_context(frames.last))!;
          expect(strict.status, PassageClearanceStatus.unavailable);
          expect(
            strict.reasons,
            contains(PassageClearanceReason.staleObservation),
          );
          if (mode == 'old-views-old-bounds') {
            final previous = (priorReport['staticScans'] as List)
                .cast<Map>()
                .singleWhere((s) => s['sceneId'] == id);
            expect(
              result.status.name,
              (previous['diagnostic'] as Map)['status'],
            );
            expect(source.certifiedBodyBoxes, previous['observedBodyBoxes']);
            expect(source.unknownBodyBoxes, previous['unknownBodyBoxes']);
          }
          // Physical labels are read after the optical source made its decision.
          final original = (fixture.prior.corpus['sequences'] as List)
              .cast<Map>()
              .singleWhere((s) => s['sceneId'] == id);
          bodyAsset(pairedRgbRoot, original['annotations'] as Map);
          final labels = bodyJson(
            '$pairedRgbRoot/${(original['annotations'] as Map)['path']}',
          );
          final hazard = labels['physicalHazard'] as bool;
          if (hazard) {
            expect(
              result.status,
              isNot(PassageClearanceStatus.measuredClear),
              reason: id,
            );
          }
          scans.add({
            'sceneId': id,
            'physicalHazard': hazard,
            'views': frames.length,
            'diagnosticStatus': result.status.name,
            'strictStatus': strict.status.name,
            'strictReasons': strict.reasons.map((r) => r.name).toList(),
            'certifiedBodyBoxes': source.certifiedBodyBoxes,
            'unknownBodyBoxes': source.unknownBodyBoxes,
            'unknownBodyCentersM': source.unobservedBodyCellCenters,
            'sections': [
              for (final s in observation.sections)
                {
                  'startM': s.forwardStartM,
                  'endM': s.forwardEndM,
                  'state': s.state.name,
                  'bodyObservedFraction': s.bodyObservedFraction,
                  'floorObservedFraction': s.floorObservedFraction,
                },
            ],
          });
        }
        final safe = scans.where((s) => s['physicalHazard'] == false).toList();
        final hazards = scans
            .where((s) => s['physicalHazard'] == true)
            .toList();
        modes.add({
          'mode': mode,
          'scans': scans,
          'summary': {
            'passableSnapshots': safe.length,
            'passableMeasuredClear': safe
                .where((s) => s['diagnosticStatus'] == 'measuredClear')
                .length,
            'hazardSnapshots': hazards.length,
            'hazardBlocked': hazards
                .where((s) => s['diagnosticStatus'] == 'blocked')
                .length,
            'hazardIncorrectlyClear': hazards
                .where((s) => s['diagnosticStatus'] == 'measuredClear')
                .length,
            'strictStaleRejected': scans
                .where((s) => s['strictStatus'] == 'unavailable')
                .length,
          },
        });
      }
      final finalSummary = modes.last['summary'] as Map;
      final report = {
        'schemaVersion': 1,
        'passed': true,
        'promotionAllowed': false,
        'scope': 'known regression frozen-state geometric diagnostics only',
        'movingFalseStops': 'not_remeasured; prior 55/55 unchanged',
        'deviceRuntime': 'not_run',
        'geometryGoalReached': finalSummary['passableMeasuredClear'] == 6,
        'manifestSha256': fixture.modelHash,
        'priorReportSha256': bodySha(
          'docs/_baseline_logs/blender_visible_body_shadow_v2.json',
        ),
        'evaluatorSha256': bodySha(
          'test/blender_scan_coverage_replay_test.dart',
        ),
        'modes': modes,
      };
      Directory('scratch').createSync(recursive: true);
      File('scratch/blender-scan-coverage-compute.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'scope': 'desktop static geometry compute; excludes neural inference and delivery', 'samples': timings})}\n',
      );
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (_write) {
        final file = File(_path);
        if (file.existsSync()) throw StateError('Scan report is write-once');
        file.writeAsStringSync(rendered);
      }
      if (_check) expect(File(_path).readAsStringSync(), rendered);
      // Coverage success is reported independently of the no-unsafe-clear gate.
      expect((modes.last['summary'] as Map)['hazardIncorrectlyClear'], 0);
      expect((modes.last['summary'] as Map)['strictStaleRejected'], 12);
    },
  );

  for (final fault in [
    'baseline-incomplete',
    'single-view',
    'no-upper-bounds',
    'depth-hole',
    'relative-units',
    'pose-mismatch',
    'session-mismatch',
    'missing-upward-views',
  ]) {
    test('complete static scan authority contrast: $fault', () {
      final fixture = ScanCoverageFixture();
      final layout = (fixture.manifest['layouts'] as List)
          .cast<Map>()
          .singleWhere((l) => l['sceneId'] == 'path-clear');
      var frames = fixture.frames(layout, 'coverage-views-new-bounds');
      if (fault == 'single-view') {
        frames = [frames.last];
      }
      if (fault == 'no-upper-bounds') {
        frames = frames
            .map(
              (f) => scanFrameCopy(
                f,
                upper: List.filled(f.width * f.height, double.nan),
              ),
            )
            .toList();
      }
      if (fault == 'depth-hole') {
        frames = frames
            .map(
              (f) => scanFrameCopy(
                f,
                valid: List.filled(f.width * f.height, false),
              ),
            )
            .toList();
      }
      if (fault == 'relative-units') {
        frames = frames
            .map((f) => scanFrameCopy(f, units: PassageUnits.relativeProximity))
            .toList();
      }
      if (fault == 'pose-mismatch') {
        frames[0] = scanFrameCopy(
          frames[0],
          origin: [0, .02, frames[0].originM[2]],
        );
      }
      if (fault == 'session-mismatch') {
        frames[0] = scanFrameCopy(frames[0], session: 2);
      }
      if (fault == 'missing-upward-views') {
        frames = frames.take(9).toList();
      }
      final result = _evaluate(
        _source(fixture.calibration('path-clear'), frames),
      );
      expect(result.status, PassageClearanceStatus.unavailable);
      if (fault == 'baseline-incomplete') {
        expect(
          result.reasons,
          contains(PassageClearanceReason.unobservedFloor),
        );
      }
    });
  }
}
