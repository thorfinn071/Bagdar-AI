import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';



enum DepthTier {
  hardware,
  midasNnapi,
  midasCpu,
  focalLength,
}



class DeviceCapabilities {
  final DepthTier bestDepthTier;
  final bool supportsNnApi;
  final int androidSdkInt;

  const DeviceCapabilities({
    required this.bestDepthTier,
    required this.supportsNnApi,
    required this.androidSdkInt,
  });

  @override
  String toString() =>
      'DeviceCapabilities(tier=$bestDepthTier, nnapi=$supportsNnApi, '
      'sdk=$androidSdkInt)';
}



class DeviceCapabilityProbe {
  DeviceCapabilityProbe._();

  static const String _kTierKey = 'vg_depth_tier_v1';
  static const String _kSdkKey  = 'vg_android_sdk_v1';
  static const MethodChannel _channel =
      MethodChannel('vision_guide/device_info');

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

    if (savedIdx != null && savedIdx < DepthTier.values.length) {
      final tier = DepthTier.values[savedIdx];
      _cached = DeviceCapabilities(
        bestDepthTier: tier,
        supportsNnApi:
            tier == DepthTier.midasNnapi || tier == DepthTier.hardware,
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
      SharedPreferences prefs) async {
    final sdk   = await _androidSdkInt();
    final nnapi = (Platform.isAndroid && sdk >= 28)
        ? await _probeNnApi()
        : false;

    final DepthTier tier;
    if (nnapi) {
      tier = DepthTier.midasNnapi;
    } else if (sdk >= 26 || !Platform.isAndroid) {
      tier = DepthTier.midasCpu;
    } else {
      tier = DepthTier.focalLength;
    }

    await prefs.setInt(_kTierKey, tier.index);
    await prefs.setInt(_kSdkKey, sdk);

    _cached = DeviceCapabilities(
      bestDepthTier: tier,
      supportsNnApi: nnapi,
      androidSdkInt: sdk,
    );
    debugPrint('DeviceCapabilityProbe: зондирование завершено — $_cached');
    return _cached!;
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

  @visibleForTesting
  static void resetCacheForTesting() => _cached = null;
}
