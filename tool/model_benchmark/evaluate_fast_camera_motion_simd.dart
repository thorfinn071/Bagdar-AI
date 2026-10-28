import 'dart:convert';
import 'dart:io';

import 'evaluate_fast_camera_motion.dart' show run;

/// Strict arithmetic parity and existing worker safety contracts. Timed
/// observations remain separate from this deterministic regression check.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2 || args.first != '--check') {
    throw ArgumentError(
      'Usage: evaluate_fast_camera_motion_simd --check [directory]',
    );
  }
  if (!Platform.isWindows) {
    throw UnsupportedError('Native experiment is Windows x64');
  }
  final dir = args.length == 2
      ? args[1]
      : 'scratch/fast-camera-simd-verification';
  Directory(dir).createSync(recursive: true);
  for (final build in ['native', 'simd']) {
    await run('powershell', [
      '-NoProfile',
      '-File',
      'tool/model_benchmark/build_fast_motion_$build.ps1',
      '-OutputDirectory',
      dir,
    ]);
  }
  final control = File('$dir/fast_motion_match.dll').absolute.path;
  final library = File('$dir/fast_motion_match_simd.dll').absolute.path;
  await run('python', [
    'tool/model_benchmark/check_fast_motion_simd_parity.py',
    control,
    library,
  ]);
  for (final name in ['profile', 'replay']) {
    await run('dart', [
      'compile',
      'exe',
      'tool/model_benchmark/${name}_fast_camera_motion_packed.dart',
      '-o',
      '$dir/$name.exe',
    ]);
  }
  await run('$dir/profile.exe', ['--check', '$dir/parity.json', library]);
  await run('$dir/replay.exe', [
    '--functional',
    '$dir/functional.json',
    library,
  ]);
  for (final name in ['parity', 'functional']) {
    final expected = jsonDecode(
      File(
        'docs/_baseline_logs/camera_fast_motion_$name.json',
      ).readAsStringSync(),
    );
    final actual = jsonDecode(File('$dir/$name.json').readAsStringSync());
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError('SIMD $name differs from the full frozen reference');
    }
  }
  await run('flutter', [
    'test',
    '--no-pub',
    '--concurrency=1',
    '--dart-define=BAGDAR_FAST_NATIVE_LIBRARY=$library',
    'test/camera_fast_motion_packed_worker_test.dart',
    'test/camera_fast_motion_packed_shadow_replay_test.dart',
  ]);
  stdout.writeln(
    'SIMD: bitwise differential scores, full 109-frame kernel/worker reports, '
    'native safety contracts and 67-frame shadow replay pass.',
  );
}
