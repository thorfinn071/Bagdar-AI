import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/strings.dart';
import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import '../../widgets/bagdar_ui.dart';
import 'onboarding_controller.dart';
import 'onboarding_copy.dart';
import 'onboarding_state.dart';
import 'onboarding_store.dart';
import 'voice/native_onboarding_voice_input.dart';
import 'voice/onboarding_voice_coordinator.dart';
import 'voice/onboarding_voice_input.dart';
import 'voice/onboarding_voice_panel.dart';

ThemeData onboardingTheme({bool highContrast = false}) =>
    BagdarTheme.buildMaterialTheme(
      highContrast ? BagdarThemeName.highContrast : BagdarThemeName.light,
    );

class OnboardingV2Screen extends StatefulWidget {
  final OnboardingController controller;
  final Future<void> Function(BuildContext, OnboardingController)? onInspect;
  final bool disposeController;
  final OnboardingVoiceInput? voiceInput;
  const OnboardingV2Screen({
    super.key,
    required this.controller,
    this.onInspect,
    this.disposeController = true,
    this.voiceInput,
  });

  @override
  State<OnboardingV2Screen> createState() => _OnboardingV2ScreenState();
}

class _OnboardingV2ScreenState extends State<OnboardingV2Screen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final Set<OnboardingText> _expandedBlocks = {};
  final FocusNode _heading = FocusNode(debugLabel: 'onboarding-heading');
  final FocusNode _exerciseHeading = FocusNode(
    debugLabel: 'onboarding-exercise',
  );
  final GlobalKey _practiceFeedbackKey = GlobalKey();
  late OnboardingStep _lastStep;
  OnboardingText? _lastPracticeMessage;
  int _lastExercise = 0;
  bool _lastQuickCheck = false;
  bool _lastUserHasControl = true;
  int _lastSessionStage = 1;
  bool _checkingHaptic = false;
  late final OnboardingVoiceCoordinator _voice;
  BagdarColors get colors => BagdarColors.of(
    MediaQuery.maybeOf(context)?.highContrast == true
        ? BagdarThemeName.highContrast
        : BagdarTheme.maybeOf(context)?.name ?? BagdarThemeName.light,
  );
  OnboardingController get c => widget.controller;
  OnboardingCopy get copy => c.copy;
  String t(OnboardingText key) => copy.t(key);
  Locale _locale(AppLanguage language) => Locale(switch (language) {
    AppLanguage.ru => 'ru',
    AppLanguage.kk => 'kk',
    AppLanguage.en => 'en',
  });
  // Voice dialogue owns spoken announcements while enabled, including the
  // recognition window after TTS. Keep screen-reader navigation available
  // without automatic live-region speech being captured as an answer.
  bool get _live => !_voice.enabled && !c.speaking && !c.stoppingSpeech;
  bool get _hasPracticeFeedback =>
      c.step == OnboardingStep.practice &&
      !c.practiceFinished &&
      const {
        OnboardingText.correctAction,
        OnboardingText.wrongAction,
        OnboardingText.wrongStop,
        OnboardingText.wrongSide,
        OnboardingText.wrongLost,
        OnboardingText.wrongPause,
        OnboardingText.practicePaused,
      }.contains(c.message);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastStep = c.step;
    _lastPracticeMessage = c.message;
    _lastExercise = c.practiceIndex;
    _lastQuickCheck = c.isQuickCheck;
    _lastUserHasControl = c.userHasControl;
    _lastSessionStage = c.sessionStage;
    c.addListener(_changed);
    _voice = OnboardingVoiceCoordinator(
      controller: c,
      input: widget.voiceInput ?? NativeOnboardingVoiceInput(),
      onInspect: widget.onInspect == null
          ? null
          : () => widget.onInspect!(context, c),
    )..addListener(_voiceChanged);
    if (c.loading) unawaited(c.initialize());
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    final changedPage =
        c.step != _lastStep ||
        c.isQuickCheck != _lastQuickCheck ||
        c.userHasControl != _lastUserHasControl ||
        (c.isQuickCheck && c.sessionStage != _lastSessionStage);
    final changedExercise =
        c.step == OnboardingStep.practice && c.practiceIndex != _lastExercise;
    final changedFeedback =
        _hasPracticeFeedback && c.message != _lastPracticeMessage;
    _lastStep = c.step;
    _lastPracticeMessage = c.message;
    _lastExercise = c.practiceIndex;
    _lastQuickCheck = c.isQuickCheck;
    _lastUserHasControl = c.userHasControl;
    _lastSessionStage = c.sessionStage;
    setState(() {});
    if (changedFeedback && !changedPage && !changedExercise) {
      _revealPracticeFeedback();
    }
    if (changedPage || changedExercise) {
      _expandedBlocks.clear();
      final targetStep = c.step;
      final targetExercise = c.practiceIndex;
      final targetQuickCheck = c.isQuickCheck;
      final targetUserHasControl = c.userHasControl;
      final targetSessionStage = c.sessionStage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            c.step != targetStep ||
            c.practiceIndex != targetExercise ||
            c.isQuickCheck != targetQuickCheck ||
            c.userHasControl != targetUserHasControl ||
            c.sessionStage != targetSessionStage) {
          return;
        }
        if (_scroll.hasClients) _scroll.jumpTo(0);
        if (changedPage || c.practiceFinished) {
          _heading.requestFocus();
        } else {
          _exerciseHeading.requestFocus();
        }
      });
    }
  }

  void _revealPracticeFeedback() {
    final targetMessage = c.message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasPracticeFeedback || c.message != targetMessage) {
        return;
      }
      final feedbackContext = _practiceFeedbackKey.currentContext;
      if (feedbackContext != null) {
        Scrollable.ensureVisible(feedbackContext, alignment: 0.5);
      }
    });
  }

  Future<void> _answerPractice(PracticeAction action) async {
    final previousMessage = c.message;
    await c.practiceAction(action);
    // Repeating the same wrong answer still needs visible feedback, while
    // unrelated controller notifications must not pull the reader's scroll.
    if (mounted && _hasPracticeFeedback && c.message == previousMessage) {
      _revealPracticeFeedback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _voice.suspend();
      c.suspend(background: true);
    } else if (state == AppLifecycleState.resumed) {
      unawaited(() async {
        await c.resume();
        if (mounted) await _voice.resume();
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    if (widget.disposeController) c.dispose();
    _scroll.dispose();
    _heading.dispose();
    _exerciseHeading.dispose();
    super.dispose();
  }

  void _back() {
    if (c.speaking) {
      unawaited(
        _afterSpeech(
          () => c.step == OnboardingStep.language ? c.later() : c.back(),
        ),
      );
      return;
    }
    if (c.busy) {
      c.suspend();
      return;
    }
    unawaited(c.step == OnboardingStep.language ? c.later() : c.back());
  }

  Future<void> _afterSpeech(Future<void> Function() action) async {
    final step = c.step;
    await c.stopSpeech();
    if (mounted &&
        c.step == step &&
        !c.busy &&
        (c.message == OnboardingText.speechStopped ||
            c.message == OnboardingText.coachStopped)) {
      await action();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inherited = MediaQuery.of(context);
    final scale =
        c.progress.accessMode == AccessMode.largeText &&
            inherited.textScaler.scale(16) < 20
        ? const TextScaler.linear(1.25)
        : inherited.textScaler;
    return Semantics(
      localeForSubtree: _locale(c.progress.language),
      child: BagdarThemeScope(
        child: MediaQuery(
          data: inherited.copyWith(textScaler: scale),
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _back();
            },
            child: Scaffold(
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        c.step == OnboardingStep.language ? 32 : 16,
                        24,
                        32,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: BagdarSpacing.contentMaxWidth,
                          ),
                          child: _page(context),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) {
    if (c.loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Text(t(OnboardingText.bootLoading)),
        ),
      );
    }
    final recovery =
        c.loadStatus == ProgressLoadStatus.corrupt ||
        c.loadStatus == ProgressLoadStatus.unsupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: c.stoppingSpeech ? null : _back,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              label: Text(t(OnboardingText.back)),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
            ExcludeSemantics(
              child: Text(
                'Bagdar',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: c.step == OnboardingStep.summary && !c.isQuickCheck
              ? Text(
                  t(OnboardingText.setupOverview),
                  key: const Key('onboarding-progress'),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                )
              : Wrap(
                  key: const Key('onboarding-progress'),
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      copy.phase(c.step),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: colors.accentPrimary,
                      ),
                    ),
                    Text(
                      c.isQuickCheck
                          ? copy.sessionProgress(c.sessionStage)
                          : copy.stepProgress(c.step),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        Focus(
          focusNode: _heading,
          child: Semantics(
            header: true,
            liveRegion: _live,
            label: c.isQuickCheck
                ? '${copy.sessionProgress(c.sessionStage)}. ${t(OnboardingText.sessionTitle)}'
                : '${copy.stepProgress(c.step)}. ${copy.title(c.step)}',
            excludeSemantics: true,
            child: Text(
              c.isQuickCheck
                  ? t(OnboardingText.sessionTitle)
                  : copy.title(c.step),
              key: ValueKey('heading-${c.step.name}'),
              style: TextStyle(
                fontSize: 32,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          c.isQuickCheck ? t(OnboardingText.sessionBody) : copy.body(c.step),
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: colors.textSecondary,
          ),
        ),
        SizedBox(height: c.step == OnboardingStep.language ? 24 : 28),
        if (c.step != OnboardingStep.language || recovery) ...[
          _instructionControl(),
          const SizedBox(height: 16),
        ],
        if (recovery) ...[
          _note(
            t(
              c.loadStatus == ProgressLoadStatus.unsupported
                  ? OnboardingText.restoreFuture
                  : OnboardingText.restoreError,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: c.busy ? null : c.retryLoad,
            child: Text(t(OnboardingText.retry)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: c.busy
                ? null
                : () => c.recover(
                    withoutSaving:
                        c.loadStatus == ProgressLoadStatus.unsupported,
                  ),
            child: Text(
              t(
                c.loadStatus == ProgressLoadStatus.unsupported
                    ? OnboardingText.storageSessionOnly
                    : OnboardingText.restart,
              ),
            ),
          ),
          if (c.loadStatus != ProgressLoadStatus.unsupported)
            TextButton(
              onPressed: c.busy ? null : () => c.recover(withoutSaving: true),
              child: Text(t(OnboardingText.storageSessionOnly)),
            ),
          if (c.message != null) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: _live, child: _note(t(c.message!))),
            if (c.hasSpeechProblem) ..._speechRecovery(),
          ],
        ] else ...[
          if (_voice.supported || _voice.phase != OnboardingVoicePhase.off) ...[
            OnboardingVoicePanel(voice: _voice),
            const SizedBox(height: 20),
          ],
          if (c.sessionOnly) ...[
            _note(t(OnboardingText.sessionOnlyNotice)),
            const SizedBox(height: 20),
          ],
          if (c.progress.accessMode == AccessMode.helper) ...[
            _helperHandoff(),
            const SizedBox(height: 20),
          ],
          ...(c.isQuickCheck ? _sessionContent() : _content()),
          if (c.message != null && !_hasPracticeFeedback) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: _live, child: _note(t(c.message!))),
            if (c.hasSpeechProblem) ..._speechRecovery(),
            if (c.message == OnboardingText.saveError)
              TextButton(
                onPressed: c.busy ? null : () => c.recover(withoutSaving: true),
                child: Text(t(OnboardingText.storageSessionOnly)),
              ),
          ],
          if (c.busy) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const ExcludeSemantics(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    liveRegion: _live,
                    child: Text(
                      t(
                        c.speaking
                            ? OnboardingText.reading
                            : c.stoppingSpeech
                            ? OnboardingText.stoppingSpeech
                            : OnboardingText.checking,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: c.stoppingSpeech
                      ? null
                      : c.speaking
                      ? () => unawaited(c.stopSpeech())
                      : c.suspend,
                  child: Text(t(OnboardingText.close)),
                ),
              ],
            ),
          ],
          SizedBox(height: c.step == OnboardingStep.language ? 40 : 28),
          if (c.isQuickCheck)
            ..._sessionActions(context)
          else if (c.step == OnboardingStep.summary)
            ..._summaryActions(context)
          else ...[
            if (c.step != OnboardingStep.practice || c.practiceFinished)
              FilledButton(
                key: const Key('onboarding-primary'),
                onPressed: !c.canContinue
                    ? null
                    : c.step == OnboardingStep.camera &&
                          c.evidence.cameraAccess != CameraAccess.granted
                    ? () =>
                          c.goTo(OnboardingStep.summary, saveCheckpoint: false)
                    : c.next,
                child: Text(
                  c.step == OnboardingStep.language
                      ? copy.continueLanguage
                      : c.step == OnboardingStep.camera &&
                            c.evidence.cameraAccess != CameraAccess.granted
                      ? t(OnboardingText.cameraLater)
                      : c.step == OnboardingStep.feedback &&
                            !c.evidence.criticalChannelVerified
                      ? t(OnboardingText.trainingWithoutSignals)
                      : t(
                          c.step == OnboardingStep.practice
                              ? OnboardingText.finishPractice
                              : OnboardingText.next,
                        ),
                ),
              ),
            SizedBox(height: c.step == OnboardingStep.language ? 20 : 12),
            if (c.step == OnboardingStep.language)
              Text(
                t(OnboardingText.languageFooter),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              )
            else
              TextButton(
                key: const Key('onboarding-later'),
                onPressed: c.stoppingSpeech
                    ? null
                    : c.speaking
                    ? () => unawaited(_afterSpeech(c.later))
                    : c.busy
                    ? () {
                        c.suspend();
                        unawaited(c.later());
                      }
                    : c.later,
                child: Text(t(OnboardingText.later)),
              ),
          ],
        ],
      ],
    );
  }

  List<Widget> _content({OnboardingStep? forStep}) => switch (forStep ??
      c.step) {
    OnboardingStep.language => [
      _choices<AppLanguage>(
        value: c.progress.language,
        onChanged: c.selectLanguage,
        options: const [
          (AppLanguage.kk, 'Қазақша', null),
          (AppLanguage.ru, 'Русский', null),
          (AppLanguage.en, 'English', null),
        ],
        large: true,
      ),
      const SizedBox(height: 36),
      _instructionControl(),
    ],
    OnboardingStep.access => [
      _choices<AccessMode>(
        value: c.progress.accessMode,
        onChanged: c.selectMode,
        options: [
          (
            AccessMode.voice,
            t(OnboardingText.voice),
            t(OnboardingText.voiceBody),
          ),
          (
            AccessMode.largeText,
            t(OnboardingText.largeText),
            t(OnboardingText.largeTextBody),
          ),
          (
            AccessMode.helper,
            t(OnboardingText.helper),
            t(OnboardingText.helperBody),
          ),
        ],
      ),
    ],
    OnboardingStep.limits => [
      _informationBlocks(OnboardingStep.limits),
      const SizedBox(height: 20),
      _check(OnboardingText.understand, c.limitsAccepted, c.acceptLimits),
    ],
    OnboardingStep.feedback => _signalTasks(),
    OnboardingStep.privacy => [_informationBlocks(OnboardingStep.privacy)],
    OnboardingStep.vocabulary => [
      _group([
        _vocabulary(c.stopCue, OnboardingText.stopMeaning, critical: true),
        _vocabulary(c.sideCue, OnboardingText.sideMeaning),
        _vocabulary(c.lostCue, OnboardingText.lostMeaning),
        _vocabulary(t(OnboardingText.pauseCue), OnboardingText.pauseMeaning),
      ]),
    ],
    OnboardingStep.practice => _practice(),
    OnboardingStep.camera => [
      _note(copy.cameraAccessDescription(c.evidence.cameraAccess)),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: c.busy ? null : c.requestCamera,
        icon: const Icon(Icons.camera_alt_outlined),
        label: Text(
          t(
            c.evidence.cameraAccess == CameraAccess.granted
                ? OnboardingText.retry
                : OnboardingText.cameraRequest,
          ),
        ),
      ),
      if (c.evidence.cameraAccess == CameraAccess.permanentlyDenied) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: c.busy ? null : c.openCameraSettings,
          child: Text(t(OnboardingText.settings)),
        ),
      ],
    ],
    OnboardingStep.device => [
      _group([
        _probe(OnboardingText.cameraFrames, c.evidence.camera),
        _probe(OnboardingText.temperature, c.evidence.thermal),
      ]),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: c.busy ? null : c.deviceCheck,
        child: Text(t(OnboardingText.checkDevice)),
      ),
    ],
    OnboardingStep.alignment => [
      _note(t(OnboardingText.alignmentHold)),
      const SizedBox(height: 20),
      _group([_probe(OnboardingText.alignment, c.evidence.alignment)]),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: c.busy ? null : c.alignmentCheck,
        child: Text(t(OnboardingText.checkAlignment)),
      ),
      const SizedBox(height: 12),
      ..._positionGuidance(),
      _check(
        OnboardingText.alignmentConfirm,
        c.alignmentAccepted,
        c.evidence.alignment.freshAt(c.now()) ? c.confirmAlignment : null,
      ),
    ],
    OnboardingStep.stationary => [
      _check(
        OnboardingText.stationaryConfirm,
        c.stationaryAccepted,
        c.confirmStationary,
      ),
      const SizedBox(height: 20),
      _group([
        _probe(OnboardingText.cameraFrames, c.evidence.camera),
        _probe(OnboardingText.temperature, c.evidence.thermal),
      ]),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: c.busy || !c.stationaryAccepted
            ? null
            : () => c.deviceCheck(stationary: true),
        child: Text(t(OnboardingText.checkStationary)),
      ),
    ],
    OnboardingStep.summary => _summary(),
  };

  List<Widget> _signalTasks() => [
    Semantics(
      header: true,
      liveRegion: _live,
      child: Text(
        t(
          _checkingHaptic
              ? OnboardingText.hapticTask
              : c.evidence.ordinaryVoiceConfirmed
              ? OnboardingText.stopTask
              : OnboardingText.ordinaryTask,
        ),
      ),
    ),
    const SizedBox(height: 16),
    if (_checkingHaptic) ...[
      _group([
        _action(
          OnboardingText.stopHaptic,
          Icons.vibration_rounded,
          c.playHaptic,
        ),
      ]),
      _check(
        OnboardingText.felt,
        c.evidence.hapticConfirmed,
        c.evidence.hapticPlayed ? c.confirmHaptic : null,
      ),
      if (!c.evidence.hapticConfirmed) _note(t(OnboardingText.hapticRecovery)),
    ] else if (!c.evidence.ordinaryVoiceConfirmed) ...[
      _group([
        _action(
          OnboardingText.ordinaryVoice,
          Icons.volume_up_outlined,
          () => c.playVoice(),
        ),
      ]),
      _check(
        OnboardingText.ordinaryHeard,
        c.evidence.ordinaryVoiceConfirmed,
        c.evidence.voiceSamplePlayed ? c.confirmOrdinaryVoice : null,
      ),
      _note(t(OnboardingText.checkSound)),
    ] else ...[
      _group([
        _action(
          OnboardingText.stopVoice,
          Icons.volume_up_outlined,
          () => c.playVoice(stop: true),
        ),
      ]),
      _check(
        OnboardingText.heard,
        c.evidence.voiceConfirmed,
        c.evidence.voiceSamplePlayed && c.evidence.stopVoicePlayed
            ? c.confirmVoice
            : null,
      ),
      _note(t(OnboardingText.checkSound)),
    ],
    const SizedBox(height: 12),
    TextButton(
      onPressed: c.busy
          ? null
          : () => setState(() => _checkingHaptic = !_checkingHaptic),
      child: Text(
        t(_checkingHaptic ? OnboardingText.useVoice : OnboardingText.useHaptic),
      ),
    ),
    const SizedBox(height: 12),
    _note(
      t(
        c.evidence.criticalChannelVerified
            ? OnboardingText.feedbackFooter
            : OnboardingText.feedbackMissing,
      ),
    ),
    const SizedBox(height: 16),
    ExpansionTile(
      title: Text(t(OnboardingText.speechSpeed)),
      children: [
        _choices<double>(
          value: c.rate,
          onChanged: c.changeRate,
          options: const [
            (0.75, '0.75×', null),
            (1, '1×', null),
            (1.25, '1.25×', null),
          ],
        ),
      ],
    ),
  ];

  List<Widget> _practice() {
    if (c.practiceFinished) {
      return [
        _note(t(OnboardingText.practiceFinished)),
        TextButton(
          onPressed: c.busy ? null : c.restartPractice,
          child: Text(t(OnboardingText.practiceRestart)),
        ),
      ];
    }
    return [
      Text(
        t(OnboardingText.trainingLabel),
        style: TextStyle(fontSize: 16, color: colors.textSecondary),
      ),
      const SizedBox(height: 16),
      _group([
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(
                focusNode: _exerciseHeading,
                child: Semantics(
                  header: true,
                  liveRegion: _live,
                  child: Text(
                    copy.sceneProgress(c.practiceIndex),
                    style: TextStyle(fontSize: 16, color: colors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                c.practicePaused
                    ? t(OnboardingText.practicePaused)
                    : c.practiceCue,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: c.busy || c.practicePaused
                    ? null
                    : () => c.listen(
                        c.practiceCue,
                        critical: c.practiceIndex == 0,
                      ),
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(t(OnboardingText.repeat)),
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (_hasPracticeFeedback) ...[
        Semantics(
          key: _practiceFeedbackKey,
          liveRegion: _live,
          child: Container(
            key: const Key('practice-feedback'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              border: Border.all(color: colors.accentPrimary),
              borderRadius: BorderRadius.circular(BagdarRadius.card),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    c.practicePaused
                        ? Icons.pause_circle_outline
                        : c.practiceAnswered
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: colors.accentPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      c.practicePaused
                          ? OnboardingText.practicePauseHint
                          : c.message!,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (c.practicePaused)
        OutlinedButton(
          onPressed: c.busy || !c.userHasControl
              ? null
              : () => _answerPractice(PracticeAction.resume),
          child: Text(t(OnboardingText.resumeAction)),
        )
      else if (!c.practiceAnswered) ...[
        Text(
          t(OnboardingText.practiceQuestion),
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        for (final action in [
          PracticeAction.stop,
          PracticeAction.check,
          PracticeAction.move,
        ]) ...[
          OutlinedButton(
            onPressed: c.busy || !c.userHasControl
                ? null
                : () => _answerPractice(action),
            child: Text(
              t(switch (action) {
                PracticeAction.stop => OnboardingText.stopAction,
                PracticeAction.check => OnboardingText.checkAction,
                _ => OnboardingText.moveAction,
              }),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
      if (c.practiceAnswered && !c.practicePaused)
        FilledButton(
          key: const Key('next-exercise'),
          onPressed: c.busy ? null : c.nextExercise,
          child: Text(
            t(
              c.practiceIndex == 3
                  ? OnboardingText.finishExamples
                  : OnboardingText.nextExample,
            ),
          ),
        ),
      if (!c.practicePaused)
        TextButton(
          onPressed: c.busy || !c.userHasControl
              ? null
              : () => _answerPractice(PracticeAction.pause),
          child: Text(t(OnboardingText.pauseAction)),
        ),
      TextButton(
        onPressed: c.busy ? null : c.restartPractice,
        child: Text(t(OnboardingText.practiceRestart)),
      ),
    ];
  }

  List<Widget> _speechRecovery() => [
    const SizedBox(height: 8),
    OutlinedButton(
      key: const Key('onboarding-retry-speech'),
      onPressed: c.busy ? null : c.retrySpeech,
      child: Text(t(OnboardingText.retry)),
    ),
    TextButton(
      onPressed: c.busy ? null : c.openSpeechSettings,
      child: Text(t(OnboardingText.speechSettings)),
    ),
  ];

  List<Widget> _sessionContent() => [
    Semantics(
      header: true,
      child: Text(
        t(switch (c.sessionStage) {
          1 => OnboardingText.sessionSignals,
          2 => OnboardingText.sessionPermission,
          _ => OnboardingText.sessionDevice,
        }),
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
    ),
    const SizedBox(height: 16),
    if (c.sessionStage == 1) ..._content(forStep: OnboardingStep.feedback),
    if (c.sessionStage == 2) ..._content(forStep: OnboardingStep.camera),
    if (c.sessionStage == 3) ...[
      _check(
        OnboardingText.stationaryConfirm,
        c.stationaryAccepted,
        c.confirmStationary,
      ),
      const SizedBox(height: 12),
      _note(t(OnboardingText.alignmentHold)),
      const SizedBox(height: 16),
      OutlinedButton(
        key: const Key('onboarding-check-session'),
        onPressed: c.canCheckSession ? c.checkSession : null,
        child: Text(t(OnboardingText.sessionCheck)),
      ),
      const SizedBox(height: 16),
      _group([
        _probe(OnboardingText.cameraFrames, c.evidence.camera),
        _probe(OnboardingText.temperature, c.evidence.thermal),
        _probe(OnboardingText.alignment, c.evidence.alignment),
      ]),
      const SizedBox(height: 16),
      ..._positionGuidance(),
      const SizedBox(height: 16),
      _check(
        OnboardingText.alignmentConfirm,
        c.alignmentAccepted,
        c.evidence.alignment.freshAt(c.now()) ? c.confirmAlignment : null,
      ),
      const SizedBox(height: 16),
      Semantics(
        liveRegion: _live,
        child: _note(
          t(
            c.admission == Admission.inspectionOnly
                ? OnboardingText.sessionReady
                : OnboardingText.sessionNotReady,
          ),
        ),
      ),
    ],
  ];

  List<Widget> _sessionActions(BuildContext context) => [
    if (c.sessionStage == 3) ...[
      FilledButton(
        key: const Key('onboarding-primary'),
        onPressed:
            c.busy ||
                c.admission != Admission.inspectionOnly ||
                widget.onInspect == null
            ? null
            : _voice.openInspection,
        child: Text(t(OnboardingText.inspection)),
      ),
      const SizedBox(height: 12),
    ],
    OutlinedButton(
      onPressed: c.busy ? null : () => c.goTo(OnboardingStep.summary),
      child: Text(t(OnboardingText.sessionSetup)),
    ),
  ];

  List<Widget> _summary() => [
    if (c.progress.checkpoint != OnboardingStep.summary)
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _note(t(OnboardingText.laterHint)),
      ),
    _group([
      _status(
        OnboardingText.setup,
        [
              OnboardingStep.language,
              OnboardingStep.access,
              OnboardingStep.limits,
              OnboardingStep.privacy,
            ].every(c.progress.complete)
            ? t(OnboardingText.confirmed)
            : t(OnboardingText.notChecked),
        () => c.goTo(OnboardingStep.language),
      ),
      _status(
        OnboardingText.signals,
        t(
          c.evidence.criticalChannelVerified
              ? OnboardingText.confirmed
              : OnboardingText.notChecked,
        ),
        () => c.goTo(OnboardingStep.feedback),
      ),
      _status(
        OnboardingText.training,
        t(
          c.progress.complete(OnboardingStep.practice)
              ? OnboardingText.confirmed
              : OnboardingText.notChecked,
        ),
        () => c.goTo(OnboardingStep.practice),
      ),
      _probe(
        OnboardingText.cameraFrames,
        c.evidence.camera,
        onTap: () => c.goTo(OnboardingStep.camera),
      ),
      _probe(
        OnboardingText.alignment,
        c.evidence.alignment,
        onTap: () => c.goTo(OnboardingStep.alignment),
        confirmationRequired: !c.evidence.alignmentConfirmed,
      ),
      _probe(
        OnboardingText.temperature,
        c.evidence.thermal,
        onTap: () => c.goTo(OnboardingStep.device),
      ),
    ]),
    const SizedBox(height: 24),
    Text(
      t(OnboardingText.genericLimited),
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 8),
    Text(t(OnboardingText.genericLimitedBody)),
    const SizedBox(height: 20),
    _note(
      t(switch (c.admission) {
        Admission.trainingRequired => OnboardingText.trainingRequired,
        Admission.recheckRequired => OnboardingText.recheckRequired,
        Admission.inspectionOnly => OnboardingText.inspectionBody,
      }),
    ),
    if (c.requiredStep != null) ...[
      const SizedBox(height: 12),
      Semantics(
        liveRegion: _live,
        child: _note(copy.nextRequiredStep(c.requiredStep!)),
      ),
    ],
  ];

  List<Widget> _summaryActions(BuildContext context) => [
    if (c.admission == Admission.inspectionOnly && widget.onInspect != null)
      FilledButton(
        key: const Key('onboarding-primary'),
        onPressed: c.busy
            ? null
            : () async {
                // Re-evaluate at the moment of explicit admission, not build time.
                if (c.admission != Admission.inspectionOnly) {
                  setState(() {});
                  return;
                }
                await _voice.openInspection();
              },
        child: Text(t(OnboardingText.inspection)),
      )
    else
      FilledButton(
        key: const Key('onboarding-primary'),
        onPressed: c.busy ? null : c.continueSetup,
        child: Text(t(OnboardingText.continueSetup)),
      ),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: c.busy ? null : () => c.restartPractice(vocabulary: true),
      child: Text(t(OnboardingText.trainingAgain)),
    ),
  ];

  Widget _helperHandoff() => _group([
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            liveRegion: _live,
            child: Text(
              t(
                c.userHasControl
                    ? OnboardingText.userControl
                    : OnboardingText.helperControl,
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          if (!c.userHasControl) ...[
            const SizedBox(height: 12),
            _note(t(OnboardingText.helperHandoffBody)),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('onboarding-handoff'),
            onPressed: c.busy
                ? null
                : () => c.transferControl(toUser: !c.userHasControl),
            child: Text(
              t(
                c.userHasControl
                    ? OnboardingText.handToHelper
                    : OnboardingText.handToUser,
              ),
            ),
          ),
        ],
      ),
    ),
  ]);

  List<Widget> _positionGuidance() => [
    if (c.step == OnboardingStep.alignment && !c.isQuickCheck)
      _check(
        OnboardingText.stationaryConfirm,
        c.stationaryAccepted,
        c.confirmStationary,
      ),
    _note(t(OnboardingText.coachBody)),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      key: const Key('onboarding-position-guide'),
      onPressed: c.canGuideAlignment ? c.guideAlignment : null,
      icon: const Icon(Icons.volume_up_outlined),
      label: Text(t(OnboardingText.coachStart)),
    ),
  ];

  Widget _informationBlocks(OnboardingStep step) => _group([
    for (final block in copy.infoBlocks(step))
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                t(block.title),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(t(block.body)),
            const SizedBox(height: 8),
            TextButton.icon(
              key: ValueKey('read-${block.body.name}'),
              onPressed: c.busy
                  ? null
                  : () => c.listen(
                      copy.blockInstruction(
                        block,
                        details: _expandedBlocks.contains(block.body),
                      ),
                    ),
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(copy.blockLabel(OnboardingText.readBlock, block)),
            ),
            TextButton(
              key: ValueKey('details-${block.body.name}'),
              onPressed: c.busy
                  ? null
                  : () => setState(() {
                      if (!_expandedBlocks.add(block.body)) {
                        _expandedBlocks.remove(block.body);
                      }
                    }),
              child: Text(
                copy.blockLabel(
                  _expandedBlocks.contains(block.body)
                      ? OnboardingText.hideDetails
                      : OnboardingText.moreDetails,
                  block,
                ),
              ),
            ),
            if (_expandedBlocks.contains(block.body)) ...[
              const SizedBox(height: 8),
              _note(t(block.details)),
            ],
          ],
        ),
      ),
  ]);

  Widget _group(List<Widget> rows) => BagdarCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          rows[i],
        ],
      ],
    ),
  );

  Widget _choices<T>({
    required T value,
    required Future<void> Function(T) onChanged,
    required List<(T, String, String?)> options,
    bool large = false,
  }) => RadioGroup<T>(
    groupValue: value,
    onChanged: (next) {
      if (next != null && !c.busy) unawaited(onChanged(next));
    },
    child: _group([
      for (final option in options)
        Semantics(
          localeForSubtree: option.$1 is AppLanguage
              ? _locale(option.$1 as AppLanguage)
              : null,
          child: MergeSemantics(
            child: Semantics(
              label: [option.$2, if (option.$3 != null) option.$3!].join('. '),
              checked: value == option.$1,
              inMutuallyExclusiveGroup: true,
              enabled: !c.busy,
              onTap: c.busy ? null : () => onChanged(option.$1),
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: c.busy ? null : () => onChanged(option.$1),
                  child: Container(
                    color: value == option.$1
                        ? colors.surfaceSelected
                        : colors.surfaceElevated,
                    constraints: BoxConstraints(minHeight: large ? 74 : 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.$2,
                                style: TextStyle(
                                  fontSize: large ? 22 : 18,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (option.$3 != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  option.$3!,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: colors.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ExcludeFocus(
                          child: IgnorePointer(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Transform.scale(
                                scale: large ? 1.6 : 1.1,
                                child: Radio<T>(
                                  value: option.$1,
                                  fillColor: WidgetStatePropertyAll(
                                    colors.accentOnPrimary,
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith(
                                        (states) =>
                                            states.contains(
                                              WidgetState.selected,
                                            )
                                            ? colors.accentPrimary
                                            : Colors.transparent,
                                      ),
                                  side: WidgetStateBorderSide.resolveWith(
                                    (states) => BorderSide(
                                      color:
                                          states.contains(WidgetState.selected)
                                          ? colors.accentPrimary
                                          : colors.controlBorder,
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]),
  );

  Widget _check(
    OnboardingText label,
    bool value,
    void Function(bool)? onChanged,
  ) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: value,
    onChanged: c.busy || !c.userHasControl || onChanged == null
        ? null
        : (next) => onChanged(next ?? false),
    title: Text(t(label), style: const TextStyle(fontSize: 17, height: 1.4)),
    activeColor: colors.accentPrimary,
  );

  Widget _action(
    OnboardingText label,
    IconData icon,
    Future<void> Function() action,
  ) => Semantics(
    button: true,
    enabled: !c.busy,
    label: t(label),
    excludeSemantics: true,
    onTap: c.busy ? null : () => unawaited(action()),
    child: InkWell(
      onTap: c.busy ? null : action,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colors.accentPrimary),
            const SizedBox(width: 16),
            Expanded(child: Text(t(label))),
            Icon(Icons.play_arrow_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    ),
  );

  Widget _vocabulary(
    String cue,
    OnboardingText meaning, {
    bool critical = false,
  }) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          cue,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(t(meaning)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: c.busy ? null : () => c.listen(cue, critical: critical),
            icon: const Icon(Icons.volume_up_outlined),
            label: Text(t(OnboardingText.listen)),
          ),
        ),
      ],
    ),
  );

  Widget _probe(
    OnboardingText label,
    ProbeResult result, {
    VoidCallback? onTap,
    bool confirmationRequired = false,
  }) {
    final text = confirmationRequired && result.freshAt(c.now())
        ? t(OnboardingText.confirmationRequired)
        : copy.probeDescription(result, c.now());
    return _status(label, text, onTap);
  }

  Widget _status(OnboardingText label, String value, VoidCallback? onTap) =>
      Semantics(
        button: onTap != null,
        liveRegion: onTap == null && _live,
        enabled: onTap == null ? null : !c.busy,
        label: '${t(label)}. $value',
        excludeSemantics: true,
        onTap: c.busy ? null : onTap,
        child: InkWell(
          onTap: c.busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(label),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _instructionControl() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: const Key('onboarding-instruction'),
      onPressed: c.speaking
          ? () => unawaited(c.stopSpeech())
          : c.busy
          ? null
          : (c.step == OnboardingStep.feedback ||
                (c.isQuickCheck && c.sessionStage == 1))
          ? () => c.listen(
              [
                c.isQuickCheck
                    ? copy.sessionProgress(c.sessionStage)
                    : copy.stepProgress(c.step),
                c.isQuickCheck
                    ? t(OnboardingText.sessionTitle)
                    : copy.title(c.step),
                if (c.progress.accessMode == AccessMode.helper)
                  t(
                    c.userHasControl
                        ? OnboardingText.userControl
                        : OnboardingText.helperControl,
                  ),
                t(
                  _checkingHaptic
                      ? OnboardingText.hapticTask
                      : c.evidence.ordinaryVoiceConfirmed
                      ? OnboardingText.stopTask
                      : OnboardingText.ordinaryTask,
                ),
                t(
                  _checkingHaptic
                      ? OnboardingText.hapticRecovery
                      : OnboardingText.checkSound,
                ),
                if (c.message != null) t(c.message!),
              ].join('\n'),
            )
          : c.repeatInstruction,
      icon: Icon(
        c.speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
        size: 27,
      ),
      label: Text(
        t(
          c.coaching
              ? OnboardingText.coachStop
              : c.speaking
              ? OnboardingText.stopSpeech
              : c.stoppingSpeech
              ? OnboardingText.stoppingSpeech
              : OnboardingText.repeatInstruction,
        ),
      ),
    ),
  );

  Widget _note(String text) => Text(
    text,
    style: TextStyle(fontSize: 16, height: 1.5, color: colors.textSecondary),
  );
}
