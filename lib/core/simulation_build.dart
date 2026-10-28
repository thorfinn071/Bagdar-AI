import 'package:flutter/foundation.dart';

/// Explicit compile-time input substitution. Ordinary app launches never set it.
const bool simulationBuild = bool.fromEnvironment('BAGDAR_SIMULATION');

void requireSimulationBuild() {
  if (!simulationBuild || kReleaseMode) {
    throw StateError(
      'Simulation requires a debug/profile BAGDAR_SIMULATION build',
    );
  }
}
