import 'core_health.dart';

export 'core_health.dart';

/// Capability-based health. Not a global singleton; hosts construct one.
class CoreHealthCoordinator {
  static const int maxLog = 64;
  static const Duration announcementCooldown = Duration(seconds: 30);

  static const Set<CoreComponent> _requiredVision = {
    CoreComponent.cameraPermission,
    CoreComponent.cameraSession,
    CoreComponent.imageStream,
  };

  final Map<CoreComponent, ComponentHealth> _components = {};
  final List<HealthTransition> _log = [];
  final List<HealthAnnouncement> _pending = [];
  DateTime? _lastAnnounceAt;
  String? _lastAnnounceKey;
  CoreRunState _lastAnnouncedRun = CoreRunState.starting;
  bool _operationalAnnounced = false;

  CoreHealthSnapshot snapshot(DateTime now) {
    final caps = deriveCapabilities(_components);
    final run = deriveRunState(_components, caps);
    return CoreHealthSnapshot(
      runState: run.state,
      reasonCode: run.reason,
      at: now,
      components: Map.unmodifiable(_components),
      capabilities: caps,
      mayAnnounceOperational:
          run.state == CoreRunState.operational && !_operationalAnnounced,
    );
  }

  List<HealthTransition> get transitionLog => List.unmodifiable(_log);

  void note({
    required CoreComponent component,
    required ComponentState state,
    required String reasonCode,
    required DateTime now,
    bool sessionTerminal = false,
    double? quality,
    int recoveryAttempts = 0,
    bool announce = true,
  }) {
    final previous = _components[component];
    if (previous != null &&
        previous.state == state &&
        previous.reasonCode == reasonCode) {
      _components[component] = ComponentHealth(
        component: component,
        state: state,
        reasonCode: reasonCode,
        updatedAt: now,
        lastSuccessAt: state == ComponentState.available
            ? now
            : previous.lastSuccessAt,
        quality: quality ?? previous.quality,
        sessionTerminal: sessionTerminal,
        recoveryAttempts: recoveryAttempts,
        affects: capabilitiesAffectedBy(component),
      );
      return;
    }

    final health = ComponentHealth(
      component: component,
      state: state,
      reasonCode: reasonCode,
      updatedAt: now,
      lastSuccessAt: state == ComponentState.available
          ? now
          : previous?.lastSuccessAt,
      quality: quality,
      sessionTerminal: sessionTerminal,
      recoveryAttempts: recoveryAttempts,
      affects: capabilitiesAffectedBy(component),
    );
    _components[component] = health;

    final caps = deriveCapabilities(_components);
    final run = deriveRunState(_components, caps);
    _log.add(
      HealthTransition(
        component: component,
        from: previous?.state,
        to: state,
        reasonCode: reasonCode,
        runState: run.state,
        at: now,
      ),
    );
    if (_log.length > maxLog) {
      _log.removeAt(0);
    }
    if (announce) {
      _queueAnnouncement(run.state, run.reason, now);
    }
  }

  List<HealthAnnouncement> drainAnnouncements() {
    final out = List<HealthAnnouncement>.from(_pending);
    _pending.clear();
    return out;
  }

  void resetSession(DateTime now) {
    _components.clear();
    _pending.clear();
    _operationalAnnounced = false;
    _lastAnnounceKey = null;
    _lastAnnouncedRun = CoreRunState.starting;
    _log.add(
      HealthTransition(
        reasonCode: 'session_reset',
        runState: CoreRunState.starting,
        at: now,
      ),
    );
    if (_log.length > maxLog) {
      _log.removeAt(0);
    }
  }

