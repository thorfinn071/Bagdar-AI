import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/a11y_prefs.dart';
import '../../models/strings.dart';
import '../../theme/bagdar_tokens.dart';
import 'inspection_voice_commands.dart';
import 'inspection_voice_coordinator.dart' show InspectionVoicePhase;
import 'voice_input.dart';
import 'voice_settings.dart';

/// One opt-in dialogue, at most one explicitly confirmed preference write.
/// Drafts have no effect on runtime sound, storage, readiness or SOS.
class VoiceSettingsCoordinator extends ChangeNotifier {
  final VoiceInput input;
  final VoiceSettingsGateway gateway;
  final AppLanguage Function() language;
  final bool Function() canInteract;
  final Future<bool> Function(String) speak;
  final Future<bool> Function() prepareInput;
  final int maxTurns;
  final Duration sessionLimit;
  VoiceSettingsPage page = VoiceSettingsPage.menu;
  InspectionVoicePhase phase = InspectionVoicePhase.off;
  VoiceSettingChange? draft;
  VoiceSettingChange? _baseline;
  VoiceSettingsPage _draftOrigin = VoiceSettingsPage.menu;
  String message = '';
  int _generation = 0;
  bool _disposed = false;
  bool _shutdownUnconfirmed = false;
  bool _saving = false;
  Future<bool>? _closing;
  Timer? _deadline;

  VoiceSettingsCoordinator({
    required this.input,
    required this.gateway,
    required this.language,
    required this.canInteract,
    required this.speak,
    required this.prepareInput,
    this.maxTurns = 12,
    this.sessionLimit = const Duration(minutes: 2),
  });

  bool get active => switch (phase) {
    InspectionVoicePhase.preparing ||
    InspectionVoicePhase.speaking ||
    InspectionVoicePhase.listening ||
    InspectionVoicePhase.handling => true,
    _ => false,
  };
  bool get canStart =>
      !_disposed &&
      !active &&
      !_saving &&
      !_shutdownUnconfirmed &&
      canInteract();
  bool get saving => _saving;
  String t(String key) => voiceSettingsText(key, language());
  String _inputText(InspectionVoiceCopy key) =>
      inspectionVoiceText(key, language());
  VoiceSettingChange _currentValue(VoiceSettingKind kind) {
    final value = gateway.read();
    return switch (kind) {
      VoiceSettingKind.rate => VoiceSettingChange.rate(value.rate),
      VoiceSettingKind.volume => VoiceSettingChange.volume(value.volume),
      VoiceSettingKind.theme => VoiceSettingChange.theme(value.theme),
    };
  }

  bool _equal(VoiceSettingChange a, VoiceSettingChange b) =>
      a.kind == b.kind &&
      a.theme == b.theme &&
      (a.number == null
          ? b.number == null
          : b.number != null && (a.number! - b.number!).abs() < .0001);

  String get question {
    final value = draft;
    if (page == VoiceSettingsPage.review && value != null) {
      final label = t(switch (value.kind) {
        VoiceSettingKind.rate => 'rateLabel',
        VoiceSettingKind.volume => 'volumeLabel',
        VoiceSettingKind.theme => 'themeLabel',
      });
      return '$label. ${t("current")}: ${voiceSettingOnlyValue(_baseline!, language())}. '
          '${t("proposed")}: ${voiceSettingOnlyValue(value, language())}. ${t("review")}';
    }
    final prefix = switch (page) {
      VoiceSettingsPage.rate => voiceSettingValue(
        _currentValue(VoiceSettingKind.rate),
        language(),
      ),
      VoiceSettingsPage.volume => voiceSettingValue(
        _currentValue(VoiceSettingKind.volume),
        language(),
      ),
      VoiceSettingsPage.appearance || VoiceSettingsPage.moreThemes =>
        voiceSettingValue(_currentValue(VoiceSettingKind.theme), language()),
      _ => '',
    };
    return prefix.isEmpty ? t(page.name) : '$prefix. ${t(page.name)}';
  }

