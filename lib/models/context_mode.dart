/// Secondary contextual mode layered on top of `AppMode`. Kept in a
/// separate enum (per the growth-direction plan) so adding bazaar /
/// livestock contexts does not require touching the existing
/// street / cane / scan switch UI everywhere it is referenced.
///
/// `ContextMode` is a *pure modifier*: it never bypasses the safety
/// pipeline, only adjusts alert thresholds and string vocabularies via
/// `AlertManager` consultation. Each entry is gated behind its own
/// `SettingsService` feature flag and defaults to [ContextMode.none].
enum ContextMode {
  /// Default. No threshold tuning, no expanded label vocabulary. All
  /// existing AppMode behaviour applies unchanged.
  none,

  /// Bazaar / market. Crowded indoor-outdoor environment with hanging
  /// signage and dense low-height obstacles. Tuning lives in
  /// `AlertManager` and `SceneNarrator`; no new model assets.
  bazaar,

  /// Livestock awareness. Enables localized announcements for cow /
  /// sheep / goat / horse / chicken / stray dog when their labels are
  /// produced by the active YOLO pack. Must never decrease
  /// vehicle/pedestrian alert sensitivity.
  livestock,
}

extension ContextModeExt on ContextMode {
  /// Key used for telemetry log payloads.
  String get tag {
    switch (this) {
      case ContextMode.none:
        return 'none';
      case ContextMode.bazaar:
        return 'bazaar';
      case ContextMode.livestock:
        return 'livestock';
    }
  }

  bool get isBazaar => this == ContextMode.bazaar;
  bool get isLivestock => this == ContextMode.livestock;
  bool get isActive => this != ContextMode.none;
}
