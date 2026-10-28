import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/scan_processing_support.dart';
import 'harness/blender_scan_complete_fixture.dart';
import 'harness/blender_scan_coverage_fixture.dart';

void main() {
  late ScanCompleteFixture fixture;
  late List<CameraHeightEnvelopeFrame> clear;
  setUpAll(() {
    fixture = ScanCompleteFixture();
    clear = fixture.frames(
      (fixture.manifest['layouts'] as List).cast<Map>().singleWhere(
        (l) => l['sceneId'] == 'path-clear',
      ),
    );
  });
  test(
    'indexed complete envelopes preserve every observation field on 12 scenes',
    () {
      for (final layout in (fixture.manifest['layouts'] as List).cast<Map>()) {
        final id = layout['sceneId'] as String;
        final frames = id == 'path-clear' ? clear : fixture.frames(layout);
        final calibration = fixture.calibration(id);
        final context = scanContext(
          frames.last,
          frames.last.depth.capturedAtUs + 2000,
        );
        final original = scanSource(
          'frozen',
          calibration,
          frames,
          context.nowUs - 1000,
        ).observationFor(context)!;
        final indexedSource = scanSource(
          'indexed',
          calibration,
          frames,
          context.nowUs - 1000,
        );
        final indexed = indexedSource.observationFor(context)!;
        expect(
          scanObservationRecord(indexed),
          scanObservationRecord(original),
          reason: id,
        );
        final hazard = scanHazard(fixture, id);
        final geometry = scanDecision(
          calibration,
          context,
          indexed,
          strict: false,
        );
        expect(
          geometry.status,
          hazard
              ? PassageClearanceStatus.blocked
              : PassageClearanceStatus.measuredClear,
          reason: id,
        );
        expect(
          scanDecision(calibration, context, indexed).status,
          PassageClearanceStatus.unavailable,
        );
        expect(
          scanObservationRecord(indexedSource.observationFor(context)!),
          scanObservationRecord(indexed),
          reason: '$id repeated query',
        );
        final current = frames
            .where((f) => context.nowUs - f.depth.capturedAtUs <= 100000)
            .toList();
        expect(current.length, 1);
        final single = scanSource(
          'indexed',
          calibration,
          current,
          context.nowUs - 1000,
        ).observationFor(context)!;
        if (!hazard) {
          expect(
            scanDecision(calibration, context, single, strict: false).status,
            PassageClearanceStatus.unavailable,
            reason: '$id fresh-only coverage',
          );
        }
      }
    },
  );
  for (final fault in [
    'single-view',
    'no-upper',
    'depth-hole',
    'height-hole',
    'first-hole',
    'bad-first',
    'relative',
    'pose',
    'session',
    'no-upward',
    'reordered',
    'empty',
    'pixel-boundary-hole',
  ]) {
    test('indexed/frozen negative observation parity: $fault', () {
      var frames = clear.toList();
      if (fault == 'single-view') frames = [frames.last];
      if (fault == 'empty') frames = [];
      if (fault == 'reordered') frames = frames.reversed.toList();
      if (fault == 'no-upward') frames = frames.take(9).toList();
      if ([
        'no-upper',
        'depth-hole',
        'relative',
        'height-hole',
        'first-hole',
        'bad-first',
        'pixel-boundary-hole',
      ].contains(fault)) {
        frames = frames.map((f) {
          final n = f.depth.width * f.depth.height;
          var lo = f.heightLowerM.toList(), hi = f.heightUpperM.toList();
          if (fault == 'height-hole') {
            lo = List.filled(n, double.nan);
            hi = List.filled(n, double.nan);
          }
          if (fault == 'pixel-boundary-hole') {
            // Crossing index-tile boundaries and image edges must not average
            // away a missing floor pixel or substitute another pixel's height.
            for (final x in [0, 7, 8, 15, 16, f.depth.width - 1]) {
              for (final y in [0, 7, 8, 15, 16, f.depth.height - 1]) {
                lo[y * f.depth.width + x] = hi[y * f.depth.width + x] =
                    double.nan;
              }
            }
          }
          return completeFrameCopy(
            f,
            depth: scanFrameCopy(
              f.depth,
              upper: fault == 'no-upper' ? List.filled(n, double.nan) : null,
              valid: fault == 'depth-hole' ? List.filled(n, false) : null,
              units: fault == 'relative'
                  ? PassageUnits.relativeProximity
                  : null,
            ),
            heightLower: lo,
            heightUpper: hi,
            firstZLower: fault == 'first-hole'
                ? List.filled(n, double.nan)
                : fault == 'bad-first'
                ? List.filled(n, 100)
                : null,
          );
        }).toList();
      }
      if (fault == 'pose' || fault == 'session') {
        frames[0] = completeFrameCopy(
          frames[0],
          depth: scanFrameCopy(
            frames[0].depth,
            origin: fault == 'pose'
                ? [0, .02, frames[0].depth.originM[2]]
                : null,
            session: fault == 'session' ? 2 : null,
          ),
        );
      }
      final context = scanContext(
        clear.last,
        clear.last.depth.capturedAtUs + 2000,
      );
      final calibration = fixture.calibration('path-clear');
      final original = scanSource(
        'frozen',
        calibration,
        frames,
        context.nowUs - 1000,
      ).observationFor(context);
      final indexed = scanSource(
        'indexed',
        calibration,
        frames,
        context.nowUs - 1000,
      ).observationFor(context);
      expect(
        indexed == null ? null : scanObservationRecord(indexed),
        original == null ? null : scanObservationRecord(original),
      );
      if (indexed != null && fault != 'pixel-boundary-hole') {
        expect(
          scanDecision(calibration, context, indexed, strict: false).status,
          PassageClearanceStatus.unavailable,
        );
      }
    });
  }
}