  String get overview {
    final value = gateway.read();
    final languageName = [
      'русский',
      'қазақша',
      'English',
    ][value.language.index];
    final haptics = (switch (value.haptics) {
      HapticStrength.weak => ['слабая', 'әлсіз', 'weak'],
      HapticStrength.normal => ['обычная', 'қалыпты', 'normal'],
      HapticStrength.strong => ['сильная', 'күшті', 'strong'],
    })[language().index];
    final signals = (value.earconEnabled
        ? ['включены', 'қосылған', 'on']
        : ['выключены', 'өшірілген', 'off'])[language().index];
    return '${voiceSettingValue(VoiceSettingChange.rate(value.rate), language())}. '
        '${voiceSettingValue(VoiceSettingChange.volume(value.volume), language())}. '
        '${voiceSettingValue(VoiceSettingChange.theme(value.theme), language())}. '
        '${t("languageLabel")}: $languageName. ${t("signalsLabel")}: $signals, '
        '${(value.earconVolume * 100).round()}%. ${t("hapticsLabel")}: $haptics. '
        '${t("readOnly")}';
  }

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
        draft = null;
        _baseline = null;
        page = VoiceSettingsPage.menu;
        _state(
          InspectionVoicePhase.unavailable,
          _inputText(InspectionVoiceCopy.shutdownFailed),
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
    var played = false;
    try {
      played = await speak(
        text,
      ).timeout(const Duration(seconds: 35), onTimeout: () => false);
    } catch (_) {}
    if (!played && _current(generation, expected)) {
      _state(
        InspectionVoicePhase.unavailable,
        _inputText(InspectionVoiceCopy.speechUnavailable),
      );
    }
    return played && _current(generation, expected);
  }

  Future<void> _finish(
    String text,
    int generation,
    AppLanguage expected,
  ) async {
    draft = null;
    _baseline = null;
    page = VoiceSettingsPage.menu;
    if (!await _close() || !_current(generation, expected)) return;
    final notice = '$text ${t("off")}';
    if (await _say(notice, generation, expected)) {
      _state(InspectionVoicePhase.off, notice);
    } else if (_current(generation, expected)) {
      _state(
        InspectionVoicePhase.unavailable,
        '$text ${_inputText(InspectionVoiceCopy.speechUnavailable)}',
      );
    }
  }