  void _queueAnnouncement(CoreRunState run, String reason, DateTime now) {
    final key = _stringKeyFor(run, reason);
    if (key == null) return;

    if (run == CoreRunState.operational) {
      if (!_requiredVisionResolved()) return;
      if (_lastAnnouncedRun == CoreRunState.degraded ||
          _lastAnnouncedRun == CoreRunState.unavailable) {
        _pending.add(
          HealthAnnouncement(
            stringKey: 'core_health_recovered',
            reasonCode: 'recovered',
            runState: CoreRunState.recovering,
            at: now,
          ),
        );
        _lastAnnounceAt = now;
        _lastAnnounceKey = 'core_health_recovered';
        _lastAnnouncedRun = CoreRunState.operational;
        _operationalAnnounced = true;
        return;
      }
      if (_operationalAnnounced) return;
      _operationalAnnounced = true;
      _lastAnnounceAt = now;
      _lastAnnounceKey = key;
      _lastAnnouncedRun = run;
      _pending.add(
        HealthAnnouncement(
          stringKey: key,
          reasonCode: reason,
          runState: run,
          at: now,
        ),
      );
      return;
    }

    if (key == _lastAnnounceKey &&
        _lastAnnounceAt != null &&
        now.difference(_lastAnnounceAt!) < announcementCooldown) {
      return;
    }

    if (run == CoreRunState.operational) return;

    _lastAnnounceAt = now;
    _lastAnnounceKey = key;
    _lastAnnouncedRun = run;
    if (run == CoreRunState.recovering) {
      _operationalAnnounced = false;
    }
    _pending.add(
      HealthAnnouncement(
        stringKey: key,
        reasonCode: reason,
        runState: run,
        at: now,
      ),
    );
  }

  bool _requiredVisionResolved() {
    for (final c in _requiredVision) {
      final h = _components[c];
      if (h == null || h.state == ComponentState.initializing) return false;
    }
    return true;
  }

  static String? _stringKeyFor(CoreRunState run, String reason) {
    switch (run) {
      case CoreRunState.operational:
        return 'system_ready';
      case CoreRunState.degraded:
        if (reason == 'alert_audio_unavailable') {
          return 'core_health_sound_unavailable';
        }
        if (reason == 'haptics_unavailable') {
          return 'core_health_haptic_unavailable';
        }
        if (reason.startsWith('camera')) {
          return 'camera_unavailable';
        }
        return 'spatial_analysis_limited';
      case CoreRunState.unavailable:
        if (reason.startsWith('camera')) return 'camera_unavailable';
        return 'spatial_analysis_limited';
      case CoreRunState.recovering:
        return 'core_health_recovered';
      case CoreRunState.starting:
      case CoreRunState.stopped:
        return null;
    }
  }

  static Set<CoreCapability> capabilitiesAffectedBy(CoreComponent c) {
    switch (c) {
      case CoreComponent.cameraPermission:
      case CoreComponent.cameraSession:
      case CoreComponent.imageStream:
        return {
          CoreCapability.mobilityVision,
          CoreCapability.genericObstacleAwareness,
          CoreCapability.surfaceHazards,
          CoreCapability.movingThreatAwareness,
        };
      case CoreComponent.genericGeometry:
        return {
          CoreCapability.genericObstacleAwareness,
          CoreCapability.surfaceHazards,
        };
      case CoreComponent.semanticObjects:
      case CoreComponent.movingThreats:
        return {CoreCapability.movingThreatAwareness};
      case CoreComponent.alertAudio:
      case CoreComponent.haptics:
        return {
          CoreCapability.mobilityVision,
          CoreCapability.fallDetection,
          CoreCapability.emergencyMessaging,
        };
      case CoreComponent.orientation:
        return {CoreCapability.mobilityVision};
      case CoreComponent.accelerometer:
      case CoreComponent.gyroscope:
        return {CoreCapability.fallDetection};
      case CoreComponent.location:
      case CoreComponent.compass:
        return {CoreCapability.pedestrianNavigation};
      case CoreComponent.emergencySms:
        return {CoreCapability.emergencyMessaging};
    }
  }

