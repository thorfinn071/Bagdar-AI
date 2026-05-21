import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/a11y_prefs.dart';
import '../models/app_mode.dart';
import '../models/speech_job.dart';
import '../services/feature_usage_tracker.dart';
import '../services/field_logger.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/earcon_service.dart';
import '../services/battery_monitor.dart';
import '../services/memory_monitor.dart';
import '../services/thermal_monitor.dart';
import '../services/proximity_beacon_service.dart';
import '../services/haptic_service.dart';
import '../services/payment_sms_service.dart';
import '../services/device_capability.dart';
import '../services/sos_service.dart';
import '../services/waypoint_service.dart';
import '../services/fall_detector.dart';
import '../services/navigation_service.dart';
import '../services/compass_service.dart';
import '../services/twogis_service.dart';
import '../services/map_package_manager.dart';
import '../services/offline_routing_service.dart';
import '../services/gtfs_service.dart';
import '../camera/alert_manager.dart';
import '../tracker/tracker.dart';
import '../tracker/track.dart';
import '../utils/performance_throttler.dart';
import '../models/strings.dart';
import '../models/nav_models.dart';
import '../services/voice_command_service.dart';
import '../services/vosk_kk_recognizer.dart';
import '../services/traffic_light_analyzer.dart';
import '../services/ocr_service.dart';
import '../services/motion_prealert.dart';
import '../services/weather_gate.dart';
import '../services/indoor_gate.dart';
import '../services/object_memory_service.dart';
import '../services/acoustic_world_model.dart';
import '../camera/object_finder_session.dart';

import '../services/orientation_service.dart';
import '../services/step_service.dart';
import '../services/winter_mode_service.dart';
import '../services/indoor_trail_recorder.dart';
import '../services/indoor_trail_replay.dart';
import '../services/bazaar_livestock_service.dart';
import '../services/mesh_buddy_alert_service.dart';
import '../services/oscp_service.dart';
import '../services/near_miss_buffer.dart';
import '../services/charging_job_scheduler.dart';
import '../services/model_pack_manager.dart';
import '../services/scene_question_service.dart';
import '../services/sonar_service.dart';

class CameraViewModel extends ChangeNotifier {
  final Tracker tracker = Tracker();
  final TtsService tts = TtsService.instance;
  final EarconService earcon = EarconService();
  final BatteryMonitor battery = BatteryMonitor();
  final ThermalMonitor thermal = ThermalMonitor();
  final MemoryMonitor memory = MemoryMonitor();
  final PerformanceThrottler throttler = PerformanceThrottler();
  final CompassService compass = CompassService();
  final OrientationService orientation = OrientationService();
  final StepService steps = StepService();
  final WaypointService waypoints = WaypointService();
  late final SosService sos = SosService(
    stepProvider: () => steps.steps,
    headingProvider: () => compass.heading,
    networkContextProvider: DeviceCapabilityProbe.getNetworkContext,
  );
  final FallDetector fallDetector = FallDetector();
  final TwoGisService twoGis = TwoGisService();
  final MapPackageManager mapPkg = MapPackageManager();
  final OfflineRoutingService offlineRouting = OfflineRoutingService();
  final GtfsService gtfs = GtfsService();
  final VoiceCommandService voice = VoiceCommandService();
  final TrafficLightAnalyzer trafficLight = TrafficLightAnalyzer();
  // Phase 3: pass `memory` so OcrService can refuse to start a new
  // PaddleOCR session when the device is under critical memory pressure
  // (PaddleLite predictors total ~80 MB resident when active).
  late final OcrService ocr = OcrService(memoryMonitor: memory);
  final MotionPreAlert motionPreAlert = MotionPreAlert();
  final WeatherGate weatherGate = WeatherGate();
  
  
  
  final IndoorGate indoorGate = IndoorGate();

  final WinterModeService winterMode = WinterModeService();

  late final AlertManager alertMgr;
  late final ProximityBeaconService proximityBeacon;
  late final NavigationService nav;
  late final PaymentSmsService paymentSms;
  final ObjectMemoryService objectMemory = ObjectMemoryService();
  final AcousticWorldModel awm = AcousticWorldModel();
  late final ObjectFinderSession objectFinder;
  late final IndoorTrailRecorder trailRecorder;
  late final IndoorTrailReplay trailReplay;
  final BazaarLivestockService bazaarLivestock = BazaarLivestockService.instance;

