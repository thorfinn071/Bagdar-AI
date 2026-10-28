import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Validates a consent-controlled recording export and emits a provenance
/// receipt. It never copies raw media; writing is opt-in through --output.
void main(List<String> arguments) {
  final manifestPath = _valueAfter(arguments, '--manifest');
  if (manifestPath == null) {
    stderr.writeln(
      'Usage: dart run tool/import_spatial_recording.dart '
      '--manifest <recording-manifest.json> [--output <receipt.json>]',
    );
    exitCode = 64;
    return;
  }
  try {
    final receipt = validateSpatialRecordingManifest(manifestPath);
    final rendered = '${const JsonEncoder.withIndent('  ').convert(receipt)}\n';
    final outputPath = _valueAfter(arguments, '--output');
    if (outputPath == null) {
      stdout.write(rendered);
    } else {
      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(rendered);
      stdout.writeln(
        'Wrote validated import receipt to ${output.absolute.path}.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('Recording import rejected: $error');
    exitCode = 1;
  }
}

Map<String, Object?> validateSpatialRecordingManifest(String manifestPath) {
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    throw FileSystemException('Recording manifest missing', manifestPath);
  }
  final decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Recording manifest root must be an object.');
  }
  final schemaVersion = decoded['schemaVersion'];
  if (schemaVersion != 1 && schemaVersion != 2) {
    throw const FormatException('Unsupported recording schema.');
  }
  final recordingId = _string(decoded, 'recordingId');
  final source = _string(decoded, 'source');
  if (source != 'recorded' && source != 'blender') {
    throw FormatException('Unsupported source: $source.');
  }
  if (schemaVersion == 2 && source != 'recorded') {
    throw const FormatException('Schema v2 requires a recorded source.');
  }
  if (schemaVersion == 2) {
    _onlyKeys(decoded, <String>{
      'schemaVersion',
      'recordingId',
      'source',
      'handling',
      'license',
      'consent',
      'retention',
      'capture',
      'rawArtifacts',
      'derivedArtifacts',
    }, 'manifest');
  }
  final handling = _string(decoded, 'handling');
  if (handling != 'private' && handling != 'public') {
    throw FormatException('Unsupported handling: $handling.');
  }
  final license = _string(decoded, 'license');
  final consent = _map(decoded, 'consent');
  if (schemaVersion == 2) {
    _onlyKeys(consent, <String>{'class', 'confirmed'}, 'consent');
  }
  final consentClass = _string(consent, 'class');
  if (source == 'recorded' && consentClass != 'explicit') {
    throw const FormatException('Recorded data requires explicit consent.');
  }
  if (consent['confirmed'] != true && source == 'recorded') {
    throw const FormatException('Recorded-data consent is not confirmed.');
  }
  final retention = _map(decoded, 'retention');
  if (schemaVersion == 2) {
    _onlyKeys(retention, <String>{
      'rawMediaInGit',
      'rawMediaPolicy',
    }, 'retention');
  }
  if (retention['rawMediaInGit'] != false ||
      _string(retention, 'rawMediaPolicy') != 'external') {
    throw const FormatException(
      'Raw/private media must remain external to Git.',
    );
  }
  final rawArtifacts = decoded['rawArtifacts'];
  if (rawArtifacts is! List || rawArtifacts.isEmpty) {
    throw const FormatException(
      'rawArtifacts must contain hash-only evidence.',
    );
  }
  final rawEvidence = <Map<String, Object?>>[];
  for (final entry in rawArtifacts) {
    if (entry is! Map) throw const FormatException('Invalid raw artifact.');
    final item = entry.cast<String, dynamic>();
    if (schemaVersion == 2) {
      _onlyKeys(item, <String>{'kind', 'sha256', 'retainedAt'}, 'raw artifact');
    }
    final retainedAt = _string(item, 'retainedAt');
    if (schemaVersion == 2 && !retainedAt.startsWith('external://')) {
      throw const FormatException('Raw media retention must be external.');
    }
    rawEvidence.add(<String, Object?>{
      'kind': _string(item, 'kind'),
      'sha256': _sha(item, 'sha256'),
      if (schemaVersion == 1) 'retainedAt': retainedAt,
      if (schemaVersion == 2) 'retentionLocation': 'external',
    });
  }

  final derived = decoded['derivedArtifacts'];
  if (derived is! List || derived.isEmpty) {
    throw const FormatException('derivedArtifacts must not be empty.');
  }
  final root = manifestFile.parent;
  final capture = schemaVersion == 2
      ? _validateCapture(_map(decoded, 'capture'))
      : null;
  final derivedEvidence = <Map<String, Object?>>[];
  String? pairPath;
  for (final entry in derived) {
    if (entry is! Map) throw const FormatException('Invalid derived artifact.');
    final item = entry.cast<String, dynamic>();
    if (schemaVersion == 2) {
      _onlyKeys(item, <String>{'kind', 'path', 'sha256'}, 'derived artifact');
    }
    final path = _safeRelativePath(_string(item, 'path'));
    final expectedHash = _sha(item, 'sha256');
    final extension = path.toLowerCase();
    if (!extension.endsWith('.json') &&
        !extension.endsWith('.jsonl') &&
        !extension.endsWith('.npy')) {
      throw FormatException('Raw media extension is forbidden: $path.');
    }
    final file = File('${root.path}${Platform.pathSeparator}$path');
    if (!file.existsSync()) throw FileSystemException('Artifact missing', path);
    if (!_isInsideRoot(file, root)) {
      throw FormatException('Artifact escapes manifest directory: $path.');
    }
    final actualHash = sha256.convert(file.readAsBytesSync()).toString();
    if (actualHash != expectedHash) {
      throw FormatException('Artifact hash mismatch: $path.');
    }
    final kind = _string(item, 'kind');
    if (schemaVersion == 2 && kind == 'frame-pairs') {
      if (pairPath != null || !extension.endsWith('.jsonl')) {
        throw const FormatException(
          'Exactly one JSONL frame-pairs artifact is required.',
        );
      }
      pairPath = path;
    }
    derivedEvidence.add(<String, Object?>{
      'path': path.replaceAll('\\', '/'),
      'sha256': actualHash,
      'kind': kind,
    });
  }
  if (schemaVersion == 2 && pairPath == null) {
    throw const FormatException('Schema v2 requires a frame-pairs artifact.');
  }
  final pairSummary = pairPath == null
      ? null
      : _validateFramePairs(
          File('${root.path}${Platform.pathSeparator}$pairPath'),
          capture!,
        );
  derivedEvidence.sort(
    (a, b) => (a['path'] as String).compareTo(b['path'] as String),
  );
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'recordingId': recordingId,
    'source': source,
    'handling': handling,
    'license': license,
    'consentClass': consentClass,
    'rawMediaImported': false,
    'manifestSha256': sha256.convert(manifestFile.readAsBytesSync()).toString(),
    'rawEvidence': rawEvidence,
    'derivedArtifacts': derivedEvidence,
    if (capture != null) 'capture': capture,
    if (pairSummary != null) 'framePairs': pairSummary,
    'status': 'validated',
  };
}

