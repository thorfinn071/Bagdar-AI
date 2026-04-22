import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ModelService.instance.debugInjectAvailableAssets(<String>{});
    DeviceCapabilityProbe.resetCacheForTesting();
  });

  group('DeviceCapabilities.isLowEnd', () {
    test('true for focal-length tier', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.focalLength,
        supportsNnApi: false,
        androidSdkInt: 26,
      );
      expect(caps.isLowEnd, isTrue);
    });

    test('true when OEM brand is on budget blacklist', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasCpu,
        supportsNnApi: false,
        androidSdkInt: 30,
        deviceInfo: DeviceInfo(
          manufacturer: 'ITEL',
          model: 'A17',
          device: 'itel',
          brand: 'ITEL',
          hardware: 'mt6580',
          sdkInt: 30,
        ),
      );
      expect(caps.isLowEnd, isTrue);
    });

    test('false for mid-range midasCpu on a normal brand', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.midasCpu,
        supportsNnApi: false,
        androidSdkInt: 30,
        deviceInfo: DeviceInfo(
          manufacturer: 'Xiaomi',
          model: 'Redmi Note 12',
          device: 'spes',
          brand: 'xiaomi',
          hardware: 'qcom',
          sdkInt: 30,
        ),
      );
      expect(caps.isLowEnd, isFalse);
    });
  });

  group('ModelService AssetManifest resolver', () {
    test('hasSmallYoloAsset reports true when injected', () async {
      final svc = ModelService.instance;
      svc.debugInjectAvailableAssets({
        'assets/yolov8n_int8.tflite',
        'assets/yolov8n_320_int8.tflite',
        'assets/labels.txt',
      });
      expect(await svc.hasSmallYoloAsset(), isTrue);
    });

    test('hasSmallYoloAsset reports false when absent', () async {
      final svc = ModelService.instance;
      svc.debugInjectAvailableAssets({
        'assets/yolov8n_int8.tflite',
        'assets/labels.txt',
      });
      expect(await svc.hasSmallYoloAsset(), isFalse);
    });
  });
}
