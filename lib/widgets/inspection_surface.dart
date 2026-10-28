import 'package:flutter/material.dart';

import '../camera/inspection_system_status.dart';
import '../camera/sos_ui_state.dart';
import '../models/strings.dart';
import '../theme/bagdar_theme.dart';
import 'sos_controls.dart';
import 'bagdar_ui.dart';

Locale get inspectionLocale => switch (S.current) {
  AppLanguage.ru => const Locale('ru', 'RU'),
  AppLanguage.kk => const Locale('kk', 'KZ'),
  AppLanguage.en => const Locale('en', 'US'),
};

/// The production camera composition. Its ordinary actions are siblings of
/// the physical gesture region, so activating a button cannot invoke a gesture.
class InspectionSurface extends StatelessWidget {
  final Widget background;
  final Widget? recovery;
  final List<Widget> overlays;
  final Widget? researchControls;
  final Widget? voiceControls;
  final bool screenCurtain;
  final SosUiState sosState;
  final InspectionSystemStatus status;
  final VoidCallback onStatus;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback? onFinish;
  final VoidCallback onSos;
  final VoidCallback onCancelSos;
  final VoidCallback onDismissSos;

  const InspectionSurface({
    super.key,
    required this.background,
    this.recovery,
    this.overlays = const [],
    this.researchControls,
    this.voiceControls,
    required this.screenCurtain,
    required this.sosState,
    required this.status,
    required this.onStatus,
    required this.onSettings,
    required this.onHelp,
    required this.onFinish,
    required this.onSos,
    required this.onCancelSos,
    required this.onDismissSos,
  });

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      background,
      if (screenCurtain) const ColoredBox(color: Colors.black),
      Semantics(
        localeForSubtree: inspectionLocale,
        child: Opacity(
          opacity: screenCurtain ? 0 : 1,
          alwaysIncludeSemantics: true,
          child: SafeArea(
            child: Column(
              children: [
                if (sosState.phase == SosUiPhase.idle)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SosControls(
                      state: sosState,
                      onSend: onSos,
                      onCancelCountdown: onCancelSos,
                      onDismiss: onDismissSos,
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bounds) => Column(
                      children: [
                        Expanded(child: recovery ?? const SizedBox.expand()),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                bounds.maxHeight * (recovery == null ? .8 : .6),
                          ),
                          child: SingleChildScrollView(
                            key: const Key('inspection-commands-scroll'),
                            padding: const EdgeInsets.all(16),
                            child: InspectionControls(
                              status: status,
                              onStatus: onStatus,
                              onSettings: onSettings,
                              onHelp: onHelp,
                              onFinish: onFinish,
                              researchControls: researchControls,
                              voiceControls: voiceControls,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ...overlays,
      if (sosState.phase != SosUiPhase.idle)
        SosSurface(
          state: sosState,
          screenCurtain: screenCurtain,
          onSend: onSos,
          onCancelCountdown: onCancelSos,
          onDismiss: onDismissSos,
        ),
    ],
  );
}

class InspectionControls extends StatelessWidget {
  final InspectionSystemStatus status;
  final VoidCallback onStatus, onSettings, onHelp;
  final VoidCallback? onFinish;
  final Widget? researchControls;
  final Widget? voiceControls;

  const InspectionControls({
    super.key,
    required this.status,
    required this.onStatus,
    required this.onSettings,
    required this.onHelp,
    required this.onFinish,
    this.researchControls,
    this.voiceControls,
  });

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 56)),
      padding: WidgetStatePropertyAll(EdgeInsets.all(16)),
      alignment: Alignment.centerLeft,
    );
    Widget action(
      String key,
      String label,
      IconData icon,
      VoidCallback? run, {
      String? semanticsLabel,
    }) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        key: Key(key),
        style: style,
        onPressed: run,
        icon: Icon(icon),
        label: Text(S.get(label), semanticsLabel: semanticsLabel),
      ),
    );
    return BagdarCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                S.get('inspection_title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (voiceControls != null) voiceControls!,
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                status.observationText,
                key: const Key('inspection-observation'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                status.movementText,
                key: const Key('inspection-movement-limit'),
              ),
            ),
            action(
              'inspection-status',
              'core_health_status',
              Icons.info_outline,
              onStatus,
              semanticsLabel:
                  '${S.get('core_health_status')}. '
                  '${status.observationText}. ${status.movementText}',
            ),
            action(
              'inspection-settings',
              'settings',
              Icons.settings_outlined,
              onSettings,
            ),
            action(
              'inspection-help',
              'inspection_help',
              Icons.help_outline,
              onHelp,
            ),
            action(
              'inspection-finish',
              'inspection_finish',
              Icons.stop_circle_outlined,
              onFinish,
            ),
            if (researchControls != null) researchControls!,
          ],
        ),
      ),
    );
  }
}

class InspectionPermissionRecovery extends StatelessWidget {
  final VoidCallback onRetry, onSystemSettings;
  const InspectionPermissionRecovery({
    super.key,
    required this.onRetry,
    required this.onSystemSettings,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: BagdarTheme.colorsOf(context).surfaceBg,
    child: SingleChildScrollView(
      key: const Key('inspection-recovery-scroll'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(S.get('camera_perm_title'))),
          const SizedBox(height: 12),
          Text(S.get('inspection_permission_recovery')),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('inspection-permission-retry'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            onPressed: onRetry,
            child: Text(S.get('inspection_retry_permission')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('inspection-system-settings'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            onPressed: onSystemSettings,
            child: Text(S.get('inspection_system_settings')),
          ),
        ],
      ),
    ),
  );
}

class InspectionCameraRecovery extends StatelessWidget {
  final VoidCallback? onRetry;
  const InspectionCameraRecovery({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => Material(
    color: BagdarTheme.colorsOf(context).surfaceBg,
    child: SingleChildScrollView(
      key: const Key('inspection-camera-recovery-scroll'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(S.get('inspection_camera_paused')),
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(S.get('inspection_camera_recovery')),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('inspection-camera-retry'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onPressed: onRetry,
            child: Text(S.get('inspection_retry_camera')),
          ),
        ],
      ),
    ),
  );
}

class InspectionHelpDialog extends StatelessWidget {
  const InspectionHelpDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(S.get('inspection_help')),
    content: SingleChildScrollView(child: Text(S.get('inspection_help_body'))),
    actions: [
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 56)),
        onPressed: () => Navigator.pop(context),
        child: Text(S.get('inspection_close')),
      ),
    ],
  );
}

class InspectionStatusDialog extends StatelessWidget {
  final InspectionSystemStatus status;
  final VoidCallback onRepeat;
  const InspectionStatusDialog({
    super.key,
    required this.status,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(S.get('core_health_status')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.observationText),
          const SizedBox(height: 12),
          Text(status.clearanceText),
          const SizedBox(height: 12),
          Text(status.movementText),
          const SizedBox(height: 16),
          Text(status.summary),
          for (final line in status.details)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(line)),
          const SizedBox(height: 12),
          Text(S.get('inspection_status_limits')),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('inspection-repeat-status'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 56)),
        onPressed: onRepeat,
        child: Text(S.get('inspection_repeat_status')),
      ),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 56)),
        onPressed: () => Navigator.pop(context),
        child: Text(S.get('inspection_close')),
      ),
    ],
  );
}
