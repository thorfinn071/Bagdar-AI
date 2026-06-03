import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arcore_depth_whitelist.dart';
import 'hardware_depth_bridge.dart';
import 'ncnn_depth_bridge.dart';

class DeviceInfo {
  final String manufacturer;
  final String model;
  final String device;
  final String brand;
  final String hardware;
  final int sdkInt;

  const DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.device,
    required this.brand,
    required this.hardware,
    required this.sdkInt,
  });

  const DeviceInfo.unknown()
    : manufacturer = '',
      model = '',
      device = '',
      brand = '',
      hardware = '',
      sdkInt = 0;

  bool get isLikelyLowEnd {
    if (sdkInt > 0 && sdkInt < 28) return true;
    final b = brand.toUpperCase();
    if (b == 'ITEL' || b == 'INFINIX' || b == 'TECNO') return true;
    return false;
  }
}

enum DepthTier { hardware, ncnnVulkan, ncnnCpu, focalLength }

/// Capability flags for optional non-camera hardware. Populated at probe
/// time and stored alongside the depth tier so growth-direction services
/// (mesh-net BLE, OSCP cane, sonar FMCW chirp, charging-mode VLM) can
/// gate themselves without re-querying the OS on every frame.
///
/// All flags default to `false` so a probe failure never claims a
/// capability the device does not have.
class HardwareCapabilities {
  /// BLE central role available (advertise/scan as the active peer).
  /// Required for both `MeshBuddyAlertService` and `OscpService`.
  final bool bleCentral;

  /// BLE peripheral role available (advertise GATT services). Some
  /// budget chipsets support central only; mesh fall-back degrades to
  /// scan-only behaviour when this is false.
  final bool blePeripheral;

  /// Microphone reports support for 48 kHz capture. Required by the
  /// FMCW sonar prototype (chirps fall in the 18–22 kHz band and need
  /// the 24 kHz Nyquist of a 48 kHz stream).
  final bool micSupports48kHz;

  /// Loudspeaker is believed to reproduce 18–22 kHz at usable SPL.
  /// `null` when unknown (most devices). Sonar pre-flight calibration
  /// will refine this at runtime; the flag is advisory only.
  final bool? speakerSupportsHighFreq;

  /// Device is currently charging (any charger type). Re-read on demand;
  /// this snapshot is a hint for the probe-time decision only.
  final bool charging;

  /// Free internal storage at probe time, in megabytes. Used by optional
  /// pack downloaders (`LanguagePackManager`, `MapPackageManager`,
  /// future `ModelPackManager`) to refuse downloads that would breach
  /// the safety margin.
  final int freeStorageMb;

  const HardwareCapabilities({
    this.bleCentral = false,
    this.blePeripheral = false,
    this.micSupports48kHz = false,
    this.speakerSupportsHighFreq,
    this.charging = false,
    this.freeStorageMb = -1,
  });

  /// Storage class buckets exposed for pack manifests so they can refuse
  /// (or warn about) installs when free space is tight.
  bool get freeStorageGtTwoGb => freeStorageMb >= 2048;
  bool get freeStorageGtFiveHundredMb => freeStorageMb >= 500;
  bool get freeStorageGtOneHundredMb => freeStorageMb >= 100;

  @override
  String toString() =>
      'HardwareCapabilities(bleCentral=$bleCentral, blePeripheral=$blePeripheral, '
      'mic48k=$micSupports48kHz, hiFreq=$speakerSupportsHighFreq, '
      'charging=$charging, freeMb=$freeStorageMb)';
}

class DeviceCapabilities {
  final DepthTier bestDepthTier;
  final int androidSdkInt;
  final DeviceInfo deviceInfo;
  final HardwareCapabilities hardware;

  const DeviceCapabilities({
    required this.bestDepthTier,
    required this.androidSdkInt,
    this.deviceInfo = const DeviceInfo.unknown(),
    this.hardware = const HardwareCapabilities(),
  });

  bool get isLowEnd =>
      deviceInfo.isLikelyLowEnd || bestDepthTier == DepthTier.focalLength;

