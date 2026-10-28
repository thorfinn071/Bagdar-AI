import 'package:flutter/material.dart';

import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';

import '../models/a11y_prefs.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/device_capability.dart';
import '../services/settings_service.dart';
import '../services/field_logger.dart';
import 'a11y/stepper_field.dart';
import 'bagdar_ui.dart';

class CameraSettingsSheet extends StatefulWidget {
  final AppLanguage currentLanguage;
  final bool useGpu;
  final bool useNativeDepthBridge;
  final bool useHardwareDepthMode;
  final bool showIndependentHardwareDepth;
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
    this.showIndependentHardwareDepth = false,
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
  late bool _clearPathAnnounce;
  late bool _batteryAnnounce;
  late bool _modeAnnounce;

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
    _clearPathAnnounce = Settings.instance.clearPathAnnounce;
    _batteryAnnounce = Settings.instance.batteryAnnounce;
    _modeAnnounce = Settings.instance.modeAnnounce;
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
    final colors = BagdarTheme.colorsOf(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: BagdarSpacing.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.get('settings'),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: BagdarSpacing.m),
                _EnumDropdownRow<BagdarThemeName>(
                  label: S.get('appearance_title'),
                  value:
                      BagdarTheme.maybeOf(context)?.name ??
                      bagdarThemeNotifier.value,
                  values: BagdarThemeName.values,
                  labelFor: (name) => S.get('theme_${name.id}'),
                  onChanged: (name) async {
                    if (name == null) return;
                    await setBagdarTheme(name);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: S.get('settings_lang_label'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        S.get('settings_lang_label'),
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      ToggleButtons(
                        constraints: const BoxConstraints(
                          minWidth: 64,
                          minHeight: 64,
                        ),
                        borderRadius: BorderRadius.circular(
                          BagdarRadius.control,
                        ),
                        borderColor: colors.divider,
                        selectedBorderColor: colors.accentPrimary,
                        selectedColor: colors.accentOnPrimary,
                        fillColor: colors.accentPrimary,
                        color: colors.textSecondary,
                        textStyle: BagdarTypography.caption.copyWith(
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
                  label:
                      '${S.get('settings_earcon_title')}: ${_earconEnabled ? S.get('sem_on') : S.get('sem_off')}',
                  child: SwitchListTile(
                    title: Text(
                      S.get('settings_earcon_title'),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      S.get('settings_earcon_desc'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
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
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      S.get('pitch_black_ui_desc'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    value: _pitchBlackUiEnabled,
                    onChanged: (v) {
                      setState(() => _pitchBlackUiEnabled = v);
                      widget.onPitchBlackUiChanged(v);
                    },
                  ),
                ),
                Divider(color: colors.divider, height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 16,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      S.get('settings_a11y_title'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label:
                      '${S.get('settings_classic_gestures')}: ${_classicGestures ? S.get('sem_on') : S.get('sem_off')}',
                  child: SwitchListTile(
                    title: Text(
                      S.get('settings_classic_gestures'),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      S.get('settings_classic_gestures_desc'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    value: _classicGestures,
                    onChanged: (v) {
                      setState(() => _classicGestures = v);
                      widget.onClassicGesturesChanged(v);
                    },
                  ),
                ),
                Semantics(
                  label: S.get('pref_clear_path_announce'),
                  child: SwitchListTile(
                    title: Text(
                      S.get('pref_clear_path_announce'),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _clearPathAnnounce,
                    onChanged: (v) {
                      setState(() => _clearPathAnnounce = v);
                      Settings.instance.setClearPathAnnounce(v);
                    },
                  ),
                ),
                Semantics(
                  label: S.get('pref_battery_announce'),
                  child: SwitchListTile(
                    title: Text(
                      S.get('pref_battery_announce'),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _batteryAnnounce,
                    onChanged: (v) {
                      setState(() => _batteryAnnounce = v);
                      Settings.instance.setBatteryAnnounce(v);
                    },
                  ),
                ),
                Semantics(
                  label: S.get('pref_mode_announce'),
                  child: SwitchListTile(
                    title: Text(
                      S.get('pref_mode_announce'),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _modeAnnounce,
                    onChanged: (v) {
                      setState(() => _modeAnnounce = v);
                      Settings.instance.setModeAnnounce(v);
                    },
                  ),
                ),
                Semantics(
                  label: S.get('tut_replay'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.accentPrimary,
                    leading: Icon(Icons.replay, color: colors.accentPrimary),
                    title: Text(S.get('tut_replay')),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onReplayTutorial();
                    },
                  ),
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
                  labelFor: (v) => S.get('verbosity_${v.name.toLowerCase()}'),
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
                Semantics(
                  label: widget.midasReady
                      ? S.get('settings_depth_active')
                      : S.get('settings_depth_not_ready'),
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: widget.midasReady
                        ? colors.accentPrimary
                        : colors.textSecondary,
                    leading: Icon(
                      widget.midasReady ? Icons.layers : Icons.layers_outlined,
                      color: widget.midasReady
                          ? colors.accentPrimary
                          : colors.textSecondary,
                    ),
                    title: Text(
                      widget.midasReady
                          ? S.get('settings_depth_active')
                          : S.get('settings_depth_not_ready'),
                      style: TextStyle(
                        color: widget.midasReady
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                    subtitle: Text(
                      _depthTierSubtitle(widget.depthTier),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                Divider(color: colors.divider, height: 20),
                Semantics(
                  label: S.get('settings_read_text'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.accentPrimary,
                    leading: Icon(
                      Icons.text_fields,
                      color: colors.accentPrimary,
                    ),
                    title: Text(S.get('settings_read_text')),
                    subtitle: Text(
                      S.get('settings_read_text_desc'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onReadText();
                    },
                  ),
                ),
                Divider(color: colors.divider, height: 20),
                Semantics(
                  label: S.get('settings_calibration'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.accentPrimary,
                    leading: Icon(
                      Icons.straighten,
                      color: colors.accentPrimary,
                    ),
                    title: Text(S.get('settings_calibration')),
                    subtitle: Text(
                      S.get('settings_calibration_desc'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onCalibrationTap();
                    },
                  ),
                ),
                Divider(color: colors.divider, height: 20),
                Semantics(
                  label: S.get('sos_settings'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.stateDanger,
                    leading: Icon(Icons.sos, color: colors.stateDanger),
                    title: Text(S.get('sos_settings')),
                    subtitle: Text(
                      widget.sosContactNumber ?? S.get('settings_sos_not_set'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onEditSosContact();
                    },
                  ),
                ),
                if (widget.onShowSettingsQr != null ||
                    widget.onScanSettingsQr != null) ...[
                  Divider(color: colors.divider, height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        S.get('backup_section_title'),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onShowSettingsQr != null)
                    Semantics(
                      label: S.get('backup_show_qr'),
                      button: true,
                      child: ListTile(
                        textColor: colors.textPrimary,
                        iconColor: colors.accentPrimary,
                        leading: Icon(
                          Icons.qr_code_2,
                          color: colors.accentPrimary,
                        ),
                        title: Text(S.get('backup_show_qr')),
                        subtitle: Text(
                          S.get('backup_show_qr_subtitle'),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onShowSettingsQr!();
                        },
                      ),
                    ),
                  if (widget.onScanSettingsQr != null)
                    Semantics(
                      label: S.get('backup_scan_qr'),
                      button: true,
                      child: ListTile(
                        textColor: colors.textPrimary,
                        iconColor: colors.accentPrimary,
                        leading: Icon(
                          Icons.qr_code_scanner,
                          color: colors.accentPrimary,
                        ),
                        title: Text(S.get('backup_scan_qr')),
                        subtitle: Text(
                          S.get('backup_scan_qr_subtitle'),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onScanSettingsQr!();
                        },
                      ),
                    ),
                ],
                Divider(color: colors.divider, height: 20),
                Semantics(
                  label: S.get('settings_scan_left'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.textSecondary,
                    title: Text(S.get('settings_scan_left')),
                    trailing: const Icon(Icons.arrow_back),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onScanLeft();
                    },
                  ),
                ),
                Semantics(
                  label: S.get('settings_scan_forward'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.textSecondary,
                    title: Text(S.get('settings_scan_forward')),
                    trailing: const Icon(Icons.arrow_upward),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onScanCenter();
                    },
                  ),
                ),
                Semantics(
                  label: S.get('settings_scan_right'),
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.textSecondary,
                    title: Text(S.get('settings_scan_right')),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onScanRight();
                    },
                  ),
                ),
                Divider(color: colors.divider, height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 16,
                  ),
                  child: Text(
                    S.get('settings_haptic_test'),
                    style: TextStyle(color: colors.textSecondary, fontSize: 16),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HapticTestButton(
                      label: '← ${S.get('nav_left')}',
                      dist: 'close',
                      pos: 'left',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                    ),
                    _HapticTestButton(
                      label: '↑ ${S.get('straight')}',
                      dist: 'close',
                      pos: 'center',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                    ),
                    _HapticTestButton(
                      label: '${S.get('nav_right')} →',
                      dist: 'close',
                      pos: 'right',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HapticTestButton(
                      label: '! ${S.get('nav_left')}',
                      dist: 'very close',
                      pos: 'left',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                      danger: true,
                    ),
                    _HapticTestButton(
                      label: '! ${S.get('straight')}',
                      dist: 'very close',
                      pos: 'center',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                      danger: true,
                    ),
                    _HapticTestButton(
                      label: '${S.get('nav_right')} !',
                      dist: 'very close',
                      pos: 'right',
                      patternFn: widget.patternFn,
                      intensFn: widget.intensFn,
                      vibrateFn: widget.vibrateFn,
                      danger: true,
                    ),
                  ],
                ),
                Divider(color: colors.divider, height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 16,
                  ),
                  child: Text(
                    S.get('settings_earcon_test'),
                    style: TextStyle(color: colors.textSecondary, fontSize: 16),
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
                      label: 'Анализ активен',
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
                Divider(color: colors.divider, height: 20),
                if (widget.onViewWaypoints != null)
                  Semantics(
                    label: S.get('waypoint_name_prompt'),
                    button: true,
                    child: ListTile(
                      textColor: colors.textPrimary,
                      iconColor: colors.stateWarning,
                      leading: const Icon(Icons.place),
                      title: Text(S.get('waypoint_name_prompt')),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: colors.textSecondary,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onViewWaypoints!();
                      },
                    ),
                  ),
                Divider(color: colors.divider, height: 20),
                Semantics(
                  label: 'Тест: Внимание (Слева)',
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.textSecondary,
                    title: const Text('Тест: Внимание (Слева)'),
                    trailing: const Icon(Icons.volume_up),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onVoiceWarningTest();
                    },
                  ),
                ),
                Semantics(
                  label: 'Тест: Критично (По центру)',
                  button: true,
                  child: ListTile(
                    textColor: colors.textPrimary,
                    iconColor: colors.stateWarning,
                    title: const Text('Тест: Критично (По центру)'),
                    trailing: const Icon(Icons.warning_amber),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onVoiceCriticalTest();
                    },
                  ),
                ),
                const SizedBox(height: BagdarSpacing.m),
                BagdarCard(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(S.get('settings_diagnostics')),
                    children: [
                      Semantics(
                        label:
                            'GPU: ${_useGpu ? S.get('sem_on') : S.get('sem_off')}',
                        child: SwitchListTile(
                          title: Text(
                            'GPU',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          value: _useGpu,
                          onChanged: (v) {
                            setState(() => _useGpu = v);
                            widget.onUseGpuChanged(v);
                          },
                        ),
                      ),
                      Semantics(
                        label:
                            'Native depth bridge: ${_useNativeDepthBridge ? S.get('sem_on') : S.get('sem_off')}',
                        child: SwitchListTile(
                          title: Text(
                            'Native depth bridge',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          subtitle: Text(
                            'libyuv preprocessing before TFLite',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                          value: _useNativeDepthBridge,
                          onChanged: (v) {
                            setState(() => _useNativeDepthBridge = v);
                            widget.onNativeDepthBridgeChanged(v);
                          },
                        ),
                      ),
                      if (widget.showIndependentHardwareDepth)
                        Semantics(
                          label:
                              'Hardware depth research mode: ${_useHardwareDepthMode ? S.get('sem_on') : S.get('sem_off')}',
                          child: SwitchListTile(
                            title: Text(
                              'Hardware depth (research)',
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            subtitle: Text(
                              'Uses an independent ARCore camera; not a Core path',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                            value: _useHardwareDepthMode,
                            onChanged: (v) {
                              setState(() => _useHardwareDepthMode = v);
                              widget.onHardwareDepthModeChanged(v);
                            },
                          ),
                        ),
                      Semantics(
                        label:
                            '${_depthTierText(widget.depthTier)}. ${_depthTierSubtitle(widget.depthTier)}',
                        child: ListTile(
                          textColor: colors.textPrimary,
                          iconColor: colors.accentPrimary,
                          leading: Icon(
                            Icons.sensors,
                            color: colors.accentPrimary,
                          ),
                          title: Text(
                            'Источник глубины: ${_depthTierText(widget.depthTier)}',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          subtitle: Text(
                            _depthTierSubtitle(widget.depthTier),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            S.get('settings_cpu_threads'),
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          DropdownButton<int>(
                            isExpanded: true,
                            itemHeight: null,
                            dropdownColor: colors.surfaceElevated,
                            value: _numThreads,
                            style: BagdarTypography.body.copyWith(
                              color: colors.textPrimary,
                            ),
                            items: [1, 2, 3, 4]
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text('$n'),
                                  ),
                                )
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
                        label:
                            'Debug HUD: ${_showDebugHud ? S.get('sem_on') : S.get('sem_off')}',
                        child: SwitchListTile(
                          title: Text(
                            'Debug HUD',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          value: _showDebugHud,
                          onChanged: (v) {
                            setState(() => _showDebugHud = v);
                            widget.onDebugHudChanged(v);
                          },
                        ),
                      ),
                      SwitchListTile(
                        title: Text(
                          'Field Logging',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                        subtitle: Text(
                          FieldLogger.instance.active
                              ? 'Recording... (${FieldLogger.instance.eventCount} events)'
                              : 'Record pipeline events for analysis',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        value: FieldLogger.instance.active,
                        activeThumbColor: colors.stateSuccess,
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _depthTierText(DepthTier? tier) {
    switch (tier) {
      case DepthTier.hardware:
        return 'ARCore / LiDAR';
      case DepthTier.ncnnVulkan:
        return 'NCNN + Vulkan';
      case DepthTier.ncnnCpu:
        return 'NCNN + CPU';
      case DepthTier.focalLength:
        return 'Focal length fallback';
      case null:
        return '—';
    }
  }

  String _depthTierSubtitle(DepthTier? tier) {
    switch (tier) {
      case DepthTier.hardware:
        return 'Native device depth';
      case DepthTier.ncnnVulkan:
        return 'NCNN runtime + Vulkan GPU';
      case DepthTier.ncnnCpu:
        return 'NCNN runtime CPU (NEON)';
      case DepthTier.focalLength:
        return 'No depth API — focal length estimate';
      case null:
        return 'Auto-detect';
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
    final colors = BagdarTheme.colorsOf(context);
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(widget.title, style: TextStyle(color: colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: widget.labelText,
              labelStyle: TextStyle(color: colors.textSecondary),
              suffixText: 'м',
              suffixStyle: TextStyle(color: colors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.controlBorder),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.accentPrimary),
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
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(
            widget.saveLabel,
            style: TextStyle(color: colors.accentPrimary),
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
    return OutlinedButton.icon(
      onPressed: () => onPlay(earcon),
      icon: const Icon(Icons.music_note_outlined, size: 24),
      label: Text(label),
    );
  }
}

/// Adapter that preserves the original `_SliderRow` call sites in
/// this sheet but renders the AAA-compliant [StepperField] under the
/// hood. The [Slider] widget had two failures: TalkBack reports
/// percentages with poor granularity on small screens, and shaky
/// hands could not reliably reach a 4 dp thumb on a 64 dp track.
/// The stepper trio has 64 × 64 dp ± buttons and announces the new
/// value verbally.
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
    return StepperField(
      label: label,
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      formatValue: _format,
      onChanged: onChanged,
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
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      label: '$label: ${labelFor(value)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            DropdownButton<T>(
              isExpanded: true,
              itemHeight: null,
              borderRadius: BorderRadius.circular(BagdarRadius.control),
              dropdownColor: colors.surfaceElevated,
              value: value,
              style: BagdarTypography.body.copyWith(color: colors.textPrimary),
              underline: Container(height: 1, color: colors.divider),
              items: values
                  .map(
                    (v) =>
                        DropdownMenuItem<T>(value: v, child: Text(labelFor(v))),
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
    final colors = BagdarTheme.colorsOf(context);
    final color = danger ? colors.stateWarning : colors.accentPrimary;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
      onPressed: () {
        final pattern = patternFn(dist, pos);
        final intensities = intensFn(dist, pattern.length);
        vibrateFn(pattern, intensities: intensities);
      },
      child: Text(label),
    );
  }
}
