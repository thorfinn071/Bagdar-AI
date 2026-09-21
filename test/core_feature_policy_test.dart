import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/core/core_feature_policy.dart';
import 'package:bagdar/models/generic_obstacle_mode.dart';
import 'package:bagdar/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoreFeaturePolicy', () {
    test('default compiled profile is Core', () {
      expect(BuildProfile.current, BuildProfile.core);
      expect(CoreFeaturePolicy.current.profile, BuildProfile.core);
      expect(CoreFeaturePolicy.current.allowsDeferredExperiments, isFalse);
    });

    test(
      'Core policy excludes every deferred experiment from init/UI/permissions',
      () {
        const policy = CoreFeaturePolicy(BuildProfile.core);
        for (final feature in CoreFeature.values) {
          expect(policy.isCompiled(feature), isFalse, reason: feature.name);
          expect(policy.mayInitialize(feature), isFalse, reason: feature.name);
          expect(
            policy.mayRequestPermission(feature),
            isFalse,
            reason: feature.name,
          );
          expect(policy.mayShowInUi(feature), isFalse, reason: feature.name);
        }
      },
    );

    test('research policy compiles and allows deferred experiments', () {
      const policy = CoreFeaturePolicy(BuildProfile.research);
      expect(policy.allowsDeferredExperiments, isTrue);
      for (final feature in CoreFeature.values) {
        expect(policy.mayInitialize(feature), isTrue, reason: feature.name);
        expect(policy.mayShowInUi(feature), isTrue, reason: feature.name);
      }
    });
  });

  group('CoreBootServices', () {
    test('Core startup list does not initialize deferred services', () {
      final names = CoreBootServices.namesFor(CoreFeaturePolicy.current);
      expect(names, CoreBootServices.required);
      expect(names, isNot(contains(CoreBootServices.paymentSms)));
      expect(names, isNot(contains(CoreBootServices.objectMemory)));
      expect(names, isNot(contains(CoreBootServices.acousticWorldModel)));
    });

    test('research startup list includes deferred services', () {
      final names = CoreBootServices.namesFor(
        const CoreFeaturePolicy(BuildProfile.research),
      );
      expect(names, containsAll(CoreBootServices.required));
      expect(names, contains(CoreBootServices.paymentSms));
      expect(names, contains(CoreBootServices.objectMemory));
      expect(names, contains(CoreBootServices.acousticWorldModel));
    });
  });

  group('Settings cannot bypass Core policy', () {
    setUp(() {
      Settings.instance.debugResetPolicy();
      SharedPreferences.setMockInitialValues({
        'feature_bazaar_mode': true,
        'feature_livestock_awareness': true,
        'feature_mesh_buddy_alerts': true,
        'feature_sonar_depth': true,
        'feature_vlm_companion': true,
        'feature_indoor_trail_memory': true,
        'feature_oscp_pod': true,
        'feature_local_asr_adaptation': true,
        'payment_sms_enabled': true,
        'winter_mode_manual': true,
        'scene_narration_enabled': true,
        'enable_kazakh_stack_v2': true,
        'generic_obstacle_mode': GenericObstacleMode.assistive.index,
      });
    });

    test('stale experiment preferences stay inert on a Core build', () async {
      await Settings.instance.init();
      expect(BuildProfile.current, BuildProfile.core);
      expect(Settings.instance.bazaarMode, isFalse);
      expect(Settings.instance.livestockAwareness, isFalse);
      expect(Settings.instance.meshBuddyAlerts, isFalse);
      expect(Settings.instance.sonarDepth, isFalse);
      expect(Settings.instance.vlmCompanion, isFalse);
      expect(Settings.instance.indoorTrailMemory, isFalse);
      expect(Settings.instance.oscpPod, isFalse);
      expect(Settings.instance.localAsrAdaptation, isFalse);
      expect(Settings.instance.paymentSmsEnabled, isFalse);
      expect(Settings.instance.winterModeManual, isFalse);
      expect(Settings.instance.sceneNarrationEnabled, isFalse);
      expect(Settings.instance.enableKazakhStackV2, isFalse);
      expect(Settings.instance.genericObstacleMode, GenericObstacleMode.shadow);
    });

    test('setters for excluded features are no-ops on Core', () async {
      await Settings.instance.init();
      await Settings.instance.setBazaarMode(true);
      await Settings.instance.setPaymentSmsEnabled(true);
      await Settings.instance.setEnableKazakhStackV2(true);
      expect(Settings.instance.bazaarMode, isFalse);
      expect(Settings.instance.paymentSmsEnabled, isFalse);
      expect(Settings.instance.enableKazakhStackV2, isFalse);
    });
  });
}
