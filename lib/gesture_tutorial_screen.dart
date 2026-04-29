import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/constants.dart';
import 'models/speech_job.dart';
import 'models/strings.dart';
import 'services/earcon_service.dart';
import 'services/feature_usage_tracker.dart';
import 'services/haptic_service.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';

enum _TutStep {
  tap,
  doubleTap,
  longPress,
  swipeHorizontal,
  swipeVertical,
  twoFinger,
  done,
}

class GestureTutorialScreen extends StatefulWidget {
  final VoidCallback? onFinished;
  final bool standalone;

  const GestureTutorialScreen({
    super.key,
    this.onFinished,
    this.standalone = true,
  });

  @override
  State<GestureTutorialScreen> createState() => _GestureTutorialScreenState();
}

class _GestureTutorialScreenState extends State<GestureTutorialScreen> {
  final TtsService _tts = TtsService.instance;
  final EarconService _earcon = EarconService();
  final VoiceCommandService _voice = VoiceCommandService();

  _TutStep _step = _TutStep.tap;
  Timer? _twoFingerTimer;
  Timer? _voiceListenTimer;
  final Set<int> _activePointers = {};
  int _maxPointersThisTouch = 0;
  DateTime? _lastPromptAt;
  int _failCount = 0;
  bool _voiceReady = false;

  Offset? _twoFingerSwipeStart;
  static const double _kTwoFingerSkipMinDy = 80.0;

  bool get _classic => Settings.instance.classicGestures;

  String get _stepKey {
    switch (_step) {
      case _TutStep.tap:
        return 'tut_tap';
      case _TutStep.doubleTap:
        return 'tut_double_tap';
      case _TutStep.longPress:
        return 'tut_long_press';
      case _TutStep.swipeHorizontal:
        return 'tut_swipe_horizontal';
      case _TutStep.swipeVertical:
        return _classic ? 'tut_swipe_down_legacy' : 'tut_swipe_up';
      case _TutStep.twoFinger:
        return 'tut_two_finger';
      case _TutStep.done:
        return 'tut_finished';
    }
  }

  String get _doneKey => '${_stepKey}_done';

  int get _stepIndex => _TutStep.values.indexOf(_step) + 1;
  int get _totalSteps => _TutStep.values.length - 1; 

  @override
  void initState() {
    super.initState();
    _earcon.init();
    _tts.init().then((_) async {
      await _tts.setLanguage(AppStrings.ttsLang);
      await _speakIntro();
      await _speakPrompt(initial: true);
    });
    _initVoice();
  }

  Future<void> _initVoice() async {
    _voice.onCommand = _onVoiceCommand;
    _voiceReady = await _voice.init(locale: AppStrings.ttsLang);
  }

  @override
  void dispose() {
    _twoFingerTimer?.cancel();
    _voiceListenTimer?.cancel();
    _voice.dispose();
    _tts.stop();
    _earcon.dispose();
    super.dispose();
  }