  static Map<CoreCapability, ComponentState> deriveCapabilities(
    Map<CoreComponent, ComponentHealth> components,
  ) {
    ComponentState combine(List<CoreComponent> required) {
      final states = [
        for (final c in required)
          components[c]?.state ?? ComponentState.initializing,
      ];
      if (states.contains(ComponentState.unavailable)) {
        return ComponentState.unavailable;
      }
      if (states.contains(ComponentState.initializing)) {
        return ComponentState.initializing;
      }
      if (states.contains(ComponentState.recovering)) {
        return ComponentState.recovering;
      }
      if (states.contains(ComponentState.degraded)) {
        return ComponentState.degraded;
      }
      if (states.contains(ComponentState.stopped)) {
        return ComponentState.stopped;
      }
      return ComponentState.available;
    }

    ComponentState worst(List<ComponentState> states) {
      const order = [
        ComponentState.unavailable,
        ComponentState.stopped,
        ComponentState.initializing,
        ComponentState.recovering,
        ComponentState.degraded,
        ComponentState.available,
      ];
      for (final s in order) {
        if (states.contains(s)) return s;
      }
      return ComponentState.initializing;
    }

    final vision = combine([
      CoreComponent.cameraPermission,
      CoreComponent.cameraSession,
      CoreComponent.imageStream,
    ]);
    final geometry =
        components[CoreComponent.genericGeometry]?.state ??
        ComponentState.initializing;
    final yolo =
        components[CoreComponent.semanticObjects]?.state ??
        ComponentState.initializing;
    final accel =
        components[CoreComponent.accelerometer]?.state ??
        ComponentState.initializing;
    final gyro =
        components[CoreComponent.gyroscope]?.state ??
        ComponentState.initializing;
    final sms =
        components[CoreComponent.emergencySms]?.state ??
        ComponentState.initializing;
    final loc =
        components[CoreComponent.location]?.state ??
        ComponentState.initializing;
    final compass =
        components[CoreComponent.compass]?.state ?? ComponentState.initializing;

    final fall = () {
      if (accel == ComponentState.unavailable) {
        return ComponentState.unavailable;
      }
      if (accel == ComponentState.initializing) {
        return ComponentState.initializing;
      }
      if (gyro == ComponentState.unavailable ||
          gyro == ComponentState.degraded) {
        return ComponentState.degraded;
      }
      return accel;
    }();

    return {
      CoreCapability.mobilityVision: vision,
      CoreCapability.genericObstacleAwareness: worst([vision, geometry]),
      CoreCapability.surfaceHazards: worst([vision, geometry]),
      CoreCapability.movingThreatAwareness: worst([vision, yolo]),
      CoreCapability.fallDetection: fall,
      CoreCapability.emergencyMessaging: sms,
      CoreCapability.pedestrianNavigation: worst([loc, compass]),
    };
  }

  static ({CoreRunState state, String reason}) deriveRunState(
    Map<CoreComponent, ComponentHealth> components,
    Map<CoreCapability, ComponentState> caps,
  ) {
    final vision = caps[CoreCapability.mobilityVision]!;
    if (vision == ComponentState.unavailable ||
        vision == ComponentState.stopped) {
      return (state: CoreRunState.unavailable, reason: 'camera_unavailable');
    }
    if (vision == ComponentState.initializing) {
      return (state: CoreRunState.starting, reason: 'vision_initializing');
    }

    final audio =
        components[CoreComponent.alertAudio]?.state ??
        ComponentState.initializing;
    final haptics =
        components[CoreComponent.haptics]?.state ?? ComponentState.initializing;
    final hasOutput =
        audio == ComponentState.available ||
        haptics == ComponentState.available ||
        audio == ComponentState.degraded ||
        haptics == ComponentState.degraded;
    if (audio == ComponentState.initializing &&
        haptics == ComponentState.initializing) {
      return (state: CoreRunState.starting, reason: 'output_initializing');
    }
    if (!hasOutput) {
      return (state: CoreRunState.unavailable, reason: 'output_unavailable');
    }

    final fall = caps[CoreCapability.fallDetection]!;
    if (fall == ComponentState.unavailable) {
      return (state: CoreRunState.degraded, reason: 'fall_unavailable');
    }

    if (vision == ComponentState.recovering ||
        audio == ComponentState.recovering) {
      return (state: CoreRunState.recovering, reason: 'recovering');
    }

    if (vision == ComponentState.degraded ||
        caps[CoreCapability.genericObstacleAwareness] ==
            ComponentState.degraded ||
        caps[CoreCapability.genericObstacleAwareness] ==
            ComponentState.unavailable ||
        audio == ComponentState.unavailable ||
        haptics == ComponentState.unavailable ||
        fall == ComponentState.degraded) {
      final reason = audio == ComponentState.unavailable
          ? 'alert_audio_unavailable'
          : haptics == ComponentState.unavailable
          ? 'haptics_unavailable'
          : vision == ComponentState.degraded
          ? 'camera_degraded'
          : 'geometry_degraded';
      return (state: CoreRunState.degraded, reason: reason);
    }

    return (state: CoreRunState.operational, reason: 'operational');
  }
}
