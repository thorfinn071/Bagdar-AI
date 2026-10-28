import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/ncnn_depth_processor.dart';
import 'package:bagdar/services/ncnn_depth_provider.dart';
import 'package:bagdar/services/ncnn_depth_worker.dart';

class _Backend implements NcnnDepthBackend {
  late String mode;
  @override
  bool init(NcnnDepthWorkerConfig config) {
    mode = config.paramPath;
    return mode != 'startup-fail';
  }

  @override
  bool get isVulkan => false;
  @override
  int get outputWidth => 256;
  @override
  int get outputHeight => 256;
  @override
  Float32List? infer(NcnnDepthInput input) {
    if (mode == 'exit') Isolate.exit();
    if (mode == 'null') return null;
    if (mode == 'constant') {
      return Float32List(256 * 256)..fillRange(0, 256 * 256, 1);
    }
    if (mode == 'nan') {
      return Float32List(256 * 256)..fillRange(0, 256 * 256, double.nan);
    }
    if (mode == 'wrong-shape') return Float32List(3);
    if (mode == 'throw') throw StateError('inference failed');
    sleep(Duration(milliseconds: input.planes[0][0]));
    return Float32List.fromList([
      for (var y = 0; y < 256; y++)
        for (var x = 0; x < 256; x++) 0.2 + y / 256 + x / 1024,
    ]);
  }

  @override
  void dispose() {
    if (mode == 'dispose-throw') throw StateError('dispose failed');
  }
}

NcnnDepthBackend _factory() => _Backend();

NcnnDepthInput _input({
  int id = 1,
  int blockMs = 0,
  int rotation = 0,
  bool mirror = false,
}) => NcnnDepthInput(
  planes: [
    Uint8List(64)
      ..fillRange(0, 64, 64)
      ..[0] = blockMs,
    Uint8List(16)..fillRange(0, 16, 128),
    Uint8List(16)..fillRange(0, 16, 128),
  ],
  rowStrides: [8, 4, 4],
  pixelStrides: [1, 1, 1],
  width: 8,
  height: 8,
  sourceTimestampUs: id,
  rotationDegrees: rotation,
  mirrored: mirror,
);

Future<NcnnDepthWorker> _start({
  String mode = 'normal',
  int timeoutMs = 2000,
}) => NcnnDepthWorker.start(
  NcnnDepthWorkerConfig(paramPath: mode, binPath: 'test'),
  backendFactory: _factory,
  replyTimeout: Duration(milliseconds: timeoutMs),
);

