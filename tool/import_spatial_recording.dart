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
  if (decoded['schemaVersion'] != 1) {
    throw const FormatException('Unsupported recording schema.');
  }
  final recordingId = _string(decoded, 'recordingId');
  final source = _string(decoded, 'source');
  if (source != 'recorded' && source != 'blender') {
    throw FormatException('Unsupported source: $source.');
  }
  final handling = _string(decoded, 'handling');
  if (handling != 'private' && handling != 'public') {
    throw FormatException('Unsupported handling: $handling.');
  }
  final license = _string(decoded, 'license');
  final consent = _map(decoded, 'consent');
  final consentClass = _string(consent, 'class');
  if (source == 'recorded' && consentClass != 'explicit') {
    throw const FormatException('Recorded data requires explicit consent.');
  }
  if (consent['confirmed'] != true && source == 'recorded') {
    throw const FormatException('Recorded-data consent is not confirmed.');
  }
  final retention = _map(decoded, 'retention');
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
    rawEvidence.add(<String, Object?>{
      'kind': _string(item, 'kind'),
      'sha256': _sha(item, 'sha256'),
      'retainedAt': _string(item, 'retainedAt'),
    });
  }

  final derived = decoded['derivedArtifacts'];
  if (derived is! List || derived.isEmpty) {
    throw const FormatException('derivedArtifacts must not be empty.');
  }
  final root = manifestFile.parent;
  final derivedEvidence = <Map<String, Object?>>[];
  for (final entry in derived) {
    if (entry is! Map) throw const FormatException('Invalid derived artifact.');
    final item = entry.cast<String, dynamic>();
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
    final actualHash = sha256.convert(file.readAsBytesSync()).toString();
    if (actualHash != expectedHash) {
      throw FormatException('Artifact hash mismatch: $path.');
    }
    derivedEvidence.add(<String, Object?>{
      'path': path.replaceAll('\\', '/'),
      'sha256': actualHash,
      'kind': _string(item, 'kind'),
    });
  }
  derivedEvidence.sort(
    (a, b) => (a['path'] as String).compareTo(b['path'] as String),
  );
  return <String, Object?>{
    'schemaVersion': 1,
    'recordingId': recordingId,
    'source': source,
    'handling': handling,
    'license': license,
    'consentClass': consentClass,
    'rawMediaImported': false,
    'manifestSha256': sha256.convert(manifestFile.readAsBytesSync()).toString(),
    'rawEvidence': rawEvidence,
    'derivedArtifacts': derivedEvidence,
    'status': 'validated',
  };
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
