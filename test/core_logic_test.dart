import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vision_guide_app/models/speech_job.dart';
import 'package:vision_guide_app/models/strings.dart';
import 'package:vision_guide_app/services/device_capability.dart';
import 'package:vision_guide_app/services/depth_provider.dart';
import 'package:vision_guide_app/utils/alert_filter.dart';
import 'package:vision_guide_app/utils/depth_hazard.dart';
import 'package:vision_guide_app/utils/distance_utils.dart';
import 'package:vision_guide_app/utils/ground_plane_analyzer.dart';
import 'package:vision_guide_app/utils/midas_service.dart';

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

    test('global cooldown: second flush within 1.2 s returns null for critical', () {
      filter.add(makeCandidate(priority: SpeechPriority.critical));
      filter.flush(1, t0); 
      filter.add(makeCandidate(priority: SpeechPriority.critical));
      
      final result = filter.flush(1, t0.add(const Duration(milliseconds: 500)));
      expect(result, isNull);
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
      
      filter.add(makeCandidate(priority: SpeechPriority.warning));
      final result = filter.flush(1, t0.add(const Duration(seconds: 3)));
      expect(result, isNotNull);
    });

    test('dense scene (5+ tracks) suppresses info alerts', () {
      filter.add(makeCandidate(priority: SpeechPriority.info));
      final result = filter.flush(5, t0);
      expect(result, isNull);
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
      final result = engine.evaluate(hazard: makeHazard(0.35), now: t0);
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
      
      engine.evaluate(
        hazard: makeHazard(FusionEngine.kCriticalThreshold),
        now: t0,
      );
      final t1 = t0.add(const Duration(seconds: 4)); 
      final result = engine.evaluate(
        hazard: makeHazard(FusionEngine.kCriticalThreshold),
        now: t1,
      );
      expect(result!.level, AlertLevel.critical);
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
    test('sdk >= 28 + nnapi → midasNnapi tier', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasNnapi,
        supportsNnApi: true,
        androidSdkInt: 30,
      );
      expect(caps.bestDepthTier, DepthTier.midasNnapi);
      expect(caps.supportsNnApi, isTrue);
    });

    test('sdk 26-27 → midasCpu tier', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasCpu,
        supportsNnApi: false,
        androidSdkInt: 27,
      );
      expect(caps.bestDepthTier, DepthTier.midasCpu);
      expect(caps.supportsNnApi, isFalse);
    });

    test('focalLength tier → no nnapi', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.focalLength,
        supportsNnApi: false,
        androidSdkInt: 26,
      );
      expect(caps.supportsNnApi, isFalse);
      expect(caps.bestDepthTier, DepthTier.focalLength);
    });

    test('toString includes all key fields', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasNnapi,
        supportsNnApi: true,
        androidSdkInt: 31,
      );
      final s = caps.toString();
      expect(s, contains('midasNnapi'));
      expect(s, contains('31'));
    });
  });

  
  
  

  group('DepthProviderFactory', () {
    test('midasNnapi caps → MidasDepthProvider with useNnApi=true', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasNnapi,
        supportsNnApi: true,
        androidSdkInt: 30,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<MidasDepthProvider>());
      expect((provider as MidasDepthProvider).useNnApi, isTrue);
      expect(provider.tier, DepthTier.midasNnapi);
    });

    test('midasCpu caps → MidasDepthProvider with useNnApi=false', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasCpu,
        supportsNnApi: false,
        androidSdkInt: 26,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<MidasDepthProvider>());
      expect((provider as MidasDepthProvider).useNnApi, isFalse);
      expect(provider.tier, DepthTier.midasCpu);
    });

    test('focalLength caps → FocalLengthDepthProvider', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.focalLength,
        supportsNnApi: false,
        androidSdkInt: 26,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<FocalLengthDepthProvider>());
      expect(provider.tier, DepthTier.focalLength);
    });

    test('hardware caps → falls back to MidasDepthProvider(nnapi=true)', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.hardware,
        supportsNnApi: true,
        androidSdkInt: 33,
      );
      final provider = DepthProviderFactory.create(caps);
      expect(provider, isA<MidasDepthProvider>());
      expect((provider as MidasDepthProvider).useNnApi, isTrue);
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

    test('createWithTier(midasCpu) → MidasDepthProvider nnapi=false', () {
      final p = DepthProviderFactory.createWithTier(DepthTier.midasCpu);
      expect(p, isA<MidasDepthProvider>());
      expect((p as MidasDepthProvider).useNnApi, isFalse);
    });
  });
}
