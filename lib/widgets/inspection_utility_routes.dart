import 'package:flutter/material.dart';

import '../theme/bagdar_theme.dart';
import 'inspection_surface.dart';

class InspectionUtilityResult<T> {
  final bool opened;
  final bool interrupted;
  final T? value;
  const InspectionUtilityResult({
    this.opened = false,
    this.interrupted = false,
    this.value,
  });
}

enum _Presentation { dialog, sheet, page }

/// Owns the utility stack, including explicitly opened child dialogs. Removal
/// uses exact route objects, never a blind pop of the navigator's current page.
class InspectionUtilityRoutes {
  final bool Function() canOpen;
  final Future<bool> Function()? releaseVoiceInput;
  final Set<Route<dynamic>> _routes = {};
  Object? _preparing;
  bool _closing = false;
  bool _disposed = false;
  int _revision = 0;

  InspectionUtilityRoutes({required this.canOpen, this.releaseVoiceInput});

  Future<void> open(
    BuildContext context, {
    required WidgetBuilder builder,
    bool bottomSheet = false,
  }) async {
    await _present<void>(
      context,
      builder: builder,
      presentation: bottomSheet ? _Presentation.sheet : _Presentation.dialog,
    );
  }

  Future<InspectionUtilityResult<T>> openDialog<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) => _present<T>(
    context,
    builder: builder,
    presentation: _Presentation.dialog,
  );

  Future<InspectionUtilityResult<T>> openPage<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    Future<void> Function()? beforeOpen,
  }) => _present<T>(
    context,
    builder: builder,
    presentation: _Presentation.page,
    beforeOpen: beforeOpen,
  );

  Future<InspectionUtilityResult<T>> openChildDialog<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) => _present<T>(
    context,
    builder: builder,
    presentation: _Presentation.dialog,
    child: true,
  );

  bool get _allowed => !_disposed && !_closing && canOpen();

  Future<InspectionUtilityResult<T>> _present<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    required _Presentation presentation,
    Future<void> Function()? beforeOpen,
    bool child = false,
  }) async {
    if (!context.mounted || !_allowed || _preparing != null) {
      return const InspectionUtilityResult();
    }
    final origin = ModalRoute.of(context);
    if (child) {
      if (!_routes.contains(origin) || origin?.isCurrent != true) {
        return const InspectionUtilityResult();
      }
    } else if (_routes.any((route) => route.isActive) ||
        (origin != null && !origin.isCurrent)) {
      return const InspectionUtilityResult();
    }
    final revision = _revision;
    final reservation = Object();
    _preparing = reservation;
    Route<T>? route;
    try {
      if (!child && releaseVoiceInput != null &&
          !await releaseVoiceInput!()) {
        return const InspectionUtilityResult(interrupted: true);
      }
      if (beforeOpen != null) await beforeOpen();
      if (!context.mounted || !_allowed || revision != _revision) {
        return const InspectionUtilityResult(interrupted: true);
      }
      if (child && (origin?.isCurrent != true || !_routes.contains(origin))) {
        return const InspectionUtilityResult(interrupted: true);
      }
      if (!child && origin != null && !origin.isCurrent) {
        return const InspectionUtilityResult(interrupted: true);
      }
      final navigator = Navigator.of(context);
      if (!navigator.mounted) {
        return const InspectionUtilityResult(interrupted: true);
      }
      final themes = InheritedTheme.capture(
        from: context,
        to: navigator.context,
      );
      Widget content(BuildContext context) => Semantics(
        localeForSubtree: inspectionLocale,
        child: builder(context),
      );
      route = switch (presentation) {
        _Presentation.dialog => DialogRoute<T>(
          context: context,
          themes: themes,
          builder: content,
        ),
        _Presentation.sheet => ModalBottomSheetRoute<T>(
          builder: content,
          isScrollControlled: true,
          useSafeArea: true,
          capturedThemes: themes,
          backgroundColor: BagdarTheme.colorsOf(context).surfaceElevated,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
        ),
        _Presentation.page => MaterialPageRoute<T>(
          builder: (context) => themes.wrap(content(context)),
        ),
      };
      _routes.add(route);
      final popped = navigator.push<T>(route);
      _preparing = null;
      final value = await popped;
      return InspectionUtilityResult(
        opened: true,
        interrupted: revision != _revision || _disposed,
        value: value,
      );
    } finally {
      if (identical(_preparing, reservation)) _preparing = null;
      if (route != null) _routes.remove(route);
    }
  }

  void close() {
    ++_revision; // Also revokes a pending external-camera preparation.
    final routes = _routes.toList(growable: false).reversed.toList();
    _routes.clear();
    if (routes.isEmpty) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        for (final route in routes) {
          final navigator = route.navigator;
          if (navigator != null && navigator.mounted && route.isActive) {
            navigator.removeRoute(route);
          }
        }
      } finally {
        _closing = false;
      }
    });
    // A close/dispose call need not coincide with a host setState. Ensure the
    // removal callback gets a frame even when the navigator is otherwise idle.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void dispose() {
    _disposed = true;
    close();
  }
}
