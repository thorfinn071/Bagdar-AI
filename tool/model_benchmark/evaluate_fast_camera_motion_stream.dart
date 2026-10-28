import 'dart:convert';
import 'dart:io';

import 'evaluate_fast_camera_motion.dart' show run;

/// Reproduce diagnostics and stream/slot failure contracts. Timings are
/// separate observations, never a deterministic software-release result.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2 || args.first != '--check') {
    throw ArgumentError(
      'Usage: evaluate_fast_camera_motion_stream --check [directory]',
    );
  }
  if (!Platform.isWindows) {
    throw UnsupportedError('Native experiment is Windows x64');
  }
  final dir = args.length == 2
      ? args[1]
      : 'scratch/fast-camera-stream-verification';
  Directory(dir).createSync(recursive: true);
  await run('powershell', [
    '-NoProfile',
    '-File',
    'tool/model_benchmark/build_fast_motion_native.ps1',
    '-OutputDirectory',
    dir,
  ]);
  final library = File('$dir/fast_motion_match.dll').absolute.path;
  await run('dart', [
    'compile',
    'exe',
    'tool/model_benchmark/replay_fast_camera_motion_stream.dart',
    '-o',
    '$dir/replay.exe',
  ]);
  for (final control in [false, true]) {
    final path = '$dir/${control ? 'control' : 'packed'}-functional.json';
    await run('$dir/replay.exe', [
      '--functional',
      path,
      library,
      if (control) '--control',
    ]);
    final report = jsonDecode(File(path).readAsStringSync()) as Map;
    final summary = report['summary'] as Map;
    if (summary['frames'] != 109 ||
        summary['admittedFullDiagnosticMatches'] != 109 ||
        summary['freshMotionRiskFrames'] != 54 ||
        summary['actualStaleAdmissions'] != 0 ||
        summary['freeSpaceCertifiedFrames'] != 0) {
      throw StateError('Full stream functional regression drift');
    }
  }
  await run('flutter', [
    'test',
    '--no-pub',
    '--concurrency=1',
    'test/independent_replay_feed_test.dart',
    'test/perception_scheduler_test.dart',
  ]);
  stdout.writeln(
    'Stream control/packed diagnostics 109/109; independent feed and app scheduler contracts pass.',
  );
}
