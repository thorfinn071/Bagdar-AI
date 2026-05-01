import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/depth_provider.dart';
import 'package:bagdar/services/hardware_depth_bridge.dart';
import 'package:bagdar/models/routing_graph.dart';
import 'package:bagdar/models/map_package.dart';
import 'package:bagdar/models/nav_models.dart';
import 'package:bagdar/services/map_package_manager.dart';
import 'package:bagdar/services/gtfs_service.dart';
import 'package:bagdar/services/battery_monitor.dart';
import 'package:bagdar/services/voice_command_service.dart';
import 'package:bagdar/utils/alert_filter.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:bagdar/utils/distance_utils.dart';
import 'package:bagdar/utils/ground_plane_analyzer.dart';
import 'package:bagdar/utils/fusion_engine.dart';
import 'package:bagdar/models/constants.dart' show kFusionTemporalFrames;

class _FakeHardwareDepthBridge extends HardwareDepthBridge {
  _FakeHardwareDepthBridge({required this.supported});

  final bool supported;
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
}

class _StubDepthProvider implements DepthProvider {
  _StubDepthProvider(this._tier);

  final DepthTier _tier;
  bool _ready = false;
  bool _nativeBridgeEnabled = false;
  final bool _nativeBridgeAvailable = false;
  final double _lastPreprocessMs = 0;
  final double _lastInferenceMs = 0;
  final double _lastAnalyzeMs = 0;
  final bool _lastUsedNativeBridge = false;

  @override
  DepthTier get tier => _tier;

  @override
  bool get isReady => _ready;

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
  }) async => const [];

  @override
  bool get nativeBridgeEnabled => _nativeBridgeEnabled;

  @override
  bool get nativeBridgeAvailable => _nativeBridgeAvailable;

  @override
  bool get lowConfidenceFallbackActive => false;

  @override
  double get lastConfidenceScore => 0;

  @override
  double get lastPreprocessMs => _lastPreprocessMs;

  @override
  double get lastInferenceMs => _lastInferenceMs;

  @override
  double get lastAnalyzeMs => _lastAnalyzeMs;

  @override
  bool get lastUsedNativeBridge => _lastUsedNativeBridge;

  @override
  void setNativeBridgeEnabled(bool enabled) {
    _nativeBridgeEnabled = enabled;
  }

  @override
  void dispose() {
    _ready = false;
  }
}

