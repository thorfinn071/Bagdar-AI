import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/depth_pipeline_controller.dart'
    show DepthPipelineController;
import 'package:bagdar/camera/fall_countdown_controller.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/thermal_monitor.dart';
import 'package:bagdar/services/winter_mode_service.dart';
import 'package:bagdar/utils/depth_hazard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WinterModeService (Winter Mode block)', () {
    late WinterModeService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      svc = WinterModeService();
      svc.loadFromSettings();
    });

    test('defaults to OFF when nothing is set', () {
      expect(svc.active, isFalse);
      expect(svc.isManualEnabled, isFalse);
      expect(svc.isAutoEnabled, isFalse);
    });

    test('manual setter persists and flips active', () async {
      await svc.setManualEnabled(true);
      expect(svc.active, isTrue);
      expect(svc.isManualEnabled, isTrue);

      final reloaded = WinterModeService();
      reloaded.loadFromSettings();
      expect(reloaded.isManualEnabled, isTrue,
          reason: 'manual toggle must survive process restart');
    });

    test(
      'auto-detect trips only after `kAutoEnableMinAge` consecutive cold '
      'readings, and auto-disables on the first warm reading',
      () {
        ThermalReadings cold(double t) => ThermalReadings(
              batteryTempC: t,
              thermalStatus: null,
              severity: ThermalSeverity.normal,
            );

        
        svc.noteThermalReading(
            cold(WinterModeService.kAutoEnableBatteryTempC - 1));
        expect(svc.isAutoEnabled, isFalse);

        
        svc.noteThermalReading(
            cold(WinterModeService.kAutoEnableBatteryTempC - 2));
        expect(svc.isAutoEnabled, isTrue);
        expect(svc.active, isTrue);

        
        svc.noteThermalReading(cold(25.0));
        expect(svc.isAutoEnabled, isFalse);
        expect(svc.active, isFalse);
      },
    );

    test(
      'auto-detect cannot turn OFF a manual toggle: user intent wins',
      () async {
        await svc.setManualEnabled(true);
        svc.noteThermalReading(const ThermalReadings(
          batteryTempC: 30.0,
          thermalStatus: null,
          severity: ThermalSeverity.normal,
        ));
        expect(svc.isAutoEnabled, isFalse,
            reason: 'warm battery = no auto-enable');
        expect(svc.active, isTrue,
            reason: 'manual toggle keeps effective state ON');
      },
    );

    test('null battery temp clears the streak without flipping state', () {
      svc.noteThermalReading(const ThermalReadings(
        batteryTempC: WinterModeService.kAutoEnableBatteryTempC - 1,
        thermalStatus: null,
        severity: ThermalSeverity.normal,
      ));
      svc.noteThermalReading(const ThermalReadings.unavailable());
      expect(svc.isAutoEnabled, isFalse);
      
      svc.noteThermalReading(const ThermalReadings(
        batteryTempC: 0.0,
        thermalStatus: null,
        severity: ThermalSeverity.normal,
      ));
      expect(svc.isAutoEnabled, isFalse,
          reason: 'null reading reset the streak');
    });
  });

  group('ThermalReadings.severityFor (Winter Mode)', () {
    test('normal mode: 41 °C is "hot", 43 °C is "critical"', () {
      expect(
        ThermalReadings.severityFor(batteryTempC: 41.0),
        ThermalSeverity.hot,
      );
      expect(
        ThermalReadings.severityFor(batteryTempC: 43.0),
        ThermalSeverity.critical,
      );
    });

    test('winter mode: critical ceiling drops to 38 °C', () {
      expect(
        ThermalReadings.severityFor(batteryTempC: 37.9, winterMode: true),
        ThermalSeverity.warm,
        reason: 'below 38 °C still "warm" (37 °C warm threshold kicks in)',
      );
      expect(
        ThermalReadings.severityFor(batteryTempC: 38.0, winterMode: true),
        ThermalSeverity.critical,
        reason: 'exactly 38 °C trips critical under Winter Mode',
      );
      expect(
        ThermalReadings.severityFor(batteryTempC: 41.0, winterMode: true),
        ThermalSeverity.critical,
      );
    });

    test(
      'ThermalReadings.kWinterCriticalTempC is 38 °C and kThermalCriticalTempC '
      'is unchanged',
      () {
        expect(ThermalReadings.kWinterCriticalTempC, 38.0);
        expect(kThermalCriticalTempC, 43.0);
      },
    );
  });

  group('DepthPipelineController._isHazardCritical (Winter Mode)', () {
    DepthHazard slippery(HazardZone zone, double score) => DepthHazard(
          type: DepthHazardType.slippery,
          zone: zone,
          midasScore: score,
          coverage: 0.5,
        );

    test(
      'normal mode: slippery in the LEFT zone is NOT critical even at high '
      'score — zone gate holds',
      () {
        final crit = DepthPipelineController.isHazardCriticalForTesting(
          slippery(HazardZone.left, 0.80),
          rollExcessive: false,
          userStationary: false,
        );
        expect(crit, isFalse,
            reason: 'default behavior from C3: only center lane is critical');
      },
    );

    test(
      'winter mode: slippery in the LEFT zone IS critical at the score '
      'floor — black ice off-center still ends a walk badly',
      () {
        final crit = DepthPipelineController.isHazardCriticalForTesting(
          slippery(HazardZone.left, 0.80),
          rollExcessive: false,
          userStationary: false,
          winterMode: true,
        );
        expect(crit, isTrue);
      },
    );

    test(
      'winter mode: slippery still suppressed for stationary users '
      '(no point shouting "Stop!" at a standing user)',
      () {
        final crit = DepthPipelineController.isHazardCriticalForTesting(
          slippery(HazardZone.left, 0.80),
          rollExcessive: false,
          userStationary: true,
          winterMode: true,
        );
        expect(crit, isFalse);
      },
    );

    test(
      'winter mode: below score floor (0.50) still not critical even off-'
      'center',
      () {
        final crit = DepthPipelineController.isHazardCriticalForTesting(
          slippery(HazardZone.right, 0.40),
          rollExcessive: false,
          userStationary: false,
          winterMode: true,
        );
        expect(crit, isFalse);
      },
    );

    test(
      'winter mode does not change behavior for non-slippery hazards',
      () {
        const pothole = DepthHazard(
          type: DepthHazardType.pothole,
          zone: HazardZone.right,
          midasScore: 0.70,
          coverage: 0.5,
        );
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            pothole,
            rollExcessive: false,
            winterMode: false,
          ),
          isFalse,
        );
        expect(
          DepthPipelineController.isHazardCriticalForTesting(
            pothole,
            rollExcessive: false,
            winterMode: true,
          ),
          isFalse,
          reason: 'off-center potholes remain non-critical in winter too',
        );
      },
    );
  });

  group('FallCountdownController window scaling (Winter Mode)', () {
    test('15 s × 0.7 ceiling-rounds to 11 s', () {
      final out = FallCountdownController.scaleDurationForTesting(
        FallCountdownController.kInitialDuration,
        FallCountdownController.kWinterCancelWindowScale,
      );
      expect(out.inSeconds, 11,
          reason: '10.5 s must round UP — leave the user slightly more time');
    });

    test('30 s × 0.7 = exactly 21 s', () {
      final out = FallCountdownController.scaleDurationForTesting(
        FallCountdownController.kCollapseDuration,
        FallCountdownController.kWinterCancelWindowScale,
      );
      expect(out.inSeconds, 21);
    });

    test('scale of 1.0 is an identity', () {
      final out = FallCountdownController.scaleDurationForTesting(
        const Duration(seconds: 15),
        1.0,
      );
      expect(out, const Duration(seconds: 15));
    });

    test('scale is clamped to at least 1 s regardless of input', () {
      final out = FallCountdownController.scaleDurationForTesting(
        const Duration(milliseconds: 200),
        0.01,
      );
      expect(out.inSeconds, greaterThanOrEqualTo(1));
    });

    test(
      'kWinterCancelWindowScale matches the documented 30 % reduction',
      () {
        expect(
          FallCountdownController.kWinterCancelWindowScale,
          WinterModeService.kCancelWindowScale,
          reason: 'both sources must declare the same 0.7 multiplier',
        );
        expect(FallCountdownController.kWinterCancelWindowScale, 0.7);
      },
    );
  });
}
