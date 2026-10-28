import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceFocus implements AudioSession {
  final release = Completer<bool>();
  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async => active ? true : release.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channel = MethodChannel('flutter_tts');
  late FlutterTts backend;
  late TtsService tts;
  late List<Map<dynamic, dynamic>> submitted;
  Future<void> event(String type, String id) => backend.platformCallHandler(
    MethodCall('bagdar.speechEvent', {'type': type, 'requestId': id}),
  );
  setUp(() {
    backend = FlutterTts();
    submitted = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'bagdarSpeak') {
            submitted.add(call.arguments as Map);
          }
          return 1;
        });
    tts = TtsService.forPlaybackTesting(tts: backend, useRequestIds: true);
  });
  tearDown(() {
    tts.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final outcome in ['complete', 'error', 'cancel', 'no-start']) {
    testWidgets(
      'prompt receipt requires correlated start and completion: $outcome',
      (tester) async {
        final playback = tts.speakInteraction('Prompt');
        await tester.pump();
        final id = submitted.single['requestId'] as String;
        await event('complete', 'old-request');
        if (outcome != 'no-start') await event('start', id);
        await event(outcome == 'no-start' ? 'complete' : outcome, id);
        await tester.pump(const Duration(milliseconds: 10));
        expect(await playback, outcome == 'complete');
      },
    );
  }
  testWidgets(
    'completion before acknowledgement and audio release cannot open input',
    (tester) async {
      final acknowledgement = Completer<void>();
      final focus = VoiceFocus();
      tts.dispose();
      tts = TtsService.forPlaybackTesting(
        tts: backend,
        useRequestIds: true,
        audioSession: focus,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'bagdarSpeak') {
          submitted.add(call.arguments as Map);
          await acknowledgement.future;
        }
        return 1;
      });
      var finished = false;
      final playback = tts.speakInteraction('Prompt').then((played) {
        finished = true;
        return played;
      });
      await tester.pump();
      final id = submitted.single['requestId'] as String;
      await event('start', id);
      await event('complete', id);
      await tester.pump(const Duration(milliseconds: 10));
      expect(finished, isFalse);
      acknowledgement.complete();
      await tester.pump(const Duration(milliseconds: 10));
      expect(finished, isFalse);
      focus.release.complete(false);
      await tester.pump(const Duration(milliseconds: 10));
      expect(await playback, isTrue);
    },
  );
  testWidgets('cancel ordinary prompts preserves the critical queue', (
    tester,
  ) async {
    final queued = TtsService.forTesting();
    tts.dispose();
    tts = queued;
    final playback = tts.speakInteraction('ordinary prompt');
    tts.say('STOP', SpeechPriority.critical);
    tts.cancelInteractionSpeech();
    expect(await playback, isFalse);
    expect(tts.queueSnapshot.map((job) => job.text), ['STOP']);
  });
  testWidgets(
    'speech listeners invalidate synchronously without delaying alerts',
    (tester) async {
      tts.dispose();
      tts = TtsService.forTesting();
      var calls = 0;
      void listener() {
        calls++;
      }

      tts.addSpeechRequestListener(listener);
      tts.say('STOP', SpeechPriority.critical);
      expect(calls, 1);
      expect(tts.queueSnapshot.single.priority, SpeechPriority.critical);
      tts.removeSpeechRequestListener(listener);
      tts.say('second warning', SpeechPriority.warning);
      expect(calls, 1);
    },
  );
}
