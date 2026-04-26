import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/depth_provider.dart';
import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/hardware_depth_bridge.dart';
import 'package:bagdar/utils/depth_hazard.dart';

class _StubFallback implements DepthProvider {
  bool disposed = false;
  bool _ready = true;

  @override
  DepthTier get tier => DepthTier.midasCpu;
  @override
  bool get isReady => _ready;
  @override
  bool get nativeBridgeEnabled => false;
  @override
  bool get nativeBridgeAvailable => false;
  @override
  bool get lowConfidenceFallbackActive => false;
  @override
  double get lastConfidenceScore => 0;
  @override
  double get lastPreprocessMs => 0;
  @override
  double get lastInferenceMs => 0;
  @override
  double get lastAnalyzeMs => 0;
  @override
  bool get lastUsedNativeBridge => false;
  @override
  Future<bool> init({int threads = 2}) async => true;
  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) async => const [];
  @override
  void setNativeBridgeEnabled(bool enabled) {}
  @override
  void dispose() {
    disposed = true;
    _ready = false;
  }
}

class _StubBridge extends HardwareDepthBridge {
  @override
  Future<bool> isSupported() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HardwareDepthProvider B-3 — aggressive fallback close', () {
    test(
      'high-confidence streak >= 30s disposes the MiDaS fallback',
      () {
        final stub = _StubFallback();
        final hp = HardwareDepthProvider(
          useNnApiFallback: false,
          bridge: _StubBridge(),
          fallbackProvider: stub,
        );

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        
        hp.debugUpdateConfidence(0.85, now: t0);
        expect(hp.debugFallbackDisposedForBattery, isFalse);
        expect(hp.debugHighConfStreakStartedAt, isNotNull);
        expect(stub.disposed, isFalse);

        
        hp.debugUpdateConfidence(
          0.85,
          now: t0.add(const Duration(seconds: 25)),
        );
        expect(hp.debugFallbackDisposedForBattery, isFalse);
        expect(stub.disposed, isFalse);

        
        hp.debugUpdateConfidence(
          0.85,
          now: t0.add(const Duration(seconds: 31)),
        );
        expect(hp.debugFallbackDisposedForBattery, isTrue);
        expect(stub.disposed, isTrue);
        expect(hp.debugFallback, isNull);
      },
    );

    test('confidence drop resets the streak', () {
      final stub = _StubFallback();
      final hp = HardwareDepthProvider(
        useNnApiFallback: false,
        bridge: _StubBridge(),
        fallbackProvider: stub,
      );

      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      hp.debugUpdateConfidence(0.85, now: t0);
      expect(hp.debugHighConfStreakStartedAt, isNotNull);

      
      hp.debugUpdateConfidence(0.5, now: t0.add(const Duration(seconds: 5)));
      expect(hp.debugHighConfStreakStartedAt, isNull);

      
      hp.debugUpdateConfidence(0.85, now: t0.add(const Duration(seconds: 6)));
      expect(hp.debugHighConfStreakStartedAt, isNotNull);
      expect(hp.debugFallbackDisposedForBattery, isFalse);
    });

    test(
      'low confidence (< kHardwareDepthMinConfidence) triggers fallback reinit',
      () async {
        final stub = _StubFallback();
        final hp = HardwareDepthProvider(
          useNnApiFallback: false,
          bridge: _StubBridge(),
          fallbackProvider: stub,
        );

        final t0 = DateTime(2025, 1, 1, 12, 0, 0);
        
        hp.debugUpdateConfidence(0.85, now: t0);
        hp.debugUpdateConfidence(
          0.85,
          now: t0.add(const Duration(seconds: 31)),
        );
        expect(hp.debugFallbackDisposedForBattery, isTrue);
        expect(hp.debugFallback, isNull);

        
        
        
        
        hp.debugUpdateConfidence(
          0.10,
          now: t0.add(const Duration(seconds: 32)),
        );

        
        await Future<void>.delayed(const Duration(milliseconds: 500));
        
        
        expect(
          hp.debugFallbackDisposedForBattery,
          isTrue,
          reason: 'failed reinit must keep the disposed flag for retry',
        );
      },
    );

    test('high confidence below threshold (0.7) does NOT start streak', () {
      final stub = _StubFallback();
      final hp = HardwareDepthProvider(
        useNnApiFallback: false,
        bridge: _StubBridge(),
        fallbackProvider: stub,
      );

      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      
      hp.debugUpdateConfidence(0.65, now: t0);
      expect(hp.debugHighConfStreakStartedAt, isNull);
      hp.debugUpdateConfidence(
        0.65,
        now: t0.add(const Duration(seconds: 60)),
      );
      expect(hp.debugFallbackDisposedForBattery, isFalse);
      expect(stub.disposed, isFalse);
    });
  });
}
