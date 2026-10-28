import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/strings.dart';
import 'inspection_voice_commands.dart';
import 'voice_input.dart';

enum InspectionVoicePhase {
  off,
  preparing,
  speaking,
  listening,
  handling,
  suspended,
  unavailable,
}

/// One explicit activation, one bounded answer, one action. No wake-word loop.
class InspectionVoiceCoordinator extends ChangeNotifier {
  final VoiceInput input;
  final AppLanguage Function() language;
  final bool Function() canInteract;
  final Future<bool> Function(String) speak;
  final Future<String?> Function(InspectionVoiceCommand) execute;
  final Future<bool> Function()? prepareInput;
  final bool Function(InspectionVoiceCommand)? isAllowed;
  final Duration answerDuration;
  int _generation = 0;
  bool _disposed = false;
  bool _shutdownUnconfirmed = false;
  Future<bool>? _closing;
  InspectionVoicePhase phase = InspectionVoicePhase.off;
  String message = '';
  String? _lastResponse;
  InspectionVoiceCommand? _lastCommand;

  InspectionVoiceCoordinator({
    required this.input,
    required this.language,
    required this.canInteract,
    required this.speak,
    required this.execute,
    this.prepareInput,
    this.isAllowed,
    this.answerDuration = const Duration(seconds: 8),
  });

  bool get active => switch (phase) {
    InspectionVoicePhase.preparing ||
    InspectionVoicePhase.speaking ||
    InspectionVoicePhase.listening ||
    InspectionVoicePhase.handling => true,
    _ => false,
  };
  bool get canStart =>
      !_disposed && !active && !_shutdownUnconfirmed && canInteract();
  String _text(InspectionVoiceCopy copy) =>
      inspectionVoiceText(copy, language());
  void _state(InspectionVoicePhase next, String text) {
    if (_disposed) return;
    phase = next;
    message = text;
    notifyListeners();
  }

  bool _current(int generation, AppLanguage expected) =>
      !_disposed &&
      generation == _generation &&
      language() == expected &&
      canInteract();

  Future<bool> _close() {
    final pending = _closing;
    if (pending != null) return pending;
    final completion = Completer<bool>();
    _closing = completion.future;
    unawaited(() async {
      var closed = false;
      try {
        await input.cancel().timeout(const Duration(seconds: 2));
        closed = true;
      } catch (_) {
        _state(
          InspectionVoicePhase.unavailable,
          _text(InspectionVoiceCopy.shutdownFailed),
        );
      } finally {
        _shutdownUnconfirmed = !closed;
        _closing = null;
        completion.complete(closed);
      }
    }());
    return completion.future;
  }

  Future<bool> _say(String text, int generation, AppLanguage expected) async {
    if (!_current(generation, expected)) return false;
    _state(InspectionVoicePhase.speaking, text);
    final played = await speak(
      text,
    ).timeout(const Duration(seconds: 35), onTimeout: () => false);
    return played && _current(generation, expected);
  }

