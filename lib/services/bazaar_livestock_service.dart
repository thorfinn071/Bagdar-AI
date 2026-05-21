import '../models/context_mode.dart';
import '../models/external_hazard.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import 'field_logger.dart';
import 'settings_service.dart';

/// Threshold overrides applied when `ContextMode.bazaar` is active.
/// These adjust the existing `AlertManager` behavior without changing
/// the safety pipeline. Tuned conservatively — field-calibrate later.
class BazaarThresholds {
  /// Crowd-alert cooldown multiplier (< 1.0 = more frequent).
  /// In a bazaar we *want* more crowd info, not less.
  static const double crowdCooldownMultiplier = 0.6;

  /// Extra priority boost for hanging / overhead obstacle labels.
  /// Applied additively to the urgency field (clamped to [0,1]).
  static const double hangingObstaclePriorityBoost = 0.15;

  /// Additional priority boost for low / ground-level obstacles
  /// (cart wheels, awning ropes, stall poles). Additive.
  static const double lowObstaclePriorityBoost = 0.10;
}

/// COCO-80 labels that map to livestock categories the app announces
/// in `ContextMode.livestock`. Only labels actually present in the
/// bundled `yolov8n_int8.tflite` are listed; custom model packs can
/// extend this set via `ModelPackManager` in a later phase.
///
/// Risk gate: livestock announcements must NEVER reduce
/// vehicle/pedestrian alert sensitivity.
class LivestockTaxonomy {
  LivestockTaxonomy._();

  /// Map from YOLO label → localized string key in `AppStrings`.
  static const Map<String, String> labelToStringKey = {
    'cow': 'livestock_cow',
    'horse': 'livestock_horse',
    'sheep': 'livestock_sheep',
    'dog': 'livestock_dog',
    'cat': 'livestock_cat',
    'bird': 'livestock_bird',
  };

  /// Fast membership check: is this YOLO label a livestock label?
  static bool isLivestock(String label) =>
      labelToStringKey.containsKey(label);

  /// All YOLO labels the livestock mode cares about, as a set for
  /// fast intersection with the per-frame label list.
  static final Set<String> labels = labelToStringKey.keys.toSet();
}

/// Service that produces `ContextMode`-aware threshold overrides for
/// `AlertManager` and emits livestock-specific `ExternalHazardEvent`s
/// when the active YOLO detection set includes livestock labels.
///
/// Phase 1 — Direction 9. No new ML model assets in this first pass.
/// Bazaar mode: tuning-only via existing `AlertManager` thresholds.
/// Livestock mode: label taxonomy + localized strings over existing
/// YOLO output.
///
/// This service is a *pure modifier* layered on top of the safety
/// pipeline. It never bypasses `AlertFilter` cooldowns.
class BazaarLivestockService {
  BazaarLivestockService._();

  static final BazaarLivestockService instance = BazaarLivestockService._();

  /// Callback to emit livestock announcements through
  /// `AlertManager.handleExternalHazard`.
  void Function(ExternalHazardEvent event)? onHazard;

  /// Cooldown between livestock announcements for the same label
  /// to avoid spamming "cow ahead, cow ahead, cow ahead".
  static const Duration _kLivestockCooldown = Duration(seconds: 8);

  final Map<String, DateTime> _lastAnnounced = {};

  /// Returns the current effective `ContextMode` from settings.
  ContextMode get contextMode => Settings.instance.contextMode;

  /// Whether bazaar threshold tuning is active right now.
  bool get isBazaar => contextMode.isBazaar;

  /// Whether livestock announcements are active right now.
  bool get isLivestock => contextMode.isLivestock;

  // -- Bazaar threshold helpers ------------------------------------------

  /// Crowd-alert cooldown multiplier for the current context. Returns
  /// 1.0 when bazaar mode is off (no change).
  double get crowdCooldownMultiplier =>
      isBazaar ? BazaarThresholds.crowdCooldownMultiplier : 1.0;

  /// Extra urgency boost for hanging / overhead obstacles. Returns
  /// 0.0 when bazaar mode is off.
  double get hangingObstacleBoost =>
      isBazaar ? BazaarThresholds.hangingObstaclePriorityBoost : 0.0;

  /// Extra urgency boost for low / ground-level obstacles. Returns
  /// 0.0 when bazaar mode is off.
  double get lowObstacleBoost =>
      isBazaar ? BazaarThresholds.lowObstaclePriorityBoost : 0.0;

  // -- Livestock label matching ------------------------------------------

  /// Call every frame from `AlertManager.processFrame` with the
  /// current set of YOLO labels. When livestock mode is active and
  /// livestock labels appear, emits localised announcements through
  /// [onHazard]. Labels that were announced within the cooldown
  /// window are suppressed.
  ///
  /// [trackDistances] maps label → approximate distance in meters
  /// (may be null when no depth is available). The announcement
  /// includes distance when known.
  void feedLabels(
    List<String> labels, {
    Map<String, double>? trackDistances,
  }) {
    if (!isLivestock) return;

    final now = DateTime.now();
    for (final label in labels) {
      if (!LivestockTaxonomy.isLivestock(label)) continue;

      // Cooldown per label.
      final last = _lastAnnounced[label];
      if (last != null && now.difference(last) < _kLivestockCooldown) {
        continue;
      }
      _lastAnnounced[label] = now;

      final stringKey = LivestockTaxonomy.labelToStringKey[label]!;
      var text = S.alert(stringKey);
      if (text == stringKey || text.isEmpty) {
        // Fallback to plain label if the string key isn't localized yet.
        text = label;
      }

      final dist = trackDistances?[label];
      if (dist != null && dist > 0) {
        text = '$text, ~${dist.toStringAsFixed(1)} ${S.alert('approx_meters')}';
      }

      try {
        onHazard?.call(ExternalHazardEvent(
          source: ExternalHazardSource.contextMode,
          text: text,
          priority: SpeechPriority.info,
          category: AlertCategory.acousticEvent,
          urgency: dist != null && dist < 1.0 ? 0.70 : 0.45,
          distanceM: dist,
          at: now,
          correlationId: 'livestock_$label',
        ));
      } catch (e) {
        FieldLogger.instance.log('livestock_emit_error', {
          'label': label,
          'error': e.toString(),
        });
      }
    }
  }

  /// Reset cooldown state (e.g. after mode switch).
  void reset() {
    _lastAnnounced.clear();
  }

  // -- Bazaar label helpers -----------------------------------------------

  /// COCO-80 labels that represent hanging or overhead obstacles
  /// relevant in bazaar environments. Used by `AlertManager` to
  /// apply the bazaar priority boost.
  static const Set<String> hangingLabels = {
    'umbrella',
    'handbag',
    'suitcase',
    'backpack',
    'dining table',
  };

  /// COCO-80 labels that represent low or ground-level obstacles
  /// common in bazaar aisles.
  static const Set<String> lowLabels = {
    'bench',
    'chair',
    'potted plant',
    'fire hydrant',
    'stop sign',
    'parking meter',
  };

  /// Returns the urgency boost for a given YOLO label under the
  /// current context mode. Returns 0.0 for non-bazaar mode or
  /// labels that don't match the boosted sets.
  double urgencyBoostForLabel(String label) {
    if (!isBazaar) return 0.0;
    if (hangingLabels.contains(label)) return hangingObstacleBoost;
    if (lowLabels.contains(label)) return lowObstacleBoost;
    return 0.0;
  }
}
