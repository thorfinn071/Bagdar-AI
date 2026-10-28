import 'dart:async';
import 'dart:convert';
import 'dart:io';

// The neural worker is only a competing slow branch in this measurement.
// Its output never supplies fast-branch identity, capture time, depth or pose.
class PinnedDepthLoadWorker {
  final Process process;
  final StreamIterator<String> lines;
  PinnedDepthLoadWorker(this.process, this.lines);
  static Future<PinnedDepthLoadWorker> start() async {
    final p = await Process.start('tools/ncnn/.venv/Scripts/python.exe', [
      '-u',
      'tool/model_benchmark/camera_processing_ncnn_worker.py',
    ]);
    p.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 60)) ||
          (jsonDecode(lines.current) as Map)['ready'] != true) {
        throw StateError('Live pinned NN unavailable');
      }
      return PinnedDepthLoadWorker(p, lines);
    } catch (_) {
      p.kill();
      await lines.cancel();
      rethrow;
    }
  }

  Future<Map> infer(String layout, int frame) async {
    process.stdin.writeln(jsonEncode({'layoutId': layout, 'frameId': frame}));
    await process.stdin.flush();
    if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('Neural worker exited');
    }
    final result = jsonDecode(lines.current) as Map;
    if (result['ok'] != true ||
        result['outputMatchesPinned'] != true ||
        result['layoutId'] != layout ||
        result['frameId'] != frame) {
      throw StateError('Pinned NN identity/output drift');
    }
    return result;
  }

  Future<void> close() async {
    await process.stdin.close();
    await lines.cancel();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (code != 0) throw StateError('Neural worker failed');
  }
}
