import 'dart:async';
import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/voice_settings.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';

class FakeVoiceSettingsGateway implements VoiceSettingsGateway {
  double rate = 1;
  double volume = .8;
  BagdarThemeName theme = BagdarThemeName.dark;
  AppLanguage language = AppLanguage.ru;
  final writes = <VoiceSettingChange>[];
  bool acknowledgement = true;
  bool throwOnSave = false;
  Completer<bool>? pendingSave;
  @override
  VoiceSettingsSnapshot read() => VoiceSettingsSnapshot(
    rate: rate,
    volume: volume,
    theme: theme,
    language: language,
    haptics: HapticStrength.normal,
    earconEnabled: true,
    earconVolume: .85,
  );
  @override
  Future<bool> save(VoiceSettingChange change) async {
    writes.add(change);
    if (throwOnSave) throw StateError('write_failed');
    final saved = pendingSave == null
        ? acknowledgement
        : await pendingSave!.future;
    if (saved) {
      switch (change.kind) {
        case VoiceSettingKind.rate:
          rate = change.number!;
        case VoiceSettingKind.volume:
          volume = change.number!;
        case VoiceSettingKind.theme:
          theme = change.theme!;
      }
    }
    return saved;
  }
}
