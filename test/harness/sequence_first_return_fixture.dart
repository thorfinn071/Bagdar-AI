import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';

import 'blender_visible_body_fixture.dart';
import 'synchronized_passage_fixture.dart';
import 'track_first_return_fixture.dart' show firstReturnCopy;

const sequenceReturnRoot = 'scratch/sequence-first-return-2026-10-09';

class SequenceReturnCapture {
  final Map batch, selection;
  final CameraVisibleDepthFrame original, supplemental;
  final List<CameraHeightEnvelopeFrame> channels;
  final DepthFrame relative;
  final PassageClearanceObservation? rig, single;
  final Map<String, Object?> sourceDecision;
  final int bodyUnknown;

  SequenceReturnCapture({
    required this.batch,
    required this.selection,
    required this.original,
    required this.supplemental,
    required this.channels,
    required this.relative,
    required this.rig,
    required this.single,
    required this.sourceDecision,
    required this.bodyUnknown,
  });
}

/// Preparation is outside the fixed functional clock and is not timing proof.
class SequenceReturnFixture {
  final base = SynchronizedPassageFixture(root: '$sequenceReturnRoot/optical');
  final pinned = PairedBodyFixture();
  final selection = bodyJson('$sequenceReturnRoot/selection.json');
  final captures = <SequenceReturnCapture>[];

  SequenceReturnFixture() {
    if (base.manifest['selectionSha256'] !=
            bodySha('$sequenceReturnRoot/selection.json') ||
        selection['corpusManifestSha256'] !=
            bodySha('$pairedRgbRoot/corpus-manifest.json') ||
        selection['neuralReceiptSha256'] !=
            bodySha('docs/_baseline_logs/blender_paired_ncnn.json')) {
      throw StateError('Sequence selection or pinned inputs changed');
    }
    for (final e in (selection['sources'] as Map).entries) {
      if (bodySha(e.key as String) != e.value) {
        throw StateError('Sequence preparation changed');
      }
    }
    if (base.batches.length != 11) throw StateError('Incomplete sequence');
    for (var i = 0; i < base.batches.length; i++) {
      final b = base.batches[i], s = (selection['frames'] as List)[i] as Map;
      final at = b['capturedAtUs'] as int;
      if (b['id'] != s['id'] ||
          b['frameId'] != i + 1 ||
          at != pairedBodyStamp + i * 200000) {
        throw StateError('Reordered or retimed sequence');
      }
      final primary = base.primary(b), p = b['primary'] as Map;
      final original = firstReturnCopy(
        primary,
        upper: bodyFloats(
          bodyAsset(base.root, p['originalSurfaceZUpper'] as Map),
        ),
      );
      bodyAsset(base.root, p['rgb'] as Map);
      final raw = b['neural'] as Map, oldRaw = s['neural'] as Map;
      if ((raw['asset'] as Map)['sha256'] !=
              (oldRaw['asset'] as Map)['sha256'] ||
          raw['rgbSha256'] != (p['rgb'] as Map)['sha256']) {
        throw StateError('Pinned neural output or RGB changed');
      }
      bodyAsset(base.root, raw['asset'] as Map);
      final relative = pinned.relative(
        s['original'] as Map,
        'path-clear',
        at,
        canonicalPreprocess: true,
      );
      final channels = base.frames(b), ctx = base.context(b, at + 2000);
      final source = base.source(b, channels, at + 1000);
      final rig = source.observationFor(ctx);
      final decision = const PassageClearanceEvaluator(policy: pairedBodyPolicy)
          .evaluate(
            request: pairedBodyRequest,
            context: ctx,
            calibration: base.calibration(b, 'rig'),
            observation: rig,
          );
      final single = CameraPassageClearanceSource(
        calibration: base.calibration(b, 'single'),
        request: pairedBodyRequest,
        frames: [original],
        producedAtUs: at + 1000,
      ).observationFor(ctx);
      captures.add(
        SequenceReturnCapture(
          batch: b,
          selection: s,
          original: original,
          supplemental: primary,
          channels: channels,
          relative: relative,
          rig: rig,
          single: single,
          sourceDecision: decision.toDiagnosticMap(),
          bodyUnknown: source.unknownBodyBoxes,
        ),
      );
    }
  }
}