  /// Convenience: true when the device satisfies the *minimum* feasibility
  /// gate for mesh-net buddy alerts (BLE central role + Android 8+).
  bool get meshFeasible =>
      hardware.bleCentral && androidSdkInt >= 26;

  /// Convenience: true when the device satisfies the minimum gate for
  /// the FMCW sonar prototype (48 kHz mic). The Hi-freq speaker flag is
  /// advisory only — calibration confirms it at runtime.
  bool get sonarFeasible => hardware.micSupports48kHz;

  @override
  String toString() =>
      'DeviceCapabilities(tier=$bestDepthTier, '
      'sdk=$androidSdkInt, model=${deviceInfo.model}, '
      'hw=$hardware)';
}

class DeviceCapabilityProbe {
  DeviceCapabilityProbe._();

  
  static const String _kTierKey = 'vg_depth_tier_v3';
  static const String _kSdkKey = 'vg_android_sdk_v3';
  static const MethodChannel _channel = MethodChannel('bagdar/device_info');

  static DeviceCapabilities? _cached;

  static DeviceCapabilities get cached {
    assert(_cached != null, 'Вызовите probe() перед обращением к cached');
    return _cached!;
  }

  static Future<DeviceCapabilities> probe() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    final savedIdx = prefs.getInt(_kTierKey);
    final savedSdk = prefs.getInt(_kSdkKey) ?? 0;

    if (savedIdx != null &&
        savedIdx >= 0 &&
        savedIdx < DepthTier.values.length) {
      final tier = DepthTier.values[savedIdx];
      _cached = DeviceCapabilities(
        bestDepthTier: tier,
        androidSdkInt: savedSdk,
      );
      debugPrint('DeviceCapabilityProbe: кеш восстановлен — $_cached');
      return _cached!;
    }

