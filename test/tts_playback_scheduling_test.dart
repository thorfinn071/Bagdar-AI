import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/tts_engine.dart';
import 'package:bagdar/services/native_tts_bridge.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

class _AudioSessionDouble implements AudioSession {
  final Future<bool> Function(bool) activate;

  _AudioSessionDouble(this.activate);

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) => activate(active);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channel = MethodChannel('flutter_tts');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('bagdar/native_tts'),
          null,
        );
    NativeTtsBridge.debugResetInstance();
  });

  testWidgets('preemption cancels a warning suspended in rate setup', (
    tester,
  ) async {
    final rateGate = Completer<void>();
    final spoken = <String>[];
    var firstRate = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setSpeechRate' && firstRate) {
        firstRate = false;
        await rateGate.future;
      }
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    await service.setUserRate(1.2);
    service.say('warning', SpeechPriority.warning);
    await tester.pump();
    expect(firstRate, isFalse);
    service.say('stop', SpeechPriority.critical, barge: true, skipHaptic: true);
    await tester.pump();
    rateGate.complete();
    await tester.pump();
    expect(spoken, ['stop']);
    await service.stop();
  });

  testWidgets('a critical burst has one backend stop and a bounded queue', (
    tester,
  ) async {
    final stopGate = Completer<void>();
    final spoken = <String>[];
    var stops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'stop') {
        stops++;
        await stopGate.future;
      }
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    for (var i = 0; i < 30; i++) {
      service.say(
        'stop $i',
        SpeechPriority.critical,
        trackId: i,
        barge: true,
        skipHaptic: true,
      );
    }
    await tester.pump();
    expect(stops, 1);
    expect(service.queueSnapshot.map((j) => j.trackId), [26, 27, 28, 29]);
    expect(spoken, isEmpty);
    stopGate.complete();
    await tester.pump();
    expect(spoken, ['stop 26']);
    await service.stop();
  });

  testWidgets('explicit stop cancels pending preparation before speak', (
    tester,
  ) async {
    final rateGate = Completer<void>();
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setSpeechRate') await rateGate.future;
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    await service.setUserRate(1.2);
    service.say('cancelled', SpeechPriority.warning);
    await tester.pump();
    await service.stop();
    rateGate.complete();
    await tester.pump();
    expect(spoken, isEmpty);
    expect(service.speaking, isFalse);
    expect(service.queueSnapshot, isEmpty);
  });

  testWidgets('a request arriving during stop survives until its completion', (
    tester,
  ) async {
    final stopGate = Completer<void>();
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'stop') await stopGate.future;
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    final stopping = service.stop();
    service.say('new session', SpeechPriority.info);
    await tester.pump();
    expect(spoken, isEmpty);
    stopGate.complete();
    await stopping;
    await tester.pump();
    expect(spoken, ['new session']);
    await service.stop();
  });

  testWidgets('a job that expires during setup never reaches speak', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 5);
    final rateGate = Completer<void>();
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setSpeechRate') await rateGate.future;
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(
      tts: FlutterTts(),
      now: () => now,
    );
    await service.setUserRate(1.2);
    service.say(
      'expired',
      SpeechPriority.warning,
      expiresAt: now.add(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    now = now.add(const Duration(seconds: 1));
    rateGate.complete();
    await tester.pump();
    expect(spoken, isEmpty);
    service.say('fresh', SpeechPriority.warning);
    await tester.pump();
    expect(spoken, ['fresh']);
    await service.stop();
  });

  testWidgets('independent critical waits for current critical completion', (
    tester,
  ) async {
    final spoken = <String>[];
    var stops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'stop') stops++;
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final tts = FlutterTts();
    final service = TtsService.forPlaybackTesting(tts: tts);
    service.say('first hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    await tts.platformCallHandler(const MethodCall('speak.onStart'));
    service.say('second hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    expect(stops, 1);
    expect(spoken, ['first hazard']);
    expect(service.queueSnapshot.single.text, 'second hazard');
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await tester.pump();
    expect(spoken, ['first hazard', 'second hazard']);
    await service.stop();
  });

  testWidgets('late speak acknowledgement cannot overlap the next dispatch', (
    tester,
  ) async {
    final speakGate = Completer<void>();
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments as String);
        if (spoken.length == 1) await speakGate.future;
      }
      return 1;
    });
    final tts = FlutterTts();
    final service = TtsService.forPlaybackTesting(tts: tts);
    service.say('old', SpeechPriority.warning);
    await tester.pump();
    expect(spoken, ['old']);
    service.say(
      'critical',
      SpeechPriority.critical,
      barge: true,
      skipHaptic: true,
    );
    await tester.pump();
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await tts.platformCallHandler(const MethodCall('speak.onStart'));
    expect(service.speaking, isFalse);
    expect(spoken, ['old']);
    speakGate.complete();
    await tester.pump();
    expect(spoken, ['old', 'critical']);
    expect(service.speaking, isTrue);
    await service.stop();
  });

  testWidgets('stop cancels the single sentence wakeup during a message burst', (
    tester,
  ) async {
    final spoken = <String>[];
    var now = DateTime.utc(2026, 10, 5);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final tts = FlutterTts();
    final service = TtsService.forPlaybackTesting(tts: tts, now: () => now);
    service.say('first', SpeechPriority.info);
    await tester.pump();
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    for (var i = 0; i < 20; i++) {
      service.say('info $i', SpeechPriority.info);
    }
    await tester.pump();
    expect(service.queueSnapshot, hasLength(4));
    expect(spoken, ['first']);
    await service.stop();
    // The widget-test teardown also asserts that no wakeup timer survived stop.
    expect(service.queueSnapshot, isEmpty);
  });

  testWidgets('missing onStart is recovered by the existing stall watchdog', (
    tester,
  ) async {
    final spoken = <String>[];
    var now = DateTime.utc(2026, 10, 5);
    var stalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(
      tts: FlutterTts(),
      now: () => now,
    );
    service.onTtsStall = () => stalls++;
    service.say('first hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    service.say('second hazard', SpeechPriority.critical, skipHaptic: true);
    now = now.add(kTtsStallTimeout - const Duration(seconds: 1));
    await tester.pump(kTtsStallTimeout - const Duration(seconds: 1));
    expect(stalls, 1);
    expect(service.playbackStalls, 1);
    expect(spoken, ['first hazard', 'second hazard']);
    await service.stop();
  });

  testWidgets('fallback checks TTL again after asynchronous language setup', (
    tester,
  ) async {
    final languageGate = Completer<void>();
    final spoken = <String>[];
    var now = DateTime.utc(2026, 10, 5);
    var nativeAttempts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setLanguage') await languageGate.future;
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    const nativeChannel = MethodChannel('bagdar/native_tts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      nativeChannel,
      (call) async {
        if (call.method == 'speak') {
          nativeAttempts++;
          return false;
        }
        return true;
      },
    );
    final bridge = NativeTtsBridge.forTesting(methodChannel: nativeChannel);
    bridge.debugSetCapabilities({
      KkTtsEngine.espeak: const KkTtsEngineCapability(
        engine: KkTtsEngine.espeak,
        available: true,
      ),
    });
    NativeTtsBridge.debugReplaceInstance(bridge);
    expect(await bridge.setEngine(KkTtsEngine.espeak), isTrue);
    final service = TtsService.forPlaybackTesting(
      tts: FlutterTts(),
      now: () => now,
    );
    service.debugSetActiveKkEngine(KkTtsEngine.espeak);
    service.say(
      'expired',
      SpeechPriority.warning,
      expiresAt: now.add(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(nativeAttempts, 1);
    now = now.add(const Duration(seconds: 1));
    languageGate.complete();
    await tester.pump();
    expect(spoken, isEmpty);
    expect(service.activeKkEngine, KkTtsEngine.russianFallback);
    service.say('fresh', SpeechPriority.warning);
    await tester.pump();
    expect(spoken, ['fresh']);
    await service.stop();
  });

  testWidgets('cancelled rate setup cannot leave an incorrect rate cache', (
    tester,
  ) async {
    final rateGate = Completer<void>();
    final rates = <double>[];
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setSpeechRate') {
        rates.add(call.arguments as double);
        if (rates.length == 1) await rateGate.future;
      }
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    await service.setUserRate(1.2);
    service.say('cancelled', SpeechPriority.warning);
    await tester.pump();
    await service.stop();
    await service.setUserRate(1);
    service.say('fresh', SpeechPriority.warning);
    await tester.pump();
    expect(rates, [0.6]);
    rateGate.complete();
    await tester.pump();
    expect(rates, [0.6, 0.5]);
    expect(spoken, ['fresh']);
    await service.stop();
  });

  testWidgets('a setup exception does not strand the next queued request', (
    tester,
  ) async {
    final rateGate = Completer<void>();
    final spoken = <String>[];
    var failFirst = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setSpeechRate' && failFirst) {
        failFirst = false;
        await rateGate.future;
        throw PlatformException(code: 'simulated_setup_failure');
      }
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(tts: FlutterTts());
    await service.setUserRate(1.2);
    service.say('failed', SpeechPriority.warning);
    await tester.pump();
    service.say('next', SpeechPriority.warning);
    rateGate.complete();
    await tester.pump();
    expect(spoken, ['next']);
    expect(service.playbackErrors, 1);
    await service.stop();
  });

  testWidgets('preemption cancels a request suspended in audio focus setup', (
    tester,
  ) async {
    final focusGate = Completer<bool>();
    final spoken = <String>[];
    var focusCalls = 0;
    final audio = _AudioSessionDouble((active) async {
      if (active && ++focusCalls == 1) return focusGate.future;
      return true;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final service = TtsService.forPlaybackTesting(
      tts: FlutterTts(),
      audioSession: audio,
    );
    service.say('warning', SpeechPriority.warning);
    await tester.pump();
    expect(focusCalls, 1);
    service.say('stop', SpeechPriority.critical, barge: true, skipHaptic: true);
    await tester.pump();
    expect(spoken, isEmpty);
    focusGate.complete(true);
    await tester.pump();
    expect(spoken, ['stop']);
    expect(focusCalls, 2);
    await service.stop();
  });

  testWidgets('completing one critical cannot release the next audio focus', (
    tester,
  ) async {
    final activations = <bool>[];
    final audio = _AudioSessionDouble((active) async {
      activations.add(active);
      return true;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => 1,
    );
    final tts = FlutterTts();
    final service = TtsService.forPlaybackTesting(
      tts: tts,
      audioSession: audio,
    );
    service.say('first hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    service.say('second hazard', SpeechPriority.critical, skipHaptic: true);
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await tester.pump();
    expect(activations, [true, true]);
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await tester.pump();
    expect(activations, [true, true, false]);
    await service.stop();
  });

  testWidgets('native error fallback restores critical non-barge protection', (
    tester,
  ) async {
    final spoken = <String>[];
    var stops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      if (call.method == 'stop') stops++;
      return 1;
    });
    const nativeChannel = MethodChannel('bagdar/native_tts');
    final bridge = NativeTtsBridge.forTesting(methodChannel: nativeChannel);
    bridge.debugSetCapabilities({
      KkTtsEngine.espeak: const KkTtsEngineCapability(
        engine: KkTtsEngine.espeak,
        available: true,
      ),
    });
    NativeTtsBridge.debugReplaceInstance(bridge);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      nativeChannel,
      (call) async {
        if (call.method == 'speak') {
          bridge.debugFireEvent({
            'type': 'error',
            'reason': 'simulated_failure',
          });
          return false;
        }
        return true;
      },
    );
    expect(await bridge.setEngine(KkTtsEngine.espeak), isTrue);
    final tts = FlutterTts();
    final service = TtsService.forPlaybackTesting(tts: tts);
    service.debugSetActiveKkEngine(KkTtsEngine.espeak);
    service.say('first hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    expect(service.playbackErrors, 1);
    expect(spoken, ['first hazard']);
    service.say('second hazard', SpeechPriority.critical, skipHaptic: true);
    await tester.pump();
    expect(stops, 1);
    expect(spoken, ['first hazard']);
    expect(service.queueSnapshot.single.text, 'second hazard');
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await tester.pump();
    expect(spoken, ['first hazard', 'second hazard']);
    await service.stop();
  });
}