  // Phase 2 — Direction 3: BLE mesh-net buddy alerts
  final MeshBuddyAlertService meshBuddy = MeshBuddyAlertService.instance;
  // Phase 2 — Direction 7: Open Smart-Cane Sensor Pod
  final OscpService oscp = OscpService.instance;
  // Phase 3 — Direction 4: Near-miss buffer
  final NearMissBuffer nearMissBuffer = NearMissBuffer.instance;
  // Phase 3 — Direction 4: Charging-gated training scheduler
  final ChargingJobScheduler chargingJobs = ChargingJobScheduler.instance;
  // Phase 3 — Direction 9: Regional model pack manager
  final ModelPackManager modelPacks = ModelPackManager.instance;
  // Phase 4 — Direction 11: On-device VLM scene companion
  final SceneQuestionService vlmCompanion = SceneQuestionService.instance;
  // Phase 5 — Direction 1: FMCW chirp echolocation prototype
  final SonarService sonar = SonarService.instance;

  AppMode mode = AppMode.street;
  String statusLine = 'Запуск Bagdar...';
  bool isCameraReady = false;
  bool showDebugHud = false;
  bool isLowPowerMode = false;
  bool isPitchBlack = false;
  bool guideDogMode = false;

  DateTime _lastRollWarnAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOrientationWarnAt = DateTime.fromMillisecondsSinceEpoch(0);

  final ValueNotifier<List<Track>> tracksNotifier = ValueNotifier(const []);

  
  
  
  
  bool get isIndoor => indoorGate.state == IndoorState.indoor;

  CameraViewModel() {
    proximityBeacon = ProximityBeaconService(earcon: earcon);
    alertMgr = AlertManager(
      tts: tts,
      earcon: earcon,
      onProximityChanged: (dist, pan) {
        if (dist == null) {
          proximityBeacon.pause();
        } else {
          proximityBeacon.update(
            dist,
            pan,
            weatherDegraded: weatherGate.degraded,
          );
        }
      },
      isGuideDogMode: () => guideDogMode,
      isIndoorMode: () => isIndoor,
    );
    nav = NavigationService(compass: compass, stepService: steps);
    paymentSms = PaymentSmsService(tts: tts, earcon: earcon);
    objectFinder = ObjectFinderSession(
      tts: tts,
      earcon: earcon,
      memory: objectMemory,
    );
    trailRecorder = IndoorTrailRecorder(
      compass: compass,
      steps: steps,
      indoorGate: indoorGate,
    );
    trailReplay = IndoorTrailReplay(
      compass: compass,
      steps: steps,
    );
    // Winter Mode: load persisted manual toggle and propagate into the
    // thermal monitor. The thermal → winterMode auto-detect feedback is
    // wired in `camera_screen.dart:_handleThermalChanged` to coexist with
    // the existing throttler / model-service thermal listeners.
    winterMode.loadFromSettings();
    thermal.setWinterMode(winterMode.active);
    winterMode.addListener(_onWinterModeChanged);
  }

  void _onWinterModeChanged() {
    thermal.setWinterMode(winterMode.active);
    notifyListeners();
  }

  Future<void> togglePaymentSms() async {
    await paymentSms.toggle();
    notifyListeners();
  }

  
  
  
  void applyIndoorTransition(IndoorTransition transition) {
    if (transition == IndoorTransition.none) return;
    throttler.setIndoorMode(isIndoor);
    if (transition == IndoorTransition.enteredIndoor) {
      earcon.play(Earcon.indoorEntered);
      tts.say(
        S.alert('indoor_mode_entered'),
        SpeechPriority.info,
        pan: 0.0,
      );
    } else {
      earcon.play(Earcon.indoorExited);
      tts.say(
        S.alert('indoor_mode_exited'),
        SpeechPriority.info,
        pan: 0.0,
      );
    }
    notifyListeners();
  }

  void setStatus(String s) {
    statusLine = s;
    notifyListeners();
  }

  void toggleDebugHud() {
    showDebugHud = !showDebugHud;
    notifyListeners();
  }

