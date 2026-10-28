import '../../models/strings.dart';
import '../../theme/bagdar_theme.dart';
import '../settings_service.dart';
import '../tts_service.dart';
import 'voice_settings.dart';

class NativeVoiceSettingsGateway implements VoiceSettingsGateway {
  final Settings settings;
  final TtsService tts;
  final bool Function() earconEnabled;
  NativeVoiceSettingsGateway({
    required this.settings,
    required this.tts,
    required this.earconEnabled,
  });

  @override
  VoiceSettingsSnapshot read() => VoiceSettingsSnapshot(
    rate: settings.speechRate,
    volume: settings.ttsVolume,
    theme: settings.themeMode,
    language: S.current,
    haptics: settings.hapticStrength,
    earconEnabled: earconEnabled(),
    earconVolume: settings.earconVolume,
  );

  @override
  Future<bool> save(VoiceSettingChange change) async {
    if (!settings.isReady || !change.valid) return false;
    switch (change.kind) {
      case VoiceSettingKind.rate:
        if (!await settings.saveVoiceSpeechRate(change.number!)) return false;
        await tts.setUserRate(settings.speechRate);
      case VoiceSettingKind.volume:
        if (!await settings.saveVoiceSpeechVolume(change.number!)) return false;
        await tts.setUserVolume(settings.ttsVolume);
      case VoiceSettingKind.theme:
        if (!await settings.saveVoiceTheme(change.theme!)) return false;
        bagdarThemeNotifier.value = settings.themeMode;
    }
    return true;
  }
}
