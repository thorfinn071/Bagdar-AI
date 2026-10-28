import 'dart:convert';
import 'dart:io';
import 'evaluate_fast_camera_motion.dart' show run;

Future<void> main(List<String> args) async {
  if (args.length != 1 || !['--check', '--measure'].contains(args.single)) {
    throw ArgumentError(
      'Usage: evaluate_fast_camera_motion_load --check|--measure',
    );
  }
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'This native experiment currently targets Windows x64 only',
    );
  }
  const dir = 'scratch/fast-camera-load-verification';
  Directory(dir).createSync(recursive: true);
  await run('powershell', [
    '-NoProfile',
    '-File',
    'tool/model_benchmark/build_fast_motion_native.ps1',
    '-OutputDirectory',
    dir,
  ]);
  final library = File('$dir/fast_motion_match.dll').absolute.path;
  for (final entry in {'profile': 'profile', 'replay': 'replay'}.entries) {
    await run('dart', [
      'compile',
      'exe',
      'tool/model_benchmark/${entry.value}_fast_camera_motion_load.dart',
      '-o',
      '$dir/${entry.key}.exe',
    ]);
  }
  await run('$dir/profile.exe', ['--check', '$dir/parity.json', library]);
  await run('$dir/replay.exe', [
    '--functional',
    '$dir/functional.json',
    library,
  ]);
  for (final report in ['parity', 'functional']) {
    final expected = jsonDecode(
      File(
        'docs/_baseline_logs/camera_fast_motion_$report.json',
      ).readAsStringSync(),
    );
    final actual = jsonDecode(File('$dir/$report.json').readAsStringSync());
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError(
        'Native full $report report differs from the frozen v2 reference',
      );
    }
  }
  await run('flutter', [
    'test',
    '--no-pub',
    '--concurrency=1',
    '--dart-define=BAGDAR_FAST_NATIVE_LIBRARY=$library',
    'test/camera_fast_motion_load_test.dart',
    'test/camera_fast_motion_load_shadow_replay_test.dart',
  ]);
  if (args.single != '--measure') return;
  await run('$dir/profile.exe', [
    '--measure',
    'docs/_baseline_logs/camera_fast_motion_load_aot_profile.json',
    library,
  ]);
  await run('dart', [
    'compile',
    'exe',
    'tool/model_benchmark/replay_fast_camera_motion.dart',
    '-o',
    '$dir/baseline.exe',
  ]);
  for (final mode in ['--elapsed', '--elapsed-nn']) {
    for (var round = 0; round < 3; round++) {
      for (final native in round.isEven ? [false, true] : [true, false]) {
        final name = native ? 'native' : 'baseline';
        final path =
            'docs/_baseline_logs/camera_fast_motion_load_${mode.substring(2)}_${name}_$round.json';
        await run('$dir/${native ? 'replay' : 'baseline'}.exe', [
          mode,
          path,
          if (native) library,
        ]);
      }
    }
  }
  await run('python', [
    'tool/model_benchmark/summarize_fast_camera_motion_load.py',
  ]);
}
