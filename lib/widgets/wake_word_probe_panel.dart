import 'package:flutter/material.dart';
import '../models/strings.dart';
import '../services/voice/wake_word_probe.dart';

class WakeWordProbePanel extends StatelessWidget {
  final WakeWordProbe probe;
  const WakeWordProbePanel({super.key, required this.probe});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: probe,
    builder: (_, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          wakeProbeText('title', S.current),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        OutlinedButton(
          key: const Key('wake-probe-toggle'),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 56)),
            padding: WidgetStatePropertyAll(EdgeInsets.all(16)),
          ),
          onPressed: probe.active
              ? probe.stop
              : probe.canStart
              ? probe.start
              : null,
          child: Text(
            wakeProbeText(probe.active ? 'stop' : 'start', S.current),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            probe.message.isEmpty
                ? wakeProbeText('off', S.current)
                : probe.message,
          ),
        ),
        Text('${wakeProbeText('count', S.current)} ${probe.detections}'),
      ],
    ),
  );
}
