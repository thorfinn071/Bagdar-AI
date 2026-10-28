import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../test/fixtures/passage_clearance_contract/scenarios.dart';

// This runner checks declared bounds, not a model or camera capture pipeline.
void main(List<String> args) {
  if (args.length != 2 || (args[0] != '--write' && args[0] != '--check')) {
    stderr.writeln(
      'Usage: dart run tool/model_benchmark/evaluate_passage_clearance_contract.dart --write|--check <report.json>',
    );
    exitCode = 64;
    return;
  }
  final cases = passageContractCases();
  final ids = <String>{};
  final counts = <String, int>{};
  final rows = <Map<String, Object?>>[];
  for (final scenario in cases) {
    if (!ids.add(scenario.id)) {
      throw StateError('Duplicate scenario: ${scenario.id}');
    }
    final result = scenario.evaluate();
    if (result.status != scenario.expectedStatus ||
        !result.reasons.toSet().containsAll(scenario.expectedReasons)) {
      throw StateError(
        'Contract mismatch ${scenario.id}: ${result.toDiagnosticMap()}',
      );
    }
    counts.update(result.status.name, (count) => count + 1, ifAbsent: () => 1);
    rows.add({'scenarioId': scenario.id, ...result.toDiagnosticMap()});
  }
  final report = {
    'schemaVersion': 1,
    'benchmarkId': 'synthetic-passage-clearance-contract-v1',
    'scope':
        'declared conservative metric bounds -> stateless contract evaluator; no depth-model inference or runtime integration',
    'sourceSha256': {
      for (final path in [
        'lib/safety/perception/passage_clearance.dart',
        'test/fixtures/passage_clearance_contract/scenarios.dart',
        'tool/model_benchmark/evaluate_passage_clearance_contract.dart',
      ])
        path: sha256.convert(File(path).readAsBytesSync()).toString(),
    },
    'scenarioCount': cases.length,
    'expectationMismatchCount': 0,
    'statuses': counts,
    'scenarios': rows,
    'modelCorrectnessEstablished': false,
    'deviceCalibrationEstablished': false,
    'runtimeIntegrated': false,
    'promotionAllowed': false,
  };
  final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  final output = File(args[1]);
  if (args[0] == '--check') {
    if (output.readAsStringSync() != rendered) {
      throw StateError('Passage contract report drift: ${output.path}');
    }
    stdout.writeln('Passage contract report matches: ${output.path}');
  } else {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(rendered);
    stdout.writeln(
      'Wrote ${cases.length} passage contract scenarios: ${output.path}',
    );
  }
}