  Future<void> start({required bool requestPermission}) async {
    if (!canStart || _saving) return;
    final generation = ++_generation;
    final expected = language();
    final session = nextVoiceSessionId();
    bool current() => _current(generation, expected);
    page = VoiceSettingsPage.menu;
    draft = null;
    _baseline = null;
    var failures = 0;
    var saveAttempted = false;
    _state(InspectionVoicePhase.preparing, t('intro'));
    _deadline?.cancel();
    _deadline = Timer(sessionLimit, () {
      unawaited(interrupt(reason: t('limit')));
    });
    try {
      if (!await _close() || !current()) return;
      if (!await prepareInput()) {
        if (current()) {
          _state(
            InspectionVoicePhase.unavailable,
            _inputText(InspectionVoiceCopy.shutdownFailed),
          );
        }
        return;
      }
      if (requestPermission &&
          !await _say(
            _inputText(InspectionVoiceCopy.privacy),
            generation,
            expected,
          )) {
        return;
      }
      if (!await _say(t('intro'), generation, expected)) return;
      _state(InspectionVoicePhase.preparing, message);
      final available = await input.prepare(
        requestPermission: requestPermission,
      );
      if (!current()) return;
      if (available != VoiceInputAvailability.ready) {
        await _finish(
          _inputText(
            available == VoiceInputAvailability.permissionDenied
                ? InspectionVoiceCopy.denied
                : InspectionVoiceCopy.unavailable,
          ),
          generation,
          expected,
        );
        return;
      }
      for (var turnId = 1; turnId <= maxTurns && current(); turnId++) {
        final expectedPage = page;
        if (!await _say(question, generation, expected)) return;
        _state(InspectionVoicePhase.preparing, question);
        var ready = false;
        final turn = VoiceInputTurn(
          sessionId: session,
          turnId: turnId,
          language: expected,
        );
        final result = await input
            .listen(
              turn,
              onReady: () {
                if (!current() || ready || page != expectedPage) return;
                ready = true;
                _state(InspectionVoicePhase.listening, t('listening'));
              },
            )
            .timeout(turn.duration + const Duration(seconds: 3));
        if (!current() || page != expectedPage) return;
        _state(InspectionVoicePhase.handling, question);
        if (!await _close() || !current()) return;
        final confidence = result.confidence;
        if (!ready ||
            !result.isFinal ||
            result.sessionId != session ||
            result.turnId != turnId ||
            result.backend != 'android_on_device' ||
            result.outcome != VoiceInputOutcome.recognized ||
            confidence == null ||
            !confidence.isFinite ||
            confidence < .75 ||
            confidence > 1) {
          await _finish(
            _inputText(switch (result.outcome) {
              VoiceInputOutcome.noSpeech => InspectionVoiceCopy.noSpeech,
              VoiceInputOutcome.permissionDenied => InspectionVoiceCopy.denied,
              VoiceInputOutcome.languageUnavailable ||
              VoiceInputOutcome.unavailable => InspectionVoiceCopy.unavailable,
              VoiceInputOutcome.cancelled ||
              VoiceInputOutcome.interrupted => InspectionVoiceCopy.interrupted,
              _ => InspectionVoiceCopy.unknown,
            }),
            generation,
            expected,
          );
          return;
        }
        final intent = parseVoiceSettings(result.text, expected, page);
        if (intent == null) {
          failures++;
          if (failures >= 2) {
            await _finish(t('unknown'), generation, expected);
            return;
          }
          if (!await _say(t('unknown'), generation, expected)) return;
          continue;
        }
        failures = 0;
        if (intent == VoiceSettingsIntent.cancel) {
          draft = null;
          await _finish(t('cancelled'), generation, expected);
          return;
        }
        if (intent == VoiceSettingsIntent.repeat) continue;
        if (intent == VoiceSettingsIntent.back) {
          page = switch (page) {
            VoiceSettingsPage.rate ||
            VoiceSettingsPage.volume => VoiceSettingsPage.speech,
            VoiceSettingsPage.moreThemes => VoiceSettingsPage.appearance,
            VoiceSettingsPage.review => _draftOrigin,
            _ => VoiceSettingsPage.menu,
          };
          draft = null;
          _baseline = null;
          continue;
        }
        if (intent == VoiceSettingsIntent.overview) {
          if (!await _say(overview, generation, expected)) return;
          continue;
        }
        if (intent == VoiceSettingsIntent.save) {
          final change = draft;
          if (change == null ||
              _baseline == null ||
              !change.valid ||
              !_equal(_currentValue(change.kind), _baseline!)) {
            await _finish(t('saveFailed'), generation, expected);
            return;
          }
          if (!current()) return;
          _state(InspectionVoicePhase.handling, t('saving'));
          _saving = true;
          saveAttempted = true;
          var saved = false;
          try {
            saved = await gateway.save(change);
          } finally {
            _saving = false;
            if (!_disposed) notifyListeners();
          }
          if (!current()) return;
          draft = null;
          await _finish(
            saved
                ? '${t("saved")}: ${voiceSettingValue(_currentValue(change.kind), expected)}.'
                : t('saveFailed'),
            generation,
            expected,
          );
          return;
        }
        final nextPage = switch (intent) {
          VoiceSettingsIntent.speech => VoiceSettingsPage.speech,
          VoiceSettingsIntent.appearance => VoiceSettingsPage.appearance,
          VoiceSettingsIntent.rate => VoiceSettingsPage.rate,
          VoiceSettingsIntent.volume => VoiceSettingsPage.volume,
          VoiceSettingsIntent.more => VoiceSettingsPage.moreThemes,
          _ => null,
        };
        if (nextPage != null) {
          page = nextPage;
          continue;
        }
        final snapshot = gateway.read();
        double step(double value, double delta, double min, double max) =>
            ((value + delta) * 10).roundToDouble().clamp(min * 10, max * 10) /
            10;
        final change = switch (intent) {
          VoiceSettingsIntent.slower => VoiceSettingChange.rate(
            step(snapshot.rate, -.1, kSpeechRateMin, kSpeechRateMax),
          ),
          VoiceSettingsIntent.faster => VoiceSettingChange.rate(
            step(snapshot.rate, .1, kSpeechRateMin, kSpeechRateMax),
          ),
          VoiceSettingsIntent.normal when page == VoiceSettingsPage.rate =>
            const VoiceSettingChange.rate(kSpeechRateDefault),
          VoiceSettingsIntent.normal => const VoiceSettingChange.volume(
            kTtsVolumeDefault,
          ),
          VoiceSettingsIntent.quieter => VoiceSettingChange.volume(
            step(snapshot.volume, -.1, kTtsVolumeMin, kTtsVolumeMax),
          ),
          VoiceSettingsIntent.louder => VoiceSettingChange.volume(
            step(snapshot.volume, .1, kTtsVolumeMin, kTtsVolumeMax),
          ),
          VoiceSettingsIntent.dark => const VoiceSettingChange.theme(
            BagdarThemeName.dark,
          ),
          VoiceSettingsIntent.light => const VoiceSettingChange.theme(
            BagdarThemeName.light,
          ),
          VoiceSettingsIntent.contrast => const VoiceSettingChange.theme(
            BagdarThemeName.highContrast,
          ),
          VoiceSettingsIntent.warm => const VoiceSettingChange.theme(
            BagdarThemeName.warm,
          ),
          _ => null,
        };
        if (change == null || !change.valid) return;
        _baseline = _currentValue(change.kind);
        if (_equal(change, _baseline!)) {
          if (!await _say(t('same'), generation, expected)) return;
          continue;
        }
        _draftOrigin = page;
        draft = change;
        page = VoiceSettingsPage.review;
      }
      if (current()) await _finish(t('limit'), generation, expected);
    } catch (_) {
      if (current()) {
        await _finish(
          saveAttempted
              ? t('saveFailed')
              : _inputText(InspectionVoiceCopy.unavailable),
          generation,
          expected,
        );
      }
    } finally {
      if (generation == _generation) {
        _deadline?.cancel();
        if (active) {
          final closed = await _close();
          if (closed && generation == _generation && !_disposed) {
            _state(
              InspectionVoicePhase.off,
              _inputText(InspectionVoiceCopy.interrupted),
            );
          }
        }
      }
    }
  }

  /// Revokes all pending answers immediately; persistence already in flight
  /// follows its own acknowledgement and is never labelled rolled back.
  Future<bool> interrupt({String? reason}) async {
    ++_generation;
    _deadline?.cancel();
    draft = null;
    _baseline = null;
    page = VoiceSettingsPage.menu;
    _state(
      InspectionVoicePhase.suspended,
      '${reason ?? _inputText(InspectionVoiceCopy.interrupted)}'
      '${_saving ? ' ${t("savePending")}' : ""}',
    );
    return _close();
  }

  Future<bool> stop() async {
    final closing = interrupt();
    final generation = _generation;
    final closed = await closing;
    if (closed && !_disposed && generation == _generation) {
      _state(
        InspectionVoicePhase.off,
        '${_saving ? '${t("savePending")} ' : ""}${t("off")}',
      );
    }
    return closed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _deadline?.cancel();
    unawaited(input.dispose());
    super.dispose();
  }
}