/// Schema v2 describes synchronized evidence, not a claim of safe guidance.
Map<String, Object> _validateCapture(Map<String, dynamic> value) {
  _onlyKeys(value, <String>{
    'deviceModel',
    'androidVersion',
    'cameraMountId',
    'rgbCameraId',
    'depthProviderId',
    'depthModelId',
    'depthModelHash',
    'preprocessId',
    'depthSemantics',
    'timestampDomain',
    'maxPairSkewUs',
  }, 'capture');
  final timestampDomain = _string(value, 'timestampDomain');
  if (timestampDomain != 'elapsedRealtimeUs') {
    throw const FormatException(
      'Capture timestamps need one monotonic domain.',
    );
  }
  final semantics = _string(value, 'depthSemantics');
  if (semantics != 'metricMeters' && semantics != 'relativeProximity') {
    throw const FormatException('Unknown depth semantics.');
  }
  final maxPairSkewUs = _integer(value, 'maxPairSkewUs');
  if (maxPairSkewUs < 1 || maxPairSkewUs > 150000) {
    throw const FormatException('maxPairSkewUs must be 1..150000.');
  }
  return <String, Object>{
    'deviceModel': _string(value, 'deviceModel'),
    'androidVersion': _string(value, 'androidVersion'),
    'cameraMountId': _string(value, 'cameraMountId'),
    'rgbCameraId': _string(value, 'rgbCameraId'),
    'depthProviderId': _string(value, 'depthProviderId'),
    'depthModelId': _string(value, 'depthModelId'),
    'depthModelHash': _string(value, 'depthModelHash'),
    'preprocessId': _string(value, 'preprocessId'),
    'depthSemantics': semantics,
    'timestampDomain': timestampDomain,
    'maxPairSkewUs': maxPairSkewUs,
  };
}

