import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/core/simulation_build.dart';
import 'package:bagdar/simulation/simulation_bundle.dart';
import 'package:bagdar/simulation/simulation_session.dart';

void main() {
  late Directory directory;
  late Map<String, dynamic> payload;
  late Map sequence;

  Future<SimulationBundle> load() async {
    final path = '${directory.path}/manifest.json';
    await File(path).writeAsString(jsonEncode(payload));
    return SimulationBundle.load(path);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bagdar-simulation-');
    final bytes = Uint8List.fromList([40, 50, 60, 70, 128, 128]);
    await File('${directory.path}/frame.i420').writeAsBytes(bytes);
    // A valid 1x1 PNG is only a preview; dimensions are not model input.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7XcAAAAASUVORK5CYII=',
    );
    await File('${directory.path}/frame.png').writeAsBytes(png);
    payload = {
      'schemaVersion': 1,
      'synthetic': true,
      'promotionAllowed': false,
      'sequences': [
        {
          'id': 'sample',
          'width': 2,
          'height': 2,
          'rotationDegrees': 0,
          'mirrored': false,
          'pixelFormat': 'i420-bt601-limited',
          'frames': [
            for (var i = 0; i < 3; i++)
              {
                'frameId': i + 1,
                'offsetUs': i * 40000,
                'deliveryDelayUs': 0,
                'drop': false,
                'yuv': {
                  'path': 'frame.i420',
                  'sha256': sha256.convert(bytes).toString(),
                },
                'preview': {
                  'path': 'frame.png',
                  'sha256': sha256.convert(png).toString(),
                },
              },
          ],
          'sensors': [
            for (var i = 0; i < 3; i++)
              {
                'offsetUs': i * 40000,
                'accelerometer': [0, 8.3, 5.2],
                'gyroscope': [0, 0, 0],
              },
          ],
        },
      ],
    };
    sequence = (payload['sequences'] as List).first as Map;
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'loads a checked runtime bundle and separates immutable camera planes',
    () async {
      final bundle = await load();
      expect(bundle.sequences.single.frames.length, 3);
      final raw = Uint8List.fromList([10, 20, 30, 40, 128, 128]);
      final image = SimulationImage(
        sourceFrameId: 2,
        capturedAt: DateTime(2026),
        width: 2,
        height: 2,
        i420: raw,
      );
      raw[0] = 250;
      expect(image.planes[0].bytes[0], 10);
      expect(image.planes[1].bytes.length, 1);
      expect(() => image.planes[0].bytes[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'rejects promotion, duplicate identities and backwards source clocks',
    () async {
      payload['promotionAllowed'] = true;
      await expectLater(load(), throwsFormatException);
      payload['promotionAllowed'] = false;
      sequence['frames'][1]['frameId'] = 1;
      await expectLater(load(), throwsFormatException);
      sequence['frames'][1]['frameId'] = 2;
      sequence['frames'][1]['offsetUs'] = 0;
      await expectLater(load(), throwsFormatException);
    },
  );

  test(
    'rejects malformed sensors, oversized images and invalid delivery order',
    () async {
      sequence['sensors'][0]['accelerometer'] = [double.nan, 0, 0];
      expect(
        () => SimulationSequence.fromJson(sequence),
        throwsFormatException,
      );
      sequence['sensors'][0]['accelerometer'] = [0, 0, 9.81];
      sequence['width'] = 4096;
      expect(
        () => SimulationSequence.fromJson(sequence),
        throwsFormatException,
      );
      sequence['width'] = 2;
      sequence['frames'][0]['deliveryDelayUs'] = 100000;
      expect(
        () => SimulationSequence.fromJson(sequence),
        throwsFormatException,
      );
    },
  );

  test('rejects path traversal and changed bytes before inference', () async {
    final bundle = await load();
    final asset = sequence['frames'][0]['yuv'] as Map;
    asset['path'] = '../frame.i420';
    await expectLater(
      bundle.readAsset(asset, maximumBytes: 6),
      throwsFormatException,
    );
    asset['path'] = 'frame.i420';
    await File('${directory.path}/frame.i420').writeAsBytes([1, 2, 3, 4, 5, 6]);
    await expectLater(
      bundle.readAsset(asset, maximumBytes: 6),
      throwsFormatException,
    );
  });

  test('capture timing retains initial delivery delay', () {
    final clock = CallbackFrameTiming.withInitialAge(1000000, 2500000);
    expect(clock.ageUs, greaterThanOrEqualTo(2500000));
    expect(clock.producedAtUs, greaterThanOrEqualTo(3500000));
  });

  test('ordinary build refuses to construct the replay source', () async {
    final bundle = await load();
    if (!simulationBuild) {
      expect(
        () => SimulationSession(
          bundle: bundle,
          sequence: bundle.sequences.single,
          outputPath: '${directory.path}/report.json',
        ),
        throwsStateError,
      );
    }
  });

  if (simulationBuild) {
    test(
      'counts pending callbacks, records disposal and deduplicates preloads',
      () async {
        final bundle = await load();
        final session = SimulationSession(
          bundle: bundle,
          sequence: bundle.sequences.single,
          outputPath: '${directory.path}/callbacks.json',
          runId: 'callback-test',
        );
        await session.prepare();
        final barrier = Completer<void>();
        session.start((_) => barrier.future);
        await session.finished.timeout(const Duration(seconds: 3));
        expect(session.diagnostics['activeFrameCallbacks'], 3);
        expect(session.diagnostics['peakFrameCallbacks'], 3);
        final previewSize = await File('${directory.path}/frame.png').length();
        expect(session.diagnostics['preloadedBytes'], 6 + previewSize);
        session.dispose();
        barrier.complete();
        await Future<void>.delayed(Duration.zero);
        expect(session.diagnostics['activeFrameCallbacks'], 0);
        expect(session.diagnostics['finishedFrameCallbacks'], 3);
        await session.writeDisposalReport(routeCompleted: true);
        final report =
            jsonDecode(
                  await File(
                    '${session.outputPath}.disposal.json',
                  ).readAsString(),
                )
                as Map;
        expect(report['disposed'], true);
        expect(report['routeCompleted'], true);
        expect(report['hostDisposalAcknowledged'], false);
        session.acknowledgeHostDisposal();
        expect(session.diagnostics['hostDisposalAcknowledged'], true);
        expect(report['promotionAllowed'], false);
      },
    );

    test(
      'synchronous callback failure is recorded without leaking in-flight count',
      () async {
        final bundle = await load();
        final session = SimulationSession(
          bundle: bundle,
          sequence: bundle.sequences.single,
          outputPath: '${directory.path}/failure.json',
        );
        await session.prepare();
        session.start((_) => throw StateError('injected callback failure'));
        await session.finished.timeout(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        await session.writeReport();
        final report =
            jsonDecode(await File(session.outputPath).readAsString()) as Map;
        expect(
          (report['events'] as List)
              .where((e) => e['type'] == 'callback_error')
              .length,
          3,
        );
        expect(session.diagnostics['activeFrameCallbacks'], 0);
        session.dispose();
      },
    );
    test(
      'preserves capture age across pause and completes without looping',
      () async {
        final bundle = await load();
        final session = SimulationSession(
          bundle: bundle,
          sequence: bundle.sequences.single,
          outputPath: '${directory.path}/report.json',
        );
        await session.prepare();
        final delivered = <SimulationImage>[];
        Future<void> frame(SimulationImage image) async => delivered.add(image);
        session.start(frame);
        expect(delivered.map((f) => f.sourceFrameId), [1]);
        session.pause();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        session.start(frame);
        await session.finished.timeout(const Duration(seconds: 3));
        expect(delivered.map((f) => f.sourceFrameId), [1, 2, 3]);
        expect(
          DateTime.now().difference(delivered[1].capturedAt).inMilliseconds,
          greaterThanOrEqualTo(90),
        );
        session.start(frame);
        expect(delivered.length, 3);
        await session.writeReport();
        final report =
            jsonDecode(await File(session.outputPath).readAsString()) as Map;
        expect(report['completedInput'], true);
        expect(report['promotionAllowed'], false);
        session.dispose();
      },
    );

    test(
      'dropped frames never reach inference, delayed frames keep source timestamp',
      () async {
        sequence['frames'][1]['drop'] = true;
        sequence['frames'][2]['deliveryDelayUs'] = 80000;
        final bundle = await load();
        final session = SimulationSession(
          bundle: bundle,
          sequence: bundle.sequences.single,
          outputPath: '${directory.path}/report.json',
        );
        await session.prepare();
        final ids = <int>[];
        var age = 0;
        session.start((image) async {
          ids.add(image.sourceFrameId);
          age = DateTime.now().difference(image.capturedAt).inMicroseconds;
        });
        await session.finished.timeout(const Duration(seconds: 3));
        expect(ids, [1, 3]);
        expect(age, greaterThanOrEqualTo(80000));
        session.dispose();
      },
    );
  }
}
