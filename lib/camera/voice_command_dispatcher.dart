import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_mode.dart';
import '../models/a11y_prefs.dart';
import '../models/constants.dart';
import '../models/language_pack.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/feature_usage_tracker.dart';
import '../services/earcon_service.dart';
import '../services/indoor_trail_replay.dart';
import '../services/indoor_trail_store.dart';
import '../services/language_pack_manager.dart';
import '../services/settings_service.dart';
import '../services/voice_adaptation_store.dart';
import '../services/voice_command_service.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import '../viewmodels/camera_view_model.dart';
import '../services/scene_narrator.dart';
import 'fall_countdown_controller.dart';

class VoiceCommandDispatcher {
  final CameraViewModel vm;
  final FallCountdownController fallCountdown;
  final VoidCallback onReadTextRequested;
  final VoidCallback onSosRequested;
  final void Function({SceneFilter filter}) onDescribeSceneRequested;
  /// Pushes the Language Packs settings screen. Required because the
  /// dispatcher has no BuildContext of its own and Navigator pushes must
  /// originate from the camera screen which owns the navigator stack.
  final VoidCallback? onShowLanguagePacks;

  VoiceCommandDispatcher({
    required this.vm,
    required this.fallCountdown,
    required this.onReadTextRequested,
    required this.onSosRequested,
    required this.onDescribeSceneRequested,
    this.onShowLanguagePacks,
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
          fallCountdown.requestVoiceCancel();
          return;
        }
        fallCountdown.cancel();
        onSosRequested();
        return;
      }
    }

    switch (cmd) {
      case VoiceCommand.cancelFall:
        if (vm.objectFinder.active) {
          vm.objectFinder.stop();
        } else if (vm.objectMemory.rememberActive) {
          vm.objectMemory.cancelRemember();
          vm.tts.say(S.get('obj_find_stopped'), SpeechPriority.info, pan: 0.0);
        } else {
          vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        }
        break;
      case VoiceCommand.cancelFind:
        if (vm.objectFinder.active) {
          vm.objectFinder.stop();
        } else if (vm.objectMemory.rememberActive) {
          vm.objectMemory.cancelRemember();
          vm.tts.say(S.get('obj_find_stopped'), SpeechPriority.info, pan: 0.0);
        } else {
          vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        }
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
        
        
        vm.tts.say(S.get('mode_street'), SpeechPriority.warning, pan: 0.0);
        break;
      case VoiceCommand.modeCane:
        vm.setMode(AppMode.cane);
        vm.tts.say(S.get('mode_cane'), SpeechPriority.warning, pan: 0.0);
        break;
      case VoiceCommand.modeScan:
        vm.setMode(AppMode.scan);
        vm.tts.say(S.get('mode_scan'), SpeechPriority.warning, pan: 0.0);
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
      case VoiceCommand.rememberObject:
      case VoiceCommand.findObject:
      case VoiceCommand.forgetObject:
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
      case VoiceCommand.restartPipeline:
        vm.tts.say(
          S.get('restart_pipeline'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        break;
      case VoiceCommand.themeDark:
        _switchTheme(BagdarThemeName.dark, 'theme_selected_dark');
        break;
      case VoiceCommand.themeLight:
        _switchTheme(BagdarThemeName.light, 'theme_selected_light');
        break;
      case VoiceCommand.themeHighContrast:
        _switchTheme(
          BagdarThemeName.highContrast,
          'theme_selected_high_contrast',
        );
        break;
      case VoiceCommand.themeWarm:
        _switchTheme(BagdarThemeName.warm, 'theme_selected_warm');
        break;
      case VoiceCommand.manageLanguagePacks:
        vm.tts.say(
          S.get('voice_manage_lang_packs_announce'),
          SpeechPriority.info,
          pan: 0.0,
        );
        onShowLanguagePacks?.call();
        break;
      case VoiceCommand.enableKkV2:
        _toggleKkV2(true);
        break;
      case VoiceCommand.disableKkV2:
        _toggleKkV2(false);
        break;
      // Phase 1 — Indoor trail (handled in handleNavCommand for
      // record/replay/landmark/delete which carry a destination arg).
      case VoiceCommand.stopTrailRecord:
        _stopTrailRecord();
        break;
      case VoiceCommand.recordTrail:
      case VoiceCommand.replayTrail:
      case VoiceCommand.addTrailLandmark:
      case VoiceCommand.deleteTrail:
        vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      // Phase 1 — Bazaar / livestock
      case VoiceCommand.toggleBazaarMode:
        _toggleBazaarMode();
        break;
      case VoiceCommand.toggleLivestockMode:
        _toggleLivestockMode();
        break;
      // Phase 1 — Voice adaptation
      case VoiceCommand.toggleVoiceAdaptation:
        _toggleVoiceAdaptation();
        break;
      case VoiceCommand.clearAdaptationData:
        _clearAdaptationData();
        break;
      // Phase 2 — Mesh-Net Buddy Alerts
      case VoiceCommand.toggleMeshBuddy:
        _toggleMeshBuddy();
        break;
      // Phase 3 — Near-Miss Buffer
      case VoiceCommand.recordNearMiss:
        _recordNearMiss();
        break;
      // Phase 5 — Sonar-on-Phone
      case VoiceCommand.toggleSonar:
        _toggleSonar();
        break;
    }
  }

  Future<void> _toggleKkV2(bool enable) async {
    await Settings.instance.setEnableKazakhStackV2(enable);
    // Re-evaluate routing immediately so the next listen window picks up
    // the new state. setLocale with the same locale is a no-op for
    // speech_to_text but triggers the reconcile path in VoiceCommandService.
    vm.voice.setLocale(AppStrings.ttsLang);
    final packInstalled = LanguagePackManager.instance.isInstalled(
      LanguagePackIds.voskKk,
    );
    final key = enable
        ? (packInstalled ? 'lang_packs_v2_enabled' : 'voice_kk_v2_pack_missing')
        : 'lang_packs_v2_disabled';
    vm.tts.say(S.get(key), SpeechPriority.info, pan: 0.0);
  }

  void _switchTheme(BagdarThemeName name, String announcementKey) {
    unawaited(setBagdarTheme(name));
    vm.tts.say(
      S.get(announcementKey),
      SpeechPriority.warning,
      pan: 0.0,
      barge: true,
    );
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
      case VoiceCommand.rememberObject:
        unawaited(vm.objectMemory.startRemember(destination));
        break;
      case VoiceCommand.findObject:
        vm.objectFinder.start(destination);
        break;
      case VoiceCommand.forgetObject:
        unawaited(vm.objectMemory.forget(destination));
        break;
      // Phase 1 — Indoor trail
      case VoiceCommand.recordTrail:
        _startTrailRecord(destination);
        break;
      case VoiceCommand.replayTrail:
        _replayTrail(destination);
        break;
      case VoiceCommand.addTrailLandmark:
        vm.trailRecorder.addLandmark(destination);
        vm.tts.say(
          S.alert('trail_landmark_added'),
          SpeechPriority.info,
          pan: 0.0,
        );
        break;
      case VoiceCommand.deleteTrail:
        _deleteTrail(destination);
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
    
    
    vm.tts.say(S.get('lang_switched'), SpeechPriority.warning, pan: 0.0);
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

  // -- Phase 1 — Indoor trail ------------------------------------------

  void _startTrailRecord(String name) {
    final langCode = Settings.instance.language == 1
        ? 'kk'
        : Settings.instance.language == 2
            ? 'en'
            : 'ru';
    unawaited(vm.trailRecorder.start(name: name, langCode: langCode).then((ok) {
      if (ok) {
        vm.tts.say(
          S.alert('trail_recording_started'),
          SpeechPriority.info,
          pan: 0.0,
        );
      } else {
        vm.tts.say(
          S.alert('trail_recording_failed'),
          SpeechPriority.info,
          pan: 0.0,
        );
      }
    }));
  }

  void _stopTrailRecord() {
    if (!vm.trailRecorder.isActive) {
      // Maybe the user is stopping a replay instead.
      if (vm.trailReplay.state != IndoorTrailReplayState.idle) {
        unawaited(vm.trailReplay.stop());
        vm.tts.say(
          S.alert('trail_replay_stopped'),
          SpeechPriority.info,
          pan: 0.0,
        );
        return;
      }
      vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
      return;
    }
    unawaited(vm.trailRecorder.stop().then((trail) {
      if (trail != null) {
        vm.tts.say(
          S.alert('trail_recording_stopped'),
          SpeechPriority.info,
          pan: 0.0,
        );
      } else {
        vm.tts.say(
          S.alert('trail_recording_empty'),
          SpeechPriority.info,
          pan: 0.0,
        );
      }
    }));
  }

  void _replayTrail(String name) {
    unawaited(vm.trailReplay.startByName(name));
  }

  void _deleteTrail(String name) {
    unawaited(IndoorTrailStore.instance.findByName(name).then((trail) async {
      if (trail == null) {
        vm.tts.say(
          S.alert('trail_not_found'),
          SpeechPriority.info,
          pan: 0.0,
        );
        return;
      }
      await IndoorTrailStore.instance.delete(trail.id);
      vm.tts.say(
        S.alert('trail_deleted'),
        SpeechPriority.info,
        pan: 0.0,
      );
    }));
  }

  // -- Phase 1 — Bazaar / livestock ------------------------------------

  void _toggleBazaarMode() {
    final current = Settings.instance.bazaarMode;
    unawaited(Settings.instance.setBazaarMode(!current));
    if (!current) {
      // Turning on bazaar → turn off livestock (mutually exclusive).
      unawaited(Settings.instance.setLivestockAwareness(false));
    }
    vm.bazaarLivestock.reset();
    final key = !current ? 'bazaar_mode_on' : 'bazaar_mode_off';
    vm.tts.say(S.alert(key), SpeechPriority.info, pan: 0.0);
    vm.earcon.play(Earcon.success);
  }

  void _toggleLivestockMode() {
    final current = Settings.instance.livestockAwareness;
    unawaited(Settings.instance.setLivestockAwareness(!current));
    if (!current) {
      // Turning on livestock → turn off bazaar (mutually exclusive).
      unawaited(Settings.instance.setBazaarMode(false));
    }
    vm.bazaarLivestock.reset();
    final key = !current ? 'livestock_mode_on' : 'livestock_mode_off';
    vm.tts.say(S.alert(key), SpeechPriority.info, pan: 0.0);
    vm.earcon.play(Earcon.success);
  }

  // -- Phase 1 — Voice adaptation --------------------------------------

  void _toggleVoiceAdaptation() {
    final current = Settings.instance.localAsrAdaptation;
    unawaited(Settings.instance.setLocalAsrAdaptation(!current));
    final key = !current ? 'voice_adapt_on' : 'voice_adapt_off';
    vm.tts.say(S.alert(key), SpeechPriority.info, pan: 0.0);
  }

  void _clearAdaptationData() {
    unawaited(VoiceAdaptationStore.instance.deleteAll());
    vm.tts.say(
      S.alert('voice_adapt_samples_cleared'),
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  // -- Phase 2 — Mesh-Net Buddy Alerts ----------------------------------

  void _toggleMeshBuddy() {
    final current = Settings.instance.meshBuddyAlerts;
    unawaited(Settings.instance.setMeshBuddyAlerts(!current));
    if (!current) {
      unawaited(vm.meshBuddy.start());
      vm.tts.say(S.alert('mesh_buddy_started'), SpeechPriority.info, pan: 0.0);
    } else {
      unawaited(vm.meshBuddy.stop());
      vm.tts.say(S.alert('mesh_buddy_stopped'), SpeechPriority.info, pan: 0.0);
    }
    vm.earcon.play(Earcon.success);
  }

  // -- Phase 3 — Near-Miss Buffer ---------------------------------------

  void _recordNearMiss() {
    unawaited(vm.nearMissBuffer.record(
      triggerSource: 'voice',
      labels: const [],
    ));
    vm.tts.say(S.alert('near_miss_recorded'), SpeechPriority.info, pan: 0.0);
    vm.earcon.play(Earcon.success);
  }

  // -- Phase 5 — Sonar-on-Phone -----------------------------------------

  void _toggleSonar() {
    final current = Settings.instance.sonarDepth;
    unawaited(Settings.instance.setSonarDepth(!current));
    if (!current) {
      unawaited(vm.sonar.start());
      vm.tts.say(S.alert('sonar_started'), SpeechPriority.info, pan: 0.0);
    } else {
      unawaited(vm.sonar.stop());
      vm.tts.say(S.alert('sonar_stopped'), SpeechPriority.info, pan: 0.0);
    }
    vm.earcon.play(Earcon.success);
  }
}
