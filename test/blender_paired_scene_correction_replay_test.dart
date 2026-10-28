import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_map_ops.dart';

const _root = 'test/fixtures/spatial_safety/blender-paired-holdout-v1';
const _reportPath = String.fromEnvironment(
  'BAGDAR_CORRECTION_REPORT',
  defaultValue: 'scratch/blender-paired-correction-diagnostic.json',
);
const _write = bool.fromEnvironment('BAGDAR_WRITE_CORRECTION_REPORT');
const _check = bool.fromEnvironment('BAGDAR_CHECK_CORRECTION_REPORT');

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
String _hash(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Uint8List _asset(Map asset) {
  final relative = asset['path'] as String;
  if (relative.contains('..') ||
      relative.contains('\\') ||
      relative.contains(':') ||
      relative.startsWith('/')) {
    throw const FormatException('Unsafe corpus path');
  }
  final file = File('$_root/$relative');
  final root = Directory(_root).resolveSymbolicLinksSync();
  if (!file.resolveSymbolicLinksSync().startsWith(
    '$root${Platform.pathSeparator}',
  )) {
    throw const FormatException('Escaped corpus asset');
  }
  final bytes = file.readAsBytesSync();
  if (sha256.convert(bytes).toString() != asset['sha256']) {
    throw FormatException('Modified corpus asset: $relative');
  }
  return bytes;
}

DepthFrame _frame(Map source, Map ncnn, bool neural, int timestampUs) {
  final width = neural ? 256 : 320;
  final height = neural ? 256 : 240;
  final values = Float32List(width * height);
  if (neural) {
    final record = (ncnn['frames'] as List).cast<Map>().singleWhere(
      (r) =>
          r['sceneId'] == source['sceneId'] &&
          r['frameIndex'] == source['frameIndex'],
    );
    expect(record['rgbSha256'], (source['rgb'] as Map)['sha256']);
    final bytes = Uint8List.fromList(
      gzip.decode(_asset(record['asset'] as Map)),
    );
    expect(bytes.length, width * height * 4);
    final data = ByteData.sublistView(bytes);
    final raw = Float32List(values.length);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = data.getFloat32(i * 4, Endian.little);
      if (!raw[i].isFinite) {
        throw const FormatException('Non-finite pinned NCNN sample');
      }
    }
    values.setAll(0, DepthMapOps.normalizeRelativeProximity(raw));
  } else {
    final bytes = _asset(source['depth'] as Map);
    final ends = <int>[];
    for (var i = 0; i < bytes.length && ends.length < 3; i++) {
      if (bytes[i] == 10) ends.add(i);
    }
    expect(ends.length, 3);
    expect(ascii.decode(bytes.sublist(0, ends[0])), 'P5');
    expect(ascii.decode(bytes.sublist(ends[0] + 1, ends[1])), '$width $height');
    expect(ascii.decode(bytes.sublist(ends[1] + 1, ends[2])), '65535');
    final offset = ends[2] + 1;
    expect(bytes.length - offset, values.length * 2);
    for (var i = 0; i < values.length; i++) {
      final mm = (bytes[offset + i * 2] << 8) | bytes[offset + i * 2 + 1];
      values[i] = mm == 0 ? double.nan : mm / 1000;
    }
  }
  final confidence = Float32List(values.length);
  for (var i = 0; i < values.length; i++) {
    confidence[i] = values[i].isFinite ? 1 : 0;
  }
  return DepthFrame(
    values: values,
    confidence01: confidence,
    width: width,
    height: height,
    timestampUs: timestampUs,
    provider: neural
        ? DepthProviderKind.ncnnRelative
        : DepthProviderKind.arcoreMetric,
    semantics: neural
        ? DepthValueSemantics.relativeProximity
        : DepthValueSemantics.metricMeters,
    modelId: neural ? 'midas-small-ncnn' : 'blender-visible-raycast-paired-v1',
    modelHash: neural
        ? 'param:${ncnn['modelParamSha256']};bin:${ncnn['modelBinSha256']}'
        : _hash('$_root/corpus-manifest.json'),
    preprocessId: neural
        ? ncnn['preprocessId'] as String
        : 'visible-radial-pgm16-mm-v1',
    cropTopFraction: 0,
    frameQuality: 1,
    alignedToImage: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'paired correction diagnostics preserve the first baseline and shadow delivery',
    () {
      final corpus = _json('$_root/corpus-manifest.json');
      final ncnn = _json('docs/_baseline_logs/blender_paired_ncnn.json');
      final yolo = _json('docs/_baseline_logs/blender_paired_yolo.json');
      final hash = _hash('$_root/corpus-manifest.json');
      expect(corpus['pilotOnly'], false);
      expect(corpus['promotionAllowed'], false);
      expect(ncnn['corpusManifestSha256'], hash);
      expect(yolo['corpusManifestSha256'], hash);
      expect(ncnn['modelParamSha256'], _hash('assets/midas_small.ncnn.param'));
      expect(ncnn['modelBinSha256'], _hash('assets/midas_small.ncnn.bin'));
      expect(yolo['artifactSha256'], _hash('assets/yolov8n_int8.tflite'));
      expect(ncnn['frames'], hasLength(132));
      expect(yolo['sequences'], hasLength(12));
      final start = DateTime.utc(2026, 10, 4);
      final modes = <Map<String, Object?>>[];
      final timingRows = <Map<String, Object?>>[];
      for (final neural in [false, true]) {
        final sequences = <Map<String, Object?>>[];
        for (final seq in (corpus['sequences'] as List).cast<Map>()) {
          _asset(seq['scene'] as Map);
          final labels =
              jsonDecode(utf8.decode(_asset(seq['annotations'] as Map))) as Map;
          final moving = labels['userMoving'] as bool;
          final detector = GenericObstacleDetector(
            collectOpeningDiagnostics: true,
          );
          final tracker = GenericObstacleTracker();
          final runtime =
              ConfidenceAuthoritySpatialRuntime(
                healthCoordinator: CoreHealthCoordinator(),
              )..beginSession(
                1,
                now: start.subtract(const Duration(milliseconds: 1)),
              );
          final rows = <Map<String, Object?>>[];
          final sources = (seq['frames'] as List).cast<Map>();
          expect(sources, hasLength(11));
          for (final source in sources) {
            _asset(source['rgb'] as Map);
            _asset(source['semantic'] as Map);
            final index = source['frameIndex'] as int;
            final offset = source['capturedOffsetMs'] as int;
            final captured = start.add(Duration(milliseconds: offset));
            final us = captured.microsecondsSinceEpoch;
            final frame = _frame(
              {...source, 'sceneId': seq['sceneId']},
              ncnn,
              neural,
              us,
            );
            final pitch = ((source['cameraPose'] as Map)['pitchDownDeg'] as num)
                .toDouble();
            final watch = Stopwatch()..start();
            final detection = detector.detect(
              frame: frame,
              pitchDeg: pitch,
              rollDeg: 0,
              motion: moving ? MotionState.walking : MotionState.stationary,
              imageTimestampUs: us,
            );
            final tracks = tracker.update(
              observations: detection.observations,
              timestampUs: us,
              relative: neural,
            );
            final geometryUs = watch.elapsedMicroseconds;
            // Fixed replay clock isolates policy. Real stage timings are separate;
            // no claimed capture-age admission is derived from these timestamps.
            final result = runtime.ingestGenericGeometry(
              header: ObservationHeader(
                providerId: neural
                    ? 'desktop-midas'
                    : 'synthetic-visible-depth',
                modelId: frame.modelId,
                modelHash: frame.modelHash,
                preprocessId: frame.preprocessId,
                sessionGeneration: 1,
                frameId: index + 1,
                sourceTimestampUs: us,
                producedAtUs: us + 1000,
                transformId:
                    'paired-${seq['sceneId']}-${frame.width}x${frame.height}',
                confidence: detection.detectorQuality.clamp(0.0, 1.0),
                health: ObservationHealth.healthy,
              ),
              detection: detection,
              tracks: tracks,
              now: captured.add(const Duration(milliseconds: 2)),
              orientationValid: true,
              userMoving: moving,
              poseQuality: 1,
            );
            watch.stop();
            expect(result.accepted, true, reason: '${seq['sceneId']}/$index');
            expect(result.decision, isNotNull);
            expect(result.submittedAction!.delivery.name, 'shadow');
            expect(runtime.arbiter.active, isNull);
            expect(result.passageClearanceApplied, false);
            final forward = RelativePolarGrid.fromSnapshot(
              result.snapshot,
              orientationValid: true,
              userMoving: moving,
            ).sector(RelativeSectorDirection.forward);
            final candidate = result.decision!.candidates.singleWhere(
              (c) => c.direction.name == 'forward',
            );
            rows.add({
              'frameIndex': index,
              'capturedOffsetMs': offset,
              'geometryReject': detection.rejectReason.name,
              'geometryQuality': detection.detectorQuality,
              'geometryObservations': detection.observations.length,
              'observations': [
                for (final o in detection.observations)
                  {
                    'geometry': o.geometry.name,
                    'zone': o.zone.name,
                    'bounds': [
                      o.normalizedBounds.left,
                      o.normalizedBounds.top,
                      o.normalizedBounds.right,
                      o.normalizedBounds.bottom,
                    ],
                    'overlap': o.corridorOverlap,
                    'confidence': o.confidence,
                    'proximity': o.relativeProximity,
                    'nearestDistanceM': o.nearestDistanceM,
                    'pixels': o.pixelCount,
                    'edgeOnly': o.edgeOnly,
                  },
              ],
              'tracks': [
                for (final t in tracks)
                  {
                    'id': t.id,
                    'hits': t.hits,
                    'misses': t.misses,
                    'confirmed': t.confirmed,
                    'geometry': t.last.geometry.name,
                    'zone': t.last.zone.name,
                    'proximity': t.last.relativeProximity,
                    'confidence': t.last.confidence,
                    'approachTrend': t.approachTrend(),
                    'metricVelocityMps': t.metricVelocityMps(),
                  },
              ],
              'surface': {
                'observed': detection.surfaceEvidence.observedFraction,
                'continuity': detection.surfaceEvidence.continuity,
                'confidence': detection.surfaceEvidence.confidence,
              },
              'unknownFloor': detection.unknownProbabilityFloor,
              'unknownReasons': [
                for (final r in detection.unknownReasons) r.name,
              ],
              'confirmedTracks': tracks.where((t) => t.confirmed).length,
              'action': result.decision!.action.kind.name,
              'rule': result.decision!.action.ruleId,
              'delivery': result.submittedAction!.delivery.name,
              'forwardUnknown': forward.unknownProbability,
              'forwardOccupancy': forward.occupancyProbability,
              'forwardPositiveEvidencePassed': candidate.positiveEvidencePassed,
              'forwardRejectionReasons': [
                for (final r in candidate.rejectionReasons) r.name,
              ],
              'passageApplied': result.passageClearanceApplied,
            });
            timingRows.add({
              'mode': neural ? 'midas-relative' : 'visible-oracle',
              'sceneId': seq['sceneId'],
              'frameIndex': index,
              'geometryTrackerUs': geometryUs,
              'geometryTrackerRuntimeUs': watch.elapsedMicroseconds,
            });
          }
          final hazard = labels['physicalHazard'] as bool;
          final stopRows = rows.where((r) => r['action'] == 'stopNow').toList();
          final firstStop = stopRows.isEmpty
              ? null
              : stopRows.first['capturedOffsetMs'] as int;
          sequences.add({
            'sceneId': seq['sceneId'],
            'pair': seq['pair'],
            'physicalHazard': hazard,
            'referencePassable': labels['referencePassable'],
            'userMoving': moving,
            'hazardOnsetMs': labels['hazardOnsetMs'],
            'latestStopOffsetMs': labels['latestStopOffsetMs'],
            'firstStopOffsetMs': firstStop,
            'onTimeStop': hazard
                ? firstStop != null &&
                      firstStop <= (labels['latestStopOffsetMs'] as int)
                : null,
            'frames': rows,
          });
        }
        final hazardSeqs = sequences
            .where((s) => s['physicalHazard'] == true)
            .toList();
        final passable = sequences
            .where(
              (s) => s['referencePassable'] == true && s['userMoving'] == true,
            )
            .toList();
        List<Map<String, Object?>> framesOf(
          Iterable<Map<String, Object?>> ss,
        ) => ss
            .expand((s) => (s['frames'] as List).cast<Map<String, Object?>>())
            .toList();
        final hazardFrames = framesOf(hazardSeqs);
        final passableFrames = framesOf(passable);
        final all = framesOf(sequences);
        modes.add({
          'mode': neural ? 'midas-relative' : 'visible-oracle',
          'summary': {
            'frames': all.length,
            'hazardSequences': hazardSeqs.length,
            'onTimeStopSequences': hazardSeqs
                .where((s) => s['onTimeStop'] == true)
                .length,
            'lateStopSequences': hazardSeqs
                .where(
                  (s) =>
                      s['onTimeStop'] == false &&
                      s['firstStopOffsetMs'] != null,
                )
                .length,
            'missedStopSequences': hazardSeqs
                .where((s) => s['firstStopOffsetMs'] == null)
                .length,
            'hazardFrames': hazardFrames.length,
            'hazardFramesWithStop': hazardFrames
                .where((r) => r['action'] == 'stopNow')
                .length,
            'hazardFramesWithoutStop': hazardFrames
                .where((r) => r['action'] != 'stopNow')
                .length,
            'unsafeContinues': hazardFrames
                .where((r) => r['action'] == 'continueForward')
                .length,
            'hazardFramesWithImminentRule': hazardFrames
                .where((r) => r['rule'] == 'SPATIAL-P0-IMMINENT')
                .length,
            'passableMovingSequences': passable.length,
            'passableMovingFrames': passableFrames.length,
            'falseStopFrames': passableFrames
                .where((r) => r['action'] == 'stopNow')
                .length,
            'falseImminentFrames': passableFrames
                .where((r) => r['rule'] == 'SPATIAL-P0-IMMINENT')
                .length,
            'passableFinalStopSequences': passable
                .where(
                  (s) =>
                      ((s['frames'] as List).last as Map)['action'] ==
                      'stopNow',
                )
                .length,
            'passableFinalHoldSequences': passable
                .where(
                  (s) =>
                      ((s['frames'] as List).last as Map)['action'] ==
                      'holdAndScan',
                )
                .length,
            'passableFinalContinueSequences': passable
                .where(
                  (s) =>
                      ((s['frames'] as List).last as Map)['action'] ==
                      'continueForward',
                )
                .length,
            'clearanceApplications': all
                .where((r) => r['passageApplied'] == true)
                .length,
          },
          'sequences': sequences,
        });
      }
      final report = {
        'schemaVersion': 1,
        'corpusManifestSha256': hash,
        'toolSha256': _hash(
          'test/blender_paired_scene_correction_replay_test.dart',
        ),
        'firstBaselineSha256': _hash(
          'docs/_baseline_logs/blender_paired_shadow.json',
        ),
        'ncnnReportSha256': _hash(
          'docs/_baseline_logs/blender_paired_ncnn.json',
        ),
        'yoloReportSha256': _hash(
          'docs/_baseline_logs/blender_paired_yolo.json',
        ),
        'scope':
            'known paired correction diagnostics; frozen RGB/model outputs; fixed-clock shadow, no device/capture-to-alert measurement',
        'semanticFusion':
            'YOLO is evaluated separately; no scoring masks or labels enter perception',
        'frameQualityAssumption':
            'aligned synthetic images and ideal admission quality; not Android provider evidence',
        'promotionAllowed': false,
        'conservativeConfidenceAuthority': true,
      'policyId': 'confidence-authority-v3',
        'modes': modes,
      };
      final rendered =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      if (_check) expect(File(_reportPath).readAsStringSync(), rendered);
      if (_write) {
        expect(
          File(_reportPath).existsSync(),
          false,
          reason: 'Never overwrite the first baseline',
        );
        File(_reportPath).writeAsStringSync(rendered);
        File(
          '${_reportPath.replaceAll('.json', '')}-timing.json',
        ).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({'scope': 'Flutter test VM desktop stage timing; excludes model inference/asset materialization/capture; not release or deadline evidence', 'samples': timingRows})}\n',
        );
      }
      expect(modes, hasLength(2));
      for (final mode in modes) {
        expect(mode['sequences'], hasLength(12));
        final summary = mode['summary'] as Map;
        expect(summary['frames'], 132);
        expect(summary['hazardFrames'], 66);
        expect(summary['passableMovingFrames'], 55);
        expect(summary['clearanceApplications'], 0);
        expect(summary['unsafeContinues'], 0);
        expect(summary['falseImminentFrames'], 0);
        expect(summary['lateStopSequences'], 0);
        expect(summary['missedStopSequences'], 0);
        expect(summary['onTimeStopSequences'], 6);
        expect(summary['hazardFramesWithStop'], 66);
      }
    },
  );
}