  Future<void> start() async {
    if (!canStart) return;
    final generation = ++_generation;
    final expected = language();
    final session = nextVoiceSessionId();
    bool current() => _current(generation, expected);
    _state(InspectionVoicePhase.preparing, _text(InspectionVoiceCopy.privacy));
    try {
      if (!await _close() || !current()) return;
      if (prepareInput != null && !await prepareInput!()) {
        if (current()) {
          _state(
            InspectionVoicePhase.unavailable,
            _text(InspectionVoiceCopy.shutdownFailed),
          );
        }
        return;
      }
      if (!current()) return;
      // Explain processing before the explicit system permission request.
      if (!await _say(
        _text(InspectionVoiceCopy.privacy),
        generation,
        expected,
      )) {
        if (current()) {
          _state(
            InspectionVoicePhase.unavailable,
            _text(InspectionVoiceCopy.speechUnavailable),
          );
        }
        return;
      }
      _state(
        InspectionVoicePhase.preparing,
        _text(InspectionVoiceCopy.privacy),
      );
      final availability = await input.prepare(requestPermission: true);
      if (!current()) return;
      if (availability != VoiceInputAvailability.ready) {
        await _end(
          availability == VoiceInputAvailability.permissionDenied
              ? InspectionVoiceCopy.denied
              : InspectionVoiceCopy.unavailable,
          generation,
          expected,
        );
        return;
      }
      if (!await _say(
        _text(InspectionVoiceCopy.prompt),
        generation,
        expected,
      )) {
        if (current()) {
          _state(
            InspectionVoicePhase.unavailable,
            _text(InspectionVoiceCopy.speechUnavailable),
          );
        }
        return;
      }
      _state(InspectionVoicePhase.preparing, _text(InspectionVoiceCopy.prompt));
      var ready = false;
      final turn = VoiceInputTurn(
        sessionId: session,
        turnId: generation,
        language: expected,
        duration: answerDuration,
      );
      final result = await input
          .listen(
            turn,
            onReady: () {
              if (!current() || ready) return;
              ready = true;
              _state(
                InspectionVoicePhase.listening,
                _text(InspectionVoiceCopy.listening),
              );
            },
          )
          .timeout(answerDuration + const Duration(seconds: 3));
      if (!current()) return;
      _state(InspectionVoicePhase.handling, message);
      // Teardown acknowledgement must precede all actions and response speech.
      if (!await _close() || !current()) return;
      final confidence = result.confidence;
      if (!ready ||
          !result.isFinal ||
          result.sessionId != session ||
          result.turnId != generation ||
          result.backend != 'android_on_device' ||
          confidence == null ||
          !confidence.isFinite ||
          confidence < .75 ||
          confidence > 1 ||
          result.outcome != VoiceInputOutcome.recognized) {
        final copy = switch (result.outcome) {
          VoiceInputOutcome.noSpeech => InspectionVoiceCopy.noSpeech,
          VoiceInputOutcome.permissionDenied => InspectionVoiceCopy.denied,
          VoiceInputOutcome.languageUnavailable ||
          VoiceInputOutcome.unavailable => InspectionVoiceCopy.unavailable,
          VoiceInputOutcome.interrupted ||
          VoiceInputOutcome.cancelled => InspectionVoiceCopy.interrupted,
          _ => InspectionVoiceCopy.unknown,
        };
        await _end(copy, generation, expected);
        return;
      }
      final command = parseInspectionVoice(result.text, expected);
      if (command == null) {
        await _end(InspectionVoiceCopy.unknown, generation, expected);
        return;
      }
      if (isAllowed?.call(command) == false) {
        await _end(InspectionVoiceCopy.actionUnavailable, generation, expected);
        return;
      }
      if (command == InspectionVoiceCommand.micOff) {
        await _end(InspectionVoiceCopy.off, generation, expected);
        return;
      }
      if (command == InspectionVoiceCommand.repeat ||
          command == InspectionVoiceCommand.help) {
        // A service status is ephemeral: repeat refreshes the snapshot.
        final refreshed =
            command == InspectionVoiceCommand.repeat &&
                _lastCommand == InspectionVoiceCommand.status
            ? await execute(InspectionVoiceCommand.status)
            : null;
        if (!current()) return;
        final response = command == InspectionVoiceCommand.repeat
            ? refreshed ?? _lastResponse ?? _text(InspectionVoiceCopy.help)
            : _text(InspectionVoiceCopy.help);
        if (command == InspectionVoiceCommand.help) _lastCommand = command;
        await _respond(response, generation, expected);
        return;
      }
      // Announce route changes before leaving, while this turn is still valid.
      if (command == InspectionVoiceCommand.settings ||
          command == InspectionVoiceCommand.finish) {
        if (!await _say(
          _text(
            command == InspectionVoiceCommand.settings
                ? InspectionVoiceCopy.settings
                : InspectionVoiceCopy.finish,
          ),
          generation,
          expected,
        )) {
          return;
        }
      }
      if (!current()) return;
      _state(InspectionVoicePhase.handling, message);
      final response = await execute(command);
      _lastCommand = command;
      if (!current()) return;
      if (response != null) {
        await _respond(response, generation, expected);
      } else {
        _state(InspectionVoicePhase.off, _text(InspectionVoiceCopy.off));
      }
    } catch (_) {
      if (current()) {
        await _end(InspectionVoiceCopy.unavailable, generation, expected);
      }
    } finally {
      // Language/route changes can invalidate a turn without a lifecycle event.
      if (!_disposed && generation == _generation && active) {
        final closed = await _close();
        if (closed && generation == _generation) {
          _state(
            InspectionVoicePhase.off,
            _text(InspectionVoiceCopy.interrupted),
          );
        }
      }
    }
  }

  Future<void> _respond(
    String text,
    int generation,
    AppLanguage expected,
  ) async {
    _lastResponse = text;
    final response = "$text ${_text(InspectionVoiceCopy.off)}";
    if (await _say(response, generation, expected)) {
      _state(InspectionVoicePhase.off, response);
    }
  }

  Future<void> _end(
    InspectionVoiceCopy copy,
    int generation,
    AppLanguage expected,
  ) async {
    if (!await _close() || !_current(generation, expected)) return;
    final text = _text(copy);
    await _say(text, generation, expected);
    if (_current(generation, expected)) _state(InspectionVoicePhase.off, text);
  }

  /// Invalidates synchronously. Warning output and SOS timers never await this.
  Future<bool> interrupt() {
    ++_generation;
    _state(
      InspectionVoicePhase.suspended,
      _text(InspectionVoiceCopy.interrupted),
    );
    return _close();
  }

  Future<void> stop() async {
    final closing = interrupt();
    final generation = _generation;
    final expected = language();
    final closed = await closing;
    if (generation != _generation || _disposed) return;
    if (closed && canInteract()) {
      await _end(InspectionVoiceCopy.off, generation, expected);
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
