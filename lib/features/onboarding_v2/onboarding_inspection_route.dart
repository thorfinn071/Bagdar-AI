import 'package:flutter/material.dart';

import 'onboarding_controller.dart';
import 'onboarding_state.dart';

/// Shared by the native entry and route tests. Returning from inspection always
/// invalidates ephemeral evidence; stored training and consent are preserved.
Future<void> openOnboardingInspection(
  BuildContext context,
  OnboardingController controller, {
  required WidgetBuilder builder,
}) async {
  if (!context.mounted || controller.admission != Admission.inspectionOnly) {
    return;
  }
  try {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
  } finally {
    controller.suspend();
  }
}
