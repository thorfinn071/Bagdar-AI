import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !['--check', '--write', '--development'].contains(args.first)) {
    stderr.writeln(
      'Usage: dart run tool/model_benchmark/evaluate_temporal_passage.dart --check|--write|--development',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  final flag = args.first == '--check'
      ? 'BAGDAR_CHECK_TEMPORAL_REPORT'
      : 'BAGDAR_WRITE_TEMPORAL_REPORT';
  final process = await Process.start(
    'flutter',
    [
      'test',
      '--no-pub',
      '--concurrency=1',
      '--dart-define=$flag=true',
      args.first == '--development'
          ? 'test/camera_temporal_passage_development_test.dart'
          : 'test/camera_temporal_passage_replay_test.dart',
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
