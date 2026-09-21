import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/depth_provider.dart';
import 'package:bagdar/services/earcon_service.dart';
import 'package:bagdar/services/hardware_depth_bridge.dart';
import 'package:bagdar/services/proximity_beacon_service.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';
import 'package:bagdar/utils/fusion_engine.dart';

class _FakeCameraImage implements CameraImage {
  @override
  List<Plane> get planes => [_FakePlane()];

  @override
  int get width => 256;

  @override
  int get height => 256;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlane implements Plane {
  @override
  Uint8List get bytes => Uint8List(256 * 256);

  @override
  int get bytesPerRow => 256;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingEarconService extends EarconService {
  int calls = 0;
  final List<Earcon> played = [];
  final List<double> pans = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> play(Earcon earcon, {double pan = 0.0, double? volume}) async {
    calls++;
    played.add(earcon);
    pans.add(pan);
  }
}

class _FakeHardwareDepthBridge extends HardwareDepthBridge {
  _FakeHardwareDepthBridge({required this.supported, required this.depthMap});

  final bool supported;
  final Float32List depthMap;
  bool started = false;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> start({int mapSize = 256}) async {
    started = supported;
    return supported;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Float32List? get latestDepthMap => depthMap;
}

class _RecordingFallbackProvider implements DepthProvider {
  _RecordingFallbackProvider(this._tier);

  final DepthTier _tier;
  bool _ready = false;
  int analyzeCalls = 0;

  @override
  DepthTier get tier => _tier;

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
  bool get lastPlaneFitOk => true;

  @override
  Future<bool> init({int threads = 2}) async {
    _ready = true;
    return true;
  }

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async {
    analyzeCalls++;
    return const [];
  }

  @override
  Future<DepthAnalysisResult> analyzeDetailed(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
    int sourceTimestampUs = 0,
    int rotationDegrees = 0,
    bool mirrored = false,
  }) async {
    analyzeCalls++;
    return wrapHazardsAsLegacy(const <DepthHazard>[]);
  }

  @override
  void setNativeBridgeEnabled(bool enabled) {}

  @override
  void dispose() {
    _ready = false;
  }
}

void main() {
  test('FusionEngine EMA keeps warnings alive after one noisy frame', () {
    final engine = FusionEngine();
    final t0 = DateTime(2025, 1, 1, 12, 0, 0);
    const hazard0 = DepthHazard(
      midasScore: 0.8,
      type: DepthHazardType.stepDown,
      zone: HazardZone.center,
      coverage: 0.5,
    );
    const hazard1 = DepthHazard(
      midasScore: 0.0,
      type: DepthHazardType.stepDown,
      zone: HazardZone.center,
      coverage: 0.5,
    );

    final first = engine.evaluate(hazard: hazard0, now: t0);
    expect(first, isNotNull);
    expect(first!.level, AlertLevel.warning);

    final second = engine.evaluate(
      hazard: hazard1,
      now: t0.add(const Duration(seconds: 4)),
    );
    expect(second, isNotNull);
    expect(second!.fusionScore, greaterThan(kFusionWarningScore));
    expect(second.level, AlertLevel.warning);
  });

  test(
    'ProximityBeaconService schedules proximity earcons at near range',
    () async {
      final earcon = _RecordingEarconService();
      final beacon = ProximityBeaconService(earcon: earcon);
      addTearDown(beacon.dispose);

      beacon.update(kBeaconNearDistM, 0.25);
      await Future.delayed(const Duration(milliseconds: 180));

      expect(earcon.calls, greaterThan(0));
      expect(earcon.played.last, Earcon.proximity);
      expect(earcon.pans.last, closeTo(0.25, 0.001));
    },
  );

  group('ProximityBeaconService weather-degraded haptic boost (M10)', () {
    test('clear weather returns base pattern unchanged', () {
      final (pattern, intensities) = ProximityBeaconService.resolveHapticPulse(
        false,
      );
      expect(pattern, equals([0, 25]));
      expect(intensities, equals([0, 140]));
    });

    test('degraded weather scales the active pulse +30 % '
        '(both duration and amplitude)', () {
      final (pattern, intensities) = ProximityBeaconService.resolveHapticPulse(
        true,
      );

      expect(pattern[0], 0);
      expect(pattern[1], (25 * 1.3).round());

      expect(intensities[0], 0);
      expect(intensities[1], (140 * 1.3).round());
    });

    test('degraded amplitude never exceeds the 255 device ceiling', () {
      final (_, intensities) = ProximityBeaconService.resolveHapticPulse(true);
      for (final v in intensities) {
        expect(v, lessThanOrEqualTo(255));
      }
    });

    test('setWeatherDegraded flips the boost flag persistently', () {
      final earcon = _RecordingEarconService();
      final beacon = ProximityBeaconService(earcon: earcon);
      addTearDown(beacon.dispose);

      expect(beacon.isWeatherDegraded, isFalse);
      beacon.setWeatherDegraded(true);
      expect(beacon.isWeatherDegraded, isTrue);
      beacon.setWeatherDegraded(false);
      expect(beacon.isWeatherDegraded, isFalse);
    });

    test('update() carries the latest weatherDegraded flag through', () {
      final earcon = _RecordingEarconService();
      final beacon = ProximityBeaconService(earcon: earcon);
      addTearDown(beacon.dispose);

      beacon.update(kBeaconNearDistM, 0.0, weatherDegraded: true);
      expect(beacon.isWeatherDegraded, isTrue);

      beacon.update(kBeaconNearDistM, 0.0, weatherDegraded: false);
      expect(beacon.isWeatherDegraded, isFalse);

      beacon.setWeatherDegraded(true);
      beacon.update(kBeaconNearDistM, 0.0);
      expect(beacon.isWeatherDegraded, isTrue);
    });
  });

  test(
    'HardwareDepthProvider falls back to NCNN on repeated low-confidence depth',
    () async {
      final depthMap =
          Float32List(
            GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize,
          )..fillRange(
            0,
            GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize,
            0.0,
          );
      final bridge = _FakeHardwareDepthBridge(
        supported: true,
        depthMap: depthMap,
      );
      final fallback = _RecordingFallbackProvider(DepthTier.ncnnCpu);
      final provider = HardwareDepthProvider(
        bridge: bridge,
        fallbackProvider: fallback,
      );
      addTearDown(provider.dispose);

      final ok = await provider.init();
      expect(ok, isTrue);
      expect(provider.tier, DepthTier.hardware);

      for (var i = 0; i < kHardwareDepthLowConfFrames; i++) {
        await provider.analyze(_FakeCameraImage());
      }

      expect(provider.lowConfidenceFallbackActive, isTrue);
      expect(
        provider.lastConfidenceScore,
        lessThan(kHardwareDepthMinConfidence),
      );
      expect(fallback.analyzeCalls, greaterThan(0));
      expect(provider.tier, DepthTier.ncnnCpu);
    },
  );
}
