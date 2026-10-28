import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final directory = Directory(
      Platform.environment['BAGDAR_WORKER_REPORT_DIR'] ??
          'scratch/device-worker-probe',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/integration-response.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 'bagdar-native-worker-device-probe-v1',
        'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'captureToCommandMeasured': false,
        'report': data,
      }),
    );
  },
);
