import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/bagdar_ui.dart';
import 'onboarding_voice_coordinator.dart';
import 'onboarding_voice_copy.dart';

class OnboardingVoicePanel extends StatelessWidget {
  final OnboardingVoiceCoordinator voice;
  const OnboardingVoicePanel({super.key, required this.voice});

  @override
  Widget build(BuildContext context) {
    final copy = voice.copy;
    final suspended = voice.phase == OnboardingVoicePhase.suspended;
    return BagdarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (voice.enabled ||
              voice.phase == OnboardingVoicePhase.complete) ...[
            Text(
              copy.t(VoiceCopy.title),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
          ],
          if (!voice.enabled &&
              voice.phase != OnboardingVoicePhase.complete) ...[
            Text(copy.t(VoiceCopy.explanation)),
          ],
          if (voice.phase != OnboardingVoicePhase.off)
            Semantics(
              // The coordinator already speaks. Do not make TalkBack repeat
              // status/answer phrases into an active recognition window.
              liveRegion: !voice.enabled,
              child: Text(
                voice.status,
                key: const Key('onboarding-voice-status'),
              ),
            ),
          if (voice.supported && (!voice.enabled || suspended)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('onboarding-voice-enable'),
              onPressed: !voice.canEnable
                  ? null
                  : () => unawaited(
                      voice.enabled ? voice.resume() : voice.enable(),
                    ),
              icon: const Icon(Icons.mic_none_rounded),
              label: Text(
                copy.t(suspended ? VoiceCopy.resumeButton : VoiceCopy.enable),
              ),
            ),
          ],
          if (voice.enabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('onboarding-voice-disable'),
              onPressed: () => unawaited(voice.disable()),
              icon: const Icon(Icons.mic_off_outlined),
              label: Text(copy.t(VoiceCopy.disable)),
            ),
          ],
        ],
      ),
    );
  }
}
