import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/services/generic_obstacle_detector.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/tracker/track.dart';
import 'package:bagdar/utils/depth_map_ops.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

const _contextCorpus = bool.fromEnvironment('BAGDAR_CONTEXT_CORPUS');
const _ncnnDepth = bool.fromEnvironment('BAGDAR_NCNN_DEPTH');
const _corpusId = _contextCorpus ? 'blender-context-v3' : 'blender-temporal-v2';
const _corpusRoot = 'test/fixtures/spatial_safety/$_corpusId';
const _ncnnDepthRoot =
    'test/fixtures/spatial_safety/blender-context-ncnn-depth-v1';
const _diagnosticPath = _contextCorpus
    ? 'docs/_baseline_logs/blender_context_detector_diagnostic.json'
    : 'docs/_baseline_logs/blender_temporal_detector_diagnostic.json';
const _reportPath = _contextCorpus
    ? _ncnnDepth
          ? 'docs/_baseline_logs/blender_context_ncnn_shadow_replay.json'
          : 'docs/_baseline_logs/blender_context_shadow_replay.json'
    : 'docs/_baseline_logs/blender_temporal_shadow_replay.json';
const _writeReport = bool.fromEnvironment('BAGDAR_WRITE_SHADOW_REPORT');
const _checkReport = bool.fromEnvironment('BAGDAR_CHECK_SHADOW_REPORT');

// Diagnostic only: valid depth in the central image, split at 60% height.
// This is pixel coverage, not proof of physical clearance or metric range.
double _centralDepthCoverage(DepthFrame frame, {required bool upper}) {
  final x0 = (frame.width * 0.3).floor();
  final x1 = (frame.width * 0.7).floor();
  final split = (frame.height * 0.6).floor();
  final y0 = upper ? 0 : split;
  final y1 = upper ? split : frame.height;
  var valid = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = y * frame.width + x;
      if (frame.confidence01[i] >= 0.15 && frame.values[i].isFinite) {
        valid++;
      }
    }
  }
  return valid / ((x1 - x0) * (y1 - y0));
}

