import 'package:flutter/material.dart';
import '../models/strings.dart';
import '../services/voice/inspection_voice_commands.dart';
import '../services/voice/inspection_voice_coordinator.dart';
import '../services/voice/voice_settings.dart';

class InspectionVoicePanel extends StatelessWidget {
  final InspectionVoicePhase phase;
  final bool active;
  final bool canStart;
  final String message;
  final VoidCallback onStart, onStop;
  final VoidCallback? onVoiceSettings;
  const InspectionVoicePanel({
    super.key,
    required this.phase,
    required this.active,
    this.canStart = true,
    required this.message,
    required this.onStart,
    required this.onStop,
    this.onVoiceSettings,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        key: const Key('inspection-voice'),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(48, 56)),
          padding: WidgetStatePropertyAll(EdgeInsets.all(16)),
          alignment: Alignment.centerLeft,
        ),
        onPressed: active
            ? onStop
            : canStart
            ? onStart
            : null,
        icon: Icon(active ? Icons.mic_off_outlined : Icons.mic_outlined),
        label: Text(
          inspectionVoiceText(
            active ? InspectionVoiceCopy.cancel : InspectionVoiceCopy.button,
            S.current,
          ),
        ),
      ),
      Semantics(
        liveRegion: true,
        child: Text(
          message.isEmpty
              ? inspectionVoiceText(InspectionVoiceCopy.privacy, S.current)
              : message,
          key: const Key('inspection-voice-state'),
        ),
      ),
      if (onVoiceSettings != null)
        TextButton.icon(
          key: const Key('inspection-voice-settings'),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 56)),
          ),
          onPressed: onVoiceSettings,
          icon: const Icon(Icons.tune),
          label: Text(voiceSettingsText('title', S.current)),
        ),
    ],
  );
}
