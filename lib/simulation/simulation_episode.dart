import 'dart:async';

import 'package:flutter/material.dart';

/// A batch episode has no visual transition to delay disposal of shared services.
/// Interactive inspection retains the normal Material route.
Future<void> runSimulationEpisode({
  required BuildContext context,
  required WidgetBuilder builder,
  required bool automatic,
  Duration timeout = const Duration(seconds: 90),
  Duration disposalTimeout = const Duration(seconds: 10),
}) async {
  final navigator = Navigator.of(context);
  final TransitionRoute<void> route = automatic
      ? PageRouteBuilder<void>(
          pageBuilder: (context, _, _) => builder(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
      : MaterialPageRoute<void>(builder: builder);
  try {
    final popped = navigator.push(route);
    if (automatic) {
      await popped.timeout(timeout);
      await route.completed.timeout(disposalTimeout);
    } else {
      await popped;
      await route.completed;
    }
  } catch (_) {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    rethrow;
  }
}
