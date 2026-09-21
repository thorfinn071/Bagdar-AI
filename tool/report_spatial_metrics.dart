import 'dart:io';
import 'dart:convert';

import '../test/harness/spatial_replay_fixture.dart';
import '../test/harness/spatial_scenario_runner.dart';

const _defaultManifest = 'test/fixtures/spatial_safety/manifest.json';

void main(List<String> arguments) {
  final mode = arguments.contains('--rc')
      ? SpatialRunMode.releaseCandidate
      : SpatialRunMode.developer;
  final manifestPath = _valueAfter(arguments, '--manifest') ?? _defaultManifest;
  final outputPath = _valueAfter(arguments, '--output');
  final fixture = SpatialReplayFixture.load(manifestPath);
  final report = SpatialScenarioRunner(fixture: fixture, mode: mode).runAll();
  final payload = <String, Object?>{
    ...report.toJson(),
    'evidence': _evidenceMetadata(arguments),
  };
  final rendered = '${const JsonEncoder.withIndent('  ').convert(payload)}\n';

  if (outputPath == null) {
    if (arguments.contains('--summary')) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'passed': report.passed,
          'mode': mode.name,
          'blockingReasons': report.blockingReasons,
          'metrics': report.metrics.toJson(),
          'evidence': payload['evidence'],
        }),
      );
    } else {
      stdout.write(rendered);
    }
  } else {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(rendered);
    stdout.writeln('Wrote spatial replay report to $outputPath.');
  }
  if (!report.passed) exitCode = 1;
}

Map<String, Object?> _evidenceMetadata(List<String> arguments) {
  String git(List<String> args) {
    final result = Process.runSync('git', args, runInShell: true);
    return result.exitCode == 0 ? result.stdout.toString().trim() : 'unknown';
  }

  final status = git(const <String>['status', '--porcelain']);
  return <String, Object?>{
    'tool': 'tool/report_spatial_metrics.dart',
    'toolSchemaVersion': 2,
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'commitSha': git(const <String>['rev-parse', 'HEAD']),
    'dirty': status != 'unknown' && status.isNotEmpty,
    'command': <String>[
      'dart',
      'run',
      'tool/report_spatial_metrics.dart',
      ...arguments,
    ],
    'manifestPath': _valueAfter(arguments, '--manifest') ?? _defaultManifest,
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
