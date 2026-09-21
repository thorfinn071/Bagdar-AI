import 'build_profile.dart';
import 'core_feature.dart';

export 'build_profile.dart';
export 'core_feature.dart';

/// Single auditable gate for deferred experiments.
///
/// Core is the release/default candidate. Research may expose experiments
/// in debug/internal builds. Persisted preferences cannot bypass a
/// compile-time exclusion.
class CoreFeaturePolicy {
  final BuildProfile profile;

  const CoreFeaturePolicy(this.profile);

  static const CoreFeaturePolicy current = CoreFeaturePolicy(
    BuildProfile.current,
  );

  /// Whether the feature's runtime is part of this compiled artifact.
  /// Source is preserved either way; this is not a tree-shaking claim.
  bool isCompiled(CoreFeature feature) => profile.isResearch;

  bool mayInitialize(CoreFeature feature) => isCompiled(feature);

  bool mayRequestPermission(CoreFeature feature) => isCompiled(feature);

  bool mayShowInUi(CoreFeature feature) => isCompiled(feature);

  /// True when any deferred experiment may be shown or started.
  bool get allowsDeferredExperiments => profile.isResearch;
}

/// Android permissions the Core artifact is allowed to *request*.
///
/// Plugin-merged extras must be stripped with `tools:node="remove"` in the
/// Core flavor overlay. Keep this list in sync with
/// `docs/bagdar-core-scope.md`.
const Set<String> kApprovedCorePermissions = {
  'android.permission.CAMERA',
  'android.permission.RECORD_AUDIO',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_CAMERA',
  'android.permission.FOREGROUND_SERVICE_LOCATION',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.WAKE_LOCK',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.SEND_SMS',
  'android.permission.VIBRATE',
  'android.permission.HIGH_SAMPLING_RATE_SENSORS',
  'android.permission.ACCESS_WIFI_STATE',
};

/// Permissions that exist only for deferred experiments and must not appear
/// as active Core requests.
const Set<String> kExcludedCorePermissions = {
  'android.permission.RECEIVE_SMS',
  'android.permission.BLUETOOTH',
  'android.permission.BLUETOOTH_ADMIN',
  'android.permission.BLUETOOTH_SCAN',
  'android.permission.BLUETOOTH_CONNECT',
  'android.permission.BLUETOOTH_ADVERTISE',
  'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.MODIFY_AUDIO_SETTINGS',
};

/// Boot-time Dart service names. Deferred names are appended only when the
/// compiled policy allows initialization.
class CoreBootServices {
  static const List<String> required = [
    'TTS',
    'Battery',
    'Thermal',
    'Memory',
    'Earcon',
    'Compass',
    'Orientation',
    'Steps',
    'Waypoints',
    'SOS',
    '2GIS',
    'Voice',
  ];

  static const String paymentSms = 'PaymentSMS';
  static const String objectMemory = 'ObjectMemory';
  static const String acousticWorldModel = 'AWM';

  static List<String> namesFor(CoreFeaturePolicy policy) {
    final names = List<String>.from(required);
    if (policy.mayInitialize(CoreFeature.paymentSms)) {
      names.add(paymentSms);
    }
    if (policy.mayInitialize(CoreFeature.objectMemoryFinder)) {
      names.add(objectMemory);
    }
    if (policy.mayInitialize(CoreFeature.acousticWorldModel)) {
      names.add(acousticWorldModel);
    }
    return names;
  }
}
