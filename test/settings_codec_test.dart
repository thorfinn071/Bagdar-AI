import 'dart:convert';

import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/services/settings_codec.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
  });

  group('SettingsCodec', () {
    test('exportToMap includes schema version and core a11y fields', () {
      final map = SettingsCodec.instance.exportToMap();
      expect(map['v'], SettingsCodec.schemaVersion);
      expect(map.containsKey('lang'), isTrue);
      expect(map.containsKey('speech_rate'), isTrue);
      expect(map.containsKey('tts_volume'), isTrue);
      expect(map.containsKey('earcon_volume'), isTrue);
      expect(map.containsKey('verbosity'), isTrue);
      expect(map.containsKey('alert_freq'), isTrue);
      expect(map.containsKey('haptic'), isTrue);
      expect(map.containsKey('sos_trigger'), isTrue);
      expect(map.containsKey('hand'), isTrue);
      expect(map.containsKey('classic_gestures'), isTrue);
      expect(map.containsKey('pitch_black'), isTrue);
      expect(map.containsKey('guide_dog'), isTrue);
    });

    test('payload never leaks SOS contact', () {
      final json = SettingsCodec.instance.exportToJson();
      expect(json.contains('contact'), isFalse);
      expect(json.contains('phone'), isFalse);
      expect(json.contains('sos_contact'), isFalse);
    });

    test('payload fits comfortably under QR version 5 size limit', () {
      
      
      final json = SettingsCodec.instance.exportToJson();
      expect(json.length, lessThan(300));
    });

    test('round-trip preserves all exported fields', () async {
      final s = Settings.instance;
      await s.setLanguage(1);
      await s.setSpeechRate(1.3);
      await s.setTtsVolume(0.8);
      await s.setEarconVolume(0.7);
      await s.setVerbosity(Verbosity.detailed);
      await s.setAlertFrequency(AlertFrequency.frequent);
      await s.setHapticStrength(HapticStrength.strong);
      await s.setSosTrigger(SosTrigger.shake);
      await s.setDominantHand(DominantHand.left);
      await s.setClassicGestures(true);
      await s.setPitchBlackUi(true);
      await s.setGuideDogMode(true);

      final json = SettingsCodec.instance.exportToJson();

      
      SharedPreferences.setMockInitialValues({});
      await Settings.instance.init();

      final ok = await SettingsCodec.instance.importFromJson(json);
      expect(ok, isTrue);

      final t = Settings.instance;
      expect(t.language, 1);
      expect(t.speechRate, closeTo(1.3, 0.01));
      expect(t.ttsVolume, closeTo(0.8, 0.01));
      expect(t.earconVolume, closeTo(0.7, 0.01));
      expect(t.verbosity, Verbosity.detailed);
      expect(t.alertFrequency, AlertFrequency.frequent);
      expect(t.hapticStrength, HapticStrength.strong);
      expect(t.sosTrigger, SosTrigger.shake);
      expect(t.dominantHand, DominantHand.left);
      expect(t.classicGestures, isTrue);
      expect(t.pitchBlackUi, isTrue);
      expect(t.guideDogMode, isTrue);
    });

    test('rejects unknown schema version', () async {
      final ok = await SettingsCodec.instance.importFromJson(
        jsonEncode({'v': 99, 'lang': 1}),
      );
      expect(ok, isFalse);
    });

    test('rejects malformed JSON', () async {
      expect(
        await SettingsCodec.instance.importFromJson('not-json'),
        isFalse,
      );
      expect(
        await SettingsCodec.instance.importFromJson('[1,2,3]'),
        isFalse,
      );
      expect(
        await SettingsCodec.instance.importFromJson(''),
        isFalse,
      );
    });

    test('clamps out-of-range numeric/enum fields', () async {
      final json = jsonEncode({
        'v': SettingsCodec.schemaVersion,
        'lang': 99,
        'speech_rate': 99.0,
        'tts_volume': -1.0,
        'earcon_volume': 5.0,
        'verbosity': 99,
        'alert_freq': -2,
        'haptic': 100,
        'sos_trigger': 100,
        'hand': 100,
      });
      final ok = await SettingsCodec.instance.importFromJson(json);
      expect(ok, isTrue);

      final t = Settings.instance;
      expect(t.language, 2); 
      expect(t.speechRate, kSpeechRateMax);
      expect(t.ttsVolume, kTtsVolumeMin);
      expect(t.earconVolume, kEarconVolumeMax);
      expect(t.verbosity, Verbosity.values.last);
      expect(t.alertFrequency, AlertFrequency.values.first);
      expect(t.hapticStrength, HapticStrength.values.last);
      expect(t.sosTrigger, SosTrigger.values.last);
      expect(t.dominantHand, DominantHand.values.last);
    });

    test('ignores unknown keys without failing import', () async {
      final json = jsonEncode({
        'v': SettingsCodec.schemaVersion,
        'mystery_key': 'oops',
        'haptic': HapticStrength.weak.index,
      });
      final ok = await SettingsCodec.instance.importFromJson(json);
      expect(ok, isTrue);
      expect(Settings.instance.hapticStrength, HapticStrength.weak);
    });

    test('peek returns parsed map for valid payload', () {
      final json = jsonEncode({
        'v': SettingsCodec.schemaVersion,
        'lang': 0,
      });
      final preview = SettingsCodec.instance.peek(json);
      expect(preview, isNotNull);
      expect(preview!['lang'], 0);
    });

    test('peek returns null for invalid version', () {
      final json = jsonEncode({'v': 42});
      expect(SettingsCodec.instance.peek(json), isNull);
    });
  });
}