  void setMode(AppMode newMode) {
    final oldMode = mode;
    mode = newMode;
    alertMgr.markModeSwitch(DateTime.now());
    FeatureUsageTracker.instance.increment(
      FeatureUsageKeys.mode(newMode.name),
    );
    FieldLogger.instance.logModeSwitch(newMode.name, from: oldMode.name);
    if (Settings.instance.modeAnnounce) {
      
      
      
      
      tts.say(
        '${S.get('mode_changed')} ${mode.label}',
        SpeechPriority.warning,
        pan: 0.0,
      );
    }
    notifyListeners();
  }

  void cycleMode(int delta) {
    const modes = AppMode.values;
    int index = (modes.indexOf(mode) + delta) % modes.length;
    if (index < 0) index = modes.length - 1;
    setMode(modes[index]);
    HapticService.vibrate([0, 100]);
  }

  void togglePitchBlack() {
    isPitchBlack = !isPitchBlack;
    unawaited(Settings.instance.setPitchBlackUi(isPitchBlack));
    final msg = isPitchBlack ? S.get('curtain_on') : S.get('curtain_off');
    
    
    tts.say(msg, SpeechPriority.info, pan: 0.0);
    HapticService.vibrate([0, 150]);
    notifyListeners();
  }

  void toggleGuideDogMode() {
    guideDogMode = !guideDogMode;
    unawaited(Settings.instance.setGuideDogMode(guideDogMode));
    final msg = guideDogMode
        ? S.alert('guide_dog_on')
        : S.alert('guide_dog_off');
    earcon.play(Earcon.success);
    
    
    tts.say(msg, SpeechPriority.info, pan: 0.0);
    HapticService.vibrate([0, 150]);
    notifyListeners();
  }

  void showHelp() {
    final key = Settings.instance.classicGestures
        ? 'help_summary_classic'
        : 'help_summary';
    
    
    tts.say(S.get(key), SpeechPriority.info, pan: 0.0);
  }

  void applyA11yPrefs() {
    final s = Settings.instance;
    unawaited(tts.setUserRate(s.speechRate));
    unawaited(tts.setUserVolume(s.ttsVolume));
    unawaited(earcon.setVolume(s.earconVolume));
    HapticService.setStrengthMultiplier(s.hapticStrength.multiplier);
  }

  Future<void> init() async {
    final List<Future<void>> services = [
      _initService('TTS', tts.init()),
      _initService('Battery', battery.init()),
      _initService('Thermal', thermal.init()),
      _initService('Memory', memory.init()),
      _initService('Earcon', earcon.init()),
      _initService('Compass', compass.init()),
      _initService('Orientation', orientation.init()),
      _initService('Steps', steps.init()),
      _initService('Waypoints', waypoints.init()),
      _initService('SOS', sos.init()),
      _initService('2GIS', twoGis.init()),
      _initService('Voice', voice.init(locale: AppStrings.ttsLang)),
      _initService('PaymentSMS', paymentSms.init()),
      _initService(
        'ObjectMemory',
        objectMemory.init(tts: tts, earcon: earcon),
      ),
      _initService('AWM', awm.init()),
    ];

    await Future.wait(services);

    awm.onAcousticEvent = (event) {
      alertMgr.handleAcousticEvent(event);
    };
    awm.onReverbEstimate = (estimate) {
      indoorGate.feedAcousticPrior(estimate);
    };

    // Phase 1 — Indoor trail replay: route prompts through AlertManager
    // so navigation cooldowns and verbosity gating apply.
    trailReplay.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };
    trailReplay.onArrived = (trail) {
      earcon.play(Earcon.success);
    };
    trailReplay.onLost = () {
      earcon.play(Earcon.fail);
    };

    // Phase 1 — Bazaar / Livestock: route livestock announcements
    // through AlertManager.
    bazaarLivestock.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Phase 2 — Mesh buddy alerts: route peer hazards through AlertManager.
    meshBuddy.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Phase 2 — OSCP smart-cane: route range hazards through AlertManager.
    oscp.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Phase 4 — VLM companion: route answers through AlertManager.
    vlmCompanion.onAnswer = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Phase 5 — Sonar: route range hazards through AlertManager.
    sonar.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Payment SMS: route alert through AlertManager.
    paymentSms.onHazard = (event) {
      alertMgr.handleExternalHazard(event);
    };

