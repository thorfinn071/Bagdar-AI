import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:bagdar/core/performance/feedback_delivery_performance.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/tts_engine.dart';
import 'package:bagdar/services/native_tts_bridge.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

class _Focus implements AudioSession {
  final Completer<bool> gate;
  final activations = <bool>[];
  _Focus(this.gate);
  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    return active ? gate.future : false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channel = MethodChannel('flutter_tts');
  const native = MethodChannel('bagdar/native_tts');
  const deadline = Duration(milliseconds: 100);
  late FlutterTts tts;
  late List<Map<dynamic, dynamic>> submitted;

  Future<void> event(String type, String id) => tts.platformCallHandler(
    MethodCall('bagdar.speechEvent', {
      'type': type,
      'requestId': id,
      'reason': 'test_error',
    }),
  );

  setUp(() {
    submitted = [];
    tts = FlutterTts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'bagdarSpeak') {
            submitted.add(call.arguments as Map);
          }
          if (call.method == 'getLanguages') return ['ru-RU'];
          if (call.method == 'getVoices') return [];
          return 1;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
    NativeTtsBridge.debugResetInstance();
  });

  testWidgets(
    'completion before speak acknowledgement releases focus after the reply',
    (tester) async {
      final acknowledgement = Completer<void>();
      final focus = _Focus(Completer<bool>()..complete(true));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'bagdarSpeak') {
          submitted.add(call.arguments as Map);
          await acknowledgement.future;
        }
        return 1;
      });
      final service = TtsService.forPlaybackTesting(
        tts: tts,
        useRequestIds: true,
        audioSession: focus,
      );
      service.say('short message', SpeechPriority.warning);
      await tester.pump();
      await event('complete', submitted.single['requestId'] as String);
      expect(service.speaking, false);
      expect(focus.activations, [true]);
      acknowledgement.complete();
      await tester.pump();
      expect(focus.activations, [true, false]);
      await service.stop();
    },
  );

  testWidgets(
    'explicit stop releases owned audio focus without waiting for an obsolete callback',
    (tester) async {
      final focus = _Focus(Completer<bool>()..complete(true));
      final service = TtsService.forPlaybackTesting(
        tts: tts,
        useRequestIds: true,
        audioSession: focus,
      );
      service.say('stopped message', SpeechPriority.warning);
      await tester.pump();
      expect(focus.activations, [true]);
      await service.stop();
      expect(focus.activations, [true, false]);
      await event('complete', submitted.single['requestId'] as String);
      expect(focus.activations, [true, false]);
    },
  );

  testWidgets('old and untagged events cannot finish or start a newer speech', (
    tester,
  ) async {
    var clockUs = 0;
    final metrics = FeedbackDeliveryPerformance(clockUs: () => clockUs);
    final service = TtsService.forPlaybackTesting(
      tts: tts,
      useRequestIds: true,
      deliveryPerformance: metrics,
    );
    service.say('old', SpeechPriority.warning);
    await tester.pump();
    final old = submitted.single['requestId'] as String;
    service.say('new', SpeechPriority.critical, barge: true, skipHaptic: true);
    await tester.pump();
    final current = submitted.last['requestId'] as String;
    expect(current, isNot(old));
    for (final type in ['start', 'complete', 'error', 'cancel']) {
      await event(type, old);
    }
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    expect(service.speaking, isTrue);
    expect(service.playbackErrors, 0);
    clockUs = 30000;
    await event('start', current);
    await event('start', current);
    final report = metrics.takeWindow();
    expect((report['counts'] as Map)['speechStarted'], 1);
    expect((report['counts'] as Map)['ignoredSpeechEvents'], 4);
    expect((report['counts'] as Map)['speechEndedWithoutStart'], 1);
    expect(((report['timings'] as Map)['requestToStart'] as Map)['p95Ms'], 30);
    expect(report['actualFirstSoundMeasured'], false);
    await event('complete', current);
    expect(service.speaking, isFalse);
    await service.stop();
  });

  testWidgets('a stale completion cannot release a protected newer critical', (
    tester,
  ) async {
    final service = TtsService.forPlaybackTesting(
      tts: tts,
      useRequestIds: true,
    );
    service.say('first', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    final first = submitted.single['requestId'] as String;
    await event('complete', first);
    service.say('second', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    final second = submitted.last['requestId'] as String;
    service.say('third', SpeechPriority.critical, skipHaptic: true);
    await event('complete', first);
    await tester.pump();
    expect(submitted, hasLength(2));
    expect(service.queueSnapshot.single.text, 'third');
    await event('complete', second);
    await tester.pump();
    expect(submitted.last['text'], 'third');
    await service.stop();
  });

  for (final operation in ['setSpeechRate', 'bagdarSpeak', 'setLanguage']) {
    testWidgets(
      'timeout in $operation quarantines until late work settles and explicit recovery',
      (tester) async {
        final gate = Completer<void>();
        var hold = true;
        final service = TtsService.forPlaybackTesting(
          tts: tts,
          useRequestIds: true,
          platformOperationTimeout: deadline,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'bagdarSpeak') {
                submitted.add(call.arguments as Map);
              }
              if (call.method == operation && hold) await gate.future;
              if (call.method == 'getLanguages') return ['ru-RU'];
              if (call.method == 'getVoices') return [];
              return 1;
            });
        if (operation == 'setLanguage') {
          final bridge = NativeTtsBridge.forTesting(methodChannel: native);
          bridge.debugSetCapabilities({
            KkTtsEngine.espeak: const KkTtsEngineCapability(
              engine: KkTtsEngine.espeak,
              available: true,
            ),
          });
          NativeTtsBridge.debugReplaceInstance(bridge);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            native,
            (call) async => call.method != 'speak',
          );
          expect(await bridge.setEngine(KkTtsEngine.espeak), true);
          service.debugSetActiveKkEngine(KkTtsEngine.espeak);
        }
        await service.setUserRate(1.2);
        service.say('timed out', SpeechPriority.warning);
        await tester.pump();
        await tester.pump(deadline);
        expect(service.playbackQuarantined, true);
        expect(service.isReady, false);
        expect(service.speaking, false);
        expect(service.queueSnapshot, isEmpty);
        expect(await service.retryPlayback(), false);
        await service.awaitIdle();
        final before = submitted.length;
        service.say('blocked', SpeechPriority.info);
        gate.complete();
        hold = false;
        await tester.pump();
        expect(submitted, hasLength(before));
        expect(service.pendingPlatformCalls, 0);
        expect(service.isReady, false);
        expect(await service.retryPlayback(), true);
        service.say('fresh', SpeechPriority.critical, skipHaptic: true);
        await tester.pump();
        expect(submitted.last['text'], 'fresh');
        await service.stop();
      },
    );
  }

  testWidgets(
    'hung audio focus cancels the queue and cannot dispatch when it finally returns',
    (tester) async {
      final gate = Completer<bool>();
      final service = TtsService.forPlaybackTesting(
        tts: tts,
        useRequestIds: true,
        audioSession: _Focus(gate),
        platformOperationTimeout: deadline,
      );
      service.say('old', SpeechPriority.warning);
      await tester.pump();
      service.say(
        'urgent',
        SpeechPriority.critical,
        barge: true,
        skipHaptic: true,
      );
      await tester.pump(deadline);
      expect(service.playbackQuarantined, true);
      expect(submitted, isEmpty);
      gate.complete(true);
      await tester.pump();
      expect(submitted, isEmpty);
      expect(service.queueSnapshot, isEmpty);
      await service.stop();
    },
  );

  testWidgets(
    'stop deadline resolves callers but retains one owned native stop',
    (tester) async {
      final gate = Completer<void>();
      var stops = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stop') {
          stops++;
          await gate.future;
        }
        if (call.method == 'bagdarSpeak') submitted.add(call.arguments as Map);
        return 1;
      });
      final service = TtsService.forPlaybackTesting(
        tts: tts,
        useRequestIds: true,
        platformOperationTimeout: deadline,
      );
      service.say('old', SpeechPriority.info);
      await tester.pump();
      var returned = false;
      unawaited(
        service.stop().then((_) {
          returned = true;
        }),
      );
      await tester.pump(deadline);
      expect(returned, true);
      expect(service.isReady, false);
      for (var i = 0; i < 30; i++) {
        unawaited(service.stop());
      }
      await tester.pump();
      expect(stops, 1);
      expect(service.pendingPlatformCalls, 1);
      gate.complete();
      await tester.pump();
      expect(service.pendingPlatformCalls, 0);
      await service.stop();
    },
  );

  testWidgets(
    'Kazakh fallback gets a different request ID and ignores previous native events',
    (tester) async {
      String? nativeId;
      final bridge = NativeTtsBridge.forTesting(methodChannel: native);
      bridge.debugSetCapabilities({
        KkTtsEngine.espeak: const KkTtsEngineCapability(
          engine: KkTtsEngine.espeak,
          available: true,
        ),
      });
      NativeTtsBridge.debugReplaceInstance(bridge);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
        call,
      ) async {
        if (call.method == 'speak') {
          nativeId = (call.arguments as Map)['requestId'] as String;
          return false;
        }
        return true;
      });
      expect(await bridge.setEngine(KkTtsEngine.espeak), true);
      final service = TtsService.forPlaybackTesting(
        tts: tts,
        useRequestIds: true,
      );
      service.debugSetActiveKkEngine(KkTtsEngine.espeak);
      service.say('қазақша', SpeechPriority.critical, skipHaptic: true);
      await tester.pump();
      final fallbackId = submitted.single['requestId'] as String;
      expect(fallbackId, isNot(nativeId));
      bridge.debugFireEvent({'type': 'complete', 'requestId': nativeId});
      bridge.debugFireEvent({'type': 'error', 'requestId': nativeId});
      expect(service.speaking, true);
      expect(service.playbackErrors, 0);
      await event('complete', fallbackId);
      expect(service.speaking, false);
      await service.stop();
    },
  );
}
