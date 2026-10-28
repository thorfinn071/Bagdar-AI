import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/services/voice/native_voice_settings_gateway.dart';
import 'package:bagdar/services/voice/voice_settings.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AckSettings implements Settings {
  bool ack = true;
  final writes = <VoiceSettingChange>[];
  @override
  bool get isReady => true;
  @override
  double speechRate = 1;
  @override
  double ttsVolume = .8;
  @override
  BagdarThemeName themeMode = BagdarThemeName.dark;
  @override
  HapticStrength get hapticStrength => HapticStrength.normal;
  @override
  double get earconVolume => .85;
  @override
  Future<bool> saveVoiceSpeechRate(double value) async {
    writes.add(VoiceSettingChange.rate(value));
    if (ack) speechRate = value;
    return ack;
  }

  @override
  Future<bool> saveVoiceSpeechVolume(double value) async {
    writes.add(VoiceSettingChange.volume(value));
    if (ack) ttsVolume = value;
    return ack;
  }

  @override
  Future<bool> saveVoiceTheme(BagdarThemeName value) async {
    writes.add(VoiceSettingChange.theme(value));
    if (ack) themeMode = value;
    return ack;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SettingsTts extends TtsService {
  final rates = <double>[], volumes = <double>[];
  SettingsTts() : super.forTesting();
  @override
  Future<void> setUserRate(double value) async {
    rates.add(value);
  }

  @override
  Future<void> setUserVolume(double value) async {
    volumes.add(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AckSettings settings;
  late SettingsTts tts;
  late NativeVoiceSettingsGateway gateway;
  setUp(() {
    settings = AckSettings();
    tts = SettingsTts();
    bagdarThemeNotifier.value = BagdarThemeName.dark;
    gateway = NativeVoiceSettingsGateway(
      settings: settings,
      tts: tts,
      earconEnabled: () => true,
    );
  });
  for (final ack in [true, false]) {
    test('speech rate runtime apply follows persistence ack $ack', () async {
      settings.ack = ack;
      expect(await gateway.save(const VoiceSettingChange.rate(1.2)), ack);
      expect(tts.rates, ack ? [1.2] : isEmpty);
    });
    test('speech volume runtime apply follows persistence ack $ack', () async {
      settings.ack = ack;
      expect(await gateway.save(const VoiceSettingChange.volume(.7)), ack);
      expect(tts.volumes, ack ? [.7] : isEmpty);
    });
    test('theme publication follows persistence ack $ack', () async {
      settings.ack = ack;
      expect(
        await gateway.save(
          const VoiceSettingChange.theme(BagdarThemeName.light),
        ),
        ack,
      );
      expect(
        bagdarThemeNotifier.value,
        ack ? BagdarThemeName.light : BagdarThemeName.dark,
      );
    });
  }
  for (final change in [
    const VoiceSettingChange.rate(.5),
    const VoiceSettingChange.rate(1.6),
    const VoiceSettingChange.volume(.4),
    const VoiceSettingChange.volume(1.1),
    const VoiceSettingChange.rate(double.nan),
    const VoiceSettingChange.volume(double.infinity),
  ]) {
    test('reject invalid setting ${change.kind} ${change.number}', () async {
      expect(await gateway.save(change), isFalse);
      expect(settings.writes, isEmpty);
      expect(tts.rates, isEmpty);
      expect(tts.volumes, isEmpty);
    });
  }
  test(
    'production preference storage preserves confirmed rate, volume and theme',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.init();
      final native = NativeVoiceSettingsGateway(
        settings: Settings.instance,
        tts: tts,
        earconEnabled: () => false,
      );
      expect(await native.save(const VoiceSettingChange.rate(1.2)), isTrue);
      expect(await native.save(const VoiceSettingChange.volume(.6)), isTrue);
      expect(
        await native.save(
          const VoiceSettingChange.theme(BagdarThemeName.highContrast),
        ),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('a11y_speech_rate'), 1.2);
      expect(Settings.instance.speechRate, 1.2);
      expect(Settings.instance.ttsVolume, .6);
      expect(Settings.instance.themeMode, BagdarThemeName.highContrast);
      expect(native.read().earconEnabled, isFalse);
      expect(native.read().haptics, HapticStrength.normal);
    },
  );
}
