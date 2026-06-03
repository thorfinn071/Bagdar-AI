import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/models/tts_engine.dart';
import 'package:bagdar/services/native_tts_bridge.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
    NativeTtsBridge.debugResetInstance();
  });

  tearDown(() {
    NativeTtsBridge.debugResetInstance();
  });

  /// Builds a `TtsService.forTesting()` and wires up the engine probe
  /// override + native bridge capabilities to drive specific resolver
  /// scenarios. Returns the configured service.
  TtsService configureService({
    required bool kkSystemTtsAvailable,
    required bool v2Enabled,
    bool rhvoiceAvailable = false,
    bool espeakAvailable = false,
  }) {
    final svc = TtsService.forTesting();
    svc.debugKkSystemTtsAvailableOverride = kkSystemTtsAvailable;
    NativeTtsBridge.instance.debugSetCapabilities({
      KkTtsEngine.rhvoice: KkTtsEngineCapability(
        engine: KkTtsEngine.rhvoice,
        available: rhvoiceAvailable,
      ),
      KkTtsEngine.espeak: KkTtsEngineCapability(
        engine: KkTtsEngine.espeak,
        available: espeakAvailable,
      ),
    });
    
    
    Settings.instance.setEnableKazakhStackV2(v2Enabled);
    return svc;
  }

  group('TtsService._resolveKkEngine — Phase 2 priority chain', () {
    test(
      'system TTS engine is preferred when the device exposes a kk voice',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: true,
          v2Enabled: true,
          rhvoiceAvailable: true,
          espeakAvailable: true,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.system);
        expect(svc.activeKkEngine, KkTtsEngine.system);
      },
    );

    test(
      'RHVoice wins over espeak when both natives are available '
      '(v2 flag on, no system voice)',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: true,
          rhvoiceAvailable: true,
          espeakAvailable: true,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.rhvoice);
        expect(svc.activeKkEngine, KkTtsEngine.rhvoice);
      },
    );

    test(
      'espeak is picked when RHVoice is missing but v2 is on',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: true,
          rhvoiceAvailable: false,
          espeakAvailable: true,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.espeak);
        expect(svc.activeKkEngine, KkTtsEngine.espeak);
      },
    );

    test(
      'russianFallback is the last resort when no native engines are available',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: true,
          rhvoiceAvailable: false,
          espeakAvailable: false,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.russianFallback);
        expect(svc.activeKkEngine, KkTtsEngine.russianFallback);
      },
    );

    test(
      'native engines are bypassed entirely when the v2 feature flag is off',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: false,
          rhvoiceAvailable: true,
          espeakAvailable: true,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.russianFallback,
            reason: 'native engines must stay gated behind '
                'Settings.enableKazakhStackV2 until acceptance criteria pass');
        expect(svc.activeKkEngine, KkTtsEngine.russianFallback);
      },
    );

    test(
      'system voice is still preferred even when the v2 flag is off',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: true,
          v2Enabled: false,
        );
        final engine = await svc.debugResolveKkEngine();
        expect(engine, KkTtsEngine.system);
      },
    );

    test(
      'onKazakhEngineResolved fires exactly once per resolution',
      () async {
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: true,
          rhvoiceAvailable: true,
        );
        final fired = <KkTtsEngine>[];
        svc.onKazakhEngineResolved = fired.add;
        await svc.debugResolveKkEngine();
        expect(fired, [KkTtsEngine.rhvoice]);
      },
    );

    test(
      'onKazakhVoiceMissing fires only on the russianFallback branch',
      () async {
        var voiceMissingHits = 0;
        final svc = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: false,
        );
        svc.onKazakhVoiceMissing = () => voiceMissingHits++;
        await svc.debugResolveKkEngine();
        expect(voiceMissingHits, 1);

        
        voiceMissingHits = 0;
        final svc2 = configureService(
          kkSystemTtsAvailable: false,
          v2Enabled: true,
          rhvoiceAvailable: true,
        );
        svc2.onKazakhVoiceMissing = () => voiceMissingHits++;
        await svc2.debugResolveKkEngine();
        expect(voiceMissingHits, 0);
      },
    );
  });

  group('KkTtsEngine helpers', () {
    test('usesNativeBridge is true only for rhvoice + espeak', () {
      expect(KkTtsEngine.rhvoice.usesNativeBridge, isTrue);
      expect(KkTtsEngine.espeak.usesNativeBridge, isTrue);
      expect(KkTtsEngine.system.usesNativeBridge, isFalse);
      expect(KkTtsEngine.russianFallback.usesNativeBridge, isFalse);
    });

    test('usesFlutterTts is true for system + russianFallback', () {
      expect(KkTtsEngine.system.usesFlutterTts, isTrue);
      expect(KkTtsEngine.russianFallback.usesFlutterTts, isTrue);
      expect(KkTtsEngine.rhvoice.usesFlutterTts, isFalse);
      expect(KkTtsEngine.espeak.usesFlutterTts, isFalse);
    });

    test('id round-trips through kkTtsEngineFromId', () {
      for (final e in KkTtsEngine.values) {
        expect(kkTtsEngineFromId(e.id), e);
      }
      expect(kkTtsEngineFromId(null), isNull);
      expect(kkTtsEngineFromId('garbage'), isNull);
    });
  });
}
