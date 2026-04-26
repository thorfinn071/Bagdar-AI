import 'dart:async';
import 'package:flutter/material.dart';
import '../models/a11y_prefs.dart';
import '../models/app_mode.dart';
import '../models/speech_job.dart';
import '../services/feature_usage_tracker.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/earcon_service.dart';
import '../services/battery_monitor.dart';
import '../services/memory_monitor.dart';
import '../services/thermal_monitor.dart';
import '../services/proximity_beacon_service.dart';
import '../services/haptic_service.dart';
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
import '../services/traffic_light_analyzer.dart';
import '../services/ocr_service.dart';
import '../services/motion_prealert.dart';
import '../services/weather_gate.dart';
import '../services/indoor_gate.dart';

import '../services/orientation_service.dart';
import '../services/step_service.dart';

class CameraViewModel extends ChangeNotifier {
  final Tracker tracker = Tracker();
  final TtsService tts = TtsService();
  final EarconService earcon = EarconService();
  final BatteryMonitor battery = BatteryMonitor();
  final ThermalMonitor thermal = ThermalMonitor();
  final MemoryMonitor memory = MemoryMonitor();
  final PerformanceThrottler throttler = PerformanceThrottler();
  final CompassService compass = CompassService();
  final OrientationService orientation = OrientationService();
  final StepService steps = StepService();
  final WaypointService waypoints = WaypointService();
  final SosService sos = SosService();
  final FallDetector fallDetector = FallDetector();
  final TwoGisService twoGis = TwoGisService();
  final MapPackageManager mapPkg = MapPackageManager();
  final OfflineRoutingService offlineRouting = OfflineRoutingService();
  final GtfsService gtfs = GtfsService();
  final VoiceCommandService voice = VoiceCommandService();
  final TrafficLightAnalyzer trafficLight = TrafficLightAnalyzer();
  final OcrService ocr = OcrService();
  final MotionPreAlert motionPreAlert = MotionPreAlert();
  final WeatherGate weatherGate = WeatherGate();
  
  
  
  final IndoorGate indoorGate = IndoorGate();

  late final AlertManager alertMgr;
  late final ProximityBeaconService proximityBeacon;
  late final NavigationService nav;

  AppMode mode = AppMode.street;
  String statusLine = 'Запуск Bagdar...';
  bool isCameraReady = false;
  bool showDebugHud = false;
  bool isLowPowerMode = false;
  bool isPitchBlack = false;
  bool guideDogMode = false;

  DateTime _lastRollWarnAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _rollExcessiveSince = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOrientationWarnAt = DateTime.fromMillisecondsSinceEpoch(0);

  final ValueNotifier<List<Track>> tracksNotifier = ValueNotifier(const []);

  
  
  
  
  bool get isIndoor => indoorGate.state == IndoorState.indoor;

  CameraViewModel() {
    proximityBeacon = ProximityBeaconService(earcon: earcon);
    alertMgr = AlertManager(
      tts: tts,
      earcon: earcon,
      onProximityChanged: (dist, pan) {},
      isGuideDogMode: () => guideDogMode,
      isIndoorMode: () => isIndoor,
    );
    nav = NavigationService(compass: compass, stepService: steps);
  }

  
  
  
  void applyIndoorTransition(IndoorTransition transition) {
    if (transition == IndoorTransition.none) return;
    throttler.setIndoorMode(isIndoor);
    if (transition == IndoorTransition.enteredIndoor) {
      tts.say(
        S.alert('indoor_mode_entered'),
        SpeechPriority.info,
        pan: 0.0,
      );
    } else {
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
    mode = newMode;
    alertMgr.markModeSwitch(DateTime.now());
    FeatureUsageTracker.instance.increment(
      FeatureUsageKeys.mode(newMode.name),
    );
    tts.say(
      '${S.get('mode_changed')} ${mode.label}',
      SpeechPriority.critical,
      pan: 0.0,
    );
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
    final msg = isPitchBlack ? S.get('curtain_on') : S.get('curtain_off');
    tts.say(msg, SpeechPriority.critical, pan: 0.0);
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
    tts.say(msg, SpeechPriority.critical, pan: 0.0);
    HapticService.vibrate([0, 150]);
    notifyListeners();
  }

  void showHelp() {
    final key = Settings.instance.classicGestures
        ? 'help_summary_classic'
        : 'help_summary';
    tts.say(S.get(key), SpeechPriority.critical, pan: 0.0);
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
    ];

    await Future.wait(services);

    applyA11yPrefs();

    tracker.ttsService = tts;

    orientation.onPitchChanged = (state) {
      final now = DateTime.now();
      if (now.difference(_lastOrientationWarnAt) < const Duration(seconds: 10))
        return;

      if (state == DevicePitch.tooHigh) {
        _lastOrientationWarnAt = now;
        tts.say(S.get('pitch_too_high'), SpeechPriority.info, pan: 0.0);
      } else if (state == DevicePitch.tooLow) {
        _lastOrientationWarnAt = now;
        tts.say(S.get('pitch_too_low'), SpeechPriority.info, pan: 0.0);
      }
    };

    orientation.onRollChanged = (excessive) {
      final now = DateTime.now();
      if (excessive) {
        _rollExcessiveSince = now;
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
      } else {
        _rollExcessiveSince = DateTime.fromMillisecondsSinceEpoch(0);
      }
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
        tts.say(S.get('nav_arrived_short'), SpeechPriority.critical, pan: 0.0);

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

    nav.onPositionUpdated = (pos) {
      sos.updateCachedPosition(pos);
    };

    fallDetector.onMotionStateChanged = (state) {
      throttler.setMotionState(state);
    };

    throttler.setMemoryPressure(memory.level);
    memory.onChanged = (readings) {
      throttler.setMemoryPressure(readings.level);
      notifyListeners();
    };

    final modeName = Settings.instance.onboardingMode;
    final saved = AppMode.values.where((m) => m.name == modeName).firstOrNull;
    if (saved != null) mode = saved;

    if (Settings.instance.isReady) {
      guideDogMode = Settings.instance.guideDogMode;
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

  void updateTracks(List<Track> tracks) {
    tracksNotifier.value = tracks;
    notifyListeners();
  }

  @override
  void dispose() {
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
    tracksNotifier.dispose();
    super.dispose();
  }
}
