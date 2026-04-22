import 'package:flutter/material.dart';
import '../../models/app_mode.dart';
import '../../services/device_capability.dart';

class DebugHud extends StatelessWidget {
  final double fps;
  final double inferenceMs;
  final double intervalMs;
  final bool useGpu;
  final int threads;
  final AppMode mode;
  final DepthTier? depthTier;

  const DebugHud({
    super.key,
    required this.fps,
    required this.inferenceMs,
    required this.intervalMs,
    required this.useGpu,
    required this.threads,
    required this.mode,
    this.depthTier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FPS:      ${fps.toStringAsFixed(1)}'),
            Text('Infer:    ${inferenceMs.toStringAsFixed(0)} ms'),
            Text('Interval: ${intervalMs.toStringAsFixed(0)} ms'),
            Text('Mode:     ${useGpu ? "GPU" : "CPU"} / $threads th'),
            Text('AppMode:  ${mode.name}'),
            if (depthTier != null) Text('Depth:    ${depthTier!.name}'),
          ],
        ),
      ),
    );
  }
}
