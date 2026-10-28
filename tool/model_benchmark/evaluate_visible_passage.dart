import 'dart:io';

/// Functional camera-visible report. Wall-clock timing is written only by
/// --write; --check delegates to the same real shadow replay without timing
/// equality. Static CLI arguments cannot select scenes or fit test frames.
Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      args.length > 2 ||
      !['--check', '--write'].contains(args.first) ||
      (args.length == 2 &&
          !['--recovery', '--association'].contains(args.last))) {
    stderr.writeln(
      'Usage: dart run tool/model_benchmark/evaluate_visible_passage.dart --check|--write [--recovery|--association]',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  final flag = args.first == '--check'
      ? 'BAGDAR_CHECK_VISIBLE_REPORT'
      : 'BAGDAR_WRITE_VISIBLE_REPORT';
  final process = await Process.start(
    'flutter',
    [
      'test',
      '--no-pub',
      '--concurrency=1',
      '--dart-define=$flag=true',
      args.last == '--association'
          ? 'test/camera_track_passage_replay_test.dart'
          : args.length == 2
          ? 'test/camera_visible_passage_recovery_test.dart'
          : 'test/camera_visible_passage_replay_test.dart',
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
