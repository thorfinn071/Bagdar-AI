import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SynchronizedRigNeuralLoad {
  final Process process;
  final StreamIterator<String> lines;
  final Map ready;
  SynchronizedRigNeuralLoad(this.process, this.lines, this.ready);

  static Future<SynchronizedRigNeuralLoad> start() async {
    final process = await Process.start('tools/ncnn/.venv/Scripts/python.exe', [
      '-u',
      'tool/model_benchmark/scan_processing_ncnn_load.py',
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 60))) {
        throw StateError('Neural worker exited before warmup');
      }
      final ready = jsonDecode(lines.current) as Map;
      if (ready['ready'] != true) throw StateError('Neural worker not ready');
      process.stdin.writeln(jsonEncode({'command': 'start'}));
      await process.stdin.flush();
      if (!await lines.moveNext().timeout(const Duration(seconds: 30)) ||
          (jsonDecode(lines.current) as Map)['started'] != true) {
        throw StateError('Neural load did not start');
      }
      return SynchronizedRigNeuralLoad(process, lines, ready);
    } catch (_) {
      process.kill();
      await lines.cancel();
      rethrow;
    }
  }

  Future<Map<String, Object?>> close() async {
    try {
      process.stdin.writeln(jsonEncode({'command': 'stop'}));
      await process.stdin.flush();
      await process.stdin.close();
      if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
        throw StateError('Neural load exited without receipt');
      }
      final result = jsonDecode(lines.current) as Map;
      if (result['stopped'] != true ||
          result['allOutputsMatchPinned'] != true ||
          (result['inferences'] as int) < 1) {
        throw StateError('Neural load/output validation failed');
      }
      await lines.cancel();
      if (await process.exitCode.timeout(const Duration(seconds: 30)) != 0) {
        throw StateError('Neural process failed');
      }
      return {'ready': ready, 'result': result};
    } finally {
      process.kill();
    }
  }
}
