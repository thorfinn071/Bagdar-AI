import 'dart:convert';
import 'dart:io';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_scan_complete_fixture.dart';
import 'harness/blender_scan_coverage_fixture.dart';
import 'harness/blender_visible_body_fixture.dart';

const _reportPath = 'docs/_baseline_logs/blender_scan_complete_replay_v1.json';
const _write = bool.fromEnvironment('BAGDAR_WRITE_SCAN_COMPLETE');
const _check = bool.fromEnvironment('BAGDAR_CHECK_SCAN_COMPLETE');

PassageEvaluationContext _context(CameraHeightEnvelopeFrame last) =>
    PassageEvaluationContext(
      nowUs: last.depth.capturedAtUs + 2000,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: last.depth.sessionGeneration,
      frameId: last.depth.frameId,
      rgbTimestampUs: last.depth.capturedAtUs,
      transformId: last.depth.transformId,
    );

CameraHeightEnvelopePassageSource _source(
  PassageCalibration calibration,
  List<CameraHeightEnvelopeFrame> frames,
) => CameraHeightEnvelopePassageSource(
  calibration: calibration,
  request: pairedBodyRequest,
  frames: frames,
  producedAtUs: frames.last.depth.capturedAtUs + 1000,
);

PassageClearanceResult _evaluate(
  CameraHeightEnvelopePassageSource source, {
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
  test('complete first-return envelopes prove geometry and reject stale scans', () {
    final fixture = ScanCompleteFixture();
    final scans = <Map<String, Object?>>[];
    final timings = <Map<String, Object?>>[];
    var originalPassableUnavailable = 0;
    var originalHazardBlocked = 0;
    for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
      final id = layout['sceneId'] as String;
      final timer = Stopwatch()..start();
      final frames = fixture.frames(layout);
      final source = _source(fixture.calibration(id), frames);
      final result = _evaluate(source);
      final strict = _evaluate(source, strict: true);
      final observation = source.observationFor(_context(frames.last))!;
      timer.stop();
      timings.add({'sceneId': id, 'computeUs': timer.elapsedMicroseconds});
      expect(strict.status, PassageClearanceStatus.unavailable);
      expect(strict.reasons, contains(PassageClearanceReason.staleObservation));
      final original = (fixture.prior.prior.corpus['sequences'] as List)
          .cast<Map>()
          .singleWhere((s) => s['sceneId'] == id);
      bodyAsset(pairedRgbRoot, original['annotations'] as Map);
      final labels = bodyJson(
        '$pairedRgbRoot/${(original['annotations'] as Map)['path']}',
      );
      final hazard = labels['physicalHazard'] as bool;
      final originalSource = _source(
        fixture.calibration(id),
        fixture.originalHeightFrames(layout),
      );
      final originalResult = _evaluate(originalSource);
      expect(
        originalResult.status,
        hazard
            ? PassageClearanceStatus.blocked
            : PassageClearanceStatus.unavailable,
        reason: '$id original height intervals',
      );
      if (hazard) {
        originalHazardBlocked++;
      } else {
        originalPassableUnavailable++;
        expect(originalSource.bodySource.unknownBodyBoxes, 0, reason: id);
        expect(
          originalResult.reasons,
          contains(PassageClearanceReason.unobservedFloor),
          reason: id,
        );
      }
      expect(
        result.status,
        hazard
            ? PassageClearanceStatus.blocked
            : PassageClearanceStatus.measuredClear,
        reason: id,
      );
      if (!hazard) {
        expect(source.bodySource.unknownBodyBoxes, 0, reason: id);
        for (final s in observation.sections) {
          expect(s.bodyObservedFraction, 1, reason: id);
          expect(s.floorObservedFraction, 1, reason: id);
        }
      }
      scans.add({
        'sceneId': id,
        'physicalHazard': hazard,
        'views': frames.length,
        'diagnosticStatus': result.status.name,
        'originalHeightStatus': originalResult.status.name,
        'strictStatus': strict.status.name,
        'strictReasons': strict.reasons.map((r) => r.name).toList(),
        'certifiedBodyBoxes': source.bodySource.certifiedBodyBoxes,
        'unknownBodyBoxes': source.bodySource.unknownBodyBoxes,
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
    final report = {
      'schemaVersion': 1,
      'passed': true,
      'geometryGoalReached': true,
      'promotionAllowed': false,
      'runtimeWired': false,
      'deviceRuntime': 'not_run',
      'scope':
          'known regression frozen-state geometry; strict runtime freshness unchanged',
      'movingFalseStops': 'not_remeasured; prior 55/55 unchanged',
      'manifestSha256': fixture.modelHash,
      'completeEnvelopeManifestSha256': bodySha(
        '$scanCompleteRoot/manifest.json',
      ),
      'canonicalHeightManifestSha256': bodySha(
        '$scanWatertightRoot/manifest.json',
      ),
      'priorReportSha256': bodySha(
        'docs/_baseline_logs/blender_scan_coverage_replay_v1.json',
      ),
      'evaluatorSha256': bodySha('test/blender_scan_complete_replay_test.dart'),
      'summary': {
        'passableMeasuredClear': 6,
        'hazardBlocked': 6,
        'hazardIncorrectlyClear': 0,
        'strictStaleRejected': 12,
      },
      'originalHeightSummary': {
        'passableUnavailable': originalPassableUnavailable,
        'hazardBlocked': originalHazardBlocked,
      },
      'scans': scans,
    };
    final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    Directory('scratch').createSync(recursive: true);
    File('scratch/blender-scan-complete-compute.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'scope': 'desktop static source/evaluation compute; excludes capture, neural inference and delivery', 'samples': timings})}\n',
    );
    if (_write) {
      final file = File(_reportPath);
      if (file.existsSync()) {
        throw StateError('Complete scan report is write-once');
      }
      file.writeAsStringSync(rendered);
    }
    if (_check) expect(File(_reportPath).readAsStringSync(), rendered);
  });
  for (final fault in [
    'positive',
    'single-view',
    'no-upper-Z',
    'depth-hole',
    'height-hole',
    'first-Z-hole',
    'bad-free-Z',
    'relative-units',
    'pose-mismatch',
    'session-mismatch',
    'missing-upward-views',
    'stale',
  ]) {
    test('complete optical authority contrast: $fault', () {
      final fixture = ScanCompleteFixture();
      final layout = (fixture.manifest['layouts'] as List)
          .cast<Map>()
          .singleWhere((l) => l['sceneId'] == 'path-clear');
      var frames = fixture.frames(layout);
      if (fault == 'single-view') {
        frames = [frames.last];
      }
      if (fault == 'no-upper-Z') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                depth: scanFrameCopy(
                  f.depth,
                  upper: List.filled(
                    f.depth.width * f.depth.height,
                    double.nan,
                  ),
                ),
              ),
            )
            .toList();
      }
      if (fault == 'depth-hole') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                depth: scanFrameCopy(
                  f.depth,
                  valid: List.filled(f.depth.width * f.depth.height, false),
                ),
              ),
            )
            .toList();
      }
      if (fault == 'height-hole') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                heightLower: List.filled(
                  f.depth.width * f.depth.height,
                  double.nan,
                ),
                heightUpper: List.filled(
                  f.depth.width * f.depth.height,
                  double.nan,
                ),
              ),
            )
            .toList();
        expect(frames.every((f) => f.structurallyValid), isTrue);
      }
      if (fault == 'bad-free-Z') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                firstZLower: List.filled(f.depth.width * f.depth.height, 100),
              ),
            )
            .toList();
      }
      if (fault == 'first-Z-hole') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                firstZLower: List.filled(
                  f.depth.width * f.depth.height,
                  double.nan,
                ),
              ),
            )
            .toList();
      }
      if (fault == 'relative-units') {
        frames = frames
            .map(
              (f) => completeFrameCopy(
                f,
                depth: scanFrameCopy(
                  f.depth,
                  units: PassageUnits.relativeProximity,
                ),
              ),
            )
            .toList();
      }
      if (fault == 'pose-mismatch') {
        frames[0] = completeFrameCopy(
          frames[0],
          depth: scanFrameCopy(
            frames[0].depth,
            origin: [0, .02, frames[0].depth.originM[2]],
          ),
        );
      }
      if (fault == 'session-mismatch') {
        frames[0] = completeFrameCopy(
          frames[0],
          depth: scanFrameCopy(frames[0].depth, session: 2),
        );
      }
      if (fault == 'missing-upward-views') {
        frames = frames.take(9).toList();
      }
      final result = _evaluate(
        _source(fixture.calibration('path-clear'), frames),
        strict: fault == 'stale',
      );
      expect(
        result.status,
        fault == 'positive'
            ? PassageClearanceStatus.measuredClear
            : PassageClearanceStatus.unavailable,
      );
      if (fault == 'stale') {
        expect(
          result.reasons,
          contains(PassageClearanceReason.staleObservation),
        );
      }
    });
  }
}
