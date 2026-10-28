import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !['--check', '--write', '--measure'].contains(args.single)) {
    stderr.writeln(
      'Usage: dart run tool/model_benchmark/evaluate_camera_processing_age.dart --check|--write|--measure',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  final mode = args.single;
  final process = await Process.start(
    'flutter',
    [
      'test',
      '--no-pub',
      '--concurrency=1',
      if (mode == '--write' || mode == '--measure')
        '--dart-define=BAGDAR_WRITE_PROCESSING_PROFILE=true',
      if (mode == '--write') '--dart-define=BAGDAR_WRITE_PROCESSING_AGE=true',
      if (mode != '--write') '--dart-define=BAGDAR_CHECK_PROCESSING_AGE=true',
      if (mode == '--measure')
        '--dart-define=BAGDAR_MEASURE_PROCESSING_AGE=true',
      'test/camera_processing_age_gate_test.dart',
      'test/camera_processing_parity_test.dart',
      'test/camera_processing_age_replay_test.dart',
    ],
    workingDirectory: root,
    runInShell: Platform.isWindows,
  );
  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  exitCode = await process.exitCode;
}
