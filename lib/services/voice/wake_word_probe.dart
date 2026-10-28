import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/build_profile.dart';
import '../../models/strings.dart';
import 'voice_input.dart';
import 'wake_word_input.dart';

final _wakeProbeClock = Stopwatch()..start();
// Only elapsed intervals are needed; changing the phone's wall clock must
// never extend the microphone session. This synthetic epoch is not logged.
DateTime _wakeProbeTime() => DateTime.fromMicrosecondsSinceEpoch(
  _wakeProbeClock.elapsedMicroseconds,
  isUtc: true,
);

bool wakeWordProbeEnabled(BuildProfile profile, bool requested) =>
    profile.isResearch && requested;

enum WakeWordProbePhase {
  off,
  preparing,
  speaking,
  waiting,
  detected,
  suspended,
  unavailable,
}

String wakeProbeText(String key, AppLanguage language) {
  const copy = {
    'title': ['Проверка обращения', 'Ояту сөзін тексеру', 'Wake word test'],
    'count': ['Обнаружений:', 'Анықталды:', 'Detections:'],
    'start': [
      'Испытать «Багдар» — 5 минут',
      '«Бағдар» сөзін сынау — 5 минут',
      'Test “Bagdar” — 5 minutes',
    ],
    'stop': [
      'Выключить микрофон обращения',
      'Ояту сөзінің микрофонын өшіру',
      'Turn off wake microphone',
    ],
    'privacy': [
      'Исследовательская проверка обращения. Аудио обрабатывается локально и не сохраняется. Команды от обращения отключены. После сигнала скажите отдельно: Багдар.',
      'Ояту сөзін зерттеу тексеруі. Дыбыс құрылғыда өңделеді, сақталмайды. Ояту сөзі пәрмен орындамайды. Дыбыстық белгіден кейін «Бағдар» деп жеке айтыңыз.',
      'Research wake word test. Audio stays on this device and is not saved. Wake detections cannot run commands. After the tone, say Bagdar on its own.',
    ],
    'preparing': [
      'Готовлю локальный детектор. Микрофон ещё не слушает.',
      'Жергілікті детектор дайындалуда. Микрофон әлі тыңдамайды.',
      'Preparing local detector. Microphone is not listening yet.',
    ],
    'waiting': [
      'Ожидаю «Багдар». Команды от обращения выключены.',
      '«Бағдар» сөзін күтемін. Ояту сөзі пәрмен орындамайды.',
      'Waiting for “Bagdar”. Wake commands are disabled.',
    ],
    'detected': [
      'Обращение обнаружено. Действие не выполнялось.',
      'Ояту сөзі анықталды. Әрекет орындалмады.',
      'Wake detected. No action was performed.',
    ],
    'off': [
      'Микрофон обращения выключен. Для запуска используйте элемент проверки.',
      'Ояту сөзінің микрофоны өшірулі. Қосу үшін тексеру элементін қолданыңыз.',
      'Wake microphone off. Use the test control to start.',
    ],
    'expired': [
      'Проверка завершена по лимиту. Микрофон обращения выключен.',
      'Тексеру уақыты аяқталды. Ояту сөзінің микрофоны өшірілді.',
      'Test limit reached. Wake microphone off.',
    ],
    'interrupted': [
      'Проверка прервана. Для продолжения включите её заново.',
      'Тексеру үзілді. Жалғастыру үшін қайта қосыңыз.',
      'Test interrupted. Activate again to continue.',
    ],
    'unavailable': [
      'Локальный детектор недоступен. Используйте обычную голосовую команду.',
      'Жергілікті детектор қолжетімсіз. Қалыпты дауыстық пәрменді қолданыңыз.',
      'Local detector unavailable. Use the ordinary voice command control.',
    ],
    'denied': [
      'Нет разрешения на микрофон. Повторите запуск через элемент проверки.',
      'Микрофонға рұқсат жоқ. Тексеру элементі арқылы қайта қосыңыз.',
      'Microphone permission denied. Activate the test control to retry.',
    ],
    'shutdown': [
      'Остановка микрофона не подтверждена. Закройте Bagdar средствами ОС.',
      'Микрофон тоқтауы расталмады. Bagdar қолданбасын жүйе арқылы жабыңыз.',
      'Microphone shutdown not confirmed. Close Bagdar using system controls.',
    ],
  };
  return copy[key]![language.index];
}

