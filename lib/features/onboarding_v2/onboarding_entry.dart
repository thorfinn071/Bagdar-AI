import 'package:shared_preferences/shared_preferences.dart';

import '../../camera_screen.dart';
import '../../models/app_mode.dart';
import '../../models/strings.dart';
import '../../services/feature_usage_tracker.dart';
import '../../services/language_pack_manager.dart';
import '../../services/native_tts_bridge.dart';
import '../../services/settings_service.dart';
import 'onboarding_controller.dart';
import 'onboarding_inspection_route.dart';
import 'native_onboarding_gateway.dart';
import 'onboarding_screen.dart';
import 'onboarding_state.dart';
import 'onboarding_store.dart';

/// The sole application entry. Legacy completion flags never grant admission.
typedef OnboardingEntryFactory = OnboardingV2Screen Function();

/// Loading returns inert data in a factory. A timed-out boot attempt cannot
/// create a controller, start a gateway, or replace the visible recovery UI.
Future<OnboardingEntryFactory> loadOnboardingV2Entry() async {
  await Settings.instance.init();
  final preferences = await SharedPreferences.getInstance();
  final languageIndex = Settings.instance.language;
  return () => OnboardingV2Screen(
    controller: OnboardingController(
      store: PreferencesOnboardingStore(preferences),
      gateway: NativeOnboardingGateway(),
      initialLanguage: AppLanguage.values[languageIndex.clamp(0, 2)],
    ),
    onInspect: (context, controller) async {
      if (controller.admission != Admission.inspectionOnly) return;
      await controller.gateway.stop();
      await Settings.instance.setLanguage(controller.progress.language.index);
      AppStrings.setLanguage(controller.progress.language);
      await FeatureUsageTracker.instance.init();
      await LanguagePackManager.instance.init();
      await NativeTtsBridge.instance.init();
      // Setup checks may expire during initialization. Runtime checks its own
      // Core health; onboarding does not seed it with a stale "ready" snapshot.
      if (!context.mounted ||
          controller.admission != Admission.inspectionOnly) {
        return;
      }
      await openOnboardingInspection(
        context,
        controller,
        builder: (_) => const AiCameraScreen(initialMode: AppMode.scan),
      );
    },
  );
}

Future<OnboardingV2Screen> createOnboardingV2Entry() async =>
    (await loadOnboardingV2Entry())();
