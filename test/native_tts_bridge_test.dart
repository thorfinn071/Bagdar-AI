import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/tts_engine.dart';
import 'package:bagdar/services/native_tts_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    NativeTtsBridge.debugResetInstance();
  });

  group('KkTtsEngineCapability.fromMap', () {
    test('parses a fully-populated map', () {
      final cap = KkTtsEngineCapability.fromMap({
        'engine': 'rhvoice',
        'available': true,
        'version': '1.0.0',
        'supportedLanguages': ['kk'],
      });
      expect(cap.engine, KkTtsEngine.rhvoice);
      expect(cap.available, isTrue);
      expect(cap.version, '1.0.0');
      expect(cap.supportedLanguages, ['kk']);
      expect(cap.unavailableReason, isEmpty);
    });

    test('falls back to russianFallback for unknown engine ids', () {
      final cap = KkTtsEngineCapability.fromMap({
        'engine': 'mystery',
        'available': false,
      });
      expect(cap.engine, KkTtsEngine.russianFallback);
      expect(cap.available, isFalse);
    });

    test('records the unavailableReason field for diagnostics', () {
      final cap = KkTtsEngineCapability.fromMap({
        'engine': 'espeak',
        'available': false,
        'unavailableReason': 'lib_missing',
      });
      expect(cap.engine, KkTtsEngine.espeak);
      expect(cap.available, isFalse);
      expect(cap.unavailableReason, 'lib_missing');
    });
  });

  group('NativeTtsBridge — channel plumbing', () {
    test(
      'availableEngines round-trips the capability list from the platform '
      'method channel',
      () async {
        const channel = MethodChannel('bagdar/native_tts');
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'availableEngines') {
              return [
                {
                  'engine': 'rhvoice',
                  'available': true,
                  'version': '1.0.0',
                },
                {
                  'engine': 'espeak',
                  'available': false,
                  'unavailableReason': 'voice_data_missing',
                },
              ];
            }
            return null;
          },
        );

        final bridge = NativeTtsBridge.forTesting(methodChannel: channel);
        await bridge.refresh();

        expect(bridge.hasRhvoiceKk(), isTrue);
        expect(bridge.hasEspeakKk(), isFalse);
        expect(
          bridge.capabilityFor(KkTtsEngine.espeak)?.unavailableReason,
          'voice_data_missing',
        );

        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );

    test(
      'setEngine forwards the engine id to the channel and updates activeEngine',
      () async {
        const channel = MethodChannel('bagdar/native_tts');
        String? lastEngineArg;
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'setEngine') {
              final args = call.arguments as Map?;
              lastEngineArg = args?['engine'] as String?;
              return true;
            }
            return null;
          },
        );

        final bridge = NativeTtsBridge.forTesting(methodChannel: channel);
        bridge.debugSetCapabilities({
          KkTtsEngine.rhvoice: const KkTtsEngineCapability(
            engine: KkTtsEngine.rhvoice,
            available: true,
          ),
        });

        final ok = await bridge.setEngine(KkTtsEngine.rhvoice);
        expect(ok, isTrue);
        expect(lastEngineArg, 'rhvoice');
        expect(bridge.activeEngine, KkTtsEngine.rhvoice);

        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );

    test(
      'setEngine refuses unavailable engines without touching the channel',
      () async {
        const channel = MethodChannel('bagdar/native_tts');
        var channelHits = 0;
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            channelHits++;
            return null;
          },
        );

        final bridge = NativeTtsBridge.forTesting(methodChannel: channel);
        bridge.debugSetCapabilities({
          KkTtsEngine.rhvoice: const KkTtsEngineCapability(
            engine: KkTtsEngine.rhvoice,
            available: false,
            unavailableReason: 'pack_not_installed',
          ),
        });

        final ok = await bridge.setEngine(KkTtsEngine.rhvoice);
        expect(ok, isFalse);
        expect(channelHits, 0,
            reason: 'unavailable engines must not round-trip to native');
        expect(bridge.activeEngine, isNull);

        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );

    test(
      'speak returns false when no engine is active (defensive guard)',
      () async {
        const channel = MethodChannel('bagdar/native_tts');
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => true,
        );

        final bridge = NativeTtsBridge.forTesting(methodChannel: channel);
        final ok = await bridge.speak(
          text: 'hello',
          priority: 'info',
        );
        expect(ok, isFalse);

        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );

    test('debugFireEvent dispatches lifecycle callbacks correctly', () {
      final bridge = NativeTtsBridge.forTesting(
        methodChannel: const MethodChannel('bagdar/native_tts'),
      );
      var started = 0;
      var completed = 0;
      String? lastError;
      bridge.onSpeechStart = () => started++;
      bridge.onSpeechComplete = () => completed++;
      bridge.onSpeechError = (r) => lastError = r;

      bridge.debugFireEvent({'type': 'start'});
      bridge.debugFireEvent({'type': 'complete'});
      bridge.debugFireEvent({'type': 'error', 'reason': 'audio_track_failed'});

      expect(started, 1);
      expect(completed, 1);
      expect(lastError, 'audio_track_failed');
    });
  });
}
