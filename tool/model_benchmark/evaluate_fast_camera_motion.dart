import 'dart:convert';
import 'dart:io';

Future<void> run(String executable, List<String> args) async {
  final process = await Process.start(
    executable.endsWith('.exe') ? File(executable).absolute.path : executable,
    args,
    runInShell: Platform.isWindows && !executable.endsWith('.exe'),
  );
  final streams = Future.wait([
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stdout.write),
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stderr.write),
  ]);
  final code = await process.exitCode;
  await streams;
  if (code != 0) {
    throw ProcessException(
      executable,
      args,
      'Fast branch verification failed',
      code,
    );
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !['--write', '--check', '--measure'].contains(args[0])) {
    throw ArgumentError(
      'Usage: evaluate_fast_camera_motion --write|--check|--measure',
    );
  }
  final mode = args.single;
  const dir = 'scratch/fast-camera-verification';
  Directory(dir).createSync(recursive: true);
  const profiler = '$dir/profile.exe', replay = '$dir/replay.exe';
  await run('dart', [
    'compile',
    'exe',
    'tool/model_benchmark/profile_fast_camera_motion.dart',
    '-o',
    profiler,
  ]);
  await run(profiler, ['--check', '$dir/parity.json']);
  const parity = 'docs/_baseline_logs/camera_fast_motion_parity.json';
  if (mode == '--write') {
    File(parity).writeAsStringSync(File('$dir/parity.json').readAsStringSync());
  } else if (File(parity).readAsStringSync() !=
      File('$dir/parity.json').readAsStringSync()) {
    throw StateError('Independent AOT parity report drift');
  }
  if (mode == '--measure') {
    await run(profiler, [
      '--measure',
      'docs/_baseline_logs/camera_fast_motion_aot_profile.json',
    ]);
    await run('dart', [
      'run',
      'tool/model_benchmark/profile_fast_camera_motion.dart',
      '--measure',
      'docs/_baseline_logs/camera_fast_motion_jit_profile.json',
    ]);
  }
  await run('dart', [
    'compile',
    'exe',
    'tool/model_benchmark/replay_fast_camera_motion.dart',
    '-o',
    replay,
  ]);
  await run(replay, ['--functional', '$dir/functional.json']);
  const functional = 'docs/_baseline_logs/camera_fast_motion_functional.json';
  if (mode == '--write') {
    File(
      functional,
    ).writeAsStringSync(File('$dir/functional.json').readAsStringSync());
  } else if (File(functional).readAsStringSync() !=
      File('$dir/functional.json').readAsStringSync()) {
    throw StateError('Functional independent worker report drift');
  }
  await run('flutter', [
    'test',
    '--no-pub',
    '--concurrency=1',
    if (mode == '--write') '--dart-define=BAGDAR_WRITE_FAST_MOTION=true',
    'test/camera_fast_motion_test.dart',
    'test/camera_fast_motion_shadow_replay_test.dart',
  ]);
  if (mode == '--measure') {
    await run(replay, [
      '--elapsed',
      'docs/_baseline_logs/camera_fast_motion_elapsed.json',
    ]);
    await run(replay, [
      '--elapsed-nn',
      'docs/_baseline_logs/camera_fast_motion_elapsed_nn.json',
    ]);
  }
}
