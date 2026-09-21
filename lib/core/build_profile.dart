/// Compile-time product profile.
///
/// Default is [core]. Research is selected only when the Dart environment
/// defines `BAGDAR_RESEARCH=true` (research flavor / internal builds).
/// A persisted user preference must never change this value.
enum BuildProfile {
  core,
  research;

  /// Compile-time current profile. `bool.fromEnvironment` is resolved at
  /// compile time; tests and the default APK are Core unless explicitly
  /// rebuilt with `--dart-define=BAGDAR_RESEARCH=true`.
  static const BuildProfile current =
      bool.fromEnvironment('BAGDAR_RESEARCH', defaultValue: false)
      ? BuildProfile.research
      : BuildProfile.core;

  bool get isCore => this == BuildProfile.core;
  bool get isResearch => this == BuildProfile.research;
}
