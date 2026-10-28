import 'package:flutter/material.dart';

import '../camera/sos_ui_state.dart';
import '../models/strings.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';

Locale _sosLocale() => switch (S.current) {
  AppLanguage.ru => const Locale('ru', 'RU'),
  AppLanguage.kk => const Locale('kk', 'KZ'),
  AppLanguage.en => const Locale('en', 'US'),
};

/// Mounted last in the camera Stack. The curtain keeps the idle control dark
/// while retaining its position, hit target and accessible action.
class SosSurface extends StatelessWidget {
  final SosUiState state;
  final bool screenCurtain;
  final VoidCallback onSend;
  final VoidCallback onCancelCountdown;
  final VoidCallback onDismiss;

  const SosSurface({
    super.key,
    required this.state,
    required this.screenCurtain,
    required this.onSend,
    required this.onCancelCountdown,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final controls = Semantics(
      localeForSubtree: _sosLocale(),
      child: SosControls(
        state: state,
        onSend: onSend,
        onCancelCountdown: onCancelCountdown,
        onDismiss: onDismiss,
      ),
    );
    if (state.phase == SosUiPhase.idle) {
      return Positioned(
        top: 0,
        right: 0,
        left: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Opacity(
              opacity: screenCurtain ? 0 : 1,
              alwaysIncludeSemantics: true,
              child: controls,
            ),
          ),
        ),
      );
    }
    // Preserve the existing visible emergency override of the screen curtain.
    return Positioned.fill(
      child: BlockSemantics(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.7),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: controls,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explicit SOS controls, also mounted when the camera's screen curtain is on.
/// Speech is delivered by the existing emergency coordinator, not this view.
class SosControls extends StatefulWidget {
  final SosUiState state;
  final VoidCallback onSend;
  final VoidCallback onCancelCountdown;
  final VoidCallback onDismiss;

  const SosControls({
    super.key,
    required this.state,
    required this.onSend,
    required this.onCancelCountdown,
    required this.onDismiss,
  });

  @override
  State<SosControls> createState() => _SosControlsState();
}

class _SosControlsState extends State<SosControls> {
  bool _confirming = false;
  DialogRoute<bool>? _confirmationRoute;

  void _closeConfirmation() {
    final route = _confirmationRoute;
    _confirmationRoute = null;
    if (route == null) return;
    // State changes can dispose this surface while Navigator is building.
    // Remove this exact dialog after the frame, never a newer route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SosControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.phase != SosUiPhase.idle) _closeConfirmation();
  }

  @override
  void dispose() {
    _closeConfirmation();
    super.dispose();
  }

  Future<void> _confirmSend(BuildContext context) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    var decisionTaken = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      builder: (dialogContext) => Semantics(
        localeForSubtree: _sosLocale(),
        child: AlertDialog(
          title: Text(S.get('sos_manual_title')),
          content: Text(S.get('sos_manual_body')),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 56)),
              onPressed: () {
                if (decisionTaken) return;
                decisionTaken = true;
                Navigator.pop(dialogContext, false);
              },
              child: Text(S.get('sos_keep_using')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
              onPressed: () {
                if (decisionTaken) return;
                decisionTaken = true;
                Navigator.pop(dialogContext, true);
              },
              child: Text(S.get('sos_send_action')),
            ),
          ],
        ),
      ),
    );
    _confirmationRoute = route;
    try {
      final confirmed = await navigator.push(route);
      if (confirmed == true &&
          mounted &&
          widget.state.phase == SosUiPhase.idle) {
        widget.onSend();
      }
    } finally {
      if (identical(_confirmationRoute, route)) _confirmationRoute = null;
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = BagdarTheme.colorsOf(context);
    const buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 56)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
    if (state.phase == SosUiPhase.idle) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          key: const Key('sos-open'),
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(colors.surfaceElevated),
            foregroundColor: WidgetStatePropertyAll(colors.textPrimary),
          ),
          onPressed: _confirming ? null : () => _confirmSend(context),
          icon: const Icon(Icons.sos),
          label: Text(S.get('sos_action')),
        ),
      );
    }
    final countdown = state.phase == SosUiPhase.countdown;
    final message = countdown
        ? '${S.get('sos_fall_countdown')} ${state.secondsLeft} ${S.get('sos_fall_seconds')}'
        : S.get(state.messageKey);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          side: BorderSide(color: colors.stateDanger, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // No live region: countdown ticks must not compete with the
              // coordinator's critical speech or move accessibility focus.
              Semantics(
                header: true,
                child: Text(
                  message,
                  style: BagdarTypography.title.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (countdown) ...[
                const SizedBox(height: 12),
                Text(
                  S.get(
                    state.cancelConfirmationPending
                        ? 'sos_cancel_pending_hint'
                        : 'sos_cancel_action_hint',
                  ),
                  style: BagdarTypography.body.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('sos-cancel'),
                  style: buttonStyle,
                  onPressed: widget.onCancelCountdown,
                  child: Text(
                    S.get(
                      state.cancelConfirmationPending
                          ? 'sos_confirm_cancel_action'
                          : 'sos_cancel_action',
                    ),
                  ),
                ),
              ] else if (state.phase != SosUiPhase.sending) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const Key('sos-dismiss'),
                  style: buttonStyle,
                  onPressed: widget.onDismiss,
                  child: Text(S.get('sos_dismiss_action')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
