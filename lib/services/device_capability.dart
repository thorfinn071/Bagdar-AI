import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'arcore_depth_whitelist.dart';
import 'hardware_depth_bridge.dart';

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

enum DepthTier { hardware, midasNnapi, midasCpu, focalLength }

class DeviceCapabilities {
  final DepthTier bestDepthTier;
  final bool supportsNnApi;
  final int androidSdkInt;
  final DeviceInfo deviceInfo;

  const DeviceCapabilities({
    required this.bestDepthTier,
    required this.supportsNnApi,
    required this.androidSdkInt,
    this.deviceInfo = const DeviceInfo.unknown(),
  });

  bool get isLowEnd =>
      deviceInfo.isLikelyLowEnd || bestDepthTier == DepthTier.focalLength;

  @override
  String toString() =>
      'DeviceCapabilities(tier=$bestDepthTier, nnapi=$supportsNnApi, '
      'sdk=$androidSdkInt, model=${deviceInfo.model})';
}

class DeviceCapabilityProbe {
  DeviceCapabilityProbe._();

  
  
  
  static const String _kTierKey = 'vg_depth_tier_v2';
  static const String _kSdkKey = 'vg_android_sdk_v2';
  static const String _kNnApiKey = 'vg_nnapi_v2';
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
    final savedNnApi = prefs.getBool(_kNnApiKey);

    if (savedIdx != null && savedIdx < DepthTier.values.length) {
      final tier = DepthTier.values[savedIdx];
      _cached = DeviceCapabilities(
        bestDepthTier: tier,
        supportsNnApi: savedNnApi ?? tier == DepthTier.midasNnapi,
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
    await prefs.remove(_kNnApiKey);
    return probe();
  }

  static Future<DeviceCapabilities> _runFreshProbe(
    SharedPreferences prefs,
  ) async {
    final info = await _readDeviceInfo();
    final sdk = info.sdkInt > 0 ? info.sdkInt : await _androidSdkInt();
    final hardwareDepth = await _probeHardwareDepthWithWhitelist(info);
    final nnapi = (Platform.isAndroid && sdk >= 28)
        ? await _probeNnApi()
        : false;

    final DepthTier tier;
    if (hardwareDepth) {
      tier = DepthTier.hardware;
    } else if (nnapi) {
      tier = DepthTier.midasNnapi;
    } else if (sdk >= 26 || !Platform.isAndroid) {
      tier = DepthTier.midasCpu;
    } else {
      tier = DepthTier.focalLength;
    }

    await prefs.setInt(_kTierKey, tier.index);
    await prefs.setInt(_kSdkKey, sdk);
    await prefs.setBool(_kNnApiKey, nnapi);

    _cached = DeviceCapabilities(
      bestDepthTier: tier,
      supportsNnApi: nnapi,
      androidSdkInt: sdk,
      deviceInfo: info,
    );
    debugPrint('DeviceCapabilityProbe: зондирование завершено — $_cached');
    return _cached!;
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

  static Future<bool> _probeNnApi() async {
    try {
      final opts = InterpreterOptions()..useNnApiForAndroid = true;
      final interp = await Interpreter.fromAsset(
        'assets/yolov8n_int8.tflite',
        options: opts,
      );
      interp.close();
      debugPrint('DeviceCapabilityProbe: NNAPI доступен');
      return true;
    } catch (e) {
      debugPrint('DeviceCapabilityProbe: NNAPI недоступен — $e');
      return false;
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

  @visibleForTesting
  static void resetCacheForTesting() => _cached = null;
}
