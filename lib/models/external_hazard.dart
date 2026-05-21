import '../models/speech_job.dart';
import '../utils/alert_filter.dart' show AlertCategory;

/// Source of a non-camera hazard event. Used purely for telemetry /
/// debugging — `AlertManager` does not branch on it; routing decisions
/// must come from [ExternalHazardEvent.priority] and
/// [ExternalHazardEvent.category].
enum ExternalHazardSource {
  /// Geomagnetic indoor trail replay prompt (Phase 1 / direction 6).
  indoorTrail,

  /// BLE mesh-net buddy alert (Phase 2 / direction 3).
  meshBuddy,

  /// Open Smart-Cane Sensor Pod range / IMU event (Phase 2 / direction 7).
  oscpPod,

  /// FMCW chirp echolocation range hit (Phase 5 / direction 1).
  sonarChirp,

  /// Bazaar / livestock context-mode triggered announcement
  /// (Phase 1 / direction 9).
  contextMode,

  /// VLM companion answer routed back through the alert lane so it
  /// inherits cooldowns (Phase 4 / direction 11).
  vlmCompanion,

  /// Payment SMS notification routed through the alert lane so it
  /// inherits alertFrequency / cooldown gating (Phase 1).
  paymentSms,
}

/// Generic event payload that every non-camera hazard producer emits
/// when it wants to surface an announcement, earcon, or haptic burst.
/// The [AlertManager.handleExternalHazard] adapter funnels these into
/// the existing `AlertFilter` so cooldowns, verbosity gating, and the
/// `alertFrequency` user preference apply identically to camera
/// hazards.
///
/// Producers are responsible for picking sensible [priority] and
/// [category] values:
///
/// - `SpeechPriority.critical` is reserved for genuine "stop" /
///   imminent-impact events (sonar near-field hit, OSCP shin contact).
///   Mesh "earlier hazard reported nearby" must use
///   `SpeechPriority.info`.
/// - `category` selects the cooldown bucket. Reuse the closest existing
///   `AlertCategory` (`approachingVehicle`, `obstacleClose`,
///   `navigationHint`, `acousticEvent`).
class ExternalHazardEvent {
  final ExternalHazardSource source;

  /// Localized text already resolved against `AppStrings` / `S.alert`
  /// by the producer. Keeping localisation outside the alert lane
  /// avoids leaking growth-direction-specific keys into the safety
  /// pipeline.
  final String text;

  /// Routing priority for `TtsService`. See class docs.
  final SpeechPriority priority;

  /// Cooldown bucket inside `AlertFilter`. See class docs.
  final AlertCategory category;

  /// Stereo pan in [-1.0, +1.0]. Producers without a bearing should
  /// pass `0.0`.
  final double pan;

  /// Urgency in [0, 1]. Used as the secondary sort key when multiple
  /// candidates compete for the same flush.
  final double urgency;

  /// Optional distance hint in meters; lets `AlertFilter` escalate
  /// repeated critical events when an object gets closer
  /// (see `AlertFilter.kEscalationDistanceFraction`).
  final double? distanceM;

  /// When the event was produced. Sub-systems must use the same clock
  /// the rest of the pipeline uses (`DateTime.now()`).
  final DateTime at;

  /// Optional opaque correlation id (e.g. mesh hazard hash, OSCP
  /// sweep id). Logged but never read by the safety pipeline.
  final String? correlationId;

  const ExternalHazardEvent({
    required this.source,
    required this.text,
    required this.priority,
    required this.category,
    required this.at,
    this.pan = 0.0,
    this.urgency = 0.5,
    this.distanceM,
    this.correlationId,
  });
}
