import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/speech_job.dart';
import '../../services/tts_service.dart';

/// Wraps a [child] and speaks a single screen-arrival announcement
/// the first time the widget is mounted. Reuses the pattern that was
/// previously inlined inside `settings_qr_import_screen.dart`.
///
/// The announcement fires from a post-frame callback so any other
/// widgets in the tree can settle their semantics before TalkBack
/// hears it. If [text] resolves to an empty string the announcement
/// is silently skipped — useful for screens whose label depends on
/// runtime state that may not be ready on first build.
class ScreenAnnouncer extends StatefulWidget {
  final Widget child;
  final String Function() textBuilder;
  final SpeechPriority priority;
  final Duration delay;
  final bool barge;
  final TtsService? tts;

  const ScreenAnnouncer({
    super.key,
    required this.child,
    required this.textBuilder,
    this.priority = SpeechPriority.info,
    this.delay = Duration.zero,
    this.barge = false,
    this.tts,
  });

  ScreenAnnouncer.text({
    Key? key,
    required Widget child,
    required String text,
    SpeechPriority priority = SpeechPriority.info,
    Duration delay = Duration.zero,
    bool barge = false,
    TtsService? tts,
  }) : this(
         key: key,
         child: child,
         textBuilder: (() => text),
         priority: priority,
         delay: delay,
         barge: barge,
         tts: tts,
       );

  @override
  State<ScreenAnnouncer> createState() => _ScreenAnnouncerState();
}

class _ScreenAnnouncerState extends State<ScreenAnnouncer> {
  bool _announced = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _announced) return;
      _announced = true;
      if (widget.delay == Duration.zero) {
        _speak();
      } else {
        _delayTimer = Timer(widget.delay, _speak);
      }
    });
  }

  void _speak() {
    if (!mounted) return;
    final text = widget.textBuilder();
    if (text.isEmpty) return;
    final tts = widget.tts ?? TtsService.instance;
    tts.say(text, widget.priority, pan: 0.0, barge: widget.barge);
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