/// Bounded detector audition. It deliberately has no command/SOS/settings callback.
class WakeWordProbe extends ChangeNotifier {
  final WakeWordInput input;
  final AppLanguage Function() language;
  final bool Function() canInteract;
  final Future<bool> Function() releaseOtherInputs;
  final Future<bool> Function(String) speak;
  final Duration sessionDuration;
  final DateTime Function() now;
  WakeWordProbePhase phase = WakeWordProbePhase.off;
  String message = '';
  int detections = 0;
  int _generation = 0;
  bool _disposed = false, _shutdownUnconfirmed = false;
  Future<bool>? _closing;
  WakeWordProbe({
    required this.input,
    required this.language,
    required this.canInteract,
    required this.releaseOtherInputs,
    required this.speak,
    this.sessionDuration = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : now = now ?? _wakeProbeTime;
  bool get active =>
      phase == WakeWordProbePhase.preparing ||
      phase == WakeWordProbePhase.speaking ||
      phase == WakeWordProbePhase.waiting ||
      phase == WakeWordProbePhase.detected;
  bool get canStart =>
      !_disposed && !active && !_shutdownUnconfirmed && canInteract();
  String _text(String key) => wakeProbeText(key, language());
  void _state(WakeWordProbePhase value, String key) {
    if (_disposed) return;
    phase = value;
    message = _text(key);
    notifyListeners();
  }

  bool _current(int generation, AppLanguage expected) =>
      !_disposed &&
      generation == _generation &&
      expected == language() &&
      canInteract();
  Future<bool> _close() {
    if (_closing != null) return _closing!;
    final completion = Completer<bool>();
    _closing = completion.future;
    unawaited(() async {
      var closed = false;
      try {
        await input.cancel().timeout(const Duration(seconds: 2));
        closed = true;
      } catch (_) {
        _state(WakeWordProbePhase.unavailable, 'shutdown');
      }
      _shutdownUnconfirmed = !closed;
      _closing = null;
      completion.complete(closed);
    }());
    return completion.future;
  }

  Future<void> start() async {
    if (!canStart) return;
    final generation = ++_generation;
    final expected = language();
    bool current() => _current(generation, expected);
    detections = 0;
    _state(WakeWordProbePhase.preparing, 'preparing');
    try {
      if (!await _close() || !current() || !await releaseOtherInputs()) {
        if (current()) _state(WakeWordProbePhase.unavailable, 'shutdown');
        return;
      }
      if (!current()) return;
      _state(WakeWordProbePhase.speaking, 'privacy');
      if (!await speak(
            message,
          ).timeout(const Duration(seconds: 35), onTimeout: () => false) ||
          !current()) {
        if (current()) _state(WakeWordProbePhase.unavailable, 'unavailable');
        return;
      }
      _state(WakeWordProbePhase.preparing, 'preparing');
      final availability = await input.prepare(requestPermission: true);
      if (!current()) return;
      if (availability != WakeWordAvailability.ready) {
        _state(
          WakeWordProbePhase.unavailable,
          availability == WakeWordAvailability.permissionDenied
              ? 'denied'
              : 'unavailable',
        );
        return;
      }
      final deadline = now().add(
        sessionDuration > const Duration(minutes: 5)
            ? const Duration(minutes: 5)
            : sessionDuration,
      );
      while (current() && detections < 10) {
        final remaining = deadline.difference(now());
        if (remaining < const Duration(seconds: 1)) break;
        var ready = false;
        final sessionId = nextVoiceSessionId();
        final result = await input
            .listen(
              sessionId: sessionId,
              duration: remaining,
              onReady: () {
                if (current() && !ready) {
                  ready = true;
                  _state(WakeWordProbePhase.waiting, 'waiting');
                }
              },
            )
            .timeout(remaining + const Duration(seconds: 3));
        if (!current()) return;
        if (!await _close() || !current()) return;
        if (!now().isBefore(deadline)) break;
        if (result.outcome == 'expired') break;
        if (!ready || !result.acceptedFor(sessionId)) {
          _state(WakeWordProbePhase.unavailable, 'unavailable');
          return;
        }
        detections++;
        _state(WakeWordProbePhase.detected, 'detected');
        if (!await speak(
              message,
            ).timeout(const Duration(seconds: 35), onTimeout: () => false) ||
            !current()) {
          if (current()) _state(WakeWordProbePhase.unavailable, 'unavailable');
          return;
        }
        _state(WakeWordProbePhase.preparing, 'preparing');
      }
      if (current() && await _close() && current()) {
        _state(WakeWordProbePhase.off, 'expired');
      }
    } catch (_) {
      if (current() && await _close() && current()) {
        _state(WakeWordProbePhase.unavailable, 'unavailable');
      }
    } finally {
      if (!_disposed && generation == _generation && active) {
        final closed = await _close();
        if (closed && generation == _generation) {
          _state(WakeWordProbePhase.suspended, 'interrupted');
        }
      }
    }
  }

  /// Invalidates before asynchronous teardown. Safety output must not await it.
  Future<bool> interrupt() {
    ++_generation;
    _state(WakeWordProbePhase.suspended, 'interrupted');
    return _close();
  }

  Future<void> stop() async {
    final closing = interrupt();
    final generation = _generation;
    if (await closing && !_disposed && generation == _generation) {
      _state(WakeWordProbePhase.off, 'off');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(input.dispose());
    super.dispose();
  }
}
