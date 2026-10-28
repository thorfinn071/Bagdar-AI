import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/camera/fall_countdown_controller.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/sos_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/services/voice_command_service.dart';
import 'package:bagdar/services/voice/on_device_voice_input.dart';
import 'package:bagdar/services/voice/voice_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingVoice extends VoiceCommandService {
  int starts = 0;
  @override
  Future<bool> startContinuousListening({
    required Duration sessionDuration,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 5),
  }) async {
    starts++;
    return true;
  }

  @override
  Future<void> stopListening() async {}
}

class CountingSos extends SosService {
  int sends = 0;
  @override
  Future<SosResult> sendSos({int retries = 3}) async {
    sends++;
    return SosResult.error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage(AppLanguage.ru);
  });
  for (final outcome in ['success', 'failure', 'cancelled', 'expired']) {
    testWidgets('fall countdown independent of microphone handoff: $outcome', (
      tester,
    ) async {
      final gate = Completer<bool>();
      final voice = CountingVoice();
      final sos = CountingSos();
      final tts = TtsService.forTesting();
      final fall = FallCountdownController(
        tts: tts,
        sos: sos,
        voice: voice,
        prepareVoiceInput: () => gate.future,
      );
      fall.start();
      expect(fall.secondsLeft, 15);
      expect(voice.starts, 0);
      expect(
        tts.queueSnapshot.any((job) => job.priority == SpeechPriority.critical),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(fall.secondsLeft, 14); // Teardown never delays the timer.
      if (outcome == 'cancelled') fall.cancel();
      if (outcome == 'expired') {
        await tester.pump(const Duration(seconds: 14));
        expect(sos.sends, 1);
        expect(fall.uiState.phase, SosUiPhase.result);
      }
      gate.complete(outcome != 'failure');
      await tester.pump();
      expect(voice.starts, outcome == 'success' ? 1 : 0);
      fall.dispose();
    });
  }

  group('shared local native input', () {
    const channel = MethodChannel('bagdar/onboarding_voice');
    const permission = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Completer<Map<String, Object>> response;
    var cancelCount = 0;
    Future<void> ready(int session) async {
      final completion = Completer<void>();
      ui.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('ready', {'sessionId': session, 'turnId': 1}),
        ),
        (_) => completion.complete(),
      );
      await completion.future;
    }

    VoiceInputTurn turn(int session) =>
        VoiceInputTurn(sessionId: session, turnId: 1, language: AppLanguage.ru);
    void finish(int session) {
      response.complete({
        'sessionId': session,
        'turnId': 1,
        'outcome': 'noSpeech',
        'isFinal': true,
      });
    }

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      cancelCount = 0;
      messenger.setMockMethodCallHandler(permission, (_) async => 1);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'availability') return 'ready';
        if (call.method == 'cancel') {
          cancelCount++;
          return null;
        }
        if (call.method == 'listen') {
          response = Completer<Map<String, Object>>();
          return response.future;
        }
        return null;
      });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(permission, null);
      messenger.setMockMethodCallHandler(channel, null);
    });
    test('onboarding reclaims callbacks after inspection returns', () async {
      final onboarding = OnDeviceVoiceInput();
      final inspection = OnDeviceVoiceInput();
      expect(
        await onboarding.prepare(requestPermission: false),
        VoiceInputAvailability.ready,
      );
      expect(
        await inspection.prepare(requestPermission: false),
        VoiceInputAvailability.ready,
      );
      await inspection.dispose();
      expect(
        await onboarding.prepare(requestPermission: false),
        VoiceInputAvailability.ready,
      );
      var wasReady = false;
      final result = onboarding.listen(
        turn(11),
        onReady: () => wasReady = true,
      );
      await Future<void>.delayed(Duration.zero);
      await ready(11);
      expect(wasReady, isTrue);
      finish(11);
      await result;
      await onboarding.dispose();
    });
    test('an old disposal cannot close or detach the current owner', () async {
      final old = OnDeviceVoiceInput();
      final current = OnDeviceVoiceInput();
      await old.prepare(requestPermission: false);
      await current.prepare(requestPermission: false);
      await old.dispose();
      expect(cancelCount, 0);
      var wasReady = false;
      final result = current.listen(turn(12), onReady: () => wasReady = true);
      await Future<void>.delayed(Duration.zero);
      await ready(12);
      expect(wasReady, isTrue);
      finish(12);
      await result;
      await current.dispose();
    });
    test(
      'cannot acquire the native channel while another turn is pending',
      () async {
        final first = OnDeviceVoiceInput();
        final next = OnDeviceVoiceInput();
        await first.prepare(requestPermission: false);
        final result = first.listen(turn(13), onReady: () {});
        await Future<void>.delayed(Duration.zero);
        expect(
          await next.prepare(requestPermission: false),
          VoiceInputAvailability.unavailable,
        );
        finish(13);
        await result;
        expect(
          await next.prepare(requestPermission: false),
          VoiceInputAvailability.ready,
        );
        await first.dispose();
        await next.dispose();
      },
    );
  });
}