    // Direction 4: wire ChargingJobScheduler gate providers.
    chargingJobs.isChargingProvider = () => battery.isCharging;
    chargingJobs.isWifiProvider = () => battery.isWifi;
    chargingJobs.batteryPctProvider = () => battery.batteryPct;
    chargingJobs.thermalProvider = () => thermal.severity;
    chargingJobs.memoryProvider = () => memory.level;

    applyA11yPrefs();

    waypoints.onNearWaypoint = (wp) {
      tts.say(
        '${S.get('waypoint_near')} ${wp.name}',
        SpeechPriority.warning,
        pan: 0.0,
      );
      earcon.play(Earcon.success);
    };
    waypoints.startProximityMonitor(intervalSec: 30);

    tracker.ttsService = tts;

    orientation.onPitchChanged = (state) {
      final now = DateTime.now();
      if (now.difference(_lastOrientationWarnAt) < const Duration(seconds: 10)) {
        return;
      }

      if (state == DevicePitch.tooHigh) {
        _lastOrientationWarnAt = now;
        tts.say(S.get('pitch_too_high'), SpeechPriority.info, pan: 0.0);
      } else if (state == DevicePitch.tooLow) {
        _lastOrientationWarnAt = now;
        tts.say(S.get('pitch_too_low'), SpeechPriority.info, pan: 0.0);
      }
    };