Map<String, dynamic> _jsonFile(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Uint8List _checkedBytes(String root, String relative, String expectedSha256) {
  if (relative.contains('..') ||
      relative.startsWith('/') ||
      relative.contains('\\')) {
    throw FormatException('unsafe corpus path: $relative');
  }
  final file = File('$root/$relative');
  final resolvedRoot = Directory(root).resolveSymbolicLinksSync();
  final resolvedFile = file.resolveSymbolicLinksSync();
  if (!resolvedFile.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
    throw FormatException('asset escapes corpus: $relative');
  }
  final bytes = file.readAsBytesSync();
  if (sha256.convert(bytes).toString() != expectedSha256) {
    throw FormatException('asset hash mismatch: $relative');
  }
  return bytes;
}

({int width, int height, List<int> samples}) _pgm16(Uint8List bytes) {
  final lineEnds = <int>[];
  for (var i = 0; i < bytes.length && lineEnds.length < 3; i++) {
    if (bytes[i] == 10) lineEnds.add(i);
  }
  if (lineEnds.length != 3) throw const FormatException('invalid PGM header');
  final magic = ascii.decode(bytes.sublist(0, lineEnds[0]));
  final size = ascii
      .decode(bytes.sublist(lineEnds[0] + 1, lineEnds[1]))
      .split(' ');
  final maximum = ascii.decode(bytes.sublist(lineEnds[1] + 1, lineEnds[2]));
  if (magic != 'P5' || size.length != 2 || maximum != '65535') {
    throw const FormatException('expected P5 uint16 depth in millimetres');
  }
  final width = int.parse(size[0]);
  final height = int.parse(size[1]);
  final offset = lineEnds[2] + 1;
  if (bytes.length - offset != width * height * 2) {
    throw const FormatException('PGM depth size mismatch');
  }
  final samples = List<int>.generate(
    width * height,
    (i) => (bytes[offset + i * 2] << 8) | bytes[offset + i * 2 + 1],
    growable: false,
  );
  return (width: width, height: height, samples: samples);
}

DepthFrame _depthFrame({
  required Uint8List bytes,
  required int timestampUs,
  required String sceneHash,
}) {
  final pgm = _pgm16(bytes);
  final values = Float32List(pgm.samples.length);
  final confidence = Float32List(pgm.samples.length);
  for (var i = 0; i < pgm.samples.length; i++) {
    final mm = pgm.samples[i];
    values[i] = mm == 0 ? double.nan : mm / 1000;
    confidence[i] = mm == 0 ? 0 : 1;
  }
  return DepthFrame(
    values: values,
    confidence01: confidence,
    width: pgm.width,
    height: pgm.height,
    timestampUs: timestampUs,
    provider: DepthProviderKind.arcoreMetric,
    semantics: DepthValueSemantics.metricMeters,
    modelId: 'blender-raycast-oracle-depth-v2',
    modelHash: sceneHash,
    preprocessId: 'pgm16-mm-to-metric-v1',
    cropTopFraction: 0,
    frameQuality: 1,
    alignedToImage: true,
  );
}

DepthFrame _ncnnDepthFrame({
  required Uint8List bytes,
  required int timestampUs,
  required Map<String, dynamic> manifest,
}) {
  final width = manifest['mapWidth'] as int;
  final height = manifest['mapHeight'] as int;
  if (width != 256 || height != 256 || bytes.length != width * height * 4) {
    throw const FormatException('invalid pinned NCNN depth map size');
  }
  final data = ByteData.sublistView(bytes);
  final raw = Float32List(width * height);
  for (var i = 0; i < raw.length; i++) {
    raw[i] = data.getFloat32(i * 4, Endian.little);
    if (!raw[i].isFinite) {
      throw const FormatException('non-finite pinned NCNN depth sample');
    }
  }
  final relative = DepthMapOps.normalizeRelativeProximity(raw);
  final confidence = Float32List(relative.length);
  for (var i = 0; i < relative.length; i++) {
    confidence[i] = relative[i].isFinite ? 1 : 0;
  }
  return DepthFrame(
    values: relative,
    confidence01: confidence,
    width: width,
    height: height,
    timestampUs: timestampUs,
    provider: DepthProviderKind.ncnnRelative,
    semantics: DepthValueSemantics.relativeProximity,
    modelId: manifest['modelId'] as String,
    modelHash:
        'sha256:param:${manifest['modelParamSha256']};bin:${manifest['modelBinSha256']}',
    preprocessId: manifest['preprocessId'] as String,
    cropTopFraction: 0,
    // The desktop diagnostic isolates model geometry. Android provider
    // quality, YUV conversion and camera health need their own device gate.
    frameQuality: 1,
    alignedToImage: true,
  );
}

List<Track> _upperBoundSemanticTracks(
  Map<String, dynamic> frame,
  int width,
  int height,
) {
  final detections = frame['detections'] as List<dynamic>;
  return <Track>[
    for (var i = 0; i < detections.length; i++)
      (() {
        final detection = detections[i] as Map<String, dynamic>;
        final box = (detection['boxNormalized'] as List<dynamic>).cast<num>();
        final x1 = box[0].toDouble() * width;
        final y1 = box[1].toDouble() * height;
        final x2 = box[2].toDouble() * width;
        final y2 = box[3].toDouble() * height;
        return Track(
          id: (frame['frameIndex'] as int) * 1000 + i + 1,
          label: 'class-${detection['classId']}',
          cx: (x1 + x2) / 2,
          cy: (y1 + y2) / 2,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          // This deliberately gives every box the most permissive distance
          // category for the runtime semantic matcher. A real distance gate
          // could only reduce the reported match count.
          dist: 'close',
          distM: -1,
          initialConf: (detection['score'] as num).toDouble(),
        );
      })(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Blender RGB predictions and pinned depth traverse shadow runtime', () {
    expect(_ncnnDepth && !_contextCorpus, isFalse);
    final corpus = _jsonFile('$_corpusRoot/corpus-manifest.json');
    final diagnostic = _jsonFile(_diagnosticPath);
    expect(corpus['corpusId'], _corpusId);
    expect(diagnostic['corpusId'], corpus['corpusId']);
    expect(
      sha256
          .convert(File('$_corpusRoot/corpus-manifest.json').readAsBytesSync())
          .toString(),
      diagnostic['corpusManifestSha256'],
    );
    final sceneHash =
        (corpus['scene'] as Map<String, dynamic>)['sha256'] as String;
    _checkedBytes(
      _corpusRoot,
      (corpus['scene'] as Map<String, dynamic>)['path'] as String,
      sceneHash,
    );
    final replay = corpus['replayManifest'] as Map<String, dynamic>;
    _checkedBytes(
      _corpusRoot,
      replay['path'] as String,
      replay['sha256'] as String,
    );
    final assets = <String, Map<String, dynamic>>{
      for (final item in corpus['assets'] as List<dynamic>)
        (item as Map<String, dynamic>)['sceneId'] as String: item,
    };
    expect(assets.length, 6);
    final ncnnManifest = _ncnnDepth
        ? _jsonFile('$_ncnnDepthRoot/manifest.json')
        : null;
    final ncnnFrames = <String, Map<String, dynamic>>{};
    if (ncnnManifest != null) {
      expect(ncnnManifest['schemaVersion'], 1);
      expect(ncnnManifest['sourceCorpusId'], _corpusId);
      expect(
        ncnnManifest['sourceCorpusManifestSha256'],
        sha256
            .convert(
              File('$_corpusRoot/corpus-manifest.json').readAsBytesSync(),
            )
            .toString(),
      );
      for (final (name, path) in <(String, String)>[
        (
          'generatorSha256',
          'tool/model_benchmark/generate_context_ncnn_depth.py',
        ),
        ('modelParamSha256', 'assets/midas_small.ncnn.param'),
        ('modelBinSha256', 'assets/midas_small.ncnn.bin'),
      ]) {
        expect(
          ncnnManifest[name],
          sha256.convert(File(path).readAsBytesSync()).toString(),
        );
      }
      expect(ncnnManifest['mapEncoding'], 'little-endian-float32-row-major');
      for (final raw in ncnnManifest['frames'] as List<dynamic>) {
        final frame = raw as Map<String, dynamic>;
        final key = '${frame['sceneId']}/${frame['frameIndex']}';
        expect(ncnnFrames.containsKey(key), isFalse);
        ncnnFrames[key] = frame;
      }
      expect(ncnnFrames, hasLength(18));
    }
    final start = DateTime.utc(2026, 9, 22, 0);
    final modelReports = <Map<String, Object?>>[];

    for (final model in diagnostic['models'] as List<dynamic>) {
      final modelData = model as Map<String, dynamic>;
      final sequences = <Map<String, Object?>>[];
      var hazardFrames = 0;
      var hazardFramesWithStop = 0;
      var hazardFramesWithContinue = 0;
      var hazardFramesWithImminentRule = 0;
      var traversableFrames = 0;
      var traversableFramesWithStop = 0;
      var traversableFramesWithImminentRule = 0;
      var semanticMatches = 0;

      for (final item in modelData['sequences'] as List<dynamic>) {
        final sequence = item as Map<String, dynamic>;
        final sceneId = sequence['sceneId'] as String;
        final asset = assets[sceneId]!;
        final sourceFrames = <int, Map<String, dynamic>>{
          for (final item in asset['frames'] as List<dynamic>)
            (item as Map<String, dynamic>)['frameIndex'] as int: item,
        };
        final detector = GenericObstacleDetector(
          collectOpeningDiagnostics: true,
        );
        final tracker = GenericObstacleTracker();
        final controller = DepthPipelineController(
          vm: CameraViewModel(),
          models: ModelService.instance,
        );
        final runtime =
            SpatialSafetyRuntime(healthCoordinator: CoreHealthCoordinator())
              ..beginSession(
                1,
                now: start.subtract(const Duration(milliseconds: 1)),
              );
        final frameReports = <Map<String, Object?>>[];

        for (final item in sequence['frames'] as List<dynamic>) {
          final frameData = item as Map<String, dynamic>;
          final frameIndex = frameData['frameIndex'] as int;
          final source = sourceFrames[frameIndex]!;
          final pose = source['cameraPose'] as Map<String, dynamic>;
          final rotation = (pose['rotationEulerRadians'] as List<dynamic>)
              .cast<num>();
          final pitchDeg = 90 - rotation[0].toDouble() * 180 / math.pi;
          expect(pitchDeg, closeTo(_contextCorpus ? 8 : 0, 0.001));
          final offset = frameData['capturedOffsetMs'] as int;
          final capturedAt = start.add(Duration(milliseconds: offset));
          final timestampUs = capturedAt.microsecondsSinceEpoch;
          final rgb = source['rgb'] as Map<String, dynamic>;
          final depth = source['depth'] as Map<String, dynamic>;
          final semantic = source['semantic'] as Map<String, dynamic>;
          _checkedBytes(
            _corpusRoot,
            rgb['path'] as String,
            rgb['sha256'] as String,
          );
          _checkedBytes(
            _corpusRoot,
            semantic['path'] as String,
            semantic['sha256'] as String,
          );
          expect(frameData['rgbSha256'], rgb['sha256']);
          final depthBytes = _checkedBytes(
            _corpusRoot,
            depth['path'] as String,
            depth['sha256'] as String,
          );
          final ncnnFrame = ncnnFrames['$sceneId/$frameIndex'];
          if (_ncnnDepth) {
            expect(ncnnFrame, isNotNull);
            expect(ncnnFrame!['rgbSha256'], rgb['sha256']);
            expect(ncnnFrame['oracleDepthSha256'], depth['sha256']);
          }
          final depthFrame = _ncnnDepth
              ? _ncnnDepthFrame(
                  bytes: _checkedBytes(
                    _ncnnDepthRoot,
                    ncnnFrame!['mapPath'] as String,
                    ncnnFrame['mapSha256'] as String,
                  ),
                  timestampUs: timestampUs,
                  manifest: ncnnManifest!,
                )
              : _depthFrame(
                  bytes: depthBytes,
                  timestampUs: timestampUs,
                  sceneHash: sceneHash,
                );
          final detection = detector.detect(
            frame: depthFrame,
            pitchDeg: pitchDeg,
            rollDeg: 0,
            motion: MotionState.walking,
            imageTimestampUs: timestampUs,
          );
          final tracks = tracker.update(
            observations: detection.observations,
            timestampUs: timestampUs,
            relative: _ncnnDepth,
          );
          final yoloTracks = _upperBoundSemanticTracks(
            frameData,
            depthFrame.width,
            depthFrame.height,
          );
          controller.updateYoloTracks(
            yoloTracks,
            imgW: depthFrame.width,
            now: capturedAt,
          );
          final frameSemanticMatches = detection.observations.where((
            observation,
          ) {
            return controller.debugSemanticFor(
                  observation: observation,
                  imageWidth: depthFrame.width,
                  imageHeight: depthFrame.height,
                  frame: depthFrame,
                  now: capturedAt,
                ) !=
                null;
          }).length;
          semanticMatches += frameSemanticMatches;
          final header = ObservationHeader(
            providerId: _ncnnDepth
                ? 'desktop-ncnn-midas-depth'
                : 'blender-raycast-oracle-depth',
            modelId: depthFrame.modelId,
            modelHash: depthFrame.modelHash,
            preprocessId: depthFrame.preprocessId,
            sessionGeneration: 1,
            frameId: frameIndex + 1,
            sourceTimestampUs: timestampUs,
            producedAtUs: timestampUs + 1000,
            transformId:
                'upright-rgb-depth-${depthFrame.width}x${depthFrame.height}-pitch-${pitchDeg.toStringAsFixed(3)}',
            confidence: detection.detectorQuality.clamp(0.0, 1.0),
            health: ObservationHealth.healthy,
          );
          final result = runtime.ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: tracks,
            now: capturedAt.add(const Duration(milliseconds: 2)),
            orientationValid: true,
            userMoving: true,
            poseQuality: 1,
          );
          expect(result.accepted, isTrue, reason: '$sceneId/$frameIndex');
          expect(
            result.submittedAction?.delivery,
            SafetyActionDelivery.shadow,
            reason: '$sceneId/$frameIndex',
          );
          expect(
            runtime.arbiter.active,
            isNull,
            reason: '$sceneId/$frameIndex',
          );
          final action = result.decision!.action.kind;
          final expected = frameData['groundTruthAction'] as String;
          if (expected == 'stopNow') {
            hazardFrames++;
            if (action == SafetyActionKind.stopNow) hazardFramesWithStop++;
            if (result.decision!.action.ruleId == 'SPATIAL-P0-IMMINENT') {
              hazardFramesWithImminentRule++;
            }
            if (action == SafetyActionKind.continueForward) {
              hazardFramesWithContinue++;
            }
          } else {
            traversableFrames++;
            if (action == SafetyActionKind.stopNow) {
              traversableFramesWithStop++;
            }
            if (result.decision!.action.ruleId == 'SPATIAL-P0-IMMINENT') {
              traversableFramesWithImminentRule++;
            }
          }
          final forward = RelativePolarGrid.fromSnapshot(
            result.snapshot,
            orientationValid: true,
            userMoving: true,
          ).sector(RelativeSectorDirection.forward);
          final forwardCandidate = result.decision!.candidates.singleWhere(
            (candidate) => candidate.direction.name == 'forward',
          );
          frameReports.add(<String, Object?>{
            'frameIndex': frameIndex,
            'cameraPitchDeg': pitchDeg,
            'expectedAction': expected,
            'geometryReject': detection.rejectReason.name,
            'groundConfidence': detection.groundConfidence,
            'geometryUnknownFloor': detection.unknownProbabilityFloor,
            'geometryUnknownReasons': <String>[
              for (final reason in detection.unknownReasons) reason.name,
            ],
            'groundDisagreementPixels': detection.groundDisagreementPixels,
            'openingDiagnostics': detection.openingDiagnostics
                ?.toDiagnosticMap(),
            'centralUpperDepthCoverage': _centralDepthCoverage(
              depthFrame,
              upper: true,
            ),
            'centralLowerDepthCoverage': _centralDepthCoverage(
              depthFrame,
              upper: false,
            ),
            'surfaceEvidence': <String, double>{
              'observedFraction': detection.surfaceEvidence.observedFraction,
              'continuity': detection.surfaceEvidence.continuity,
              'confidence': detection.surfaceEvidence.confidence,
            },
            'geometryObservations': detection.observations.length,
            'geometryComponents': <Map<String, Object?>>[
              for (final observation in detection.observations)
                <String, Object?>{
                  'geometry': observation.geometry.name,
                  'zone': observation.zone.name,
                  'confidence': observation.confidence,
                  'relativeProximity': observation.relativeProximity,
                  'corridorOverlap': observation.corridorOverlap,
                  'pixelCount': observation.pixelCount,
                  'bounds': <double>[
                    observation.normalizedBounds.left,
                    observation.normalizedBounds.top,
                    observation.normalizedBounds.right,
                    observation.normalizedBounds.bottom,
                  ],
                },
            ],
            'confirmedTracks': tracks.where((track) => track.confirmed).length,
            'yoloBoxes': yoloTracks.length,
            'possibleSemanticMatches': frameSemanticMatches,
            'runtimeStatus': result.status.name,
            'plannedAction': action.name,
            'plannedRuleId': result.decision!.action.ruleId,
            'submittedDelivery': result.submittedAction!.delivery.name,
            'arbiterEvent': result.arbiterEvent?.type.name,
            'arbiterReason': result.arbiterEvent?.reason,
            'forwardOccupancy': forward.occupancyProbability,
            'forwardTraversability': forward.traversabilityProbability,
            'forwardUnknown': forward.unknownProbability,
            'forwardObservedFraction': forwardCandidate.observedFraction,
            'forwardConfidence': forward.confidence,
            'forwardRejectionReasons': <String>[
              for (final reason in forwardCandidate.rejectionReasons)
                reason.name,
            ],
            'forwardPositiveEvidencePassed':
                forwardCandidate.positiveEvidencePassed,
            'shadowCorrection': result.decision!.shadowCorrection?.name,
          });
        }
        sequences.add(<String, Object?>{
          'sceneId': sceneId,
          'state': sequence['state'],
          'frames': frameReports,
        });
      }
      modelReports.add(<String, Object?>{
        'modelId': modelData['modelId'],
        'artifactSha256': modelData['artifactSha256'],
        'summary': <String, int>{
          'hazardFrames': hazardFrames,
          'hazardFramesWithStop': hazardFramesWithStop,
          'hazardFramesWithContinueForward': hazardFramesWithContinue,
          'hazardFramesWithImminentRule': hazardFramesWithImminentRule,
          'traversableFrames': traversableFrames,
          'traversableFramesWithStop': traversableFramesWithStop,
          'traversableFramesWithImminentRule':
              traversableFramesWithImminentRule,
          'possibleSemanticMatches': semanticMatches,
        },
        'sequences': sequences,
      });
    }

    final report = <String, Object?>{
      'schemaVersion': 2,
      'benchmarkId': _contextCorpus
          ? _ncnnDepth
                ? 'blender-context-ncnn-depth-shadow-runtime-v1'
                : 'blender-context-oracle-depth-shadow-runtime-v3'
          : 'blender-temporal-oracle-depth-shadow-runtime-v2',
      'toolSha256': sha256
          .convert(
            File(
              'test/blender_temporal_shadow_replay_test.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      'corpusManifestSha256': diagnostic['corpusManifestSha256'],
      if (ncnnManifest != null)
        'ncnnDepthManifestSha256': sha256
            .convert(File('$_ncnnDepthRoot/manifest.json').readAsBytesSync())
            .toString(),
      'detectorDiagnosticSha256': sha256
          .convert(File(_diagnosticPath).readAsBytesSync())
          .toString(),
      'depthSource': _ncnnDepth
          ? 'pinned desktop NCNN CPU MiDaS raw output, percentile-normalized as relative proximity; not metres'
          : 'Blender raycast PGM16 metric oracle, not phone depth inference',
      'rgbSource': 'hash-pinned precomputed TFLite/ONNX detector predictions',
      'semanticDistanceAssumption':
          'all boxes close; upper bound on associations',
      'runtimeScope': _ncnnDepth
          ? 'pinned desktop NCNN inference -> GenericObstacleDetector -> GenericObstacleTracker -> SpatialSafetyRuntime; no Android YUV/CameraImage/TTS/device'
          : 'GenericObstacleDetector -> GenericObstacleTracker -> SpatialSafetyRuntime; no CameraImage/NCNN/TTS/device',
      'models': modelReports,
      'promotionAllowed': false,
      'blockingReasons': <String>[
        _ncnnDepth
            ? 'desktop NCNN uses RGB input and forced frame quality; Android YUV, camera alignment and provider health are untested'
            : 'Blender raycast depth bypasses camera capture and phone depth inference',
        'RGB model boxes are precomputed desktop predictions, not on-device tracks',
        'synthetic coverage and conservative stops do not establish hazard recognition or route usability',
        if (_contextCorpus)
          _ncnnDepth
              ? 'context doorway still stops for uncertain forward space; synthetic ramp decisions do not establish real-depth usability'
              : 'context doorway and ramp still stop for uncertain forward space; real-depth usability remains unmeasured',
      ],
    };
    final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    if (_checkReport) {
      expect(File(_reportPath).readAsStringSync(), rendered);
    }
    if (_writeReport) {
      File(_reportPath).writeAsStringSync(rendered);
    }
    expect(modelReports, hasLength(4));
    for (final model in modelReports) {
      expect(model['sequences'], hasLength(6));
      expect((model['summary'] as Map<String, int>)['hazardFrames'], 12);
      expect(
        (model['summary']
            as Map<String, int>)['hazardFramesWithContinueForward'],
        0,
        reason: 'the shadow planner must hold every blocked corpus frame',
      );
      expect(
        (model['summary']
            as Map<String, int>)['traversableFramesWithImminentRule'],
        0,
        reason: 'a passable synthetic scene must not be labelled imminent',
      );
      final sequences = model['sequences']! as List<Map<String, Object?>>;
      final doorway = sequences.singleWhere(
        (sequence) =>
            sequence['sceneId'] ==
            (_contextCorpus ? 'context-doorway' : 'temporal-doorway'),
      );
      for (final frame in doorway['frames']! as List<Map<String, Object?>>) {
        expect(frame['plannedAction'], SafetyActionKind.stopNow.name);
        if (_ncnnDepth) {
          expect(frame['forwardUnknown'] as double, greaterThanOrEqualTo(0.65));
          expect(
            frame['geometryUnknownReasons'] as List<String>,
            containsAll(<String>[
              'unverifiedAperture',
              'groundModelDisagreement',
            ]),
          );
          expect(frame['groundDisagreementPixels'] as int, greaterThan(0));
          final opening = frame['openingDiagnostics']! as Map<String, Object?>;
          expect(opening['authority'], 'diagnostic_only');
          expect(opening['widthM'], isNull);
          expect(opening['headroomM'], isNull);
          expect(
            opening['surfaceContinuity'] as double,
            greaterThan(
              (frame['surfaceEvidence']! as Map<String, double>)['continuity']!,
            ),
            reason: 'the opening fit excludes the near side posts',
          );
          continue;
        }
        final components =
            frame['geometryComponents']! as List<Map<String, Object?>>;
        expect(
          components.any(
            (component) => component['geometry'] == 'broadSurface',
          ),
          isFalse,
          reason: 'door posts and lintel must not become a solid centre wall',
        );
        expect(frame['plannedRuleId'], 'SPATIAL-P0-DEGRADED-MOVING');
      }
      if (_contextCorpus && !_ncnnDepth) {
        final ramp = sequences.singleWhere(
          (sequence) => sequence['sceneId'] == 'context-ramp',
        );
        for (final frame in ramp['frames']! as List<Map<String, Object?>>) {
          expect(frame['centralUpperDepthCoverage'] as double, lessThan(0.5));
          expect(
            frame['centralLowerDepthCoverage'] as double,
            greaterThan(0.95),
          );
          expect(frame['plannedAction'], SafetyActionKind.stopNow.name);
          expect(
            frame['forwardRejectionReasons'] as List<String>,
            contains('unknownArea'),
            reason: 'visible ground cannot clear the unobserved upper corridor',
          );
        }
      }
      if (_contextCorpus && _ncnnDepth) {
        final ramp = sequences.singleWhere(
          (sequence) => sequence['sceneId'] == 'context-ramp',
        );
        final frames = ramp['frames']! as List<Map<String, Object?>>;
        expect(frames, hasLength(3));
        for (final frame in frames) {
          expect(frame['plannedAction'], SafetyActionKind.continueForward.name);
          expect(frame['forwardPositiveEvidencePassed'], isTrue);
          expect(frame['forwardRejectionReasons'], isEmpty);
        }
        expect(
          (model['summary'] as Map<String, int>)['hazardFramesWithStop'],
          12,
          reason: 'better surface support must not release a blocked frame',
        );
        expect(
          (model['summary'] as Map<String, int>)['traversableFramesWithStop'],
          3,
          reason: 'only the three uncertain doorway frames still stop',
        );
      }
    }
  });
}
