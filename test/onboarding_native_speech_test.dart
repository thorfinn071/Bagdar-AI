import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/native_onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ttsChannel = MethodChannel('flutter_tts');
  const settingsChannel = MethodChannel('bagdar/onboarding');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NativeOnboardingGateway gateway;
  late List<String> languages;
  var engineError = false;
  var initializationFailure = false;
  var spoken = <String>[];

  Future<void> event(String method, [dynamic arguments]) async {
    final completed = Completer<void>();
    ui.channelBuffers.push(
      'flutter_tts',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  setUp(() async {
    languages = ['ru-RU', 'en-US', 'kk-KZ'];
    engineError = initializationFailure = false;
    spoken = [];
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'getLanguages') return languages;
      if (call.method == 'getVoices') return [];
      if (call.method == 'setPitch' && initializationFailure) {
        throw PlatformException(code: 'engine_missing');
      }
      if (call.method == 'speak' || call.method == 'bagdarSpeak') {
        final tagged = call.method == 'bagdarSpeak';
        final text = call.arguments is Map
            ? call.arguments['text'] as String
            : call.arguments as String;
        if (text != '.') {
          spoken.add(text);
          if (tagged) {
            final requestId = call.arguments['requestId'] as String;
            expect(requestId, startsWith('bagdar-'));
            await event('bagdar.speechEvent', {
              'type': 'start',
              'requestId': requestId,
            });
            await event('bagdar.speechEvent', {
              'type': engineError ? 'error' : 'complete',
              'requestId': requestId,
              'reason': engineError ? 'synthesis_failed' : null,
            });
          } else {
            await event('speak.onStart');
            await event(
              engineError ? 'speak.onError' : 'speak.onComplete',
              engineError ? 'synthesis_failed' : null,
            );
          }
        }
      }
      return 1;
    });
    TtsService.instance.dispose();
    await TtsService.instance.stop();
    gateway = NativeOnboardingGateway();
  });

  tearDown(() async {
    await gateway.stop();
    TtsService.instance.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(ttsChannel, null);
    messenger.setMockMethodCallHandler(settingsChannel, null);
    AppStrings.setAlertLanguage(null);
  });

  test(
    'engine error callback is a failed playback and explicit retry speaks again',
    () async {
      engineError = true;
      expect(
        await gateway.speak('Проверка звука', AppLanguage.ru),
        OnboardingSpeechResult.failed,
      );
      engineError = false;
      expect(
        await gateway.speak('Проверка звука', AppLanguage.ru),
        OnboardingSpeechResult.played,
      );
      expect(spoken, ['Проверка звука', 'Проверка звука']);
    },
  );

  test('failed initialization can recover on an explicit retry', () async {
    initializationFailure = true;
    expect(
      await gateway.speak('Проверка', AppLanguage.ru),
      OnboardingSpeechResult.engineUnavailable,
    );
    expect(spoken, isEmpty);
    initializationFailure = false;
    expect(
      await gateway.speak('Проверка', AppLanguage.ru),
      OnboardingSpeechResult.played,
    );
    expect(spoken, ['Проверка']);
  });

  test(
    'a missing selected language never silently confirms a fallback voice',
    () async {
      languages = ['ru-RU', 'en-US'];
      expect(
        await gateway.speak('Дауыс', AppLanguage.kk),
        OnboardingSpeechResult.voiceUnavailable,
      );
      expect(spoken, isEmpty);
      languages = ['ru-RU'];
      expect(
        await gateway.speak('Example', AppLanguage.en),
        OnboardingSpeechResult.voiceUnavailable,
      );
      expect(spoken, isEmpty);
    },
  );

  test(
    'speech settings bridge reports unavailable methods and explicit success',
    () async {
      expect(await gateway.openSpeechSettings(), isFalse);
      messenger.setMockMethodCallHandler(settingsChannel, (call) async {
        expect(call.method, 'openSpeechSettings');
        return true;
      });
      expect(await gateway.openSpeechSettings(), isTrue);
    },
  );
}
