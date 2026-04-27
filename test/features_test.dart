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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingEarconService extends EarconService {
  int calls = 0;
  final List<Earcon> played = [];
  final List<double> pans = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> play(Earcon earcon, {double pan = 0.0}) async {
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
  }) async {
    analyzeCalls++;
    return const [];
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

  test('ProximityBeaconService schedules proximity earcons at near range', () async {
    final earcon = _RecordingEarconService();
    final beacon = ProximityBeaconService(earcon: earcon);
    addTearDown(beacon.dispose);

    beacon.update(kBeaconNearDistM, 0.25);
    await Future.delayed(const Duration(milliseconds: 180));

    expect(earcon.calls, greaterThan(0));
    expect(earcon.played.last, Earcon.proximity);
    expect(earcon.pans.last, closeTo(0.25, 0.001));
  });

  test('HardwareDepthProvider falls back to NCNN on repeated low-confidence depth', () async {
    final depthMap = Float32List(GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize)
      ..fillRange(0, GroundPlaneAnalyzer.kMapSize * GroundPlaneAnalyzer.kMapSize, 0.0);
    final bridge = _FakeHardwareDepthBridge(supported: true, depthMap: depthMap);
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
    expect(provider.lastConfidenceScore, lessThan(kHardwareDepthMinConfidence));
    expect(fallback.analyzeCalls, greaterThan(0));
    expect(provider.tier, DepthTier.ncnnCpu);

  });
}