Map<String, Object> _validateFramePairs(
  File file,
  Map<String, Object> capture,
) {
  // Keep the offline validator bounded even if a malformed export is supplied.
  if (file.lengthSync() > 16 * 1024 * 1024) {
    throw const FormatException('Frame-pairs artifact exceeds 16 MiB.');
  }
  final lines = file.readAsLinesSync();
  if (lines.isEmpty) {
    throw const FormatException('Frame-pairs artifact is empty.');
  }
  var alignedCount = 0;
  var missingCount = 0;
  var maxObservedSkewUs = 0;
  var previousGeneration = -1;
  var previousFrameId = 0;
  var previousRgbTimestampUs = 0;
  var previousDepthTimestampUs = 0;
  final allowedKeys = <String>{
    'frameIndex',
    'sessionGeneration',
    'frameId',
    'rgbTimestampUs',
    'rgbSha256',
    'rgbTransformId',
    'depthStatus',
    'depthTimestampUs',
    'depthSha256',
    'depthTransformId',
  };
  for (var index = 0; index < lines.length; index++) {
    final decoded = jsonDecode(lines[index]);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.any((key) => !allowedKeys.contains(key))) {
      throw FormatException('Invalid frame-pair fields at line ${index + 1}.');
    }
    if (_integer(decoded, 'frameIndex') != index) {
      throw FormatException('Non-contiguous frameIndex at line ${index + 1}.');
    }
    final generation = _integer(decoded, 'sessionGeneration');
    final frameId = _integer(decoded, 'frameId');
    final rgbTimestampUs = _integer(decoded, 'rgbTimestampUs');
    _sha(decoded, 'rgbSha256');
    final rgbTransformId = _string(decoded, 'rgbTransformId');
    if (generation < 1 ||
        generation < previousGeneration ||
        frameId < 1 ||
        (generation == previousGeneration && frameId <= previousFrameId) ||
        rgbTimestampUs <= previousRgbTimestampUs) {
      throw FormatException('Out-of-order frame at line ${index + 1}.');
    }
    if (generation != previousGeneration) previousDepthTimestampUs = 0;
    previousGeneration = generation;
    previousFrameId = frameId;
    previousRgbTimestampUs = rgbTimestampUs;

    final status = _string(decoded, 'depthStatus');
    if (status == 'aligned') {
      final depthTimestampUs = _integer(decoded, 'depthTimestampUs');
      _sha(decoded, 'depthSha256');
      final depthTransformId = _string(decoded, 'depthTransformId');
      final skewUs = (rgbTimestampUs - depthTimestampUs).abs();
      if (depthTimestampUs <= previousDepthTimestampUs ||
          skewUs > (capture['maxPairSkewUs'] as int) ||
          depthTransformId != rgbTransformId) {
        throw FormatException('Unaligned/reused depth at line ${index + 1}.');
      }
      previousDepthTimestampUs = depthTimestampUs;
      if (skewUs > maxObservedSkewUs) maxObservedSkewUs = skewUs;
      alignedCount++;
    } else if (status == 'missing') {
      if (decoded['depthTimestampUs'] != null ||
          decoded['depthSha256'] != null ||
          decoded['depthTransformId'] != null) {
        throw FormatException(
          'Missing depth has payload at line ${index + 1}.',
        );
      }
      missingCount++;
    } else {
      throw FormatException('Unknown depthStatus at line ${index + 1}.');
    }
  }
  return <String, Object>{
    'frameCount': lines.length,
    'alignedCount': alignedCount,
    'missingCount': missingCount,
    'maxObservedSkewUs': maxObservedSkewUs,
    'accuracyMetricsReady': false,
  };
}

bool _isInsideRoot(File file, Directory root) {
  var rootPath = root.resolveSymbolicLinksSync();
  var filePath = file.resolveSymbolicLinksSync();
  if (Platform.isWindows) {
    rootPath = rootPath.toLowerCase();
    filePath = filePath.toLowerCase();
  }
  return filePath.startsWith('$rootPath${Platform.pathSeparator}');
}

int _integer(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is int) return result;
  throw FormatException('$key must be an integer.');
}

void _onlyKeys(Map<String, dynamic> value, Set<String> allowed, String label) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('Unexpected $label field.');
  }
}

String? _valueAfter(List<String> arguments, String option) {
  final index = arguments.indexOf(option);
  if (index < 0) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw ArgumentError('Missing value after $option.');
  }
  return arguments[index + 1];
}

Map<String, dynamic> _map(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is Map) return result.cast<String, dynamic>();
  throw FormatException('$key must be an object.');
}

String _string(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is String && result.trim().isNotEmpty) return result;
  throw FormatException('$key must be a non-empty string.');
}

String _sha(Map<String, dynamic> value, String key) {
  final result = _string(value, key);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(result)) {
    throw FormatException('$key must be a lowercase SHA-256 digest.');
  }
  return result;
}

String _safeRelativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  if (normalized.startsWith('/') ||
      normalized.contains(':') ||
      segments.any((segment) => segment.isEmpty || segment == '..')) {
    throw FormatException('Unsafe derived artifact path: $path.');
  }
  return normalized;
}
