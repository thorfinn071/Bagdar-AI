/// Component and capability health for Bagdar Core.
///
/// Pure data. Time is supplied by callers. UI, TTS, and tests consume
/// [CoreHealthSnapshot] from [CoreHealthCoordinator].
library;

enum CoreComponent {
  cameraPermission,
  cameraSession,
  imageStream,
  alertAudio,
  haptics,
  genericGeometry,
  semanticObjects,
  movingThreats,
  orientation,
  accelerometer,
  gyroscope,
  location,
  compass,
  emergencySms,
}

enum ComponentState {
  initializing,
  available,
  degraded,
  unavailable,
  recovering,
  stopped,
}

enum CoreCapability {
  mobilityVision,
  genericObstacleAwareness,
  surfaceHazards,
  movingThreatAwareness,
  fallDetection,
  emergencyMessaging,
  pedestrianNavigation,
}

enum CoreRunState {
  starting,
  operational,
  degraded,
  unavailable,
  recovering,
  stopped,
}

class ComponentHealth {
  final CoreComponent component;
  final ComponentState state;
  final String reasonCode;
  final DateTime updatedAt;
  final DateTime? lastSuccessAt;
  final double? quality;
  final bool sessionTerminal;
  final int recoveryAttempts;
  final DateTime? nextAttemptAt;
  final Set<CoreCapability> affects;

  const ComponentHealth({
    required this.component,
    required this.state,
    required this.reasonCode,
    required this.updatedAt,
    this.lastSuccessAt,
    this.quality,
    this.sessionTerminal = false,
    this.recoveryAttempts = 0,
    this.nextAttemptAt,
    this.affects = const {},
  });

  bool get isUsable =>
      state == ComponentState.available || state == ComponentState.degraded;
}

class CoreHealthSnapshot {
  final CoreRunState runState;
  final String reasonCode;
  final DateTime at;
  final Map<CoreComponent, ComponentHealth> components;
  final Map<CoreCapability, ComponentState> capabilities;
  final bool mayAnnounceOperational;

  const CoreHealthSnapshot({
    required this.runState,
    required this.reasonCode,
    required this.at,
    required this.components,
    required this.capabilities,
    required this.mayAnnounceOperational,
  });

  ComponentState capability(CoreCapability c) =>
      capabilities[c] ?? ComponentState.initializing;

  bool get isOperational => runState == CoreRunState.operational;
}

class HealthAnnouncement {
  final String stringKey;
  final String reasonCode;
  final CoreRunState runState;
  final DateTime at;

  const HealthAnnouncement({
    required this.stringKey,
    required this.reasonCode,
    required this.runState,
    required this.at,
  });
}

class HealthTransition {
  final CoreComponent? component;
  final ComponentState? from;
  final ComponentState? to;
  final String reasonCode;
  final CoreRunState runState;
  final DateTime at;

  const HealthTransition({
    this.component,
    this.from,
    this.to,
    required this.reasonCode,
    required this.runState,
    required this.at,
  });
}
