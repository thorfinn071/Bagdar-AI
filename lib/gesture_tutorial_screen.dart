import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/constants.dart';
import 'models/speech_job.dart';
import 'models/strings.dart';
import 'models/a11y_prefs.dart';
import 'services/earcon_service.dart';
import 'services/feature_usage_tracker.dart';
import 'services/haptic_service.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'theme/bagdar_theme.dart';
import 'theme/bagdar_tokens.dart';

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
    if (mounted && MediaQuery.of(context).accessibleNavigation) return;
    _tts.say(S.get('tut_intro'), SpeechPriority.warning, pan: 0.0);
    await _tts.awaitCurrentSpeech();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _speakPrompt({bool initial = false}) async {
    if (_step == _TutStep.done) {
      if (mounted && !MediaQuery.of(context).accessibleNavigation) {
        _tts.say(S.get('tut_finished'), SpeechPriority.warning, pan: 0.0);
      }
      return;
    }
    _lastPromptAt = DateTime.now();
    if (mounted && !MediaQuery.of(context).accessibleNavigation) {
      _tts.say(S.get(_stepKey), SpeechPriority.warning, pan: 0.0);
    }
    if (!initial) {
      HapticService.vibrate(const [0, 40]);
    }
    _scheduleVoiceListen();
  }

  void _scheduleVoiceListen() {
    if (!_voiceReady) return;
    if (mounted && MediaQuery.of(context).accessibleNavigation) return;
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
      case VoiceCommand.confirm:
        unawaited(_advance());
        break;
      default:
        break;
    }
  }

  void _speakDetailedHelp() {
    final detailKey = 'tut_detail_${_step.name}';
    _tts.say(S.get(detailKey), SpeechPriority.warning, pan: 0.0);
  }

  Future<void> _advance() async {
    if (_step == _TutStep.done) return;
    _failCount = 0;
    _voiceListenTimer?.cancel();
    unawaited(_voice.stopListening());
    _earcon.play(Earcon.success);
    _tts.say(S.get(_doneKey), SpeechPriority.warning, pan: 0.0);
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
    _tts.say(S.get('tut_finished'), SpeechPriority.warning, pan: 0.0);
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

  double get _swipeVelocityThreshold {
    final sensitivity = Settings.instance.tapSensitivity;
    switch (sensitivity) {
      case TapSensitivity.sensitive:
        return 150.0;
      case TapSensitivity.normal:
        return 250.0;
    }
  }

  void _handleHorizontalSwipe(double? v) {
    if (v == null) return;
    if (v.abs() < _swipeVelocityThreshold) return;
    if (_step == _TutStep.swipeHorizontal) {
      unawaited(_advance());
    } else {
      _throttledReprompt();
    }
  }

  void _handleVerticalSwipe(double? v) {
    if (v == null) return;
    if (v.abs() < _swipeVelocityThreshold) return;
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
        _tts.say(S.get('tut_fail_hint'), SpeechPriority.warning, pan: 0.0);
        _failCount = 0;
      }
      return;
    }
    _lastPromptAt = now;
    _speakPrompt();
  }

  @override
  Widget build(BuildContext context) {
    final accessible = MediaQuery.of(context).accessibleNavigation;
    final colors = BagdarTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: colors.surfaceBg,
      body: SafeArea(
        child: Listener(
          onPointerDown: accessible ? null : _handlePointerDown,
          onPointerMove: accessible ? null : _handlePointerMove,
          onPointerUp: accessible ? null : _handlePointerUp,
          onPointerCancel: (_) {
            _activePointers.clear();
            _twoFingerTimer?.cancel();
            _twoFingerSwipeStart = null;
          },
          child: GestureDetector(
            behavior: accessible
                ? HitTestBehavior.deferToChild
                : HitTestBehavior.opaque,
            onTap: accessible ? null : _handleTap,
            onDoubleTap: accessible ? null : _handleDoubleTap,
            onLongPress: accessible ? null : _handleLongPress,
            onHorizontalDragEnd: accessible
                ? null
                : (d) => _handleHorizontalSwipe(d.primaryVelocity),
            onVerticalDragEnd: accessible
                ? null
                : (d) => _handleVerticalSwipe(d.primaryVelocity),
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
                              style: BagdarTypography.label.copyWith(
                                color: colors.accentPrimary,
                              ),
                            ),
                            const SizedBox(height: BagdarSpacing.m),
                            _StepIndicator(
                              total: _totalSteps,
                              current: _stepIndex,
                              color: colors.accentPrimary,
                              inactive: colors.divider,
                              semanticsLabel: S
                                  .get('tut_progress')
                                  .replaceFirst('{step}', '$_stepIndex')
                                  .replaceFirst('{total}', '$_totalSteps'),
                            ),
                            const SizedBox(height: BagdarSpacing.xl),
                            AnimatedSwitcher(
                              duration: BagdarMotion.duration(
                                context,
                                BagdarMotion.medium,
                              ),
                              child: Column(
                                key: ValueKey<_TutStep>(_step),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colors.accentPrimary.withValues(
                                        alpha: 0.12,
                                      ),
                                      border: Border.all(
                                        color: colors.accentPrimary,
                                        width: BagdarBorders.rule,
                                      ),
                                    ),
                                    child: Icon(
                                      _stepIcon(_step),
                                      size: 64,
                                      color: colors.accentPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: BagdarSpacing.l),
                                  Text(
                                    _step == _TutStep.done
                                        ? S.get('tut_finished')
                                        : S.get(_stepKey),
                                    textAlign: TextAlign.center,
                                    style: BagdarTypography.body.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: BagdarSpacing.m,
                  right: BagdarSpacing.m,
                  child: Semantics(
                    button: true,
                    label: S.get('tut_skip'),
                    child: TextButton(
                      onPressed: () {
                        SystemSound.play(SystemSoundType.click);
                        _skip();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        backgroundColor: colors.surfaceElevated,
                        padding: const EdgeInsets.symmetric(
                          horizontal: BagdarSpacing.m,
                          vertical: BagdarSpacing.s,
                        ),
                      ),
                      child: Text(
                        S.get('tut_skip'),
                        style: BagdarTypography.caption,
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

/// Signage-style progress bars for the tutorial. Decorative bars carry a
/// single [semanticsLabel] (e.g. "Step 3 of 6") so TalkBack announces
/// progress without reading each bar individually.
class _StepIndicator extends StatelessWidget {
  final int total;
  final int current;
  final Color color;
  final Color inactive;
  final String semanticsLabel;

  const _StepIndicator({
    required this.total,
    required this.current,
    required this.color,
    required this.inactive,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(total, (i) {
          final done = i < current;
          return AnimatedContainer(
            duration: BagdarMotion.duration(context, BagdarMotion.medium),
            width: done ? 28 : 16,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: BagdarSpacing.xs),
            decoration: BoxDecoration(
              color: done ? color : inactive,
              borderRadius: BorderRadius.circular(BagdarRadius.sharp),
            ),
          );
        }),
      ),
    );
  }
}
