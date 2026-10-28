import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bagdar/core/performance/perception_performance.dart';
import 'package:bagdar/services/ncnn_depth_provider.dart';
import 'package:bagdar/services/device_capability.dart';

/// Real phone NCNN worker probe with generated YUV, no camera/SOS permissions.
/// Measures worker/UI only; it does not measure real capture or hazard accuracy.
class _GeneratedImage implements CameraImage {
  @override
  int get width => 256;
  @override
  int get height => 256;
  @override
  final List<Plane> planes = [
    _GeneratedPlane(
      Uint8List.fromList([
        for (var y = 0; y < 256; y++)
          for (var x = 0; x < 256; x++) 32 + ((x * 13 + y * 7) % 192),
      ]),
      256,
    ),
    _GeneratedPlane(Uint8List(128 * 128)..fillRange(0, 128 * 128, 128), 128),
    _GeneratedPlane(Uint8List(128 * 128)..fillRange(0, 128 * 128, 128), 128),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GeneratedPlane implements Plane {
  @override
  final Uint8List bytes;
  @override
  final int bytesPerRow;
  _GeneratedPlane(this.bytes, this.bytesPerRow);
  @override
  int? get bytesPerPixel => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('real Android NCNN worker profile with generated YUV', (
    tester,
  ) async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'This probe requires a physical Android phone',
    );
    final rawDevice = await const MethodChannel(
      'bagdar/device_info',
    ).invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
    final device = DeviceInfo(
      manufacturer: rawDevice?['manufacturer'] as String? ?? '',
      model: rawDevice?['model'] as String? ?? '',
      device: rawDevice?['device'] as String? ?? '',
      brand: rawDevice?['brand'] as String? ?? '',
      hardware: rawDevice?['hardware'] as String? ?? '',
      sdkInt: (rawDevice?['sdkInt'] as num?)?.toInt() ?? 0,
    );
    expect(
      device.model,
      isNotEmpty,
      reason: 'Named physical device is required',
    );
    expect(
      device.isEmulator,
      isFalse,
      reason: 'Emulator is not phone performance evidence',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
    final performance = PerceptionPerformance();
    void timings(List<FrameTiming> frames) {
      for (final frame in frames) {
        performance.record(
          PerceptionStage.uiBuild,
          frame.buildDuration.inMicroseconds,
        );
        performance.record(
          PerceptionStage.uiRaster,
          frame.rasterDuration.inMicroseconds,
        );
      }
    }

    binding.addTimingsCallback(timings);
    final probe = EventLoopLagProbe(
      (us) => performance.record(PerceptionStage.eventLoopLag, us),
    );
    final image = _GeneratedImage();
    try {
      await tester.runAsync(() async {
        final provider = await NcnnDepthProvider.tryCreate();
        expect(provider, isNotNull);
        final worker = provider!;
        final load = Stopwatch()..start();
        var accepted = 0;
        var rejected = 0;
        const threads = int.fromEnvironment(
          'BAGDAR_PROFILE_THREADS',
          defaultValue: 2,
        );
        try {
          expect(
            await worker.init(threads: threads),
            isTrue,
            reason: 'Real NCNN initialization required',
          );
          final loadMs = load.elapsedMicroseconds / 1000;
          // Warmup is paid but excluded from the measured sample window.
          await worker.analyzeDetailed(image);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          performance.takeWindow();
          probe.start();
          for (var i = 0; i < 20; i++) {
            final total = Stopwatch()..start();
            final result = await worker.analyzeDetailed(
              image,
              sourceTimestampUs: DateTime.now().microsecondsSinceEpoch,
            );
            performance.record(
              PerceptionStage.depthProviderRoundTrip,
              total.elapsedMicroseconds,
            );
            if (worker.lastAnalyzeMs > 0) {
              performance.record(
                PerceptionStage.depthWorkerProcessing,
                (worker.lastAnalyzeMs * 1000).round(),
              );
            }
            if (result.frame == null) {
              rejected++;
            } else {
              accepted++;
            }
            if (!worker.isReady) break;
          }
          binding.reportData ??= {};
          binding.reportData!['ncnnWorkerProfile'] = {
            'inputKind': 'generated_yuv_worker_probe',
            'device': {
              'manufacturer': device.manufacturer,
              'model': device.model,
              'hardware': device.hardware,
              'androidSdk': device.sdkInt,
            },
            'captureToCommandMeasured': false,
            'fieldAccuracyMeasured': false,
            'depthTier': worker.tier.name,
            'threads': threads,
            'loadMs': loadMs,
            'warmupExcluded': true,
            'acceptedMaps': accepted,
            'unavailableMaps': rejected,
            'performance': performance.takeWindow(),
          };
          expect(
            worker.lastInferenceMs,
            greaterThan(0),
            reason: 'Probe must execute real native inference',
          );
          expect(
            accepted,
            greaterThan(0),
            reason:
                'Native call timing alone does not prove valid model output',
          );
        } finally {
          probe.stop();
          worker.dispose();
          await worker.shutdown();
        }
      });
    } finally {
      probe.stop();
      binding.removeTimingsCallback(timings);
    }
  });
}