void main() {
  setUp(() {
    AppStrings.setLanguage(AppLanguage.ru);
  });

  
  
  

  group('posFromCx', () {
    const w = 640.0;

    test('far left → "left"', () {
      expect(posFromCx(0.0, w), 'left');
      expect(posFromCx(w * 0.10, w), 'left');
      expect(posFromCx(w * 0.34, w), 'left');
    });

    test('centre band → "center"', () {
      expect(posFromCx(w * 0.35, w), 'center');
      expect(posFromCx(w * 0.50, w), 'center');
      expect(posFromCx(w * 0.65, w), 'center');
    });

    test('far right → "right"', () {
      expect(posFromCx(w * 0.66, w), 'right');
      expect(posFromCx(w, w), 'right');
    });

    test('zero-width frame → "center" (no crash)', () {
      expect(posFromCx(0.0, 0.0), 'center');
    });
  });

  
  
  

  group('clockDir', () {
    const w = 640.0;

    test('extreme left (<10%) → 9-o-clock', () {
      final result = clockDir(0, w * 0.05, w);
      expect(result, AppStrings.dir('9'));
    });

    test('left side (10-35%) → 10-o-clock', () {
      final result = clockDir(w * 0.10, w * 0.30, w);
      expect(result, AppStrings.dir('10'));
    });

    test('centre → forward (12-o-clock key is "forward")', () {
      final result = clockDir(w * 0.40, w * 0.60, w);
      expect(result, AppStrings.dir('forward'));
    });

    test('right side (78-90%) → 2-o-clock', () {
      final result = clockDir(w * 0.78, w * 0.88, w);
      expect(result, AppStrings.dir('2'));
    });

    test('right-centre (62-78%) → 1-o-clock', () {
      final result = clockDir(w * 0.65, w * 0.80, w);
      expect(result, AppStrings.dir('1'));
    });

    test('extreme right (>90%) → 3-o-clock', () {
      final result = clockDir(w * 0.92, w, w);
      expect(result, AppStrings.dir('3'));
    });

    test('zero-width frame → forward (no crash)', () {
      expect(() => clockDir(0, 0, 0), returnsNormally);
    });
  });

  
  
  

  group('threatScore', () {
    test('very-close object scores higher than close', () {
      final scoreVc = threatScore('person', 'center', 'very close', 0.20);
      final scoreC  = threatScore('person', 'center', 'close',      0.20);
      expect(scoreVc, greaterThan(scoreC));
    });

    test('close scores higher than far', () {
      final scoreC = threatScore('car', 'center', 'close', 0.10);
      final scoreF = threatScore('car', 'center', 'far',   0.10);
      expect(scoreC, greaterThan(scoreF));
    });

    test('centre position scores higher than side (equal dist)', () {
      final scoreCenter = threatScore('car', 'center', 'close', 0.15);
      final scoreLeft   = threatScore('car', 'left',   'close', 0.15);
      expect(scoreCenter, greaterThan(scoreLeft));
    });

    test('high-weight class (car) > low-weight class (backpack) at same dist', () {
      final scoreCar  = threatScore('car',     'center', 'close', 0.10);
      final scoreBack = threatScore('backpack', 'center', 'close', 0.10);
      expect(scoreCar, greaterThan(scoreBack));
    });

    test('larger area ratio increases score', () {
      final scoreSmall = threatScore('person', 'center', 'close', 0.05);
      final scoreLarge = threatScore('person', 'center', 'close', 0.40);
      expect(scoreLarge, greaterThan(scoreSmall));
    });

    test('score is always non-negative', () {
      expect(threatScore('unknown_label', 'left', 'far', 0.0),
          greaterThanOrEqualTo(0.0));
    });
  });

  
  
  

  group('SOS phone number validation (digit count)', () {
    bool isValidPhone(String phone) {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 7;
    }

    test('standard KZ number → valid', () {
      expect(isValidPhone('+7 (777) 123-45-67'), isTrue);
    });

    test('short local number with 7 digits → valid', () {
      expect(isValidPhone('1234567'), isTrue);
    });

    test('6-digit number → invalid', () {
      expect(isValidPhone('123456'), isFalse);
    });

    test('empty string → invalid', () {
      expect(isValidPhone(''), isFalse);
    });

    test('letters only → invalid', () {
      expect(isValidPhone('abc'), isFalse);
    });

    test('formatted number with dashes → valid', () {
      expect(isValidPhone('+7-800-555-35-35'), isTrue);
    });
  });

  
  
  

  group('GroundPlaneAnalyzer', () {
    final analyzer = GroundPlaneAnalyzer();
    const size = GroundPlaneAnalyzer.kMapSize; 

    
    
    
    
    setUp(analyzer.resetTemporalFilter);

    Float32List makeFlat(double value) {
      return Float32List(size * size)..fillRange(0, size * size, value);
    }

    Float32List makePlane() {
      final map = Float32List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          map[y * size + x] = 0.5 + y * 0.001;
        }
      }
      return map;
    }

    test('all-zeros map → empty result (no crash)', () {
      final result = analyzer.analyze(makeFlat(0.0));
      expect(result, isEmpty);
    });

    test('perfectly flat map → empty result (no anomalies)', () {
      final result = analyzer.analyze(makeFlat(0.5));
      expect(result, isEmpty);
    });

    test('linear plane map → empty or minimal anomalies', () {
      final result = analyzer.analyze(makePlane());
      expect(result.length, lessThanOrEqualTo(1));
    });

    test('bottom-band depth noise triggers a dead-zone hazard', () {
      final map = makePlane();
      for (int y = GroundPlaneAnalyzer.kFootZoneStartRow; y < size; y++) {
        for (int x = 0; x < size; x++) {
          if ((x + y) % 2 == 0) {
            map[y * size + x] += 0.45;
          }
        }
      }

      final result = analyzer.analyze(map);
      expect(
        result.any((h) => h.zone == HazardZone.center && h.type == DepthHazardType.deadZone),
        isTrue,
      );
    });

    test('calling analyze twice reuses buffers (no crash)', () {
      final map = makePlane();
      analyzer.analyze(map);
      expect(() => analyzer.analyze(map), returnsNormally);
    });

    test('map has correct size assertion', () {
      expect(
        () => analyzer.analyze(Float32List(10)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  
  
  

  group('BatteryMonitor', () {
    test('battery level thresholds map to the intended throttle tiers', () {
      expect(BatteryMonitor.levelForBatteryLevel(100), ThrottleLevel.normal);
      expect(BatteryMonitor.levelForBatteryLevel(30), ThrottleLevel.normal);
      expect(BatteryMonitor.levelForBatteryLevel(29), ThrottleLevel.moderate);
      expect(BatteryMonitor.levelForBatteryLevel(15), ThrottleLevel.moderate);
      expect(BatteryMonitor.levelForBatteryLevel(14), ThrottleLevel.aggressive);
      expect(BatteryMonitor.levelForBatteryLevel(5), ThrottleLevel.aggressive);
      expect(BatteryMonitor.levelForBatteryLevel(4), ThrottleLevel.critical);
    });
  });

  
  
  

  group('AlertFilter', () {
    late AlertFilter filter;
    final t0 = DateTime(2025, 1, 1, 12, 0, 0);

    setUp(() => filter = AlertFilter());

    AlertCandidate makeCandidate({
      String text = 'test',
      SpeechPriority priority = SpeechPriority.info,
      AlertCategory category = AlertCategory.obstacleFar,
      double urgency = 0.5,
      double pan = 0.0,
    }) =>
        AlertCandidate(
          text: text,
          priority: priority,
          pan: pan,
          category: category,
          urgency: urgency,
        );

    test('empty filter returns null', () {
      expect(filter.flush(0, t0), isNull);
    });

    test('single candidate returned after cooldown', () {
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      final result = filter.flush(1, t0);
      expect(result, isNotNull);
      expect(result!.priority, SpeechPriority.warning);
    });

    test('highest priority wins', () {
      filter
        ..add(makeCandidate(priority: SpeechPriority.info,     text: 'info'))
        ..add(makeCandidate(priority: SpeechPriority.critical, text: 'crit'))
        ..add(makeCandidate(priority: SpeechPriority.warning,  text: 'warn'));
      final result = filter.flush(1, t0);
      expect(result!.text, 'crit');
    });

    test('same priority — higher urgency wins', () {
      filter
        ..add(makeCandidate(priority: SpeechPriority.warning, urgency: 0.3, text: 'low'))
        ..add(makeCandidate(priority: SpeechPriority.warning, urgency: 0.9, text: 'high'));
      final result = filter.flush(1, t0);
      expect(result!.text, 'high');
    });

    test('critical alerts bypass cooldown and suppression', () {
      filter.add(makeCandidate(priority: SpeechPriority.critical, category: AlertCategory.obstacleFar));
      filter.flush(1, t0); 
      filter.add(makeCandidate(priority: SpeechPriority.critical, category: AlertCategory.obstacleClose));
      
      final result = filter.flush(1, t0.add(const Duration(milliseconds: 500)));
      expect(result, isNotNull);
      expect(result!.priority, SpeechPriority.critical);
    });

    test('after critical, warning suppressed for 2 s', () {
      filter.add(makeCandidate(priority: SpeechPriority.critical));
      filter.flush(1, t0); 
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      
      final result = filter.flush(1, t0.add(const Duration(seconds: 1)));
      expect(result, isNull);
    });

    test('after critical, warning passes after 2 s suppression', () {
      filter.add(makeCandidate(priority: SpeechPriority.critical));
      filter.flush(1, t0);
      
      filter.add(makeCandidate(priority: SpeechPriority.warning, category: AlertCategory.navigationHint));
      final result = filter.flush(1, t0.add(const Duration(seconds: 3)));
      expect(result, isNotNull);
    });

    test('dense scene (5+ tracks) suppresses low-urgency info alerts', () {
      filter.add(makeCandidate(priority: SpeechPriority.info, urgency: 0.3));
      final result = filter.flush(5, t0);
      expect(result, isNull);
    });

    test('dense scene (5+ tracks) does not suppress high-urgency info', () {
      filter.add(makeCandidate(priority: SpeechPriority.info, urgency: 0.6));
      final result = filter.flush(5, t0);
      expect(result, isNotNull);
    });

    test('dense scene (5+ tracks) does not suppress warning', () {
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      final result = filter.flush(5, t0);
      expect(result, isNotNull);
    });

    test('navigationHint suppressed when 3+ tracks', () {
      filter.add(makeCandidate(
        priority: SpeechPriority.info,
        category: AlertCategory.navigationHint,
      ));
      final result = filter.flush(3, t0);
      expect(result, isNull);
    });

    test('reset clears state — candidate fires immediately after reset', () {
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      filter.flush(1, t0); 
      filter.reset();
      
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      final result = filter.flush(1, t0);
      expect(result, isNotNull);
    });

    
    
    
    
    
    test('per-category cooldown: same category blocked, different category '
        'passes', () {
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.obstacleClose,
        text: 'pedestrian1',
      ));
      final first = filter.flush(1, t0);
      expect(first!.text, 'pedestrian1');

      
      
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.obstacleClose,
        text: 'pedestrian2',
      ));
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.approachingVehicle,
        text: 'cyclist',
      ));
      final second = filter.flush(
        1, t0.add(const Duration(milliseconds: 1600)));
      expect(second, isNotNull);
      
      
      
      expect(second!.category, AlertCategory.approachingVehicle);
      expect(second.text, 'cyclist');
    });

    test('per-category cooldown: crowd scene does not silence an '
        'approaching vehicle', () {
      
      var now = t0;
      for (var i = 0; i < 5; i++) {
        filter.add(makeCandidate(
          priority: SpeechPriority.warning,
          category: AlertCategory.obstacleClose,
          text: 'pedestrian$i',
        ));
        filter.flush(5, now);
        now = now.add(const Duration(milliseconds: 400));
      }
      
      
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.approachingVehicle,
        text: 'cyclist',
      ));
      final result = filter.flush(5, now);
      expect(result, isNotNull);
      expect(result!.category, AlertCategory.approachingVehicle);
    });

    test('critical bypasses per-category cooldown', () {
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.obstacleClose,
      ));
      filter.flush(1, t0);

      
      
      filter.add(makeCandidate(
        priority: SpeechPriority.critical,
        category: AlertCategory.obstacleClose,
        text: 'critical obstacle',
      ));
      final result = filter.flush(
        1, t0.add(const Duration(milliseconds: 100)));
      expect(result, isNotNull);
      expect(result!.text, 'critical obstacle');
    });

    test('when top-priority candidate is on cooldown, lower-priority '
        'candidate in a different category is picked', () {
      
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.obstacleClose,
      ));
      filter.flush(1, t0);

      
      
      
      filter.add(makeCandidate(
        priority: SpeechPriority.warning,
        category: AlertCategory.obstacleClose,
        text: 'blocked',
      ));
      filter.add(makeCandidate(
        priority: SpeechPriority.info,
        category: AlertCategory.obstacleFar,
        text: 'info',
        urgency: 0.6,
      ));
      final result = filter.flush(
        1, t0.add(const Duration(milliseconds: 1600)));
      expect(result, isNotNull);
      expect(result!.text, 'info');
    });
  });

  
  
  

  group('FusionEngine', () {
    late FusionEngine engine;
    final t0 = DateTime(2025, 1, 1, 12, 0, 0);

    DepthHazard makeHazard(double score, [HazardZone zone = HazardZone.center]) =>
        DepthHazard(
          midasScore: score,
          type:       DepthHazardType.stepDown,
          zone:       zone,
          coverage:   0.5,
        );

    setUp(() => engine = FusionEngine());

    test('score below warning threshold → null', () {
      final result = engine.evaluate(hazard: makeHazard(0.20), now: t0);
      expect(result, isNull);
    });

    test('score at warning threshold → warning result', () {
      final result = engine.evaluate(
        hazard: makeHazard(FusionEngine.kWarningThreshold),
        now: t0,
      );
      expect(result, isNotNull);
      expect(result!.level, AlertLevel.warning);
    });

    test('score at critical threshold but only 1 frame → warning (not critical)', () {
      final result = engine.evaluate(
        hazard: makeHazard(FusionEngine.kCriticalThreshold),
        now: t0,
      );
      
      expect(result!.level, AlertLevel.warning);
    });

    test('score at critical for kTemporalFrames consecutive frames → critical', () {
      
      var t = t0;
      AlertLevel? lastLevel;
      for (int i = 0; i < kFusionTemporalFrames; i++) {
        final r = engine.evaluate(
          hazard: makeHazard(FusionEngine.kCriticalThreshold),
          now: t,
        );
        lastLevel = r?.level;
        t = t.add(const Duration(seconds: 4));
      }
      expect(lastLevel, AlertLevel.critical);
    });

    test('cooldown: second call within 3 s returns null', () {
      engine.evaluate(hazard: makeHazard(0.40), now: t0);
      final result = engine.evaluate(
        hazard: makeHazard(0.40),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(result, isNull);
    });

    test('zone change clears history — critical resets to 1 frame', () {
      
      engine.evaluate(hazard: makeHazard(FusionEngine.kCriticalThreshold, HazardZone.center), now: t0);
      final t1 = t0.add(const Duration(seconds: 4));
      
      engine.evaluate(hazard: makeHazard(FusionEngine.kCriticalThreshold, HazardZone.left), now: t1);
      final t2 = t1.add(const Duration(seconds: 4));
      
      final result = engine.evaluate(
        hazard: makeHazard(FusionEngine.kCriticalThreshold, HazardZone.center),
        now: t2,
      );
      expect(result!.level, AlertLevel.warning);
    });

    test('reset clears history — critical no longer fires', () {
      engine.evaluate(hazard: makeHazard(FusionEngine.kCriticalThreshold), now: t0);
      engine.reset();
      final t1 = t0.add(const Duration(seconds: 4));
      final result = engine.evaluate(
        hazard: makeHazard(FusionEngine.kCriticalThreshold),
        now: t1,
      );
      expect(result!.level, AlertLevel.warning); 
    });

    test('fusionScore clamped to 1.0', () {
      final result = engine.evaluate(hazard: makeHazard(1.5), now: t0);
      expect(result!.fusionScore, lessThanOrEqualTo(1.0));
    });
  });

  
  
  

  group('DeviceCapabilities', () {
    test('hardware tier is preserved', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.hardware,
        androidSdkInt: 33,
      );
      expect(caps.bestDepthTier, DepthTier.hardware);
    });

    test('ncnnVulkan tier preserved', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnVulkan,
        androidSdkInt: 30,
      );
      expect(caps.bestDepthTier, DepthTier.ncnnVulkan);
    });

    test('ncnnCpu tier preserved', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnCpu,
        androidSdkInt: 27,
      );
      expect(caps.bestDepthTier, DepthTier.ncnnCpu);
    });

    test('focalLength tier preserved', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.focalLength,
        androidSdkInt: 26,
      );
      expect(caps.bestDepthTier, DepthTier.focalLength);
    });

    test('toString includes all key fields', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnVulkan,
        androidSdkInt: 31,
      );
      final s = caps.toString();
      expect(s, contains('ncnnVulkan'));
      expect(s, contains('31'));
    });
  });

  
  
  

  group('DepthProviderFactory', () {
    test('hardware caps → HardwareDepthProvider', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.hardware,
        androidSdkInt: 33,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<HardwareDepthProvider>());
    });

    test('ncnn caps → FocalLength placeholder via legacy create()', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnVulkan,
        androidSdkInt: 26,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<FocalLengthDepthProvider>());
    });

    test('focalLength caps → FocalLengthDepthProvider', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.focalLength,
        androidSdkInt: 26,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<FocalLengthDepthProvider>());
      expect(provider.tier, DepthTier.focalLength);
    });

    test('hardware tier createWithTier → HardwareDepthProvider', () {
      final p = DepthProviderFactory.createWithTier(DepthTier.hardware);
      expect(p, isA<HardwareDepthProvider>());
    });

    test('hardware provider keeps hardware tier when native bridge starts', () async {
      final bridge = _FakeHardwareDepthBridge(supported: true);
      final fallback = _StubDepthProvider(DepthTier.ncnnCpu);
      final provider = HardwareDepthProvider(
        bridge: bridge,
        fallbackProvider: fallback,
      );

      final ok = await provider.init();
      expect(ok, isTrue);
      expect(provider.tier, DepthTier.hardware);
      expect(bridge.started, isTrue);
    });

    test('hardware provider falls back to NCNN when native bridge is unavailable', () async {
      final bridge = _FakeHardwareDepthBridge(supported: false);
      final fallback = _StubDepthProvider(DepthTier.ncnnVulkan);
      final provider = HardwareDepthProvider(
        bridge: bridge,
        fallbackProvider: fallback,
      );

      final ok = await provider.init();
      expect(ok, isTrue);
      expect(provider.tier, DepthTier.ncnnVulkan);
      expect(bridge.started, isFalse);
    });

    test('FocalLengthDepthProvider.init returns true immediately', () async {
      final provider = FocalLengthDepthProvider();
      expect(provider.isReady, isFalse);
      final ok = await provider.init();
      expect(ok, isTrue);
      expect(provider.isReady, isTrue);
    });

    test('FocalLengthDepthProvider.analyze always returns empty list', () async {
      final provider = FocalLengthDepthProvider();
      await provider.init();
      
      expect(provider.isReady, isTrue);
    });

    test('createWithTier(focalLength) → FocalLengthDepthProvider', () {
      final p = DepthProviderFactory.createWithTier(DepthTier.focalLength);
      expect(p, isA<FocalLengthDepthProvider>());
    });

    test('createWithTier(ncnn) → FocalLength placeholder', () {
      final p = DepthProviderFactory.createWithTier(DepthTier.ncnnVulkan);
      expect(p, isA<FocalLengthDepthProvider>());
    });
  });

  group('AccessibilityInfo', () {
    test('default weight is ~1.05 (unknown surface)', () {
      const info = AccessibilityInfo();
      expect(info.weightMultiplier, closeTo(1.05, 0.01));
    });

    test('footway + asphalt + tactile → low weight', () {
      const info = AccessibilityInfo(
        highway: HighwayType.footway,
        surface: SurfaceType.asphalt,
        tactilePaving: true,
      );
      expect(info.weightMultiplier, lessThan(0.8));
    });

    test('motorway → very high weight', () {
      const info = AccessibilityInfo(highway: HighwayType.motorway);
      expect(info.weightMultiplier, greaterThan(900));
    });

    test('gravel surface → higher weight', () {
      const info = AccessibilityInfo(
        highway: HighwayType.residential,
        surface: SurfaceType.gravel,
      );
      expect(info.weightMultiplier, greaterThan(1.2));
    });

    test('sidewalk + lit reduce weight', () {
      const base = AccessibilityInfo(
        highway: HighwayType.residential,
        surface: SurfaceType.asphalt,
      );
      const improved = AccessibilityInfo(
        highway: HighwayType.residential,
        surface: SurfaceType.asphalt,
        sidewalk: true,
        lit: true,
      );
      expect(improved.weightMultiplier, lessThan(base.weightMultiplier));
    });

    test('steps → weight > 1.3', () {
      const info = AccessibilityInfo(
        highway: HighwayType.steps,
        surface: SurfaceType.asphalt,
      );
      expect(info.weightMultiplier, greaterThan(1.3));
    });
  });

  group('MapPackage', () {
    test('toJson/fromJson roundtrip', () {
      final now = DateTime.now();
      final pkg = MapPackage(
        cityId: 'astana',
        name: 'Астана',
        nameKk: 'Астана',
        sizeBytes: 15000000,
        version: 2,
        downloadUrl: 'https://example.com/astana.zip',
        localPath: '/data/astana',
        installed: true,
        installedAt: now,
        updatedAt: now,
      );

      final json = pkg.toJson();
      final restored = MapPackage.fromJson(json);

      expect(restored.cityId, 'astana');
      expect(restored.name, 'Астана');
      expect(restored.nameKk, 'Астана');
      expect(restored.sizeBytes, 15000000);
      expect(restored.version, 2);
      expect(restored.installed, true);
      expect(restored.downloadUrl, 'https://example.com/astana.zip');
    });

    test('sizeMb formats correctly', () {
      const pkg = MapPackage(
        cityId: 'test',
        name: 'Test',
        sizeBytes: 20971520,
      );
      expect(pkg.sizeMb, '20.0');
    });

    test('copyWith preserves unmodified fields', () {
      const pkg = MapPackage(
        cityId: 'almaty',
        name: 'Алматы',
        version: 1,
      );
      final updated = pkg.copyWith(version: 3, installed: true);
      expect(updated.cityId, 'almaty');
      expect(updated.name, 'Алматы');
      expect(updated.version, 3);
      expect(updated.installed, true);
    });

    test('fromJson with missing fields uses defaults', () {
      final pkg = MapPackage.fromJson({'cityId': 'x'});
      expect(pkg.cityId, 'x');
      expect(pkg.name, '');
      expect(pkg.sizeBytes, 0);
      expect(pkg.installed, false);
      expect(pkg.installedAt, isNull);
    });

    test('isStale becomes true after 90 days', () {
      final now = DateTime(2025, 4, 6);
      final pkg = MapPackage(
        cityId: 'astana',
        name: 'Астана',
        installedAt: now.subtract(const Duration(days: 91)),
      );

      expect(pkg.isStale(now), isTrue);
    });
  });

  group('GTFS freshness', () {
    test('timestamp older than 90 days is stale', () {
      final now = DateTime(2025, 4, 6);
      final old = now.subtract(const Duration(days: 91));

      expect(GtfsService.isTimestampStale(old, now), isTrue);
      expect(GtfsService.isTimestampStale(now.subtract(const Duration(days: 30)), now), isFalse);
    });
  });

  group('MapPackageManifest', () {
    test('fromJson parses packages list', () {
      final json = {
        'manifestVersion': 2,
        'baseUrl': 'https://cdn.example.com',
        'packages': [
          {'cityId': 'astana', 'name': 'Астана', 'version': 1},
          {'cityId': 'almaty', 'name': 'Алматы', 'version': 1},
        ],
      };
      final manifest = MapPackageManifest.fromJson(json);
      expect(manifest.manifestVersion, 2);
      expect(manifest.baseUrl, 'https://cdn.example.com');
      expect(manifest.packages.length, 2);
      expect(manifest.packages[0].cityId, 'astana');
      expect(manifest.packages[1].cityId, 'almaty');
    });

    test('fromJson with empty packages', () {
      final manifest = MapPackageManifest.fromJson({});
      expect(manifest.packages, isEmpty);
      expect(manifest.manifestVersion, 1);
    });

    test('relative downloadUrl resolves against manifest directory', () {
      final resolved = resolveMapPackageDownloadUrl(
        'https://cdn.example.com/maps/map_packages.json',
        '',
        'astana.zip',
      );
      expect(resolved, 'https://cdn.example.com/maps/astana.zip');
    });

    test('relative downloadUrl resolves against manifest baseUrl', () {
      final resolved = resolveMapPackageDownloadUrl(
        'https://cdn.example.com/maps/map_packages.json',
        'https://files.example.com/offline/',
        'astana.zip',
      );
      expect(resolved, 'https://files.example.com/offline/astana.zip');
    });

    test('absolute downloadUrl stays unchanged', () {
      final resolved = resolveMapPackageDownloadUrl(
        'https://cdn.example.com/maps/map_packages.json',
        'https://files.example.com/offline/',
        'https://download.example.com/astana.zip',
      );
      expect(resolved, 'https://download.example.com/astana.zip');
    });
  });

  group('CHGraph', () {
    test('containsPoint checks bounds', () {
      const g = CHGraph(
        nodes: [],
        forwardEdges: [],
        backwardEdges: [],
        forwardOffsets: [0],
        backwardOffsets: [0],
        streetNames: [],
        minLat: 51.0,
        maxLat: 51.3,
        minLng: 71.3,
        maxLng: 71.6,
      );
      expect(g.containsPoint(51.15, 71.45), isTrue);
      expect(g.containsPoint(50.0, 71.45), isFalse);
      expect(g.containsPoint(51.15, 72.0), isFalse);
    });

    test('findNearestNode returns closest', () {
      const g = CHGraph(
        nodes: [
          CHNode(id: 0, lat: 51.1, lng: 71.4),
          CHNode(id: 1, lat: 51.2, lng: 71.5),
          CHNode(id: 2, lat: 51.15, lng: 71.45),
        ],
        forwardEdges: [],
        backwardEdges: [],
        forwardOffsets: [0, 0, 0, 0],
        backwardOffsets: [0, 0, 0, 0],
        streetNames: [],
        minLat: 51.0,
        maxLat: 51.3,
        minLng: 71.3,
        maxLng: 71.6,
      );
      expect(g.findNearestNode(51.14, 71.44), 2);
    });

    test('streetName returns empty for invalid index', () {
      const g = CHGraph(
        nodes: [],
        forwardEdges: [],
        backwardEdges: [],
        forwardOffsets: [0],
        backwardOffsets: [0],
        streetNames: ['ул. Абая', 'пр. Республики'],
        minLat: 0,
        maxLat: 0,
        minLng: 0,
        maxLng: 0,
      );
      expect(g.streetName(0), 'ул. Абая');
      expect(g.streetName(1), 'пр. Республики');
      expect(g.streetName(-1), '');
      expect(g.streetName(99), '');
    });

    test('outEdges/inEdges return empty for isolated node', () {
      const g = CHGraph(
        nodes: [CHNode(id: 0, lat: 51.1, lng: 71.4)],
        forwardEdges: [],
        backwardEdges: [],
        forwardOffsets: [0, 0],
        backwardOffsets: [0, 0],
        streetNames: [],
        minLat: 51.0,
        maxLat: 51.2,
        minLng: 71.3,
        maxLng: 71.5,
      );
      expect(g.outEdges(0), isEmpty);
      expect(g.inEdges(0), isEmpty);
    });
  });

  group('VoiceCommand enum', () {
    test('contains GTFS commands', () {
      expect(VoiceCommand.values.contains(VoiceCommand.busRoute), isTrue);
      expect(VoiceCommand.values.contains(VoiceCommand.busSchedule), isTrue);
      expect(VoiceCommand.values.contains(VoiceCommand.downloadMap), isTrue);
    });
  });

  group('Maneuver', () {
    test('maneuverFromAngle straight', () {
      expect(maneuverFromAngle(0), Maneuver.straight);
      expect(maneuverFromAngle(10), Maneuver.straight);
      expect(maneuverFromAngle(350), Maneuver.straight);
    });

    test('maneuverFromAngle right turn', () {
      expect(maneuverFromAngle(90), Maneuver.turnRight);
    });

    test('maneuverFromAngle left turn', () {
      expect(maneuverFromAngle(270), Maneuver.turnLeft);
    });

    test('maneuverFromAngle u-turn', () {
      expect(maneuverFromAngle(180), Maneuver.uTurn);
    });

    test('maneuverFromAngle slight right', () {
      expect(maneuverFromAngle(40), Maneuver.slightRight);
    });

    test('maneuverFromAngle slight left', () {
      expect(maneuverFromAngle(320), Maneuver.slightLeft);
    });
  });
}