    orientation.onRollChanged = (excessive) {
      if (!excessive) return;
      earcon.play(Earcon.fail);
      HapticService.vibrate([0, 100, 80, 100]);
      Future.delayed(const Duration(seconds: 3), () {
        if (!orientation.isRollExcessive) return;
        final t = DateTime.now();
        if (t.difference(_lastRollWarnAt) < const Duration(seconds: 20)) {
          return;
        }
        _lastRollWarnAt = t;
        tts.say(
          S.get('phone_tilted_sideways'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      });
    };

    battery.onThrottleChanged = (level) {
      isLowPowerMode =
          (level == ThrottleLevel.aggressive ||
          level == ThrottleLevel.critical);
      throttler.setLowPowerMode(isLowPowerMode);
      notifyListeners();
    };

    nav.onInstruction = (msg) => tts.say(msg, SpeechPriority.info, pan: 0.0);
    nav.onOffRoute = () {
      tts.say(S.get('nav_off_route'), SpeechPriority.warning, pan: 0.0);
      tts.say(S.get('nav_rerouting_try'), SpeechPriority.info, pan: 0.0);
    };
    nav.onSoftOffRoute = () =>
        tts.say(S.get('nav_maybe_off_route'), SpeechPriority.info, pan: 0.0);
    nav.onArrived = () =>
        
        
        tts.say(S.get('nav_arrived_short'), SpeechPriority.warning, pan: 0.0);

    nav.onOffRouteBearing = (bearing, distanceMeters) {
      final clockHint = _bearingToClockHint(bearing);
      tts.say(
        '$clockHint. $distanceMeters ${S.get('meters')}.',
        SpeechPriority.warning,
        pan: 0.0,
      );
    };

    nav.onRerouteRequested = _rerouteFromPosition;

    nav.onGpsError = (msg) => tts.say(msg, SpeechPriority.warning, pan: 0.0);

    nav.onNavMuteChanged = (msg) =>
        tts.say(msg, SpeechPriority.warning, pan: 0.0);

    nav.onPositionUpdated = (pos) {
      sos.updateCachedPosition(pos);
    };

    nav.onRouteStarted = (destination) {
      sos.setPlannedDestination(destination);
    };
    nav.onRouteStopped = () {
      sos.setPlannedDestination(null);
    };

    fallDetector.onMotionStateChanged = (state) {
      throttler.setMotionState(state);
    };

    throttler.setMemoryPressure(memory.level);
    memory.onChanged = (readings) {
      throttler.setMemoryPressure(readings.level);
      FieldLogger.instance.logMemoryPressure(
        readings.level.name,
        availMb: readings.isAvailable ? readings.availMB : null,
        totalMb: readings.isAvailable ? readings.totalMB : null,
      );
      // Vosk-kk loads a ~150 MB acoustic model into RAM. Under critical
      // pressure (~250 MB available), keeping it resident risks OOM kill
      // of the foreground process — far worse than degrading to
      // speech_to_text for the kk locale until pressure recovers. The
      // VoiceCommandService routing layer transparently falls back to
      // speech_to_text on the next listen window after dispose.
      if (readings.level == MemoryPressureLevel.critical &&
          VoskKkRecognizer.instance.isReady) {
        FieldLogger.instance.log('vosk_kk_unloaded_oom', {
          'availMb': readings.availMB,
        });
        unawaited(VoskKkRecognizer.instance.dispose());
      }
      notifyListeners();
    };

    final modeName = Settings.instance.onboardingMode;
    final saved = AppMode.values.where((m) => m.name == modeName).firstOrNull;
    if (saved != null) mode = saved;

    if (Settings.instance.isReady) {
      guideDogMode = Settings.instance.guideDogMode;
      isPitchBlack = Settings.instance.pitchBlackUi;
    }

    notifyListeners();
  }

  Future<NavRoute?> _rerouteFromPosition(double fromLat, double fromLng) async {
    final currentRoute = nav.route;
    final currentTransit = nav.transitRoute;
    double toLat = 0, toLng = 0;
    String dest = '';
    if (currentRoute != null && currentRoute.steps.isNotEmpty) {
      final last = currentRoute.steps.last;
      toLat = last.endLat;
      toLng = last.endLng;
      dest = currentRoute.destinationName;
    } else if (currentTransit != null && currentTransit.legs.isNotEmpty) {
      final lastLeg = currentTransit.legs.last;
      final arr = lastLeg.arrivalStop;
      if (arr != null) {
        toLat = arr.lat;
        toLng = arr.lng;
        dest = currentTransit.destinationName;
      }
    }
    if (toLat == 0 && toLng == 0) return null;

    if (offlineRouting.isReady) {
      final r = await offlineRouting.getWalkRoute(
        fromLat,
        fromLng,
        toLat,
        toLng,
        destinationName: dest,
      );
      if (r != null) return r;
    }
    if (twoGis.hasApiKey) {
      return twoGis.getWalkRoute(
        fromLat,
        fromLng,
        toLat,
        toLng,
        destinationName: dest,
      );
    }
    return null;
  }

  String _bearingToClockHint(double bearing) {
    const hintKeys = <String>[
      'forward',
      '1',
      '2',
      '3',
      '2',
      '1',
      'forward',
      '11',
      '10',
      '9',
      '10',
      '11',
    ];
    final idx = ((bearing % 360) / 30).round() % 12;
    return S.dir(hintKeys[idx]);
  }

  Future<void> _initService(String name, Future<void> initCall) async {
    try {
      await initCall;
    } catch (e) {
      debugPrint('CameraViewModel: Service $name failed to init: $e');
    }
  }

  void updateTracks(
    List<Track> tracks, {
    int imgW = 0,
    int imgH = 0,
  }) {
    tracksNotifier.value = tracks;
    if (imgW > 0 && imgH > 0) {
      objectMemory.onTracks(tracks, imgW, imgH);
      objectFinder.onTracks(tracks, imgW, imgH);
    }
    notifyListeners();
  }

  void objectMemoryFeed(CameraImage image, DateTime now) {
    if (objectMemory.rememberActive) objectMemory.feed(image, now);
    if (objectFinder.active) objectFinder.feed(image, now);
  }

  @override
  void dispose() {
    winterMode.removeListener(_onWinterModeChanged);
    winterMode.dispose();
    bazaarLivestock.onHazard = null;
    meshBuddy.onHazard = null;
    oscp.onHazard = null;
    vlmCompanion.onAnswer = null;
    sonar.onHazard = null;
    trailReplay.onHazard = null;
    paymentSms.onHazard = null;
    tts.dispose();
    earcon.dispose();
    battery.dispose();
    thermal.dispose();
    memory.dispose();
    proximityBeacon.dispose();
    compass.dispose();
    orientation.dispose();
    steps.dispose();
    waypoints.dispose();
    fallDetector.dispose();
    nav.dispose();
    ocr.dispose();
    paymentSms.dispose();
    objectMemory.dispose();
    objectFinder.dispose();
    awm.dispose();
    trailRecorder.dispose();
    trailReplay.dispose();
    meshBuddy.dispose();
    oscp.dispose();
    chargingJobs.dispose();
    vlmCompanion.dispose();
    sonar.dispose();
    modelPacks.dispose();
    tracksNotifier.dispose();
    super.dispose();
  }
}
