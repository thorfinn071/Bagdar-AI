import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_mode.dart';
import '../models/a11y_prefs.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';
import '../services/earcon_service.dart';
import 'camera_screen.dart';
import 'gesture_tutorial_screen.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';


const String kOnboardingDoneKey = 'onboarding_done';
const String kOnboardingModeKey = 'onboarding_mode';


Future<Widget> resolveStartScreen() async {
  if (Settings.instance.onboardingDone) return const AiCameraScreen();
  return const OnboardingScreen();
}


class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _page = PageController();
  final TtsService _tts = TtsService.instance;
  final VoiceCommandService _voice = VoiceCommandService();
  final EarconService _earcon = EarconService();

  int _current = 0;
  AppMode? _chosenMode;
  DominantHand _chosenHand = DominantHand.right;

  int _retryCount = 0;
  static const int _maxRetries = 5;

  bool _calibrated = false;
  bool _pendingSkip = false;
  Timer? _skipConfirmTimer;
  Timer? _skipReplayTimer;
  Timer? _startupTimer;

  final Set<int> _activePointers = {};
  Timer? _emergencyTimer;
  static const Duration _kEmergencyHold = Duration(seconds: 4); // Increased to 4 seconds (F-05)

  bool _micPermissionDenied = false;
  bool _startupFinished = false;
  bool _pendingEmergencyExit = false;
  Timer? _emergencyExitConfirmTimer;

  List<String> get _stepNarrations => [
    S.get('onb_welcome_intro_tts'),
    S.get('onb_dominant_hand_tts'),
    S.get('onb_mode_tts'),
    S.get('onb_perm_tts'),
    S.get('onb_calib_tts'),
    S.get('onb_ready_tts'),
  ];

  @override
  void initState() {
    super.initState();
    _voice.init();
    _earcon.init();
    _tts.init().then((_) async {
      AppStrings.setLanguage(AppLanguage.values[Settings.instance.language]);
      await _tts.setLanguage(AppStrings.ttsLang);
      if (mounted) {
        setState(() {
          _calibrated = Settings.instance.isCalibrated;
          _chosenHand = Settings.instance.dominantHand;
        });
      }
      
      // Play soft welcome chime immediately
      await _earcon.play(Earcon.paymentReceived);

      // Enforce a 7-second start-up pause so the blind user can prepare
      _startupTimer = Timer(const Duration(seconds: 7), () async {
        if (!mounted) return;
        _tts.say(
          S.get('onb_blind_intro'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        await _tts.awaitIdle();
        if (!mounted || _startupFinished) return;

        // F-04: Proactive microphone permission check
        final hasMic = await Permission.microphone.isGranted;
        if (!hasMic) {
          _tts.say(
            S.get('onb_mic_prime_tts'),
            SpeechPriority.warning,
            barge: true,
          );
          await _tts.awaitIdle();
          if (!mounted || _startupFinished) return;
          
          await _earcon.play(Earcon.proximity);
          await Future.delayed(const Duration(milliseconds: 1000));
          if (!mounted || _startupFinished) return;

          final granted = await _voice.requestPermission();
          if (!granted && mounted) {
            _micPermissionDenied = true;
            _tts.say(
              S.get('onb_mic_denied_fallback_tts'),
              SpeechPriority.critical,
              barge: true,
            );
            await _tts.awaitIdle();
          }
        }
        
        if (!mounted || _startupFinished) return;
        _startupFinished = true;
        await _speakAndListen(0);
      });

      if (!_tts.languageAvailable && mounted) {
        _showTtsLanguageWarning();
      }
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _skipConfirmTimer?.cancel();
    _skipReplayTimer?.cancel();
    _emergencyTimer?.cancel();
    _emergencyExitConfirmTimer?.cancel();
    _voice.onCommand = null;
    _voice.onListenDone = null;
    _voice.onError = null;
    _voice.stopListening();
    _voice.dispose();
    _earcon.dispose();
    _tts.stop();
    _page.dispose();
    super.dispose();
  }

  void _next() {
    if (_current < 5) {
      _page.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goTo(int index) {
    _page.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    unawaited(_speakAndListen(index));
  }

  void _cancelStartup() {
    _startupTimer?.cancel();
    _startupFinished = true;
  }

  String _getStepHelpPrompt(int index) {
    switch (index) {
      case 0:
        return S.get('onb_help_prompt_lang');
      case 1:
        return S.get('onb_help_prompt_hand');
      case 2:
        return S.get('onb_help_prompt_mode');
      case 3:
        return S.get('onb_help_prompt_perm');
      case 4:
        return S.get('onb_help_prompt_calib');
      case 5:
        return S.get('onb_help_prompt_ready');
      default:
        return '';
    }
  }

  Future<void> _handleHelpCommand() async {
    _cancelStartup();
    await _voice.stopListening();
    await _tts.stop();
    await _earcon.play(Earcon.success);
    _tts.say(
      _getStepHelpPrompt(_current),
      SpeechPriority.warning,
      barge: true,
    );
    await _tts.awaitIdle();
    if (!mounted) return;
    unawaited(_doSpeakAndListen(_current));
  }

  void _requestEmergencyExitConfirm() {
    _pendingEmergencyExit = true;
    _tts.say(
      S.get('onb_emergency_skip_confirm'),
      SpeechPriority.critical,
      barge: true,
    );
    _emergencyExitConfirmTimer?.cancel();
    _emergencyExitConfirmTimer = Timer(const Duration(seconds: 10), () {
      _cancelEmergencyExitConfirm(announce: false);
    });
  }

  void _cancelEmergencyExitConfirm({bool announce = false}) {
    if (!_pendingEmergencyExit) return;
    _pendingEmergencyExit = false;
    _emergencyExitConfirmTimer?.cancel();
    if (announce) {
      _tts.say(
        S.get('onb_skip_cancelled'),
        SpeechPriority.info,
        barge: true,
      );
    }
  }

  Future<void> _speakAndListen(int index) async {
    _retryCount = 0;
    await _doSpeakAndListen(index);
  }

  Future<void> _doSpeakAndListen(int index) async {
    _startupTimer?.cancel();
    await _voice.stopListening();
    await _tts.stop();
    if (!mounted) return;

    final accessible = MediaQuery.of(context).accessibleNavigation;
    if (accessible) {
      // TalkBack/VoiceOver is active. Suppress VUI completely.
      return;
    }

    String speechText = _stepNarrations[index];
    if (index == 5) {
      // Step 5 (Ready Screen): read the controls guide audio tour right here!
      speechText = '${S.get('onb_ready_tts')} ${S.get('help_summary')}';
    }

    _tts.say(
      speechText,
      SpeechPriority.warning,
      barge: true,
    );

    // Wait until the ENTIRE TTS queue is drained.
    await _tts.awaitIdle();
    if (!mounted || _current != index) return;

    if (_micPermissionDenied) {
      // Microphone access is denied. Do not start listening.
      return;
    }

    // 500ms silence buffer so the mic doesn't capture trailing TTS audio.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || _current != index) return;

    _voice.onCommand = _handleVoiceCommand;
    _voice.onListenDone = () {
      _handleListenError(index, 'stt_timeout');
    };
    _voice.onError = (errorMsg) {
      _handleListenError(index, 'stt_error: $errorMsg');
    };
    _voice.setLocale(AppStrings.ttsLang);

    // F-07 & F-14: Play mic open tone and wait for it to finish
    await _earcon.play(Earcon.indoorExited);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted || _current != index) return;

    await _voice.startListening(
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _handleListenError(int index, String reason) async {
    if (!mounted || _current != index) return;
    debugPrint('Onboarding voice command failed: $reason');

    // F-07: Play mic closed tone
    await _earcon.play(Earcon.indoorEntered);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted || _current != index) return;

    _retryCount++;
    if (_retryCount >= _maxRetries) {
      _tts.say(
        S.get('onb_mic_exhausted'),
        SpeechPriority.warning,
        barge: true,
      );
      return;
    }

    // Play distinct no-match earcon (F-02)
    await _earcon.play(Earcon.fail);
    
    // Reprompt listing valid options for the current step (F-02)
    final repromptText = '${S.get('voice_unknown')} ${_getStepHelpPrompt(index)}';
    _tts.say(
      repromptText,
      SpeechPriority.warning,
      barge: true,
    );
    await _tts.awaitIdle();
    if (!mounted || _current != index) return;

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _current == index) {
        _doSpeakAndListen(index);
      }
    });
  }

  void _handleVoiceCommand(VoiceCommand cmd) {
    if (!mounted) return;
    debugPrint('Onboarding voice command received: $cmd');
    
    // Play mic closed tone for known commands (F-07)
    if (cmd != VoiceCommand.unknown) {
      _earcon.play(Earcon.indoorEntered);
    }

    if (_pendingEmergencyExit) {
      if (cmd == VoiceCommand.confirm) {
        _cancelEmergencyExitConfirm();
        unawaited(_emergencyExit());
      } else if (cmd == VoiceCommand.cancel) {
        _cancelEmergencyExitConfirm(announce: true);
      }
      return;
    }

    if (_pendingSkip) {
      if (cmd == VoiceCommand.confirm) {
        _cancelSkipConfirm();
        unawaited(_emergencyExit());
      } else if (cmd == VoiceCommand.cancel) {
        _cancelSkipConfirm(announce: true);
      }
      return;
    }

    switch (cmd) {
      case VoiceCommand.langRussian:
        if (_current == 0) unawaited(_switchLanguage(AppLanguage.ru));
        break;
      case VoiceCommand.langKazakh:
        if (_current == 0) unawaited(_switchLanguage(AppLanguage.kk));
        break;
      case VoiceCommand.langEnglish:
        if (_current == 0) unawaited(_switchLanguage(AppLanguage.en));
        break;
      case VoiceCommand.dominantHandRight:
        if (_current == 1) unawaited(_setDominantHand(DominantHand.right));
        break;
      case VoiceCommand.dominantHandLeft:
        if (_current == 1) unawaited(_setDominantHand(DominantHand.left));
        break;
      case VoiceCommand.modeStreet:
        if (_current == 2) unawaited(_selectMode(AppMode.street));
        break;
      case VoiceCommand.modeCane:
        if (_current == 2) unawaited(_selectMode(AppMode.cane));
        break;
      case VoiceCommand.modeScan:
        if (_current == 2) unawaited(_selectMode(AppMode.scan));
        break;
      case VoiceCommand.allowPermission:
        if (_current == 3) unawaited(_requestCameraPermission());
        break;
      case VoiceCommand.confirm:
        _handleConfirmCommand();
        break;
      case VoiceCommand.cancel:
        _handleCancelCommand();
        break;
      case VoiceCommand.back:
        _handleBackCommand();
        break;
      case VoiceCommand.tutorialSkip:
        _requestSkipConfirm();
        break;
      case VoiceCommand.tutorialRepeat:
        unawaited(_speakAndListen(_current));
        break;
      case VoiceCommand.showHelp:
        unawaited(_handleHelpCommand());
        break;
      case VoiceCommand.unknown:
      default:
        _handleListenError(_current, 'unknown_command');
        break;
    }
  }

  void _handleConfirmCommand() {
    _cancelStartup();
    switch (_current) {
      case 0:
      case 1:
        _next();
        break;
      case 2:
        // Require explicit mode selection before proceeding
        if (_chosenMode == null) {
          _tts.say(
            S.get('onb_mode_choose_first'),
            SpeechPriority.warning,
            barge: true,
          );
        } else {
          _next();
        }
        break;
      case 3:
        unawaited(_requestCameraPermission());
        break;
      case 4:
        unawaited(_afterCalibration());
        break;
      case 5:
        unawaited(_finish());
        break;
    }
  }

  void _handleBackCommand() {
    _cancelStartup();
    if (_current > 0) {
      _goTo(_current - 1);
    }
  }

  void _handleCancelCommand() {
    _cancelStartup();
    if (_pendingEmergencyExit) {
      _cancelEmergencyExitConfirm(announce: true);
      return;
    }
    if (_pendingSkip) {
      _cancelSkipConfirm(announce: true);
      return;
    }
    switch (_current) {
      case 3: // Permissions: user said "no" to camera permission
        _tts.say(S.get('onb_perm_denied_retry'), SpeechPriority.critical, barge: true);
        break;
      case 4: // Calibration: user said "no" to calibration -> skip it
        _tts.say(S.get('onb_calib_skip_tts'), SpeechPriority.warning, barge: true);
        unawaited(_afterCalibration());
        break;
      default:
        break;
    }
  }

  Future<void> _switchLanguage(AppLanguage lang) async {
    AppStrings.setLanguage(lang);
    await Settings.instance.setLanguage(lang.index);
    await _tts.setLanguage(AppStrings.ttsLang);
    _voice.setLocale(AppStrings.ttsLang);
    if (mounted) {
      setState(() {});
      _tts.say(
        S.get('onb_lang_switched'),
        SpeechPriority.warning,
        barge: true,
      );
      await _tts.awaitIdle();
      if (!mounted) return;
      _next();
    }
  }

  Future<void> _setDominantHand(DominantHand hand) async {
    _chosenHand = hand;
    await Settings.instance.setDominantHand(hand);
    if (mounted) {
      setState(() {});
      final handName = hand == DominantHand.right ? S.get('onb_hand_right') : S.get('onb_hand_left');
      final text = S.get('onb_hand_changed').replaceFirst('{hand}', handName);
      _tts.say(
        text,
        SpeechPriority.warning,
        barge: true,
      );
      await _tts.awaitIdle();
      if (!mounted) return;
      _next();
    }
  }

  Future<void> _selectMode(AppMode mode) async {
    setState(() => _chosenMode = mode);
    final text = S
        .get('onb_mode_select_announce')
        .replaceFirst('{mode}', mode.label);
    _tts.say(text, SpeechPriority.warning, barge: true);
    
    // F-01 & F-13: Wait for TTS idle, reset retry count, and speak re-arm confirmation prompt
    await _tts.awaitIdle();
    if (!mounted || _current != 2) return;
    _retryCount = 0;
    _tts.say(
      S.get('onb_mode_confirm_prompt'),
      SpeechPriority.warning,
      barge: true,
    );
    await _tts.awaitIdle();
    if (!mounted || _current != 2) return;
    unawaited(_doSpeakAndListen(2));
  }

  void _cycleLanguage() {
    if (_current != 0) return;
    final next = AppLanguage.values[
        (AppStrings.current.index + 1) % AppLanguage.values.length];
    unawaited(_switchLanguage(next));
  }

  void _cycleHand(int dir) {
    if (_current != 1) return;
    final next = _chosenHand == DominantHand.right ? DominantHand.left : DominantHand.right;
    unawaited(_setDominantHand(next));
  }

  void _cycleMode(int dir) {
    if (_current != 2) return;
    const modes = AppMode.values;
    final cur = _chosenMode == null ? -1 : modes.indexOf(_chosenMode!);
    final next = modes[(cur + dir + modes.length) % modes.length];
    _selectMode(next);
  }

  void _requestSkipConfirm() {
    _pendingSkip = true;
    _tts.say(
      S.get('onb_skip_confirm'),
      SpeechPriority.warning,
      barge: true,
    );
    _skipConfirmTimer?.cancel();
    _skipReplayTimer?.cancel();

    _skipConfirmTimer = Timer(const Duration(seconds: 10), () {
      _pendingSkip = false;
      _skipReplayTimer?.cancel();
    });
    _skipReplayTimer = Timer(const Duration(seconds: 5), () {
      if (!_pendingSkip) return;
      _tts.say(
        S.get('onb_skip_confirm'),
        SpeechPriority.warning,
        barge: true,
      );
    });
  }

  void _cancelSkipConfirm({bool announce = false}) {
    if (!_pendingSkip) return;
    _pendingSkip = false;
    _skipConfirmTimer?.cancel();
    _skipReplayTimer?.cancel();
    if (announce) {
      _tts.say(
        S.get('onb_skip_cancelled'),
        SpeechPriority.info,
        barge: true,
      );
    }
  }

  void _handleTap() {
    _cancelStartup();
    if (_pendingEmergencyExit) {
      _cancelEmergencyExitConfirm(announce: true);
      return;
    }
    if (_pendingSkip) {
      _cancelSkipConfirm(announce: true);
      return;
    }
    unawaited(_speakAndListen(_current));
  }

  void _handleDoubleTap() {
    _cancelStartup();
    if (_pendingEmergencyExit) {
      _cancelEmergencyExitConfirm();
      unawaited(_emergencyExit());
      return;
    }
    if (_pendingSkip) {
      _pendingSkip = false;
      _skipConfirmTimer?.cancel();
      _skipReplayTimer?.cancel();
      unawaited(_emergencyExit());
      return;
    }
    _primaryAction();
  }

  void _primaryAction() {
    _handleConfirmCommand();
  }

  void _handleVerticalSwipe(DragEndDetails d) {
    _cancelStartup();
    final v = d.primaryVelocity;
    if (v == null || v.abs() < 300) return;
    final isUp = v < 0;
    if (_current == 0) {
      _cycleLanguage();
      return;
    }
    if (_current == 1) {
      _cycleHand(isUp ? 1 : -1);
      return;
    }
    if (_current == 2) {
      _cycleMode(isUp ? 1 : -1);
      return;
    }
    if (!isUp) {
      _requestSkipConfirm();
    } else {
      unawaited(_speakAndListen(_current));
    }
  }

  void _handlePointerDown(PointerDownEvent e) {
    _cancelStartup();
    _activePointers.add(e.pointer);
    if (_activePointers.length == 2) {
      _emergencyTimer?.cancel();
      _emergencyTimer = Timer(_kEmergencyHold, () {
        if (_activePointers.length >= 2) {
          _requestEmergencyExitConfirm();
        }
      });
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    if (_activePointers.length < 2) {
      _emergencyTimer?.cancel();
      _emergencyTimer = null;
    }
  }

  Future<void> _emergencyExit() async {
    _emergencyTimer?.cancel();
    await Settings.instance.setOnboardingDone(true);
    await Settings.instance.setOnboardingMode((_chosenMode ?? AppMode.street).name);
    // Do NOT set tutorialSeen/audioTourSeen to true on emergency exit (F-05)
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AiCameraScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _requestCameraPermission() async {
    await _voice.stopListening();
    await _tts.stop();
    if (!mounted) return;

    // Detect TalkBack for appropriate guidance
    final accessible = MediaQuery.of(context).accessibleNavigation;
    final guideKey = accessible ? 'onb_perm_talkback_guide' : 'onb_perm_tap_guide';
    _tts.say(S.get(guideKey), SpeechPriority.critical, barge: true);

    // Play proximity earcon and wait briefly so the user hears the audio cue
    // before the OS permission dialog pops up and steals focus.
    await _earcon.play(Earcon.proximity);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Request permissions
    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
    ].request();
    if (!mounted) return;

    final camOk = results[Permission.camera]?.isGranted ?? false;
    final micOk = results[Permission.microphone]?.isGranted ?? false;

    // Announce each result
    if (camOk) {
      _tts.say(S.get('onb_perm_camera_ok'), SpeechPriority.info);
    }
    if (micOk) {
      _tts.say(S.get('onb_perm_mic_ok'), SpeechPriority.info);
    }

    if (camOk) {
      await _earcon.play(Earcon.success);
      _tts.say(S.get('onb_perm_all_granted'), SpeechPriority.warning, barge: true);
      await _tts.awaitIdle();
      if (!mounted) return;
      _next();
      return;
    }

    final camStatus = results[Permission.camera] ?? PermissionStatus.denied;
    if (camStatus.isPermanentlyDenied) {
      await _earcon.play(Earcon.fail);
      _tts.say(
        S.get('camera_perm_blind_intro'),
        SpeechPriority.critical,
        barge: true,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _PermDeniedDialog(
          onSettings: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          onCancel: () => Navigator.pop(ctx),
        ),
      );
      return;
    }

    // Denied but not permanently — offer retry via voice
    if (mounted) {
      await _earcon.play(Earcon.fail);
      _tts.say(
        S.get('onb_perm_denied_retry'),
        SpeechPriority.critical,
        barge: true,
      );
      await _tts.awaitIdle();
      if (!mounted) return;
      // Re-enable voice listening so user can say "allow" or "skip"
      unawaited(_speakAndListen(3));
    }
  }

  Future<void> _showTtsLanguageWarning() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tts_lang_warned') == true) return;
    await prefs.setBool('tts_lang_warned', true);
    if (!mounted) return;
    final colors = BagdarTheme.colorsOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text(
          S.get('tts_lang_title'),
          style: BagdarTypography.title.copyWith(color: colors.textPrimary),
        ),
        content: Text(
          S.get('tts_lang_body'),
          style: BagdarTypography.body.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.get('tts_lang_open'),
              style:
                  BagdarTypography.body.copyWith(color: colors.accentPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _afterCalibration() async {
    if (Settings.instance.tutorialSeen) {
      _next();
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => GestureTutorialScreen(
          standalone: false,
          onFinished: () {
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await _tts.setLanguage(AppStrings.ttsLang);
    setState(() => _calibrated = Settings.instance.isCalibrated);
    _next();
  }

  Future<void> _ensureTutorialSeen() async {
    if (Settings.instance.tutorialSeen) return;
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => GestureTutorialScreen(
          standalone: false,
          onFinished: () {
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await _tts.setLanguage(AppStrings.ttsLang);
  }

  Future<void> _finish() async {
    await _ensureTutorialSeen();
    if (!mounted) return;
    await Settings.instance.setOnboardingDone(true);
    await Settings.instance.setOnboardingMode((_chosenMode ?? AppMode.street).name);
    await Settings.instance.setAudioTourSeen(true); // Marked seen because controls guide was read
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AiCameraScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
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
          onPointerUp: accessible ? null : _handlePointerUp,
          onPointerCancel: (_) {
            _activePointers.clear();
            _emergencyTimer?.cancel();
            _emergencyTimer = null;
          },
          child: GestureDetector(
            behavior: accessible ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
            onTap: accessible ? null : _handleTap,
            onDoubleTap: accessible ? null : _handleDoubleTap,
            onLongPress: accessible ? null : _cycleLanguage,
            onVerticalDragEnd: accessible ? null : _handleVerticalSwipe,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: _ProgressDots(current: _current, total: 6),
                ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    onPageChanged: _onPageChanged,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _PageReveal(
                        child: _PageLanguage(
                          currentLang: AppStrings.current,
                          onLang: _switchLanguage,
                          onNext: _next,
                        ),
                      ),
                      _PageReveal(
                        child: _PageDominantHand(
                          chosenHand: _chosenHand,
                          onSelect: _setDominantHand,
                          onNext: _next,
                        ),
                      ),
                      _PageReveal(
                        child: _PageDefaultMode(
                          chosenMode: _chosenMode,
                          onSelect: _selectMode,
                          onNext: _next,
                        ),
                      ),
                      _PageReveal(
                        child: _PagePermissions(
                          onAllowCamera: _requestCameraPermission,
                          onSkip: _next,
                        ),
                      ),
                      _PageReveal(
                        child: _PageCalibration(
                          onNext: () => unawaited(_afterCalibration()),
                        ),
                      ),
                      _PageReveal(
                        child: _PageReady(
                          mode: _chosenMode ?? AppMode.street,
                          calibrated: _calibrated,
                          onStart: _finish,
                          onBack: () => _goTo(4),
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
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      label: S.get('sem_step_of').replaceFirst('{step}', '${current + 1}').replaceFirst('{total}', '$total'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: BagdarMotion.duration(context, BagdarMotion.medium),
            width: active ? 32 : 12,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: active
                  ? colors.accentPrimary
                  : colors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(BagdarRadius.sharp),
            ),
          );
        }),
      ),
    );
  }
}

class _PageLanguage extends StatelessWidget {
  final AppLanguage currentLang;
  final ValueChanged<AppLanguage> onLang;
  final VoidCallback onNext;
  const _PageLanguage({
    required this.currentLang,
    required this.onLang,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.language, color: colors.accentPrimary, size: 48),
            const SizedBox(height: 16),
            Text(
              S.get('onb_welcome_title'),
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              S.get('onb_lang_sub'),
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: ToggleButtons(
                borderRadius: BorderRadius.circular(BagdarRadius.panel),
                borderColor: colors.divider,
                selectedBorderColor: colors.accentPrimary,
                selectedColor: colors.accentOnPrimary,
                fillColor: colors.accentPrimary,
                color: colors.textSecondary,
                constraints: const BoxConstraints(minHeight: 64, minWidth: 100),
                textStyle: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
                isSelected: [
                  currentLang == AppLanguage.ru,
                  currentLang == AppLanguage.kk,
                  currentLang == AppLanguage.en,
                ],
                onPressed: (i) => onLang(AppLanguage.values[i]),
                children: const [
                  Text('RU'),
                  Text('ҚЗ'),
                  Text('EN'),
                ],
              ),
            ),
            const Spacer(),
            _PrimaryButton(label: S.get('onb_btn_continue'), onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _PageDominantHand extends StatelessWidget {
  final DominantHand chosenHand;
  final ValueChanged<DominantHand> onSelect;
  final VoidCallback onNext;
  const _PageDominantHand({
    required this.chosenHand,
    required this.onSelect,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.pan_tool, color: colors.accentPrimary, size: 48),
            const SizedBox(height: 16),
            Text(
              S.get('settings_dominant_hand'),
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              S.get('onb_dominant_hand_tts').split(' —').first,
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _HandCard(
              hand: DominantHand.right,
              selected: chosenHand == DominantHand.right,
              onTap: () => onSelect(DominantHand.right),
            ),
            const SizedBox(height: 12),
            _HandCard(
              hand: DominantHand.left,
              selected: chosenHand == DominantHand.left,
              onTap: () => onSelect(DominantHand.left),
            ),
            const Spacer(),
            _PrimaryButton(label: S.get('onb_btn_continue'), onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  final DominantHand hand;
  final bool selected;
  final VoidCallback onTap;
  const _HandCard({
    required this.hand,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = hand == DominantHand.right ? S.get('onb_hand_right') : S.get('onb_hand_left');
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: labelText,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: BagdarMotion.duration(context, BagdarMotion.fast),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected
                ? colors.accentPrimary.withValues(alpha: 0.08)
                : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(BagdarRadius.card),
            border: Border.all(
              color: selected ? colors.accentPrimary : colors.divider,
              width: selected ? BagdarBorders.thin : BagdarBorders.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                hand == DominantHand.right ? Icons.gesture : Icons.gesture_outlined,
                color: selected ? colors.accentPrimary : colors.textSecondary,
                size: 28,
              ),
              const SizedBox(width: 14),
              Text(
                labelText,
                style: BagdarTypography.caption.copyWith(
                  color: selected ? colors.accentPrimary : colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: colors.accentPrimary,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDefaultMode extends StatelessWidget {
  final AppMode? chosenMode;
  final ValueChanged<AppMode> onSelect;
  final VoidCallback onNext;
  const _PageDefaultMode({
    required this.chosenMode,
    required this.onSelect,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility, color: colors.accentPrimary, size: 48),
            const SizedBox(height: 16),
            Text(
              S.get('onb_welcome_sub').split('\n').first,
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              S.get('onb_mode_tts').split(' —').first,
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ...AppMode.values.map(
              (mode) => _ModeCard(
                mode: mode,
                selected: chosenMode == mode,
                onTap: () => onSelect(mode),
              ),
            ),
            const Spacer(),
            _PrimaryButton(label: S.get('onb_btn_continue'), onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final AppMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  String get _description => mode.description;

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}. $_description',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: BagdarMotion.duration(context, BagdarMotion.fast),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected
                ? colors.accentPrimary.withValues(alpha: 0.08)
                : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(BagdarRadius.card),
            border: Border.all(
              color: selected ? colors.accentPrimary : colors.divider,
              width: selected ? BagdarBorders.thin : BagdarBorders.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.accentPrimary.withValues(alpha: 0.15)
                      : colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(BagdarRadius.card),
                ),
                child: Icon(
                  mode.icon,
                  color: selected ? colors.accentPrimary : colors.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: BagdarTypography.caption.copyWith(
                        color: selected ? colors.accentPrimary : colors.textPrimary,
                        fontWeight: BagdarTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _description,
                      style: BagdarTypography.label.copyWith(
                        color: colors.textSecondary,
                        fontWeight: BagdarTypography.weightRegular,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: colors.accentPrimary,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagePermissions extends StatelessWidget {
  final Future<void> Function() onAllowCamera;
  final VoidCallback onSkip;
  const _PagePermissions({required this.onAllowCamera, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.security, color: colors.accentPrimary, size: 44),
            const SizedBox(height: 20),
            Text(
              S.get('onb_perm_title'),
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_perm_sub'),
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            _PermRow(
              icon: Icons.camera_alt,
              label: S.get('perm_camera'),
              reason: S.get('perm_camera_reason'),
              required: true,
            ),
            const SizedBox(height: 10),
            _PermRow(
              icon: Icons.mic,
              label: S.get('perm_mic'),
              reason: S.get('perm_mic_reason'),
              required: false,
            ),
            const SizedBox(height: 10),
            _PermRow(
              icon: Icons.location_on,
              label: S.get('perm_location'),
              reason: S.get('perm_location_reason'),
              required: false,
            ),
            const Spacer(),
            _PrimaryButton(
              label: S.get('onb_btn_allow_camera'),
              onPressed: () {
                unawaited(onAllowCamera());
              },
            ),
            const SizedBox(height: 10),
            _SecondaryButton(label: S.get('onb_btn_skip'), onPressed: onSkip),
          ],
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String reason;
  final bool required;
  const _PermRow({
    required this.icon,
    required this.label,
    required this.reason,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      label: '$label. $reason. ${required ? S.get('sem_required') : S.get('sem_optional_perm')}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          border: Border.all(color: colors.divider, width: BagdarBorders.hairline),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: required ? colors.accentPrimary : colors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: BagdarTypography.label.copyWith(
                      color: colors.textPrimary,
                      letterSpacing: 0,
                    ),
                  ),
                  Text(
                    reason,
                    style: BagdarTypography.label.copyWith(
                      color: colors.textSecondary,
                      fontWeight: BagdarTypography.weightRegular,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: required
                    ? colors.accentPrimary.withValues(alpha: 0.12)
                    : colors.surfaceElevated,
                borderRadius: BorderRadius.circular(BagdarRadius.sharp),
              ),
              child: Text(
                required
                    ? S.get('perm_camera_required')
                    : S.get('perm_optional'),
                style: BagdarTypography.label.copyWith(
                  color: required ? colors.accentPrimary : colors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageCalibration extends StatelessWidget {
  final VoidCallback onNext;

  const _PageCalibration({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.straighten, color: colors.accentPrimary, size: 36),
            const SizedBox(height: 20),
            Text(
              S.get('onb_calib_title'),
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_calib_sub'),
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(BagdarRadius.card),
                border: Border.all(color: colors.divider, width: BagdarBorders.hairline),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _PersonIcon(
                        label: S.get('scan_see'),
                        color: colors.accentPrimary,
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                '◄',
                                style: TextStyle(
                                  color: colors.accentPrimary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '2 м',
                                style: TextStyle(
                                  color: colors.accentPrimary,
                                  fontSize: 13,
                                  fontWeight: BagdarTypography.weightBold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '►',
                                style: TextStyle(
                                  color: colors.accentPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 90,
                            color: colors.accentPrimary.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                      _PersonIcon(
                        label: S.label('person'),
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colors.accentPrimary,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.get('onb_calib_app_note'),
                          style: BagdarTypography.label.copyWith(
                            color: colors.accentPrimary,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            _PrimaryButton(label: S.get('onb_btn_continue'), onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _PersonIcon extends StatelessWidget {
  final String label;
  final Color color;
  const _PersonIcon({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person, color: color, size: 18),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _PageReady extends StatelessWidget {
  final AppMode mode;
  final bool calibrated;
  final VoidCallback onStart;
  final VoidCallback onBack;
  const _PageReady({
    required this.mode,
    required this.calibrated,
    required this.onStart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle, color: colors.stateSuccess, size: 40),
            const SizedBox(height: 20),
            Text(
              S.get('onb_ready_title'),
              style: BagdarTypography.title.copyWith(
                color: colors.textPrimary,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_ready_sub'),
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _CheckItem(
              icon: Icons.volume_up,
              text: S.get('onb_check_alerts'),
              done: true,
            ),
            const SizedBox(height: 8),
            _CheckItem(
              icon: mode.icon,
              text:
                  '${S.get('mode_changed')} «${mode.label}» ${S.get('onb_check_mode')}',
              done: true,
            ),
            const SizedBox(height: 8),
            _CheckItem(
              icon: Icons.straighten,
              text: S.get('onb_check_calib'),
              done: calibrated,
              hint: calibrated ? null : S.get('onb_check_calib_skip'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.accentPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(BagdarRadius.card),
                border: Border.all(
                  color: colors.accentPrimary.withValues(alpha: 0.2),
                  width: BagdarBorders.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.get('onb_feat_settings').split(' —').first,
                    style: BagdarTypography.label.copyWith(
                      color: colors.accentPrimary,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TipRow(icon: Icons.hearing, text: S.get('onb_feat_scan')),
                  _TipRow(icon: Icons.tune, text: S.get('onb_feat_mode')),
                  _TipRow(
                    icon: Icons.settings,
                    text: S.get('onb_feat_settings'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _PrimaryButton(label: S.get('onb_btn_start'), onPressed: onStart),
            const SizedBox(height: 10),
            _SecondaryButton(
              label: S.get('onb_btn_back_calib'),
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool done;
  final String? hint;
  const _CheckItem({
    required this.icon,
    required this.text,
    required this.done,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      label: '$text. ${done ? S.get('sem_done') : "${S.get('sem_not_done')}. ${hint ?? ""}"}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done
                  ? colors.stateSuccess.withValues(alpha: 0.12)
                  : colors.surfaceElevated,
              borderRadius: BorderRadius.circular(BagdarRadius.card),
            ),
            child: Icon(
              done ? Icons.check : icon,
              color: done ? colors.stateSuccess : colors.textSecondary,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: BagdarTypography.label.copyWith(
                    color: done ? colors.textPrimary : colors.textSecondary,
                    fontWeight: BagdarTypography.weightRegular,
                    letterSpacing: 0,
                  ),
                ),
                if (hint != null && !done)
                  Text(
                    hint!,
                    style: BagdarTypography.label.copyWith(
                      color: colors.textSecondary,
                      fontWeight: BagdarTypography.weightRegular,
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, color: colors.textSecondary, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: BagdarTypography.label.copyWith(
                color: colors.textSecondary,
                fontWeight: BagdarTypography.weightRegular,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accentPrimary,
            foregroundColor: colors.accentOnPrimary,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BagdarRadius.card),
            ),
            elevation: 0,
          ),
          child: Text(
            label,
            style: BagdarTypography.caption.copyWith(
              fontWeight: BagdarTypography.weightBold,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BagdarRadius.card),
              side: BorderSide(color: colors.divider, width: BagdarBorders.hairline),
            ),
          ),
          child: Text(
            label,
            style: BagdarTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PermDeniedDialog extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onCancel;
  const _PermDeniedDialog({
    required this.onSettings,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Dialog.fullscreen(
      backgroundColor: colors.surfaceBg,
      child: Semantics(
        liveRegion: true,
        label: S.get('camera_perm_blind_intro'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancel,
          onDoubleTap: onSettings,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.no_photography,
                    color: colors.stateDanger,
                    size: 56,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    S.get('camera_perm_title'),
                    style: BagdarTypography.title.copyWith(
                      color: colors.textPrimary,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    S.get('camera_perm_blind_intro'),
                    style: BagdarTypography.body.copyWith(
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  _PrimaryButton(
                    label: S.get('settings'),
                    onPressed: onSettings,
                  ),
                  const SizedBox(height: 10),
                  _SecondaryButton(
                    label: S.get('cancel'),
                    onPressed: onCancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageReveal extends StatelessWidget {
  final Widget child;
  const _PageReveal({required this.child});

  @override
  Widget build(BuildContext context) {
    if (BagdarMotion.reduceMotionOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: BagdarMotion.medium,
      curve: BagdarMotion.standard,
      builder: (context, t, _) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
