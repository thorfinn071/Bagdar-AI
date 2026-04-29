import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_mode.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import 'camera_screen.dart';
import 'gesture_tutorial_screen.dart';



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

  int _current = 0;
  AppMode _chosenMode = AppMode.street;

  bool _calibrated = false;
  bool _pendingSkip = false;
  Timer? _skipConfirmTimer;

  final Set<int> _activePointers = {};
  Timer? _emergencyTimer;
  static const Duration _kEmergencyHold = Duration(seconds: 2);

  List<String> get _stepNarrations => [
    S.get('onb_welcome_tts'),
    S.get('onb_perm_tts'),
    S.get('onb_calib_tts'),
    S.get('onb_ready_tts'),
  ];

  @override
  void initState() {
    super.initState();
    _tts.init().then((_) async {
      AppStrings.setLanguage(AppLanguage.values[Settings.instance.language]);
      await _tts.setLanguage(AppStrings.ttsLang);
      if (mounted) setState(() => _calibrated = Settings.instance.isCalibrated);
      _tts.say(
        S.get('onb_blind_intro'),
        SpeechPriority.critical,
        pan: 0.0,
      );
      await _tts.awaitCurrentSpeech();
      if (!mounted) return;
      _speak(0);
      if (!_tts.languageAvailable && mounted) {
        _showTtsLanguageWarning();
      }
    });
  }

  @override
  void dispose() {
    _skipConfirmTimer?.cancel();
    _emergencyTimer?.cancel();
    _tts.stop();
    _page.dispose();
    super.dispose();
  }

  void _next() {
    if (_current < 3) {
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
    _speak(index, barge: true);
  }

  void _speak(int index, {bool barge = false}) {
    _tts.say(
      _stepNarrations[index],
      barge ? SpeechPriority.critical : SpeechPriority.info,
      barge: barge,
    );
  }

  Future<void> _switchLanguage(AppLanguage lang) async {
    AppStrings.setLanguage(lang);
    await Settings.instance.setLanguage(lang.index);
    await _tts.setLanguage(AppStrings.ttsLang);
    if (mounted) {
      setState(() {});
      _tts.say(
        S.get('onb_lang_switched'),
        SpeechPriority.critical,
        barge: true,
      );
      await _tts.awaitCurrentSpeech();
      if (!mounted) return;
      _speak(_current, barge: true);
    }
  }

  void _cycleLanguage() {
    final next = AppLanguage.values[
        (AppStrings.current.index + 1) % AppLanguage.values.length];
    unawaited(_switchLanguage(next));
  }

  void _cycleMode(int dir) {
    const modes = AppMode.values;
    final cur = modes.indexOf(_chosenMode);
    final next = modes[(cur + dir + modes.length) % modes.length];
    setState(() => _chosenMode = next);
    final text = S
        .get('onb_mode_select_announce')
        .replaceFirst('{mode}', next.label);
    _tts.say(text, SpeechPriority.critical, barge: true);
  }

  void _requestSkipConfirm() {
    _pendingSkip = true;
    _tts.say(
      S.get('onb_skip_confirm'),
      SpeechPriority.critical,
      barge: true,
    );
    _skipConfirmTimer?.cancel();
    _skipConfirmTimer = Timer(const Duration(seconds: 5), () {
      _pendingSkip = false;
    });
  }

  void _handleTap() {
    if (_pendingSkip) {
      _pendingSkip = false;
      _skipConfirmTimer?.cancel();
      _tts.say(
        S.get('onb_skip_cancelled'),
        SpeechPriority.critical,
        barge: true,
      );
      return;
    }
    _speak(_current, barge: true);
  }

  void _handleDoubleTap() {
    if (_pendingSkip) {
      _pendingSkip = false;
      _skipConfirmTimer?.cancel();
      unawaited(_emergencyExit());
      return;
    }
    _primaryAction();
  }

  void _primaryAction() {
    switch (_current) {
      case 0:
        _next();
        break;
      case 1:
        unawaited(_requestCameraPermission());
        break;
      case 2:
        unawaited(_afterCalibration());
        break;
      case 3:
        unawaited(_finish());
        break;
    }
  }

  void _handleVerticalSwipe(DragEndDetails d) {
    final v = d.primaryVelocity;
    if (v == null || v.abs() < 300) return;
    final isUp = v < 0;
    if (_current == 0) {
      _cycleMode(isUp ? 1 : -1);
      return;
    }
    if (!isUp) {
      _requestSkipConfirm();
    } else {
      _speak(_current, barge: true);
    }
  }

  void _handlePointerDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    if (_activePointers.length == 2) {
      _emergencyTimer?.cancel();
      _emergencyTimer = Timer(_kEmergencyHold, () {
        if (_activePointers.length >= 2) {
          unawaited(_emergencyExit());
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
    await Settings.instance.setOnboardingMode(_chosenMode.name);
    await Settings.instance.setTutorialSeen(true);
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
    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
    ].request();
    if (!mounted) return;

    final status = results[Permission.camera] ?? PermissionStatus.denied;

    if (status.isGranted) {
      _next();
      return;
    }

    if (status.isPermanentlyDenied) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            S.get('camera_perm_title'),
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            S.get('camera_perm_body'),
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.get('cancel')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: Text(S.get('settings')),
            ),
          ],
        ),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.get('camera_perm_body'))));
    }
  }

  Future<void> _showTtsLanguageWarning() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tts_lang_warned') == true) return;
    await prefs.setBool('tts_lang_warned', true);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          S.get('tts_lang_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          S.get('tts_lang_body'),
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.get('tts_lang_open'),
              style: const TextStyle(color: Colors.cyanAccent),
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
    await Settings.instance.setOnboardingMode(_chosenMode.name);
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerUp,
          onPointerCancel: (_) {
            _activePointers.clear();
            _emergencyTimer?.cancel();
            _emergencyTimer = null;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: _handleTap,
            onDoubleTap: _handleDoubleTap,
            onLongPress: _cycleLanguage,
            onVerticalDragEnd: _handleVerticalSwipe,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: _ProgressDots(current: _current, total: 4),
                ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    onPageChanged: _onPageChanged,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _PageMode(
                        chosen: _chosenMode,
                        currentLang: AppStrings.current,
                        onSelect: (m) => setState(() => _chosenMode = m),
                        onLang: _switchLanguage,
                        onNext: _next,
                      ),
                      _PagePermissions(
                        onAllowCamera: _requestCameraPermission,
                        onSkip: _next,
                      ),
                      _PageCalibration(
                        onNext: () => unawaited(_afterCalibration()),
                      ),
                      _PageReady(
                        mode: _chosenMode,
                        calibrated: _calibrated,
                        onStart: _finish,
                        onBack: () => _goTo(2),
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
    return Semantics(
      label: S.get('sem_step_of').replaceFirst('{step}', '${current + 1}').replaceFirst('{total}', '$total'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: active ? 24 : 8,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: active ? Colors.cyanAccent : Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class _PageMode extends StatelessWidget {
  final AppMode chosen;
  final AppLanguage currentLang;
  final ValueChanged<AppMode> onSelect;
  final ValueChanged<AppLanguage> onLang;
  final VoidCallback onNext;
  const _PageMode({
    required this.chosen,
    required this.currentLang,
    required this.onSelect,
    required this.onLang,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  S.get('onb_lang_title'),
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const Spacer(),
                ToggleButtons(
                  borderRadius: BorderRadius.circular(8),
                  borderColor: Colors.white24,
                  selectedBorderColor: Colors.cyanAccent,
                  selectedColor: Colors.black,
                  fillColor: Colors.cyanAccent,
                  color: Colors.white70,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  isSelected: [
                    currentLang == AppLanguage.ru,
                    currentLang == AppLanguage.kk,
                    currentLang == AppLanguage.en,
                  ],
                  onPressed: (i) => onLang(AppLanguage.values[i]),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text('RU'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text('ҚЗ'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text('EN'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Icon(Icons.visibility, color: Colors.cyanAccent, size: 40),
            const SizedBox(height: 16),
            Text(
              S.get('onb_welcome_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              S.get('onb_welcome_sub'),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ...AppMode.values.map(
              (mode) => _ModeCard(
                mode: mode,
                selected: chosen == mode,
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
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}. $_description',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? Colors.cyanAccent.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.cyanAccent : Colors.white12,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.cyanAccent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  mode.icon,
                  color: selected ? Colors.cyanAccent : Colors.white38,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: selected ? Colors.cyanAccent : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _description,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.cyanAccent,
                  size: 20,
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
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.security, color: Colors.cyanAccent, size: 36),
            const SizedBox(height: 20),
            Text(
              S.get('onb_perm_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_perm_sub'),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 15,
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
    return Semantics(
      label: '$label. $reason. ${required ? S.get('sem_required') : S.get('sem_optional_perm')}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: required ? Colors.cyanAccent : Colors.white38,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    reason,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: required
                    ? Colors.cyanAccent.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                required
                    ? S.get('perm_camera_required')
                    : S.get('perm_optional'),
                style: TextStyle(
                  color: required ? Colors.cyanAccent : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
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
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.straighten, color: Colors.cyanAccent, size: 36),
            const SizedBox(height: 20),
            Text(
              S.get('onb_calib_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_calib_sub'),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _PersonIcon(
                        label: S.get('scan_see'),
                        color: Colors.cyanAccent,
                      ),
                      Column(
                        children: [
                          const Row(
                            children: [
                              Text(
                                '◀',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '2 м',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '▶',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 90,
                            color: Colors.cyanAccent.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                      _PersonIcon(
                        label: S.label('person'),
                        color: Colors.white38,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.cyanAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.get('onb_calib_app_note'),
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
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
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 40),
            const SizedBox(height: 20),
            Text(
              S.get('onb_ready_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.get('onb_ready_sub'),
              style: const TextStyle(
                color: Colors.white60,
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
                color: Colors.cyanAccent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.get('onb_feat_settings').split(' —').first,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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
                  ? Colors.greenAccent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              done ? Icons.check : icon,
              color: done ? Colors.greenAccent : Colors.white38,
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
                  style: TextStyle(
                    color: done ? Colors.white : Colors.white54,
                    fontSize: 13,
                  ),
                ),
                if (hint != null && !done)
                  Text(
                    hint!,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white54,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12, width: 0.5),
            ),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }
}
