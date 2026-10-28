import 'dart:io';

import 'package:crypto/crypto.dart';

const historicalReplaySourceRoot =
    'docs/_baseline_sources/scene_logic_before_2026_10_16';

/// Original holdout checks still require the current frozen implementation.
/// Known-corpus regressions may verify exact archived Dart sources instead;
/// models, corpus assets and all other inputs must still match current files.
void verifyFrozenReplaySources(
  Map<String, dynamic> sources, {
  bool allowHistoricalSources = false,
  Directory? root,
}) {
  if (sources.isEmpty) {
    throw const FormatException('Frozen replay sources must not be empty.');
  }
  final repository = (root ?? Directory.current).absolute.uri;
  bool matches(Uri path, String hash) {
    final file = File.fromUri(path);
    return file.existsSync() &&
        sha256.convert(file.readAsBytesSync()).toString() == hash;
  }

  for (final entry in sources.entries) {
    final path = entry.key;
    if (path.isEmpty ||
        path.contains(':') ||
        path.contains('\\') ||
        path.startsWith('/') ||
        path.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw FormatException('Unsafe frozen replay source: $path');
    }
    final hash = entry.value as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw FormatException('Invalid frozen replay hash: $path');
    }
    if (matches(repository.resolve(path), hash)) continue;
    if (allowHistoricalSources &&
        path.endsWith('.dart') &&
        matches(
          repository.resolve('$historicalReplaySourceRoot/$path.snapshot'),
          hash,
        )) {
      continue;
    }
    throw StateError('Frozen source drift: $path');
  }
}
