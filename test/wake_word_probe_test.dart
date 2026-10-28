import 'dart:async';
import 'package:bagdar/core/build_profile.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/wake_word_input.dart';
import 'package:bagdar/services/voice/wake_word_probe.dart';
import 'package:flutter_test/flutter_test.dart';

class ProbeInput implements WakeWordInput {
  WakeWordAvailability availability = WakeWordAvailability.ready;
  Completer<WakeWordResult>? response;
  Completer<void>? cancellation;
  Future<WakeWordAvailability>? preparation;
  void Function()? ready;
  int session = 0, listens = 0, cancels = 0;
  bool failCancel = false, autoReady = true;
  final durations = <Duration>[];
  @override
  Future<WakeWordAvailability> prepare({
    required bool requestPermission,
  }) async => preparation == null ? availability : await preparation!;
  @override
  Future<WakeWordResult> listen({
    required int sessionId,
    required Duration duration,
    required void Function() onReady,
  }) {
    session = sessionId;
    listens++;
    durations.add(duration);
    ready = onReady;
    response = Completer<WakeWordResult>();
    if (autoReady) onReady();
    return response!.future;
  }

  void detect({
    int? id,
    bool released = true,
    double? confidence = .9,
    int? age = 0,
    String backend = 'vosk_kz_0_42',
  }) {
    response!.complete(
      WakeWordResult(
        sessionId: id ?? session,
        outcome: 'detected',
        backend: backend,
        keyword: 'bagdar',
        released: released,
        confidence: confidence,
        wordDurationMs: 600,
        ageMs: age,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (failCancel) throw StateError('unconfirmed');
    if (cancellation != null) await cancellation!.future;
    if (response != null && !response!.isCompleted) {
      response!.complete(
        WakeWordResult(
          sessionId: session,
          outcome: 'cancelled',
          released: true,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
  }
}

void main() {
  late ProbeInput input;
  late WakeWordProbe probe;
  late List<String> speech;
  late AppLanguage language;
  late bool foreground, release, played;
  late DateTime time;
  setUp(() {
    input = ProbeInput();
    speech = [];
    language = AppLanguage.ru;
    foreground = release = played = true;
    time = DateTime(2026, 10, 13);
    probe = WakeWordProbe(
      input: input,
      language: () => language,
      canInteract: () => foreground,
      releaseOtherInputs: () async => release,
      speak: (text) async {
        speech.add(text);
        return played;
      },
      now: () => time,
    );
  });
  tearDown(() {
    input.failCancel = false;
    probe.dispose();
  });

  test('Core never enables probe even if a define requests it', () {
    expect(wakeWordProbeEnabled(BuildProfile.core, true), isFalse);
    expect(wakeWordProbeEnabled(BuildProfile.research, false), isFalse);
    expect(wakeWordProbeEnabled(BuildProfile.research, true), isTrue);
  });
  for (final lang in AppLanguage.values) {
    testWidgets('explicit local probe, one detection then off: ${lang.name}', (
      tester,
    ) async {
      language = lang;
      final session = probe.start();
      await tester.pump();
      expect(probe.phase, WakeWordProbePhase.waiting);
      expect(speech.first, wakeProbeText('privacy', lang));
      input.detect();
      await tester.pump();
      expect(probe.detections, 1);
      expect(input.listens, 2);
      expect(speech.last, wakeProbeText('detected', lang));
      await probe.stop();
      await session;
      expect(probe.phase, WakeWordProbePhase.off);
      expect(probe.detections, 1);
      expect(input.listens, 2);
    });
  }
  for (final scenario in [
    'no readiness',
    'stale session',
    'missing confidence',
    'low confidence',
    'invalid confidence',
    'old detection',
    'wrong backend',
    'no release',
  ]) {
    testWidgets('rejects $scenario without rearming', (tester) async {
      input.autoReady = scenario != 'no readiness';
      final session = probe.start();
      await tester.pump();
      input.detect(
        id: scenario == 'stale session' ? -1 : null,
        confidence: scenario == 'missing confidence'
            ? null
            : scenario == 'low confidence'
            ? .84
            : scenario == 'invalid confidence'
            ? double.nan
            : .9,
        age: scenario == 'old detection' ? 1001 : 0,
        backend: scenario == 'wrong backend'
            ? 'android_on_device'
            : 'vosk_kz_0_42',
        released: scenario != 'no release',
      );
      await session;
      expect(probe.detections, 0);
      expect(input.listens, 1);
      expect(probe.phase, WakeWordProbePhase.unavailable);
    });
  }
  for (final availability in WakeWordAvailability.values.where(
    (v) => v != WakeWordAvailability.ready,
  )) {
    test('unavailable input is never opened: ${availability.name}', () async {
      input.availability = availability;
      await probe.start();
      expect(input.listens, 0);
      expect(probe.phase, WakeWordProbePhase.unavailable);
    });
  }
  test(
    'other microphone teardown failure prevents detector preparation',
    () async {
      release = false;
      await probe.start();
      expect(input.listens, 0);
      expect(speech, isEmpty);
    },
  );
  test('unconfirmed own cancellation blocks restarting', () async {
    input.failCancel = true;
    await probe.start();
    expect(probe.canStart, isFalse);
    expect(input.listens, 0);
    expect(probe.message, wakeProbeText('shutdown', language));
  });
  test('failed disclosure speech never opens microphone', () async {
    played = false;
    await probe.start();
    expect(input.listens, 0);
  });
  testWidgets(
    'stop invalidates before acknowledgement and ignores a queued detection',
    (tester) async {
      final session = probe.start();
      await tester.pump();
      input.cancellation = Completer<void>();
      final stopping = probe.stop();
      expect(probe.phase, WakeWordProbePhase.suspended);
      input.detect();
      await tester.pump();
      expect(probe.detections, 0);
      input.cancellation!.complete();
      await stopping;
      await session;
      expect(probe.phase, WakeWordProbePhase.off);
    },
  );
  testWidgets('background invalidates, and foreground does not restart', (
    tester,
  ) async {
    final session = probe.start();
    await tester.pump();
    foreground = false;
    await probe.interrupt();
    await session;
    foreground = true;
    await tester.pump(const Duration(seconds: 10));
    expect(input.listens, 1);
    expect(probe.phase, WakeWordProbePhase.suspended);
  });
  testWidgets('language change rejects old result and closes the capture', (
    tester,
  ) async {
    final session = probe.start();
    await tester.pump();
    language = AppLanguage.en;
    input.detect();
    await session;
    expect(probe.detections, 0);
    expect(input.listens, 1);
    expect(probe.phase, WakeWordProbePhase.suspended);
  });
  testWidgets('stop during model loading cannot begin capture later', (
    tester,
  ) async {
    final preparation = Completer<WakeWordAvailability>();
    input.preparation = preparation.future;
    final session = probe.start();
    await tester.pump();
    expect(probe.phase, WakeWordProbePhase.preparing);
    await probe.stop();
    preparation.complete(WakeWordAvailability.ready);
    await session;
    expect(input.listens, 0);
    expect(probe.phase, WakeWordProbePhase.off);
  });
  testWidgets('session deadline bounds rearming across speech and capture', (
    tester,
  ) async {
    final session = probe.start();
    await tester.pump();
    expect(input.durations.single, const Duration(minutes: 5));
    time = time.add(const Duration(minutes: 5));
    input.detect();
    await session;
    expect(input.listens, 1);
    expect(probe.phase, WakeWordProbePhase.off);
  });
  testWidgets('maximum ten detections ends session', (tester) async {
    final session = probe.start();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      input.detect();
      await tester.pump();
    }
    await session;
    expect(input.listens, 10);
    expect(probe.detections, 10);
    expect(probe.phase, WakeWordProbePhase.off);
  });
}
