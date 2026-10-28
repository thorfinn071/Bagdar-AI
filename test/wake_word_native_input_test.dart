import 'dart:async';
import 'dart:ui' as ui;
import 'package:bagdar/services/voice/vosk_wake_word_input.dart';
import 'package:bagdar/services/voice/wake_word_input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bagdar/wake_word');
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late VoskWakeWordInput input;
  var availability = 'ready', granted = true, failCancel = false;
  late List<String> calls;
  Completer<Map<String, Object>>? pending;
  Future<void> ready(int session) async {
    final completion = Completer<void>();
    ui.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('ready', {'sessionId': session}),
      ),
      (_) => completion.complete(),
    );
    await completion.future;
  }

  void complete(int session) => pending!.complete({
    'sessionId': session,
    'outcome': 'detected',
    'keyword': 'bagdar',
    'backend': 'vosk_kz_0_42',
    'released': true,
    'confidence': .9,
    'wordDurationMs': 500.0,
    'ageMs': 0,
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    input = VoskWakeWordInput();
    calls = [];
    pending = null;
    availability = 'ready';
    granted = true;
    failCancel = false;
    messenger.setMockMethodCallHandler(
      permission,
      (_) async => granted ? 1 : 0,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'availability':
          return availability;
        case 'prepare':
          return 'ready';
        case 'cancel':
          if (failCancel) throw PlatformException(code: 'shutdown_unconfirmed');
          return null;
        case 'listen':
          expect(call.arguments['experimental'], true);
          expect(call.arguments['durationMs'], 300000);
          pending = Completer<Map<String, Object>>();
          return pending!.future;
      }
      return null;
    });
  });
  tearDown(() async {
    failCancel = false;
    await input.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permission, null);
  });
  for (final native in ['disabled', 'modelMissing', 'unavailable']) {
    test(
      'unavailable $native never requests native preparation or capture',
      () async {
        availability = native;
        expect(
          await input.prepare(requestPermission: true),
          isNot(WakeWordAvailability.ready),
        );
        expect(calls, ['availability']);
      },
    );
  }
  test('denied permission never prepares model or opens capture', () async {
    granted = false;
    expect(
      await input.prepare(requestPermission: false),
      WakeWordAvailability.permissionDenied,
    );
    expect(calls, ['availability']);
  });
  test(
    'readiness correlation and actual release metadata survive transport',
    () async {
      expect(
        await input.prepare(requestPermission: false),
        WakeWordAvailability.ready,
      );
      var count = 0;
      final result = input.listen(
        sessionId: 41,
        duration: const Duration(minutes: 5),
        onReady: () => count++,
      );
      await Future<void>.delayed(Duration.zero);
      await ready(40);
      expect(count, 0);
      await ready(41);
      expect(count, 1);
      complete(41);
      expect((await result).acceptedFor(41), true);
    },
  );
  test(
    'second owner cannot acquire while a native listen is pending',
    () async {
      await input.prepare(requestPermission: false);
      final first = input.listen(
        sessionId: 42,
        duration: const Duration(minutes: 5),
        onReady: () {},
      );
      await Future<void>.delayed(Duration.zero);
      final other = VoskWakeWordInput();
      expect(
        await other.prepare(requestPermission: false),
        WakeWordAvailability.unavailable,
      );
      await other.dispose();
      expect(calls.where((c) => c == 'cancel'), isEmpty);
      complete(42);
      await first;
    },
  );
  test(
    'disposing old owner does not close current owner or detach readiness',
    () async {
      final old = VoskWakeWordInput();
      await old.prepare(requestPermission: false);
      await input.prepare(requestPermission: false);
      await old.dispose();
      expect(calls.where((c) => c == 'cancel'), isEmpty);
      var count = 0;
      final result = input.listen(
        sessionId: 43,
        duration: const Duration(minutes: 5),
        onReady: () => count++,
      );
      await Future<void>.delayed(Duration.zero);
      await ready(43);
      expect(count, 1);
      complete(43);
      await result;
    },
  );
  test('cancellation failure remains visible for microphone handoff', () async {
    await input.prepare(requestPermission: false);
    failCancel = true;
    await expectLater(input.cancel(), throwsA(isA<PlatformException>()));
  });
  test('listen requires preparation and a bounded duration', () async {
    final result = await input.listen(
      sessionId: 44,
      duration: const Duration(minutes: 5),
      onReady: () {},
    );
    expect(result.acceptedFor(44), false);
    await input.prepare(requestPermission: false);
    final long = await input.listen(
      sessionId: 44,
      duration: const Duration(minutes: 6),
      onReady: () {},
    );
    expect(long.outcome, 'unavailable');
    expect(calls.contains('listen'), false);
  });
}
