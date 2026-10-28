import 'dart:async';
import 'package:flutter/material.dart';
import '../models/strings.dart';
import '../services/voice/inspection_voice_commands.dart';
import '../services/voice/voice_settings.dart';
import '../services/voice/voice_settings_coordinator.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';

class VoiceSettingsDialog extends StatefulWidget {
  final VoiceSettingsCoordinator Function(bool Function()) createController;
  final void Function(VoiceSettingsCoordinator)? onDisposed;
  final bool autoStart;
  final bool screenCurtain;
  const VoiceSettingsDialog({
    super.key,
    required this.createController,
    this.onDisposed,
    this.autoStart = false,
    this.screenCurtain = false,
  });
  @override
  State<VoiceSettingsDialog> createState() => _VoiceSettingsDialogState();
}

class _VoiceSettingsDialogState extends State<VoiceSettingsDialog>
    with WidgetsBindingObserver {
  late final VoiceSettingsCoordinator controller;
  bool _allowPop = false;
  bool _closing = false;
  bool _canInteract() =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      ModalRoute.of(context)?.isCurrent == true;
  @override
  void initState() {
    super.initState();
    controller = widget.createController(_canInteract);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canInteract()) {
          unawaited(controller.start(requestPermission: false));
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(controller.interrupt());
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final closed = await controller.stop();
    if (!mounted) return;
    if (closed) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    }
    _closing = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    widget.onDisposed?.call(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<BagdarThemeName>(
    valueListenable: bagdarThemeNotifier,
    builder: (context, theme, _) => Theme(
      data: BagdarTheme.buildMaterialTheme(theme),
      child: Opacity(
        opacity: widget.screenCurtain ? 0 : 1,
        alwaysIncludeSemantics: true,
        child: _buildDialog(context),
      ),
    ),
  );

  Widget _buildDialog(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final question = controller.question;
              final message = controller.message;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      voiceSettingsText('title', S.current),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(question, key: const Key('voice-settings-question')),
                  if (message.isNotEmpty && message != question) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const Key('voice-settings-state'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('voice-settings-start'),
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 56)),
                    ),
                    onPressed: controller.active
                        ? () => unawaited(controller.stop())
                        : controller.canStart
                        ? () => unawaited(
                            controller.start(requestPermission: true),
                          )
                        : null,
                    child: Text(
                      controller.active
                          ? inspectionVoiceText(
                              InspectionVoiceCopy.cancel,
                              S.current,
                            )
                          : voiceSettingsText('start', S.current),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('voice-settings-close'),
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 56)),
                    ),
                    onPressed: () => unawaited(_close()),
                    child: Text(voiceSettingsText('close', S.current)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
