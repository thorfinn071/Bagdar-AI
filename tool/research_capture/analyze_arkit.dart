import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/research/recorded_rgbd.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:crypto/crypto.dart';

// Called only after the Python importer audit, and checks every consumed digest
// again. All outputs belong outside the original immutable capture directory.
void main(List<String> args) {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/research_capture/analyze_arkit.dart '
      '<capture-directory> <audit.json> <new-output-directory> [profile.json]',
    );
    exitCode = 64;
    return;
  }
  try {
    final root = Directory(args[0]).absolute;
    final audit =
        jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
    final manifestFile = File('${root.path}/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    if (audit['integrityPassed'] != true ||
        audit['recordingId'] != manifest['recordingId'] ||
        audit['manifestSha256'] !=
            sha256.convert(manifestFile.readAsBytesSync()).toString()) {
      throw const FormatException('Audit/manifest mismatch.');
    }
    Uint8List payload(Map<String, dynamic> descriptor) {
      final path = descriptor['path'] as String;
      if (path.contains('\\') ||
          path.contains(':') ||
          path.startsWith('/') ||
          path.split('/').any((v) => v.isEmpty || v == '.' || v == '..')) {
        throw const FormatException('Unsafe payload path.');
      }
      final file = File('${root.path}/$path');
      if (FileSystemEntity.isLinkSync(file.path) ||
          !file.resolveSymbolicLinksSync().startsWith(
            '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
          )) {
        throw const FormatException('Payload escaped capture.');
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length != descriptor['byteLength'] ||
          sha256.convert(bytes).toString() != descriptor['sha256']) {
        throw const FormatException('Consumed payload changed after audit.');
      }
      return bytes;
    }

    final rows = const LineSplitter()
        .convert(
          utf8.decode(
            payload((manifest['frames'] as Map).cast<String, dynamic>()),
          ),
        )
        .where((line) => line.trim().isNotEmpty)
        .map((line) => (jsonDecode(line) as Map).cast<String, dynamic>())
        .toList();
    final rid = manifest['recordingId'] as String;
    final inputProfile = args.length == 4
        ? (jsonDecode(File(args[3]).readAsStringSync()) as Map)
              .cast<String, dynamic>()
        : null;
    if (inputProfile != null && inputProfile['recordingId'] != rid) {
      throw const FormatException('Profile belongs to another recording.');
    }
    if (inputProfile != null &&
        (inputProfile['format'] != 'bagdar-physical-evidence-profile-v1' ||
            inputProfile['schemaVersion'] != 1 ||
            inputProfile['captureManifestSha256'] != audit['manifestSha256'])) {
      throw const FormatException('Unsupported or unbound empirical profile.');
    }
    if (inputProfile != null &&
        [
          'metricErrorBoundsValidated',
          'metricScaleValidated',
          'physicalAlignmentValidated',
          'floorReferenceValidated',
          'clockBindingValidated',
          'wholePixelBoundsValidated',
          'promotionAllowed',
          'bodyVolumeCoverageEstablished',
          'safetyReplayReady',
          'ordinaryCameraWired',
        ].any((key) => inputProfile[key] == true)) {
      throw const FormatException(
        'Empirical profile cannot self-grant physical authority.',
      );
    }
    final profile = PhysicalEvidenceProfile(
      id: inputProfile?['id'] as String? ?? '$rid:unverified',
      recordingId: rid,
      diagnosticWorldToWalking:
          (inputProfile?['diagnosticWorldToWalkingRowMajor'] as List?)
              ?.cast<num>()
              .map((v) => v.toDouble())
              .toList(),
      empiricalSampleErrorM: (inputProfile?['empiricalSampleErrorM'] as num?)
          ?.toDouble(),
    );
    final output = Directory(args[2]).absolute;
    if (output.existsSync() ||
        output.path == root.path ||
        output.path.startsWith('${root.path}${Platform.pathSeparator}')) {
      throw const FormatException(
        'Use a new output directory outside the capture.',
      );
    }
    output.createSync(recursive: true);
    final clock = RecordedReplayClock(
      rid,
      rows.first['sourceTimestampUs'] as int,
    );
    const request = PassageClearanceRequest(
      referenceFrameId: 'measured-walking-frame-required',
      lateralCenterM: 0,
      widthM: .9,
      headroomM: 1.85,
      forwardStartM: .2,
      forwardEndM: 3.5,
      maximumFloorRiseM: .05,
      maximumFloorDropM: .05,
    );
    const policy = PassageClearancePolicy(
      maximumAgeUs: 100000,
      maximumPairSkewUs: 0,
      maximumProcessingLatencyUs: 100000,
      minimumConfidence: .99,
    );
    final reports = <Map<String, Object?>>[];
    final timing = <int>[];
    for (final row in rows) {
      final watch = Stopwatch()..start();
      final depth = row['depth'] as Map<String, dynamic>?;
      if (depth == null) {
        watch.stop();
        timing.add(watch.elapsedMicroseconds);
        reports.add({
          'frameId': row['frameId'],
          'status': 'unavailable',
          'reasons': ['depth_unavailable'],
          'runtimeDecisionStatus': 'not_run',
          'analysisElapsedUs': watch.elapsedMicroseconds,
          'replayAgeUs': watch.elapsedMicroseconds,
          'captureToDecisionMs': null,
        });
        continue;
      }
      final width = depth['width'] as int, height = depth['height'] as int;
      final bytes = payload(
        (depth['planes'] as List).single as Map<String, dynamic>,
      );
      final b = ByteData.sublistView(bytes);
      Uint8List auxiliary(String key) => row[key] == null
          ? Uint8List(0)
          : payload(
              ((row[key]['planes'] as List).single as Map)
                  .cast<String, dynamic>(),
            );
      final frame = RecordedRgbdFrame(
        recordingId: rid,
        sourceIdentity: audit['manifestSha256'],
        deviceModel: manifest['deviceModel'],
        trackingState: row['trackingState'],
        frameId: row['frameId'],
        sourceTimestampUs: row['sourceTimestampUs'],
        width: width,
        height: height,
        rgbWidth: row['rgb']['width'],
        rgbHeight: row['rgb']['height'],
        axisDepthM: Float32List.fromList([
          for (var i = 0; i < width * height; i++)
            b.getFloat32(i * 4, Endian.little),
        ]),
        confidence: auxiliary('confidence'),
        validity: auxiliary('validity'),
        rgbIntrinsics: (row['intrinsics'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
        cameraTransform: (row['cameraTransform'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
      );
      final stamp = clock.timestamp(frame);
      final source = RecordedPassageEvidenceSource(
        frame: frame,
        clock: clock,
        profile: profile,
        request: request,
        producedAtUs: stamp + watch.elapsedMicroseconds,
      );
      final geometry = source.geometryDiagnostics(
        stamp + watch.elapsedMicroseconds,
      );
      final context = PassageEvaluationContext(
        nowUs: stamp + watch.elapsedMicroseconds,
        timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
        sessionGeneration: 1,
        frameId: frame.frameId,
        rgbTimestampUs: stamp,
        transformId: source.transformId,
      );
      final proof = const PassageClearanceEvaluator(policy: policy).evaluate(
        request: request,
        context: context,
        calibration: source.calibration,
        observation: source.observationFor(context),
      );
      watch.stop();
      geometry['expiredAfterAnalysis'] =
          watch.elapsedMicroseconds > policy.maximumAgeUs;
      timing.add(watch.elapsedMicroseconds);
      reports.add({
        'frameId': frame.frameId,
        'status': proof.status.name,
        'reasons': source.reasonsAt(stamp + watch.elapsedMicroseconds),
        'evaluatorReasons': proof.reasons.map((v) => v.name).toList(),
        'geometry': geometry,
        'bodyObservedFraction': 0,
        'floorObservedFraction': 0,
        'runtimeDecisionStatus': 'not_run',
        'captureToDecisionMs': null,
        'clockMode': RecordedReplayClock.mode,
        'analysisElapsedUs': watch.elapsedMicroseconds,
        'replayAgeUs': watch.elapsedMicroseconds,
        'replayAgeScope':
            'host analysis only; native capture and transport age unknown',
      });
    }
    timing.sort();
    int? percentile(double p) =>
        timing.isEmpty ? null : timing[(p * timing.length).ceil() - 1];
    final result = {
      'schemaVersion': 1,
      'recordingId': rid,
      'scope': 'recorded-provider-feasibility-only',
      'captureManifestSha256': audit['manifestSha256'],
      'frames': reports,
      'measuredClearFrames': 0,
      'falseStopReductionEstablished': false,
      'runtimeComparisonStatus':
          'blocked_before_runtime_by_missing_physical_evidence',
      'captureToDecisionStatus': 'not_established',
      'clockMode': RecordedReplayClock.mode,
      'genericObstacleDelivery': 'shadow',
      'ordinaryCameraWired': false,
      'promotionAllowed': false,
      'timingScope':
          'Windows per-frame payload read/hash/decode/provider/evaluator/diagnostic; excludes initial audit/metadata parse, capture, inference, feedback',
      'analysisElapsedUs': timing,
      'analysisTimingUs': {
        'samples': timing.length,
        'p50': percentile(.5),
        'p95': percentile(.95),
      },
    };
    File('${output.path}/feasibility.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    File(
      '${output.path}/frames.jsonl',
    ).writeAsStringSync('${reports.map(jsonEncode).join('\n')}\n');
    File(
      '${output.path}/coverage.svg',
    ).writeAsStringSync(_coverageSvg(audit, reports));
    stdout.writeln(
      'Wrote ${output.path}; no clearance or runtime reduction established.',
    );
    exitCode = 2; // Integrity success is distinct from unmet physical gate.
  } on Object catch (error) {
    stderr.writeln('ARKit feasibility rejected: $error');
    exitCode = 1;
  }
}

String _coverageSvg(
  Map<String, dynamic> audit,
  List<Map<String, Object?>> rows,
) {
  final available = (audit['frames'] as List).cast<Map>().firstWhere(
    (row) => row['nativePixelAvailability'] != null,
    orElse: () => <String, Object?>{},
  );
  final grid = available['nativePixelAvailability']?['grid8x6Counts'] as List?;
  final totals =
      available['nativePixelAvailability']?['grid8x6Totals'] as List?;
  final rectangles = StringBuffer();
  final geometryRows = rows.where((r) => r['geometry'] is Map).toList();
  final geometry = geometryRows.isEmpty
      ? null
      : geometryRows.first['geometry'] as Map;
  final nearGap = geometry?['nearGapM'] as num?;
  final gapText = nearGap == null
      ? 'Placement / near gap: not established'
      : 'Conditional near gap: ${nearGap.toStringAsFixed(3)} m';
  final gapWidth = nearGap == null
      ? 0
      : (360 * nearGap / 3.3).clamp(0, 360).round();
  for (var y = 0; y < 6; y++) {
    for (var x = 0; x < 8; x++) {
      final n = totals?[y][x] as int? ?? 0;
      final count = grid?[y][x] as int? ?? 0;
      final shade = n == 0 ? 230 : (230 - 150 * count / n).round();
      rectangles.write(
        '<rect x="${24 + x * 48}" y="${90 + y * 40}" width="46" height="38" fill="rgb($shade,$shade,245)"/>',
      );
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="850" height="420" viewBox="0 0 850 420">'
      '<rect width="850" height="420" fill="white"/><g font-family="Arial" fill="#20252b">'
      '<text x="24" y="35" font-size="20">ARKit sample availability / whole-volume evidence</text>'
      '<text x="24" y="65" font-size="14">First depth frame: high-confidence samples (not free space)</text>'
      '$rectangles<text x="445" y="125" font-size="16">Body 0.2-3.5 m: UNKNOWN</text>'
      '<text x="445" y="160" font-size="16">Floor: UNKNOWN</text>'
      '<text x="445" y="195" font-size="14">Whole-pixel bounds: unavailable</text>'
      '<text x="445" y="230" font-size="14">Native clock binding: not established</text>'
      '<text x="445" y="270" font-size="14">$gapText</text>'
      '<rect x="445" y="287" width="360" height="18" fill="#e8e8ec"/>'
      '<rect x="445" y="287" width="$gapWidth" height="18" fill="#777783"/>'
      '<text x="445" y="330" font-size="12">Frustum geometry only; body and floor remain UNKNOWN</text>'
      '<text x="24" y="370" font-size="14">No CONTINUE, path-clear claim, or Android validation is inferred from this diagram.</text>'
      '</g></svg>\n';
}
