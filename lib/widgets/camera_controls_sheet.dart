import 'package:flutter/material.dart';

import '../models/a11y_prefs.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/device_capability.dart';
import '../services/settings_service.dart';
import '../services/field_logger.dart';

class CameraSettingsSheet extends StatefulWidget {
  final AppLanguage currentLanguage;
  final bool useGpu;
  final bool useNativeDepthBridge;
  final bool useHardwareDepthMode;
  final int numThreads;
  
  final bool showDebugHud;
  final bool earconEnabled;
  final bool pitchBlackUiEnabled;
  final bool classicGestures;
  final double speechRate;
  final double ttsVolume;
  final double earconVolume;
  final Verbosity verbosity;
  final AlertFrequency alertFrequency;
  final HapticStrength hapticStrength;
  final SosTrigger sosTrigger;
  final DominantHand dominantHand;
  final DepthTier? depthTier;
  final bool midasReady;
  final String? sosContactNumber;

  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<bool> onUseGpuChanged;
  final ValueChanged<bool> onNativeDepthBridgeChanged;
  final ValueChanged<bool> onHardwareDepthModeChanged;
  final ValueChanged<int> onNumThreadsChanged;
  final ValueChanged<bool> onDebugHudChanged;
  final ValueChanged<bool> onEarconEnabledChanged;
  final ValueChanged<bool> onPitchBlackUiChanged;
  final ValueChanged<bool> onClassicGesturesChanged;
  final ValueChanged<double> onSpeechRateChanged;
  final ValueChanged<double> onTtsVolumeChanged;
  final ValueChanged<double> onEarconVolumeChanged;
  final ValueChanged<Verbosity> onVerbosityChanged;
  final ValueChanged<AlertFrequency> onAlertFrequencyChanged;
  final ValueChanged<HapticStrength> onHapticStrengthChanged;
  final ValueChanged<SosTrigger> onSosTriggerChanged;
  final ValueChanged<DominantHand> onDominantHandChanged;
  final VoidCallback onReplayTutorial;
  final VoidCallback onReadText;
  final VoidCallback onCalibrationTap;
  final VoidCallback onEditSosContact;
  final VoidCallback onScanLeft;
  final VoidCallback onScanCenter;
  final VoidCallback onScanRight;
  final VoidCallback onVoiceWarningTest;
  final VoidCallback onVoiceCriticalTest;
  final void Function(Earcon earcon) onPlayEarcon;
  final List<int> Function(String dist, String pos) patternFn;
  final List<int> Function(String dist, int len) intensFn;
  final Future<void> Function(List<int>, {List<int>? intensities}) vibrateFn;
  final VoidCallback? onViewWaypoints;
  final VoidCallback? onShowSettingsQr;
  final VoidCallback? onScanSettingsQr;

  const CameraSettingsSheet({
    super.key,
    required this.currentLanguage,
    required this.useGpu,
    required this.useNativeDepthBridge,
    required this.useHardwareDepthMode,
    required this.numThreads,
    required this.showDebugHud,
    required this.earconEnabled,
    required this.pitchBlackUiEnabled,
    required this.classicGestures,
    required this.speechRate,
    required this.ttsVolume,
    required this.earconVolume,
    required this.verbosity,
    required this.alertFrequency,
    required this.hapticStrength,
    required this.sosTrigger,
    required this.dominantHand,
    this.depthTier,
    required this.midasReady,
    required this.sosContactNumber,
    required this.onLanguageChanged,
    required this.onUseGpuChanged,
    required this.onNativeDepthBridgeChanged,
    required this.onHardwareDepthModeChanged,
    required this.onNumThreadsChanged,
    required this.onDebugHudChanged,
    required this.onEarconEnabledChanged,
    required this.onPitchBlackUiChanged,
    required this.onClassicGesturesChanged,
    required this.onSpeechRateChanged,
    required this.onTtsVolumeChanged,
    required this.onEarconVolumeChanged,
    required this.onVerbosityChanged,
    required this.onAlertFrequencyChanged,
    required this.onHapticStrengthChanged,
    required this.onSosTriggerChanged,
    required this.onDominantHandChanged,
    required this.onReplayTutorial,
    required this.onReadText,
    required this.onCalibrationTap,
    required this.onEditSosContact,
    required this.onScanLeft,
    required this.onScanCenter,
    required this.onScanRight,
    required this.onVoiceWarningTest,
    required this.onVoiceCriticalTest,
    required this.onPlayEarcon,
    required this.patternFn,
    required this.intensFn,
    required this.vibrateFn,
    this.onViewWaypoints,
    this.onShowSettingsQr,
    this.onScanSettingsQr,
  });

