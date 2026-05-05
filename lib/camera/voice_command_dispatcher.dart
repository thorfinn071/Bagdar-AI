import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_mode.dart';
import '../models/a11y_prefs.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/feature_usage_tracker.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../viewmodels/camera_view_model.dart';
import '../services/scene_narrator.dart';
import 'fall_countdown_controller.dart';

class VoiceCommandDispatcher {
  final CameraViewModel vm;
  final FallCountdownController fallCountdown;
  final VoidCallback onReadTextRequested;
  final VoidCallback onSosRequested;
  final void Function({SceneFilter filter}) onDescribeSceneRequested;

  VoiceCommandDispatcher({
    required this.vm,
    required this.fallCountdown,
    required this.onReadTextRequested,
    required this.onSosRequested,
    required this.onDescribeSceneRequested,
  });

  void handleCommand(VoiceCommand cmd) {
    if (cmd != VoiceCommand.unknown) {
      FeatureUsageTracker.instance
        ..increment(FeatureUsageKeys.voiceCommand(cmd.name))
        ..increment(FeatureUsageKeys.voiceCommandTotal);
    }

    if (fallCountdown.active) {
      if (cmd == VoiceCommand.cancelFall || cmd == VoiceCommand.sos) {
        if (cmd == VoiceCommand.cancelFall) {
          fallCountdown.cancel();
          return;
        }
        fallCountdown.cancel();
        onSosRequested();
        return;
      }
    }

    switch (cmd) {
      case VoiceCommand.cancelFall:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.scanAll:
        onDescribeSceneRequested(filter: SceneFilter.all);
        break;
      case VoiceCommand.scanLeft:
        onDescribeSceneRequested(filter: SceneFilter.left);
        break;
      case VoiceCommand.scanRight:
        onDescribeSceneRequested(filter: SceneFilter.right);
        break;
      case VoiceCommand.scanForward:
        onDescribeSceneRequested(filter: SceneFilter.forward);
        break;
      case VoiceCommand.readText:
        onReadTextRequested();
        break;
      case VoiceCommand.modeStreet:
        vm.setMode(AppMode.street);
        vm.tts.say(S.get('mode_street'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.modeCane:
        vm.setMode(AppMode.cane);
        vm.tts.say(S.get('mode_cane'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.modeScan:
        vm.setMode(AppMode.scan);
        vm.tts.say(S.get('mode_scan'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.toggleMode:
        vm.cycleMode(1);
        break;
      case VoiceCommand.togglePitchBlackUi:
        vm.togglePitchBlack();
        break;
      case VoiceCommand.toggleGuideDogMode:
        vm.toggleGuideDogMode();
        break;
      case VoiceCommand.togglePaymentSms:
        unawaited(vm.togglePaymentSms());
        break;
      case VoiceCommand.stopNavigation:
        vm.nav.stopNavigation();
        vm.tts.say(S.get('nav_stopped'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.whereAmI:
        vm.tts.say(vm.nav.getWhereAmI(), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.navStatus:
        vm.tts.say(vm.nav.getStatusSummary(), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.confirmBoarded:
        vm.nav.confirmBoarded();
        break;
      case VoiceCommand.saveWaypoint:
        unawaited(_saveWaypointFromVoice());
        break;
      case VoiceCommand.sos:
        onSosRequested();
        break;
      case VoiceCommand.showHelp:
        vm.showHelp();
        break;
      case VoiceCommand.unknown:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.navigateTo:
      case VoiceCommand.transitTo:
      case VoiceCommand.nearestStop:
      case VoiceCommand.busRoute:
      case VoiceCommand.busSchedule:
      case VoiceCommand.downloadMap:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.speechRateFaster:
        _increaseSpeechRate();
        break;
      case VoiceCommand.speechRateSlower:
        _decreaseSpeechRate();
        break;
      case VoiceCommand.volumeUp:
        _increaseVolume();
        break;
      case VoiceCommand.volumeDown:
        _decreaseVolume();
        break;
      case VoiceCommand.langRussian:
        unawaited(_setLanguage(AppLanguage.ru));
        break;
      case VoiceCommand.langKazakh:
        unawaited(_setLanguage(AppLanguage.kk));
        break;
      case VoiceCommand.langEnglish:
        unawaited(_setLanguage(AppLanguage.en));
        break;
      case VoiceCommand.batteryStatus:
        _announceBatteryStatus();
        break;
      case VoiceCommand.verbosityMinimal:
        _setVerbosity(Verbosity.minimal);
        break;
      case VoiceCommand.verbosityNormal:
        _setVerbosity(Verbosity.normal);
        break;
      case VoiceCommand.verbosityDetailed:
        _setVerbosity(Verbosity.detailed);
        break;
      case VoiceCommand.alertsRare:
        _setAlertFrequency(AlertFrequency.rare);
        break;
      case VoiceCommand.alertsNormal:
        _setAlertFrequency(AlertFrequency.normal);
        break;
      case VoiceCommand.alertsFrequent:
        _setAlertFrequency(AlertFrequency.frequent);
        break;
      case VoiceCommand.sosTriggerTripleTap:
        _setSosTrigger(SosTrigger.tripleTap);
        break;
      case VoiceCommand.sosTriggerShake:
        _setSosTrigger(SosTrigger.shake);
        break;
      case VoiceCommand.hapticStrong:
        _setHapticStrength(HapticStrength.strong);
        break;
      case VoiceCommand.hapticWeak:
        _setHapticStrength(HapticStrength.weak);
        break;
      case VoiceCommand.settingsHelp:
        vm.tts.say(
          S.get('voice_settings_commands'),
          SpeechPriority.info,
          pan: 0.0,
        );
        break;
      case VoiceCommand.tutorialSkip:
      case VoiceCommand.tutorialRepeat:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
    }
  }

  void handleNavCommand(VoiceCommand cmd, String destination) {
    if (cmd != VoiceCommand.unknown) {
      FeatureUsageTracker.instance
        ..increment(FeatureUsageKeys.voiceCommand(cmd.name))
        ..increment(FeatureUsageKeys.voiceCommandTotal);
    }
    switch (cmd) {
      case VoiceCommand.navigateTo:
        vm.tts.say(
          '${S.get('nav_searching')} $destination',
          SpeechPriority.info,
          pan: 0.0,
        );
        unawaited(_startNavigateTo(destination));
        break;
      case VoiceCommand.transitTo:
        vm.tts.say(
          '${S.get('nav_searching')} $destination',
          SpeechPriority.info,
          pan: 0.0,
        );
        unawaited(_startTransitTo(destination));
        break;
      case VoiceCommand.busRoute:
      case VoiceCommand.busSchedule:
      case VoiceCommand.downloadMap:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      default:
        break;
    }
  }

  Future<void> _startNavigateTo(String destination) async {
    try {
      final pos = await _currentPositionForNav();
      if (pos == null) {
        vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final places = vm.offlineRouting.poiReady
          ? await vm.offlineRouting.searchPlaces(
              destination,
              pos.latitude,
              pos.longitude,
            )
          : await vm.twoGis.searchPlaces(
              destination,
              pos.latitude,
              pos.longitude,
            );
      if (places.isEmpty) {
        vm.tts.say(S.get('nav_not_found'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final target = places.first;
      vm.tts.say(S.get('nav_building_route'), SpeechPriority.info, pan: 0.0);
      final route = vm.offlineRouting.isReady
          ? await vm.offlineRouting.getWalkRoute(
              pos.latitude,
              pos.longitude,
              target.lat,
              target.lng,
              destinationName: target.name,
            )
          : await vm.twoGis.getWalkRoute(
              pos.latitude,
              pos.longitude,
              target.lat,
              target.lng,
              destinationName: target.name,
            );
      if (route == null) {
        vm.tts.say(
          S.get('nav_route_failed'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        return;
      }
      vm.nav.startWalkNavigation(route);
    } catch (e) {
      debugPrint('startNavigateTo error: $e');
      vm.tts.say(S.get('nav_route_failed'), SpeechPriority.warning, pan: 0.0);
    }
  }

  Future<void> _startTransitTo(String destination) async {
    try {
      final pos = await _currentPositionForNav();
      if (pos == null) {
        vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      if (!vm.twoGis.hasApiKey) {
        vm.tts.say(S.get('nav_no_api_key'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final places = await vm.twoGis.searchPlaces(
        destination,
        pos.latitude,
        pos.longitude,
      );
      if (places.isEmpty) {
        vm.tts.say(S.get('nav_not_found'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final target = places.first;
      vm.tts.say(S.get('nav_building_route'), SpeechPriority.info, pan: 0.0);
      final route = await vm.twoGis.getTransitRoute(
        pos.latitude,
        pos.longitude,
        target.lat,
        target.lng,
        destinationName: target.name,
      );
      if (route == null) {
        vm.tts.say(
          S.get('nav_route_failed'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        return;
      }
      vm.nav.startTransitNavigation(route);
    } catch (e) {
      debugPrint('startTransitTo error: $e');
      vm.tts.say(S.get('nav_route_failed'), SpeechPriority.warning, pan: 0.0);
    }
  }

  Future<Position?> _currentPositionForNav() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _saveWaypointFromVoice() async {
    try {
      final name = 'WP ${DateTime.now().toIso8601String().substring(11, 16)}';
      final wp = await vm.waypoints.saveCurrentLocation(name);
      if (wp == null) {
        vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      vm.tts.say(S.get('waypoint_saved'), SpeechPriority.info, pan: 0.0);
    } catch (e) {
      debugPrint('saveWaypointFromVoice error: $e');
    }
  }

  void _increaseSpeechRate() {
    final cur = Settings.instance.speechRate;
    final next = (cur + kVoiceSpeechRateStep).clamp(kSpeechRateMin, kSpeechRateMax);
    unawaited(Settings.instance.setSpeechRate(next));
    unawaited(vm.tts.setUserRate(next));
    vm.tts.say(S.get('vc_speed_up'), SpeechPriority.info, pan: 0.0);
  }

  void _decreaseSpeechRate() {
    final cur = Settings.instance.speechRate;
    final next = (cur - kVoiceSpeechRateStep).clamp(kSpeechRateMin, kSpeechRateMax);
    unawaited(Settings.instance.setSpeechRate(next));
    unawaited(vm.tts.setUserRate(next));
    vm.tts.say(S.get('vc_speed_down'), SpeechPriority.info, pan: 0.0);
  }

  void _increaseVolume() {
    final cur = Settings.instance.ttsVolume;
    final next = (cur + kVoiceVolumeStep).clamp(kTtsVolumeMin, kTtsVolumeMax);
    unawaited(Settings.instance.setTtsVolume(next));
    unawaited(vm.tts.setUserVolume(next));
    vm.tts.say(S.get('vc_volume_up'), SpeechPriority.info, pan: 0.0);
  }

  void _decreaseVolume() {
    final cur = Settings.instance.ttsVolume;
    final next = (cur - kVoiceVolumeStep).clamp(kTtsVolumeMin, kTtsVolumeMax);
    unawaited(Settings.instance.setTtsVolume(next));
    unawaited(vm.tts.setUserVolume(next));
    vm.tts.say(S.get('vc_volume_down'), SpeechPriority.info, pan: 0.0);
  }

  Future<void> _setLanguage(AppLanguage lang) async {
    AppStrings.setLanguage(lang);
    await Settings.instance.setLanguage(lang.index);
    await vm.tts.setLanguage(AppStrings.ttsLang);
    vm.voice.setLocale(AppStrings.ttsLang);
    vm.tts.say(S.get('lang_switched'), SpeechPriority.critical, pan: 0.0);
  }

  void _announceBatteryStatus() {
    final battery = vm.battery.batteryLevel;
    vm.tts.say(
      S.get('vc_battery_status').replaceFirst('{battery}', battery.toString()),
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  void _setVerbosity(Verbosity v) {
    unawaited(Settings.instance.setVerbosity(v));
    vm.tts.say(
      '${S.get('settings_verbosity')}: ${S.get('verbosity_${v.name}')}',
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  void _setAlertFrequency(AlertFrequency v) {
    unawaited(Settings.instance.setAlertFrequency(v));
    vm.tts.say(
      '${S.get('settings_alert_frequency')}: ${S.get('freq_${v.name}')}',
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  void _setSosTrigger(SosTrigger v) {
    unawaited(Settings.instance.setSosTrigger(v));
    final label = switch (v) {
      SosTrigger.twoFingerHold => S.get('sos_trigger_two_finger'),
      SosTrigger.tripleTap => S.get('sos_trigger_triple_tap'),
      SosTrigger.shake => S.get('sos_trigger_shake'),
    };
    vm.tts.say('${S.get('settings_sos_trigger')}: $label', SpeechPriority.info, pan: 0.0);
  }

  void _setHapticStrength(HapticStrength v) {
    unawaited(Settings.instance.setHapticStrength(v));
    vm.applyA11yPrefs();
    vm.tts.say(
      '${S.get('settings_haptic_strength')}: ${S.get('haptic_${v.name}')}',
      SpeechPriority.info,
      pan: 0.0,
    );
  }
}
