import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Pins the computation actually executed by a replay and its immutable inputs.
/// Historical whole-app timing receipts remain separate: editing onboarding or
/// speech must not invalidate an unchanged optical arithmetic regression.
void verifyReplaySourceContract(String path, {Directory? root}) {
  final repository = (root ?? Directory.current).absolute.uri;
  final contract =
      jsonDecode(File.fromUri(repository.resolve(path)).readAsStringSync())
          as Map<String, dynamic>;
  if (contract['schemaVersion'] != 1) {
    throw const FormatException('Unsupported replay source contract.');
  }
  final sources = (contract['sources'] as Map<String, dynamic>)
      .cast<String, String>();
  final entrypoints = (contract['entrypoints'] as List<dynamic>).cast<String>();
  if (sources.isEmpty || entrypoints.isEmpty) {
    throw const FormatException(
      'Replay contract needs sources and entrypoints.',
    );
  }

  Uri checkedPath(String relative) {
    if (relative.isEmpty ||
        relative.contains('\\') ||
        relative.contains(':') ||
        relative.startsWith('/') ||
        relative.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw FormatException('Unsafe replay source path: $relative');
    }
    return repository.resolve(relative);
  }

  final pinnedDart = <Uri>{};
  for (final entry in sources.entries) {
    final source = checkedPath(entry.key);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.value)) {
      throw FormatException('Invalid replay source hash: ${entry.key}');
    }
    final file = File.fromUri(source);
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()).toString() != entry.value) {
      throw StateError('Replay source or fixture changed: ${entry.key}');
    }
    if (entry.key.endsWith('.dart')) pinnedDart.add(source);
  }

  final pending = entrypoints.map(checkedPath).toList();
  final dependencies = <Uri>{};
  final imports = RegExp(r'''(?:import|export|part)\s+['"]([^'"]+)['"]''');
  while (pending.isNotEmpty) {
    final source = pending.removeLast();
    if (!dependencies.add(source)) continue;
    if (!pinnedDart.contains(source)) {
      throw StateError('Unpinned replay dependency: $source');
    }
    for (final match in imports.allMatches(
      File.fromUri(source).readAsStringSync(),
    )) {
      final name = match.group(1)!;
      final Uri dependency;
      if (name.startsWith('package:bagdar/')) {
        dependency = repository.resolve(
          'lib/${name.substring('package:bagdar/'.length)}',
        );
      } else if (!name.contains(':')) {
        dependency = source.resolve(name);
      } else {
        continue;
      }
      if (!dependency.toString().startsWith(repository.toString())) {
        throw StateError('Replay import escapes the repository: $name');
      }
      pending.add(dependency);
    }
  }
  if (dependencies.length != pinnedDart.length) {
    throw StateError('Replay contract contains unrelated Dart sources.');
  }
}