    return _runFreshProbe(prefs);
  }

  static Future<DeviceCapabilities> reprobeAndSave() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTierKey);
    await prefs.remove(_kSdkKey);
    return probe();
  }

  static Future<DeviceCapabilities> _runFreshProbe(
    SharedPreferences prefs,
  ) async {
    final info = await _readDeviceInfo();
    final sdk = info.sdkInt > 0 ? info.sdkInt : await _androidSdkInt();
    final hardwareDepth = await _probeHardwareDepthWithWhitelist(info);
    final ncnnAvailable = _probeNcnn();
    final hw = await _readHardwareCapabilities();

    final DepthTier tier;
    if (hardwareDepth) {
      tier = DepthTier.hardware;
    } else if (ncnnAvailable) {
      tier = DepthTier.ncnnVulkan;
    } else {
      tier = DepthTier.focalLength;
    }

    await prefs.setInt(_kTierKey, tier.index);
    await prefs.setInt(_kSdkKey, sdk);

    _cached = DeviceCapabilities(
      bestDepthTier: tier,
      androidSdkInt: sdk,
      deviceInfo: info,
      hardware: hw,
    );
    debugPrint('DeviceCapabilityProbe: зондирование завершено — $_cached');
    return _cached!;
  }

  /// Probe non-camera hardware. The native side (`bagdar/device_info`
  /// `getHardwareCapabilities`) is the source of truth when present;
  /// older builds return `null` and we fall back to conservative
  /// defaults. Result is never cached on disk because charging state is
  /// inherently volatile — re-probe on demand if a service needs a
  /// fresh read.
  static Future<HardwareCapabilities> _readHardwareCapabilities() async {
    if (!Platform.isAndroid) return const HardwareCapabilities();
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getHardwareCapabilities')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return const HardwareCapabilities();
      return HardwareCapabilities(
        bleCentral: (raw['bleCentral'] as bool?) ?? false,
        blePeripheral: (raw['blePeripheral'] as bool?) ?? false,
        micSupports48kHz: (raw['micSupports48kHz'] as bool?) ?? false,
        speakerSupportsHighFreq: raw['speakerSupportsHighFreq'] as bool?,
        charging: (raw['charging'] as bool?) ?? false,
        freeStorageMb: ((raw['freeStorageMb'] as num?) ?? -1).toInt(),
      );
    } catch (e) {
      debugPrint(
        'DeviceCapabilityProbe: getHardwareCapabilities unavailable '
        '($e). Optional features will gate themselves off.',
      );
      return const HardwareCapabilities();
    }
  }

  /// Re-read volatile hardware state (charging / free storage). Cheap.
  /// Optional pack downloaders should call this before kicking off
  /// large downloads instead of trusting the boot-time snapshot.
  static Future<HardwareCapabilities> readHardwareCapabilities() =>
      _readHardwareCapabilities();

  static bool _probeNcnn() {
    if (!Platform.isAndroid) return false;
    final bridge = NcnnDepthBridge.tryCreate();
    if (bridge == null) {
      debugPrint('DeviceCapabilityProbe: NCNN bridge unavailable');
      return false;
    }
    debugPrint('DeviceCapabilityProbe: NCNN bridge available');
    return true;
  }

  static Future<DeviceInfo> _readDeviceInfo() async {
    if (!Platform.isAndroid) return const DeviceInfo.unknown();
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceInfo',
      );
      if (raw == null) return const DeviceInfo.unknown();
      return DeviceInfo(
        manufacturer: (raw['manufacturer'] as String?) ?? '',
        model: (raw['model'] as String?) ?? '',
        device: (raw['device'] as String?) ?? '',
        brand: (raw['brand'] as String?) ?? '',
        hardware: (raw['hardware'] as String?) ?? '',
        sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('DeviceCapabilityProbe: getDeviceInfo failed ($e)');
      return const DeviceInfo.unknown();
    }
  }

  static Future<bool> _probeHardwareDepthWithWhitelist(DeviceInfo info) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final verdict = Platform.isAndroid
        ? ArCoreDepthWhitelist.verdict(
            manufacturer: info.manufacturer,
            model: info.model,
            brand: info.brand,
            sdkInt: info.sdkInt,
          )
        : ArCoreDepthVerdict.unknown;
    switch (verdict) {
      case ArCoreDepthVerdict.unsupported:
        debugPrint(
          'DeviceCapabilityProbe: ARCore depth blacklisted '
          '(${info.brand}/${info.model}) — skipping probe',
        );
        return false;
      case ArCoreDepthVerdict.supported:
        debugPrint(
          'DeviceCapabilityProbe: ARCore depth whitelisted '
          '(${info.model}) — skipping probe',
        );
        return true;
      case ArCoreDepthVerdict.unknown:
        return _probeHardwareDepth();
    }
  }

  static Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final sdk = await _channel.invokeMethod<int>('getSdkInt');
      return sdk ?? 26;
    } catch (e) {
      debugPrint('DeviceCapabilityProbe: getSdkInt ошибка ($e), fallback=26');
      return 26;
    }
  }

  static Future<bool> _probeHardwareDepth() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final bridge = HardwareDepthBridge();
      final supported = await bridge.isSupported();
      debugPrint(
        'DeviceCapabilityProbe: hardware depth ${supported ? "доступен" : "недоступен"}',
      );
      return supported;
    } catch (e) {
      debugPrint('DeviceCapabilityProbe: hardware depth probe failed ($e)');
      return false;
    }
  }

  static Future<int> getFreeBytesAtPath(String path) async {
    if (!Platform.isAndroid) return -1;
    try {
      final bytes = await _channel.invokeMethod<int>('getFreeBytesAtPath', {
        'path': path,
      });
      return bytes ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Returns whatever opportunistic network locators the OS exposes:
  /// Wi-Fi SSID/BSSID, registered cell tower fingerprint, carrier name.
  /// All fields are optional. Used by SOS fallback when GPS is unavailable.
  /// Returns an empty map on non-Android or any failure.
  static Future<Map<String, String>> getNetworkContext() async {
    if (!Platform.isAndroid) return const <String, String>{};
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getNetworkContext')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return const <String, String>{};
      final out = <String, String>{};
      for (final entry in raw.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key == null || value == null || value.isEmpty) continue;
        out[key] = value;
      }
      return out;
    } catch (_) {
      return const <String, String>{};
    }
  }

  @visibleForTesting
  static void resetCacheForTesting() => _cached = null;
}