class _Image implements CameraImage {
  @override
  int get width => 8;
  @override
  int get height => 8;
  @override
  List<Plane> get planes => [_Plane(8, 64), _Plane(4, 16), _Plane(4, 16)];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plane implements Plane {
  final int stride;
  final int size;
  _Plane(this.stride, this.size);
  @override
  Uint8List get bytes => Uint8List(size)..fillRange(0, size, 64);
  @override
  int get bytesPerRow => stride;
  @override
  int? get bytesPerPixel => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blocking backend leaves owner timers responsive', () async {
    final worker = await _start();
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    try {
      final reply = await worker.analyze(_input(blockMs: 180).freeze());
      expect(reply.result.frame, isNotNull);
      expect(ticks, greaterThanOrEqualTo(5));
      expect(worker.queuedInputs, 0);
    } finally {
      timer.cancel();
      expect(await worker.close(), isTrue);
    }
  });

  test(
    'one active and only newest pending, without superseding active',
    () async {
      final worker = await _start();
      try {
        final first = worker.analyze(_input(id: 1, blockMs: 120).freeze());
        final second = worker.analyze(_input(id: 2).freeze());
        final third = worker.analyze(_input(id: 3).freeze());
        expect(worker.queuedInputs, 2);
        expect(
          (await second).result.health.rejectionReason,
          'worker_superseded',
        );
        expect((await first).result.frame!.timestampUs, 1);
        expect((await third).result.frame!.timestampUs, 3);
        expect(worker.supersededCount, 1);
        expect(worker.queuedInputs, 0);
      } finally {
        await worker.close();
      }
    },
  );

  test(
    'input freeze and returned results remain independent of reused buffers',
    () async {
      final worker = await _start();
      try {
        final input = _input(blockMs: 80);
        final frozen = input.freeze();
        input.planes[0].fillRange(0, 64, 200);
        final first = await worker.analyze(frozen);
        expect(first.result.alignedLuma!.last, 64);
        final values = List<double>.of(first.result.frame!.values);
        await worker.analyze(_input(id: 2).freeze());
        expect(first.result.frame!.values, values);
        expect(first.result.alignedLuma!.last, 64);
      } finally {
        await worker.close();
      }
    },
  );

  test(
    'transport preserves the existing processor outputs and transforms',
    () async {
      final worker = await _start();
      final backend = _Backend()
        ..init(
          const NcnnDepthWorkerConfig(paramPath: 'normal', binPath: 'test'),
        );
      final inline = NcnnDepthProcessor(backend);
      try {
        for (final rotation in [0, 90, 180, 270]) {
          for (final mirrored in [false, true]) {
            final input = _input(
              id: 100 + rotation,
              rotation: rotation,
              mirror: mirrored,
            );
            final expected = inline.process(input).result;
            final actual = (await worker.analyze(input.freeze())).result;
            expect(actual.frame!.values, expected.frame!.values);
            expect(actual.frame!.confidence01, expected.frame!.confidence01);
            expect(actual.alignedLuma, expected.alignedLuma);
            expect(actual.frame!.timestampUs, expected.frame!.timestampUs);
            expect(actual.frame!.rotationDegrees, rotation);
            expect(actual.frame!.mirrored, mirrored);
            expect(
              actual.health.components.toLogMap(),
              expected.health.components.toLogMap(),
            );
            expect(
              actual.health.rejectionReason,
              expected.health.rejectionReason,
            );
            expect(
              actual.legacyHazards.map((h) => h.toString()),
              expected.legacyHazards.map((h) => h.toString()),
            );
          }
        }
      } finally {
        await worker.close();
        backend.dispose();
      }
    },
  );

  test(
    'deadline returns unavailable and shutdown waits for native completion',
    () async {
      final worker = await _start(timeoutMs: 40);
      final reply = await worker.analyze(_input(blockMs: 180).freeze());
      expect(reply.result.frame, isNull);
      expect(reply.result.health.rejectionReason, 'worker_timeout');
      expect(worker.queuedInputs, 1);
      expect(worker.timeoutCount, 1);
      final shutdown = Stopwatch()..start();
      expect(await worker.close(), isTrue);
      expect(shutdown.elapsedMilliseconds, greaterThan(70));
      expect(await worker.close(), isTrue);
      expect(
        (await worker.analyze(_input().freeze())).result.health.rejectionReason,
        'worker_closed',
      );
    },
  );

  test(
    'pending keeps deadline measured from enqueue, including dispatch',
    () async {
      final worker = await _start(timeoutMs: 100);
      try {
        final first = worker.analyze(_input(blockMs: 60).freeze());
        final pending = worker.analyze(_input(id: 2, blockMs: 200).freeze());
        await first;
        expect((await pending).result.health.rejectionReason, 'worker_timeout');
        expect(worker.timeoutCount, greaterThanOrEqualTo(1));
      } finally {
        await worker.close();
      }
    },
  );

  test(
    'delayed owner timer cannot admit a reply after the real deadline',
    () async {
      final worker = await _start(timeoutMs: 40);
      try {
        final pending = worker.analyze(_input().freeze());
        sleep(const Duration(milliseconds: 160));
        final result = await pending;
        expect(result.result.frame, isNull);
        expect(result.result.health.rejectionReason, 'worker_timeout');
        expect(worker.timeoutCount, 1);
      } finally {
        await worker.close();
      }
    },
  );

  for (final mode in ['null', 'constant', 'nan', 'wrong-shape', 'throw']) {
    test(
      '$mode output is unavailable and never empty healthy geometry',
      () async {
        final worker = await _start(mode: mode);
        try {
          final reply = await worker.analyze(_input().freeze());
          expect(reply.result.frame, isNull);
          expect(reply.result.health.genericObstacleAvailable, isFalse);
          expect(reply.result.legacyHazards, isEmpty);
        } finally {
          await worker.close();
        }
      },
    );
  }

  test(
    'worker startup failure terminates without leaking its native owner',
    () async {
      await expectLater(_start(mode: 'startup-fail'), throwsStateError);
      final next = await _start();
      expect(await next.close(), isTrue);
    },
  );

  test(
    'unexpected worker exit completes active and pending as unavailable',
    () async {
      final worker = await _start(mode: 'exit');
      final first = worker.analyze(_input().freeze());
      final pending = worker.analyze(_input(id: 2).freeze());
      expect((await first).result.frame, isNull);
      expect((await pending).result.frame, isNull);
      expect(await worker.close(), isFalse);
    },
  );

  test(
    'failed native disposal is not reported as acknowledged cleanup',
    () async {
      final worker = await _start(mode: 'dispose-throw');
      expect(await worker.close(), isFalse);
    },
  );

  test(
    'provider preserves session disable and suppresses completion after dispose',
    () async {
      final worker = await _start(mode: 'null');
      final provider = NcnnDepthProvider.withWorker(worker);
      var disabled = 0;
      provider.onSessionDisabled = () => disabled++;
      for (var i = 0; i < 4; i++) {
        expect((await provider.analyzeDetailed(_Image())).frame, isNull);
      }
      expect(disabled, 1);
      expect(provider.debugIsPermanentlyDisabled, isTrue);
      expect(provider.isReady, isFalse);
      provider.dispose();
      await provider.shutdown();

      final slow = await _start();
      final activeProvider = NcnnDepthProvider.withWorker(slow);
      final pending = activeProvider.analyzeDetailed(_Image());
      activeProvider.dispose();
      expect((await pending).health.rejectionReason, 'worker_closed');
      await activeProvider.shutdown();
      expect(activeProvider.isReady, isFalse);
    },
  );

  test(
    'malformed planes and oversized inputs fail before native transport',
    () {
      expect(
        () => NcnnDepthInput(
          planes: [Uint8List(1)],
          rowStrides: [1],
          pixelStrides: [1],
          width: 8,
          height: 8,
        ).freeze(),
        throwsArgumentError,
      );
      expect(
        () => NcnnDepthInput(
          planes: [Uint8List(64), Uint8List(16), Uint8List(16)],
          rowStrides: [7, 4, 4],
          pixelStrides: [1, 1, 1],
          width: 8,
          height: 8,
        ).freeze(),
        throwsArgumentError,
      );
      expect(
        () => NcnnDepthInput(
          planes: [Uint8List(17 * 1024 * 1024), Uint8List(16), Uint8List(16)],
          rowStrides: [8, 4, 4],
          pixelStrides: [1, 1, 1],
          width: 8,
          height: 8,
        ).freeze(),
        throwsArgumentError,
      );
    },
  );
}