  Future<void> _speakIntro() async {
    _tts.say(S.get('tut_intro'), SpeechPriority.critical, pan: 0.0);
    await _tts.awaitCurrentSpeech();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _speakPrompt({bool initial = false}) async {
    if (_step == _TutStep.done) {
      _tts.say(S.get('tut_finished'), SpeechPriority.critical, pan: 0.0);
      return;
    }
    _lastPromptAt = DateTime.now();
    _tts.say(S.get(_stepKey), SpeechPriority.critical, pan: 0.0);
    if (!initial) {
      HapticService.vibrate(const [0, 40]);
    }
    _scheduleVoiceListen();
  }

  void _scheduleVoiceListen() {
    if (!_voiceReady) return;
    _voiceListenTimer?.cancel();
    _voiceListenTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _step == _TutStep.done) return;
      unawaited(_voice.startListening());
    });
  }

  void _onVoiceCommand(VoiceCommand cmd) {
    switch (cmd) {
      case VoiceCommand.tutorialSkip:
        unawaited(_skip());
        break;
      case VoiceCommand.tutorialRepeat:
        unawaited(_speakPrompt());
        break;
      case VoiceCommand.showHelp:
        _speakDetailedHelp();
        break;
      default:
        break;
    }
  }

  void _speakDetailedHelp() {
    final detailKey = 'tut_detail_${_step.name}';
    _tts.say(S.get(detailKey), SpeechPriority.critical, pan: 0.0);
  }

  Future<void> _advance() async {
    if (_step == _TutStep.done) return;
    _failCount = 0;
    _voiceListenTimer?.cancel();
    unawaited(_voice.stopListening());
    _earcon.play(Earcon.success);
    _tts.say(S.get(_doneKey), SpeechPriority.critical, pan: 0.0);
    HapticService.vibrate(const [0, 60, 40, 60]);

    final next = _TutStep.values[_step.index + 1];
    await _tts.awaitCurrentSpeech();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _step = next);
    if (next == _TutStep.done) {
      await _finish();
    } else {
      await _speakPrompt();
    }
  }

  Future<void> _finish() async {
    await Settings.instance.setTutorialSeen(true);
    await FeatureUsageTracker.instance.setTutorialCompletedNow();
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!.call();
    } else if (widget.standalone && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _skip() async {
    _voiceListenTimer?.cancel();
    unawaited(_voice.stopListening());
    await Settings.instance.setTutorialSeen(true);
    _tts.say(S.get('tut_finished'), SpeechPriority.critical, pan: 0.0);
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!.call();
    } else if (widget.standalone && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _handleTap() {
    if (_maxPointersThisTouch > 1) return;
    if (_step == _TutStep.tap) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handleDoubleTap() {
    if (_step == _TutStep.doubleTap) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handleLongPress() {
    if (_maxPointersThisTouch > 1) return;
    if (_step == _TutStep.longPress) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handleHorizontalSwipe(double? v) {
    if (v == null) return;
    if (v.abs() < 300) return;
    if (_step == _TutStep.swipeHorizontal) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handleVerticalSwipe(double? v) {
    if (v == null) return;
    if (v.abs() < 300) return;
    if (_step != _TutStep.swipeVertical) {
      _throttledReprompt();
      return;
    }
    final wantUp = !_classic;
    final gotUp = v < 0;
    if (gotUp == wantUp) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (_activePointers.isEmpty) {
      _maxPointersThisTouch = 0;
      _twoFingerSwipeStart = null;
    }
    _activePointers.add(e.pointer);
    if (_activePointers.length > _maxPointersThisTouch) {
      _maxPointersThisTouch = _activePointers.length;
    }
    if (_activePointers.length == 2) {
      _twoFingerSwipeStart = e.position;
      if (_step == _TutStep.twoFinger) {
        _twoFingerTimer?.cancel();
        _twoFingerTimer = Timer(kSosTwoFingerHold, () {
          if (_activePointers.length >= 2 && _step == _TutStep.twoFinger) {
            unawaited(_advance());
          }
        });
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_activePointers.length < 2) return;
    final start = _twoFingerSwipeStart;
    if (start == null) return;
    final dy = e.position.dy - start.dy;
    if (dy >= _kTwoFingerSkipMinDy) {
      _twoFingerSwipeStart = null;
      _twoFingerTimer?.cancel();
      unawaited(_skip());
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    if (_activePointers.length < 2) {
      _twoFingerTimer?.cancel();
      _twoFingerSwipeStart = null;
    }
  }

  void _throttledReprompt() {
    HapticService.vibrate(const [0, 50]);
    _earcon.play(Earcon.fail);
    _failCount++;
    final now = DateTime.now();
    if (_lastPromptAt != null &&
        now.difference(_lastPromptAt!) < const Duration(seconds: 3)) {
      if (_failCount >= 2) {
        _lastPromptAt = now;
        _tts.say(S.get('tut_fail_hint'), SpeechPriority.critical, pan: 0.0);
        _failCount = 0;
      }
      return;
    }
    _lastPromptAt = now;
    _speakPrompt();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: (_) {
            _activePointers.clear();
            _twoFingerTimer?.cancel();
            _twoFingerSwipeStart = null;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onDoubleTap: _handleDoubleTap,
            onLongPress: _handleLongPress,
            onHorizontalDragEnd: (d) => _handleHorizontalSwipe(d.primaryVelocity),
            onVerticalDragEnd: (d) => _handleVerticalSwipe(d.primaryVelocity),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Semantics(
                    liveRegion: true,
                    label: S.get(_stepKey),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              S.get('tut_title'),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 14,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              S
                                  .get('tut_progress')
                                  .replaceFirst('{step}', '$_stepIndex')
                                  .replaceFirst('{total}', '$_totalSteps'),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Icon(
                              _stepIcon(_step),
                              size: 72,
                              color: Colors.cyanAccent,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _step == _TutStep.done
                                  ? S.get('tut_finished')
                                  : S.get(_stepKey),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Semantics(
                    button: true,
                    label: S.get('tut_skip'),
                    child: TextButton(
                      onPressed: () {
                        SystemSound.play(SystemSoundType.click);
                        _skip();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        S.get('tut_skip'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _stepIcon(_TutStep step) {
    switch (step) {
      case _TutStep.tap:
        return Icons.touch_app;
      case _TutStep.doubleTap:
        return Icons.double_arrow;
      case _TutStep.longPress:
        return Icons.mic;
      case _TutStep.swipeHorizontal:
        return Icons.swap_horiz;
      case _TutStep.swipeVertical:
        return _classic ? Icons.arrow_downward : Icons.arrow_upward;
      case _TutStep.twoFinger:
        return Icons.sos;
      case _TutStep.done:
        return Icons.check_circle;
    }
  }
}
 