  @override
  State<CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<CameraSettingsSheet> {
  late AppLanguage _language;
  late bool _useGpu;
  late bool _useNativeDepthBridge;
  late bool _useHardwareDepthMode;
  late int _numThreads;
  late bool _showDebugHud;
  late bool _earconEnabled;
  late bool _pitchBlackUiEnabled;
  late bool _classicGestures;
  late double _speechRate;
  late double _ttsVolume;
  late double _earconVolume;
  late Verbosity _verbosity;
  late AlertFrequency _alertFrequency;
  late HapticStrength _hapticStrength;
  late SosTrigger _sosTrigger;
  late DominantHand _dominantHand;

  @override
  void initState() {
    super.initState();
    _language = widget.currentLanguage;
    _useGpu = widget.useGpu;
    _useNativeDepthBridge = widget.useNativeDepthBridge;
    _useHardwareDepthMode = widget.useHardwareDepthMode;
    _numThreads = widget.numThreads;
    _showDebugHud = widget.showDebugHud;
    _earconEnabled = widget.earconEnabled;
    _pitchBlackUiEnabled = widget.pitchBlackUiEnabled;
    _classicGestures = widget.classicGestures;
    _speechRate = widget.speechRate;
    _ttsVolume = widget.ttsVolume;
    _earconVolume = widget.earconVolume;
    _verbosity = widget.verbosity;
    _alertFrequency = widget.alertFrequency;
    _hapticStrength = widget.hapticStrength;
    _sosTrigger = widget.sosTrigger;
    _dominantHand = widget.dominantHand;
  }

  @override
  void didUpdateWidget(covariant CameraSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLanguage != widget.currentLanguage) {
      _language = widget.currentLanguage;
    }
    if (oldWidget.useGpu != widget.useGpu) {
      _useGpu = widget.useGpu;
    }
    if (oldWidget.useNativeDepthBridge != widget.useNativeDepthBridge) {
      _useNativeDepthBridge = widget.useNativeDepthBridge;
    }
    if (oldWidget.useHardwareDepthMode != widget.useHardwareDepthMode) {
      _useHardwareDepthMode = widget.useHardwareDepthMode;
    }
    if (oldWidget.numThreads != widget.numThreads) {
      _numThreads = widget.numThreads;
    }
    if (oldWidget.showDebugHud != widget.showDebugHud) {
      _showDebugHud = widget.showDebugHud;
    }
    if (oldWidget.earconEnabled != widget.earconEnabled) {
      _earconEnabled = widget.earconEnabled;
    }
    if (oldWidget.pitchBlackUiEnabled != widget.pitchBlackUiEnabled) {
      _pitchBlackUiEnabled = widget.pitchBlackUiEnabled;
    }
    if (oldWidget.classicGestures != widget.classicGestures) {
      _classicGestures = widget.classicGestures;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.get('settings'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Язык / Тіл',
              child: Row(
                children: [
                  const Text(
                    'Язык / Тіл',
                    style: TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  ToggleButtons(
                    borderRadius: BorderRadius.circular(8),
                    borderColor: Colors.white24,
                    selectedBorderColor: Colors.cyanAccent,
                    selectedColor: Colors.black,
                    fillColor: Colors.cyanAccent,
                    color: Colors.white70,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    isSelected: [
                      _language == AppLanguage.ru,
                      _language == AppLanguage.kk,
                      _language == AppLanguage.en,
                    ],
                    onPressed: (i) {
                      final lang = AppLanguage.values[i];
                      if (_language == lang) return;
                      setState(() => _language = lang);
                      widget.onLanguageChanged(lang);
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text('RU'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text('ҚЗ'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text('EN'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Использовать GPU: ${_useGpu ? "включено" : "выключено"}',
              child: SwitchListTile(
                title: const Text('GPU', style: TextStyle(color: Colors.white)),
                value: _useGpu,
                onChanged: (v) {
                  setState(() => _useGpu = v);
                  widget.onUseGpuChanged(v);
                },
              ),
            ),
            Semantics(
              label:
                  'Native depth bridge: ${_useNativeDepthBridge ? "включено" : "выключено"}',
              child: SwitchListTile(
                title: const Text(
                  'Native depth bridge',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'libyuv preprocessing before TFLite',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _useNativeDepthBridge,
                onChanged: (v) {
                  setState(() => _useNativeDepthBridge = v);
                  widget.onNativeDepthBridgeChanged(v);
                },
              ),
            ),
            Semantics(
              label:
                  'Hardware depth mode: ${_useHardwareDepthMode ? "включено" : "выключено"}',
              child: SwitchListTile(
                title: const Text(
                  'Hardware depth mode',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Pauses Flutter camera and starts ARCore / ARKit depth',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _useHardwareDepthMode,
                onChanged: (v) {
                  setState(() => _useHardwareDepthMode = v);
                  widget.onHardwareDepthModeChanged(v);
                },
              ),
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.cyanAccent,
              leading: const Icon(Icons.sensors, color: Colors.cyanAccent),
              title: Text(
                'Источник глубины: ${_depthTierText(widget.depthTier)}',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _depthTierSubtitle(widget.depthTier),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            Row(
              children: [
                const Text('CPU потоки', style: TextStyle(color: Colors.white)),
                const Spacer(),
                DropdownButton<int>(
                  dropdownColor: Colors.grey[850],
                  value: _numThreads,
                  style: const TextStyle(color: Colors.white),
                  items: [1, 2, 3, 4]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _numThreads = v);
                    widget.onNumThreadsChanged(v);
                  },
                ),
              ],
            ),
            Semantics(
              label: 'Показать отладку: ${_showDebugHud ? "вкл" : "выкл"}',
              child: SwitchListTile(
                title: const Text(
                  'Debug HUD',
                  style: TextStyle(color: Colors.white),
                ),
                value: _showDebugHud,
                onChanged: (v) {
                  setState(() => _showDebugHud = v);
                  widget.onDebugHudChanged(v);
                },
              ),
            ),
            SwitchListTile(
              title: const Text(
                'Field Logging',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                FieldLogger.instance.active
                    ? 'Recording... (${FieldLogger.instance.eventCount} events)'
                    : 'Record pipeline events for analysis',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: FieldLogger.instance.active,
              activeColor: Colors.greenAccent,
              onChanged: (v) async {
                if (v) {
                  await Settings.instance.setFieldLogging(true);
                  final caps = DeviceCapabilityProbe.cached;
                  await FieldLogger.instance.startSession(
                    deviceModel: caps.deviceInfo.model,
                    androidSdk: caps.androidSdkInt,
                    depthTier: caps.bestDepthTier.name,
                  );
                } else {
                  await Settings.instance.setFieldLogging(false);
                  await FieldLogger.instance.stopSession();
                }
                if (context.mounted) setState(() {});
              },
            ),
            Semantics(
              label: 'Звуковые сигналы: ${_earconEnabled ? "вкл" : "выкл"}',
              child: SwitchListTile(
                title: const Text(
                  'Звуковые сигналы',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Мгновенные тоны для событий',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _earconEnabled,
                onChanged: (v) {
                  setState(() => _earconEnabled = v);
                  widget.onEarconEnabledChanged(v);
                  if (v) widget.onPlayEarcon(Earcon.success);
                },
              ),
            ),
            Semantics(
              label:
                  '${S.get('pitch_black_ui')}: ${_pitchBlackUiEnabled ? S.get('pitch_black_on') : S.get('pitch_black_off')}',
              child: SwitchListTile(
                title: Text(
                  S.get('pitch_black_ui'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  S.get('pitch_black_ui_desc'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _pitchBlackUiEnabled,
                onChanged: (v) {
                  setState(() => _pitchBlackUiEnabled = v);
                  widget.onPitchBlackUiChanged(v);
                },
              ),
            ),
            const Divider(color: Colors.white24, height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  S.get('settings_a11y_title'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            Semantics(
              label:
                  '${S.get('settings_classic_gestures')}: ${_classicGestures ? "вкл" : "выкл"}',
              child: SwitchListTile(
                title: Text(
                  S.get('settings_classic_gestures'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  S.get('settings_classic_gestures_desc'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: _classicGestures,
                onChanged: (v) {
                  setState(() => _classicGestures = v);
                  widget.onClassicGesturesChanged(v);
                },
              ),
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.cyanAccent,
              leading: const Icon(Icons.replay, color: Colors.cyanAccent),
              title: Text(S.get('tut_replay')),
              onTap: () {
                Navigator.pop(context);
                widget.onReplayTutorial();
              },
            ),
            _SliderRow(
              label: S.get('settings_speech_rate'),
              value: _speechRate,
              min: kSpeechRateMin,
              max: kSpeechRateMax,
              divisions: 9,
              suffix: 'x',
              onChanged: (v) {
                setState(() => _speechRate = v);
                widget.onSpeechRateChanged(v);
              },
            ),
            _SliderRow(
              label: S.get('settings_tts_volume'),
              value: _ttsVolume,
              min: kTtsVolumeMin,
              max: kTtsVolumeMax,
              divisions: 10,
              asPercent: true,
              onChanged: (v) {
                setState(() => _ttsVolume = v);
                widget.onTtsVolumeChanged(v);
              },
            ),
            _SliderRow(
              label: S.get('settings_earcon_volume'),
              value: _earconVolume,
              min: kEarconVolumeMin,
              max: kEarconVolumeMax,
              divisions: 10,
              asPercent: true,
              onChanged: (v) {
                setState(() => _earconVolume = v);
                widget.onEarconVolumeChanged(v);
              },
            ),
            _EnumDropdownRow<Verbosity>(
              label: S.get('settings_verbosity'),
              value: _verbosity,
              values: Verbosity.values,
              labelFor: (v) => S.get(
                'verbosity_${v.name.toLowerCase()}',
              ),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _verbosity = v);
                widget.onVerbosityChanged(v);
              },
            ),
            _EnumDropdownRow<AlertFrequency>(
              label: S.get('settings_alert_frequency'),
              value: _alertFrequency,
              values: AlertFrequency.values,
              labelFor: (v) => S.get('freq_${v.name}'),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _alertFrequency = v);
                widget.onAlertFrequencyChanged(v);
              },
            ),
            _EnumDropdownRow<HapticStrength>(
              label: S.get('settings_haptic_strength'),
              value: _hapticStrength,
              values: HapticStrength.values,
              labelFor: (v) => S.get('haptic_${v.name}'),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _hapticStrength = v);
                widget.onHapticStrengthChanged(v);
              },
            ),
            _EnumDropdownRow<SosTrigger>(
              label: S.get('settings_sos_trigger'),
              value: _sosTrigger,
              values: SosTrigger.values,
              labelFor: (v) {
                switch (v) {
                  case SosTrigger.twoFingerHold:
                    return S.get('sos_trigger_two_finger');
                  case SosTrigger.tripleTap:
                    return S.get('sos_trigger_triple_tap');
                  case SosTrigger.shake:
                    return S.get('sos_trigger_shake');
                }
              },
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sosTrigger = v);
                widget.onSosTriggerChanged(v);
              },
            ),
            _EnumDropdownRow<DominantHand>(
              label: S.get('settings_dominant_hand'),
              value: _dominantHand,
              values: DominantHand.values,
              labelFor: (v) => S.get('hand_${v.name}'),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _dominantHand = v);
                widget.onDominantHandChanged(v);
              },
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: widget.midasReady ? Colors.cyanAccent : Colors.white38,
              leading: Icon(
                widget.midasReady ? Icons.layers : Icons.layers_outlined,
                color: widget.midasReady ? Colors.cyanAccent : Colors.white38,
              ),
              title: Text(
                widget.midasReady
                    ? 'Анализ глубины: активен'
                    : 'Анализ глубины: не готов',
                style: TextStyle(
                  color: widget.midasReady ? Colors.white : Colors.white38,
                ),
              ),
              subtitle: Text(
                _depthTierSubtitle(widget.depthTier),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            const Divider(color: Colors.white24, height: 20),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.cyanAccent,
              leading: const Icon(Icons.text_fields, color: Colors.cyanAccent),
              title: const Text('Прочитать текст'),
              subtitle: const Text(
                'OCR — распознавание текста в кадре',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onReadText();
              },
            ),
            const Divider(color: Colors.white24, height: 20),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.lightBlueAccent,
              leading: const Icon(
                Icons.straighten,
                color: Colors.lightBlueAccent,
              ),
              title: const Text('Калибровка камеры'),
              subtitle: const Text(
                'Встаньте точно на 2 м от человека и нажмите',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onCalibrationTap();
              },
            ),
            const Divider(color: Colors.white24, height: 20),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.redAccent,
              leading: const Icon(Icons.sos, color: Colors.redAccent),
              title: Text(S.get('sos_settings')),
              subtitle: Text(
                widget.sosContactNumber ?? 'Не задан',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onEditSosContact();
              },
            ),
            if (widget.onShowSettingsQr != null ||
                widget.onScanSettingsQr != null) ...[
              const Divider(color: Colors.white24, height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 16,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    S.get('backup_section_title'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              if (widget.onShowSettingsQr != null)
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.cyanAccent,
                  leading: const Icon(
                    Icons.qr_code_2,
                    color: Colors.cyanAccent,
                  ),
                  title: Text(S.get('backup_show_qr')),
                  subtitle: Text(
                    S.get('backup_show_qr_subtitle'),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onShowSettingsQr!();
                  },
                ),
              if (widget.onScanSettingsQr != null)
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.cyanAccent,
                  leading: const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.cyanAccent,
                  ),
                  title: Text(S.get('backup_scan_qr')),
                  subtitle: Text(
                    S.get('backup_scan_qr_subtitle'),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onScanSettingsQr!();
                  },
                ),
            ],
            const Divider(color: Colors.white24, height: 20),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.white70,
              title: const Text('Что слева?'),
              trailing: const Icon(Icons.arrow_back),
              onTap: () {
                Navigator.pop(context);
                widget.onScanLeft();
              },
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.white70,
              title: const Text('Что впереди?'),
              trailing: const Icon(Icons.arrow_upward),
              onTap: () {
                Navigator.pop(context);
                widget.onScanCenter();
              },
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.white70,
              title: const Text('Что справа?'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.pop(context);
                widget.onScanRight();
              },
            ),
            const Divider(color: Colors.white24, height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                'Тест вибрации (режим Трость)',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _HapticTestButton(
                  label: '← Влево',
                  dist: 'close',
                  pos: 'left',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                ),
                _HapticTestButton(
                  label: '↑ Центр',
                  dist: 'close',
                  pos: 'center',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                ),
                _HapticTestButton(
                  label: 'Вправо →',
                  dist: 'close',
                  pos: 'right',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _HapticTestButton(
                  label: '! Влево',
                  dist: 'very close',
                  pos: 'left',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                  danger: true,
                ),
                _HapticTestButton(
                  label: '! Центр',
                  dist: 'very close',
                  pos: 'center',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                  danger: true,
                ),
                _HapticTestButton(
                  label: 'Вправо !',
                  dist: 'very close',
                  pos: 'right',
                  patternFn: widget.patternFn,
                  intensFn: widget.intensFn,
                  vibrateFn: widget.vibrateFn,
                  danger: true,
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                'Тест звуковых сигналов',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _EarconTestButton(
                  label: 'Появился',
                  earcon: Earcon.objectAppeared,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Ушёл',
                  earcon: Earcon.objectLeft,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Путь свободен',
                  earcon: Earcon.pathClear,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Приближается',
                  earcon: Earcon.approaching,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Улица',
                  earcon: Earcon.modeStreet,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Трость',
                  earcon: Earcon.modeCane,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Скан',
                  earcon: Earcon.modeScan,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Успех',
                  earcon: Earcon.success,
                  onPlay: widget.onPlayEarcon,
                ),
                _EarconTestButton(
                  label: 'Ошибка',
                  earcon: Earcon.fail,
                  onPlay: widget.onPlayEarcon,
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            if (widget.onViewWaypoints != null)
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.orangeAccent,
                leading: const Icon(Icons.place),
                
                title: Text(S.get('waypoint_name_prompt')),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onViewWaypoints!();
                },
              ),
            const Divider(color: Colors.white24, height: 20),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.white54,
              title: const Text('Тест: Внимание (Слева)'),
              trailing: const Icon(Icons.volume_up),
              onTap: () {
                Navigator.pop(context);
                widget.onVoiceWarningTest();
              },
            ),
            ListTile(
              textColor: Colors.white,
              iconColor: Colors.orange,
              title: const Text('Тест: Критично (По центру)'),
              trailing: const Icon(Icons.warning_amber),
              onTap: () {
                Navigator.pop(context);
                widget.onVoiceCriticalTest();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _depthTierText(DepthTier? tier) {
    switch (tier) {
      case DepthTier.hardware:
        return 'ARCore / LiDAR';
      case DepthTier.midasNnapi:
        return 'MiDaS + NNAPI';
      case DepthTier.midasCpu:
        return 'MiDaS + CPU';
      case DepthTier.focalLength:
        return 'Fallback по фокусному расстоянию';
      case null:
        return 'не определён';
    }
  }

  String _depthTierSubtitle(DepthTier? tier) {
    switch (tier) {
      case DepthTier.hardware:
        return 'Нативная глубина с устройства';
      case DepthTier.midasNnapi:
        return 'MiDaS fallback выполняется через NNAPI';
      case DepthTier.midasCpu:
        return 'MiDaS fallback выполняется на CPU';
      case DepthTier.focalLength:
        return 'Нет depth API — используется оценка по калибровке';
      case null:
        return 'Источник глубины будет выбран автоматически';
    }
  }
}

class CameraCalibrationDialog extends StatefulWidget {
  final String title;
  final String description;
  final String labelText;
  final String saveLabel;
  final String cancelLabel;
  final String initialValue;

  const CameraCalibrationDialog({
    super.key,
    this.title = 'Калибровка расстояния',
    this.description =
        'Введите точное расстояние до человека в кадре (в метрах).',
    this.labelText = 'Расстояние (м)',
    this.saveLabel = 'Сохранить',
    this.cancelLabel = 'Отмена',
    this.initialValue = '2.0',
  });

  @override
  State<CameraCalibrationDialog> createState() =>
      _CameraCalibrationDialogState();
}

class _CameraCalibrationDialogState extends State<CameraCalibrationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: widget.labelText,
              labelStyle: const TextStyle(color: Colors.white54),
              suffixText: 'м',
              suffixStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white30),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.cancelLabel,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(
            widget.saveLabel,
            style: const TextStyle(color: Colors.cyanAccent),
          ),
        ),
      ],
    );
  }
}

class _EarconTestButton extends StatelessWidget {
  final String label;
  final Earcon earcon;
  final void Function(Earcon earcon) onPlay;

  const _EarconTestButton({
    required this.label,
    required this.earcon,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Тест earcon: $label',
      child: GestureDetector(
        onTap: () => onPlay(earcon),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 0.5),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final bool asPercent;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.suffix = '',
    this.asPercent = false,
    required this.onChanged,
  });

  String _format(double v) {
    if (asPercent) return '${(v * 100).round()}%';
    return '${v.toStringAsFixed(1)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${_format(value)}',
      slider: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white24,
                label: _format(value),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _format(value),
                textAlign: TextAlign.end,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnumDropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T?> onChanged;

  const _EnumDropdownRow({
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${labelFor(value)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            DropdownButton<T>(
              dropdownColor: Colors.grey[850],
              value: value,
              style: const TextStyle(color: Colors.white),
              underline: Container(height: 1, color: Colors.white24),
              items: values
                  .map(
                    (v) => DropdownMenuItem<T>(
                      value: v,
                      child: Text(labelFor(v)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _HapticTestButton extends StatelessWidget {
  final String label;
  final String dist;
  final String pos;
  final bool danger;
  final List<int> Function(String dist, String pos) patternFn;
  final List<int> Function(String dist, int len) intensFn;
  final Future<void> Function(List<int>, {List<int>? intensities}) vibrateFn;

  const _HapticTestButton({
    required this.label,
    required this.dist,
    required this.pos,
    required this.patternFn,
    required this.intensFn,
    required this.vibrateFn,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.orangeAccent : Colors.cyanAccent;
    return Semantics(
      button: true,
      label: 'Тест вибрации: $label',
      child: GestureDetector(
        onTap: () {
          final pattern = patternFn(dist, pos);
          final intensities = intensFn(dist, pattern.length);
          vibrateFn(pattern, intensities: intensities);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.06),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
