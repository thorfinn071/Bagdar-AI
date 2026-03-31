import 'package:flutter/material.dart';
import 'strings.dart';

enum AppMode { street, cane, scan }

extension AppModeExt on AppMode {
  String get label {
    switch (this) {
      case AppMode.street: return S.get('mode_street');
      case AppMode.cane:   return S.get('mode_cane');
      case AppMode.scan:   return S.get('mode_scan');
    }
  }

  String get description {
    switch (this) {
      case AppMode.street: return S.get('mode_street_desc');
      case AppMode.cane:   return S.get('mode_cane_desc');
      case AppMode.scan:   return S.get('mode_scan_desc');
    }
  }

  IconData get icon {
    switch (this) {
      case AppMode.street: return Icons.directions_walk;
      case AppMode.cane:   return Icons.accessibility_new;
      case AppMode.scan:   return Icons.search;
    }
  }

  AppMode get next =>
      AppMode.values[(index + 1) % AppMode.values.length];
}
