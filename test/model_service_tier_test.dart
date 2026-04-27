import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/device_capability.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:bagdar/services/thermal_monitor.dart';

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
        androidSdkInt: 26,
      );
      expect(caps.isLowEnd, isTrue);
    });

    test('true when OEM brand is on budget blacklist', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnCpu,
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

    test('false for mid-range ncnnCpu on a normal brand', () {
      const caps = DeviceCapabilities(
        bestDepthTier: DepthTier.ncnnCpu,
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

  group('ModelService B-1 — adaptive YOLO tier on thermal severity', () {
    test(
      'thermal hot/critical wants small tier when asset is bundled',
      () {
        final svc = ModelService.instance;
        for (final sev in [
          ThermalSeverity.hot,
          ThermalSeverity.critical,
        ]) {
          expect(
            svc.debugDesiredTierForThermal(
              sev,
              hasSmall: true,
              isLowEnd: false,
            ),
            YoloInputTier.small,
            reason: 'severity=$sev with small-asset bundled must swap to small',
          );
        }
      },
    );

    test(
      'thermal hot/critical falls back to no-op when small asset missing',
      () {
        final svc = ModelService.instance;
        expect(
          svc.debugDesiredTierForThermal(
            ThermalSeverity.hot,
            hasSmall: false,
            isLowEnd: false,
          ),
          isNull,
          reason: 'no-op (null) preserves current tier when asset absent',
        );
      },
    );

    test(
      'thermal warm/normal returns standard for mid-range, small for low-end',
      () {
        final svc = ModelService.instance;
        for (final sev in [
          ThermalSeverity.normal,
          ThermalSeverity.warm,
        ]) {
          expect(
            svc.debugDesiredTierForThermal(
              sev,
              hasSmall: true,
              isLowEnd: false,
            ),
            YoloInputTier.standard,
          );
          expect(
            svc.debugDesiredTierForThermal(
              sev,
              hasSmall: true,
              isLowEnd: true,
            ),
            YoloInputTier.small,
          );
        }
      },
    );
  });
}
