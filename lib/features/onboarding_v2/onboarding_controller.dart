import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/strings.dart';
import 'onboarding_copy.dart';
import 'onboarding_gateway.dart';
import 'onboarding_state.dart';
import 'onboarding_store.dart';

enum PracticeAction { stop, move, check, pause, resume }

class OnboardingController extends ChangeNotifier {
  final OnboardingStore store;
  final OnboardingGateway gateway;
  final DateTime Function() now;
  final OnboardingSessionGate gate = OnboardingSessionGate();
  final OnboardingEvidence evidence = OnboardingEvidence();
  OnboardingProgress progress;
  OnboardingStep step = OnboardingStep.language;
  ProgressLoadStatus loadStatus = ProgressLoadStatus.empty;
  bool loading = true;
  bool busy = false;
  bool speaking = false;
  bool stoppingSpeech = false;
  bool coaching = false;
  bool limitsAccepted = false;
  bool alignmentAccepted = false;
  bool stationaryAccepted = false;
  bool sessionOnly;
  bool quickCheck = false;
  double rate = 1;
  OnboardingText? message;
  int practiceIndex = 0;
  bool practiceAnswered = false;
  bool practicePaused = false;
  bool _disposed = false;
  int _generation = 0;
  int _permissionRevision = 0;
  bool _foreground = true;
  Timer? _freshnessTimer;
  String? _lastSpeechText;
  bool _lastSpeechCritical = false;
  bool? _lastSpeechSampleStop;
  bool _lastSpeechGuidance = false;

  OnboardingController({
    required this.store,
    required this.gateway,
    AppLanguage initialLanguage = AppLanguage.ru,
    this.sessionOnly = false,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       progress = OnboardingProgress(language: initialLanguage);

  OnboardingCopy get copy => OnboardingCopy(progress.language);
  Admission get admission => sessionOnly
      ? Admission.trainingRequired
      : gate.evaluate(progress, evidence, now());
  OnboardingStep? get requiredStep =>
      gate.nextRequiredStep(progress, evidence, now());
  bool get practiceFinished => practiceIndex >= 4;
  bool get trainingComplete => !sessionOnly && gate.trainingComplete(progress);
  bool get userHasControl => evidence.userHasControl;
  bool get isForeground => _foreground && !_disposed;
  int get interactionGeneration => _generation;
  bool get canGuideAlignment =>
      !busy && !loading && userHasControl && stationaryAccepted && !sessionOnly;
  bool get isQuickCheck =>
      quickCheck && step == OnboardingStep.summary && trainingComplete;
  int get sessionStage => !evidence.criticalChannelVerified
      ? 1
      : evidence.cameraAccess != CameraAccess.granted
      ? 2
      : 3;
  bool get canCheckSession =>
      isQuickCheck &&
      userHasControl &&
      !busy &&
      stationaryAccepted &&
      evidence.criticalChannelVerified &&
      evidence.cameraAccess == CameraAccess.granted;
  bool get hasSpeechProblem => const {
    OnboardingText.voiceMissing,
    OnboardingText.speechEngineUnavailable,
    OnboardingText.speechInterrupted,
    OnboardingText.speechTimedOut,
    OnboardingText.speechFailed,
    OnboardingText.speechSettingsUnavailable,
  }.contains(message);
  bool get canContinue =>
      !busy &&
      !loading &&
      switch (step) {
        OnboardingStep.limits => userHasControl && limitsAccepted,
        OnboardingStep.practice => userHasControl && practiceFinished,
        OnboardingStep.summary => admission == Admission.inspectionOnly,
        _ => true,
      };

  String get practiceCue => practiceIndex >= 4
      ? copy.t(OnboardingText.practiceFinished)
      : switch (practiceIndex) {
          0 => _runtimeString('generic_obstacle_stop'),
          1 => _runtimeString('generic_obstacle_left'),
          2 => _runtimeString('spatial_stop_sensing_unavailable'),
          _ => copy.t(OnboardingText.pauseCue),
        };

  String _runtimeString(String key) {
    // Existing runtime vocabulary, in the currently chosen onboarding language.
    final previous = AppStrings.current;
    AppStrings.setLanguage(progress.language);
    final value = AppStrings.get(key);
    AppStrings.setLanguage(previous);
    return value;
  }

  String get stopCue => _runtimeString(trainingStopCommand(now()).speechKey);
  String get sideCue => _runtimeString('generic_obstacle_left');
  String get lostCue => _runtimeString('spatial_stop_sensing_unavailable');

  String get stepInstruction {
    final ownership = progress.accessMode == AccessMode.helper
        ? '${copy.t(userHasControl ? OnboardingText.userControl : OnboardingText.helperControl)}. ${copy.t(OnboardingText.helperHandoffBody)}\n'
        : '';
    if (isQuickCheck) {
      return ownership +
          [
            copy.sessionProgress(sessionStage),
            copy.t(OnboardingText.sessionTitle),
            copy.t(OnboardingText.sessionBody),
            copy.t(OnboardingText.checkSound),
            copy.cameraAccessDescription(evidence.cameraAccess),
            copy.t(OnboardingText.stationaryConfirm),
            copy.t(OnboardingText.alignmentHold),
            copy.probeDescription(evidence.camera, now()),
            copy.probeDescription(evidence.thermal, now()),
            copy.probeDescription(evidence.alignment, now()),
            copy.t(OnboardingText.alignmentConfirm),
            copy.t(
              admission == Admission.inspectionOnly
                  ? OnboardingText.sessionReady
                  : OnboardingText.sessionNotReady,
            ),
            if (message != null) copy.t(message!),
          ].join('\n');
    }
    final details = switch (step) {
      OnboardingStep.access => [
        copy.t(OnboardingText.voice),
        copy.t(OnboardingText.voiceBody),
        copy.t(OnboardingText.largeText),
        copy.t(OnboardingText.largeTextBody),
        copy.t(OnboardingText.helper),
        copy.t(OnboardingText.helperBody),
      ],
      OnboardingStep.feedback => [
        copy.t(OnboardingText.ordinaryVoice),
        copy.t(OnboardingText.stopVoice),
        copy.t(OnboardingText.stopHaptic),
        copy.t(OnboardingText.heard),
        copy.t(OnboardingText.felt),
        copy.t(
          evidence.criticalChannelVerified
              ? OnboardingText.feedbackFooter
              : OnboardingText.feedbackMissing,
        ),
      ],
      OnboardingStep.camera => [
        copy.cameraAccessDescription(evidence.cameraAccess),
      ],
      OnboardingStep.device => [
        copy.t(OnboardingText.cameraFrames),
        copy.probeDescription(evidence.camera, now()),
        copy.t(OnboardingText.temperature),
        copy.probeDescription(evidence.thermal, now()),
      ],
      OnboardingStep.stationary => [
        copy.t(OnboardingText.stationaryConfirm),
        copy.probeDescription(evidence.camera, now()),
      ],
      OnboardingStep.limits => [
        for (final block in copy.infoBlocks(step)) copy.blockInstruction(block),
        copy.t(OnboardingText.understand),
      ],
      OnboardingStep.privacy => [
        for (final block in copy.infoBlocks(step)) copy.blockInstruction(block),
      ],
      OnboardingStep.vocabulary => [
        stopCue,
        copy.t(OnboardingText.stopMeaning),
        sideCue,
        copy.t(OnboardingText.sideMeaning),
        lostCue,
        copy.t(OnboardingText.lostMeaning),
        copy.t(OnboardingText.pauseMeaning),
      ],
      OnboardingStep.practice => [
        if (practiceFinished)
          copy.t(OnboardingText.practiceFinished)
        else ...[
          copy.sceneProgress(practiceIndex),
          practicePaused ? copy.t(OnboardingText.practicePaused) : practiceCue,
        ],
      ],
      OnboardingStep.alignment => [
        copy.t(OnboardingText.alignmentHold),
        copy.t(OnboardingText.coachBody),
        if (evidence.alignment.status != ProbeStatus.notChecked)
          copy.probeDescription(evidence.alignment, now()),
        copy.t(OnboardingText.alignmentConfirm),
      ],
      OnboardingStep.summary => [
        copy.t(OnboardingText.genericLimitedBody),
        copy.t(switch (admission) {
          Admission.trainingRequired => OnboardingText.trainingRequired,
          Admission.recheckRequired => OnboardingText.recheckRequired,
          Admission.inspectionOnly => OnboardingText.inspectionBody,
        }),
        if (requiredStep != null) copy.nextRequiredStep(requiredStep!),
      ],
      _ => <String>[],
    };
    return ownership +
        [
          copy.stepProgress(step),
          copy.title(step).replaceAll('\n', ' '),
          copy.body(step),
          if (loadStatus == ProgressLoadStatus.corrupt)
            copy.t(OnboardingText.restoreError),
          if (loadStatus == ProgressLoadStatus.unsupported)
            copy.t(OnboardingText.restoreFuture),
          ...details,
          if (message != null) copy.t(message!),
        ].join('\n');
  }

  Future<void> repeatInstruction() => listen(stepInstruction);

  Future<void> initialize() async {
    ProgressLoad loaded;
    try {
      loaded = await store.load().timeout(const Duration(seconds: 15));
    } catch (_) {
      loaded = const ProgressLoad(ProgressLoadStatus.corrupt);
    }
    if (_disposed) return;
    loadStatus = loaded.status;
    progress = loaded.progress ?? progress;
    evidence.userHasControl = progress.accessMode != AccessMode.helper;
    practiceIndex = progress.completedExercises;
    quickCheck = trainingComplete;
    step = quickCheck ? OnboardingStep.summary : progress.checkpoint;
    limitsAccepted = progress.complete(OnboardingStep.limits);
    loading = false;
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _notify(),
    );
    _notify();
    if (isQuickCheck) await refreshCameraPermission();
  }

  Future<void> retryLoad() async {
    if (_disposed || busy || loading) return;
    loading = true;
    message = null;
    _notify();
    await initialize();
  }

  Future<void> _run(
    Future<void> Function(int generation) action, {
    bool recovery = false,
    bool speech = false,
    OnboardingText failure = OnboardingText.saveError,
  }) async {
    if (_disposed || busy || loading || !_foreground) return;
    if (!recovery &&
        (loadStatus == ProgressLoadStatus.corrupt ||
            loadStatus == ProgressLoadStatus.unsupported)) {
      return;
    }
    final generation = _generation;
    busy = true;
    speaking = speech;
    message = null;
    _notify();
    try {
      await action(generation);
    } catch (_) {
      if (_active(generation)) message = failure;
    } finally {
      if (_active(generation)) {
        busy = false;
        speaking = false;
        _notify();
      }
    }
  }

  bool _active(int generation) => !_disposed && generation == _generation;

  Future<bool> _commit(OnboardingProgress value, int generation) async {
    if (!_active(generation)) return false;
    if (!sessionOnly) await store.save(value);
    if (!_active(generation)) return false;
    progress = value;
    loadStatus = ProgressLoadStatus.loaded;
    return true;
  }

  Future<void> selectLanguage(AppLanguage language) => _run((generation) async {
    await gateway.stop();
    if (await _commit(progress.selectLanguage(language), generation)) {
      evidence.invalidateFeedback();
      evidence.invalidateDevice();
      practiceIndex = 0;
      quickCheck = false;
      practiceAnswered = practicePaused = false;
    }
  });

  Future<void> selectMode(AccessMode mode) => _run((generation) async {
    if (mode == progress.accessMode) return;
    await gateway.stop();
    if (await _commit(progress.copyWith(accessMode: mode), generation)) {
      evidence.userHasControl = mode != AccessMode.helper;
      _clearPersonalConfirmations();
    }
  });

  Future<void> transferControl({bool toUser = true}) => _run((
    generation,
  ) async {
    if (progress.accessMode != AccessMode.helper || userHasControl == toUser) {
      return;
    }
    await gateway.stop();
    if (!_active(generation)) return;
    evidence.userHasControl = toUser;
    _clearPersonalConfirmations();
    message = toUser
        ? OnboardingText.userControl
        : OnboardingText.helperControl;
  });

  void _clearPersonalConfirmations() {
    evidence.invalidateFeedback();
    evidence.alignmentConfirmed = evidence.stationaryConfirmed = false;
    alignmentAccepted = stationaryAccepted = false;
    limitsAccepted = progress.complete(OnboardingStep.limits);
    practiceAnswered = practicePaused = false;
  }

  Future<void> goTo(OnboardingStep target, {bool saveCheckpoint = true}) =>
      _run((generation) async {
        await gateway.stop();
        final value = progress.copyWith(
          checkpoint: saveCheckpoint ? target : progress.checkpoint,
        );
        if (await _commit(value, generation)) {
          step = target;
          quickCheck = false;
          if (target == OnboardingStep.practice) {
            practiceIndex = progress.completedExercises;
            practiceAnswered = practicePaused = false;
          }
        }
      });

  Future<void> back() => goTo(
    isQuickCheck
        ? OnboardingStep.summary
        : step == OnboardingStep.summary
        ? progress.checkpoint == OnboardingStep.summary
              ? OnboardingStep.stationary
              : progress.checkpoint
        : OnboardingStep.values[(step.index - 1).clamp(0, 11)],
  );

  Future<void> later() => goTo(OnboardingStep.summary, saveCheckpoint: false);

  Future<void> next() => _run((generation) async {
    if (step == OnboardingStep.limits && (!userHasControl || !limitsAccepted) ||
        step == OnboardingStep.practice &&
            (!userHasControl || !practiceFinished)) {
      return;
    }
    if (step == OnboardingStep.summary) return;
    await gateway.stop();
    final completed = switch (step) {
      OnboardingStep.feedback => evidence.criticalChannelVerified,
      OnboardingStep.camera => evidence.cameraAccess == CameraAccess.granted,
      OnboardingStep.device =>
        evidence.camera.freshAt(now()) && evidence.thermal.freshAt(now()),
      OnboardingStep.alignment =>
        evidence.alignment.freshAt(now()) && alignmentAccepted,
      OnboardingStep.stationary =>
        evidence.camera.freshAt(now()) && stationaryAccepted,
      _ => true,
    };
    final modules = Map<OnboardingStep, ModuleStatus>.of(progress.modules)
      ..[step] = completed ? ModuleStatus.completed : ModuleStatus.blocked;
    final target = OnboardingStep.values[step.index + 1];
    if (await _commit(
      progress.copyWith(modules: modules, checkpoint: target),
      generation,
    )) {
      step = target;
    }
  });

  void acceptLimits(bool value) {
    if (!_canConfirm) return;
    limitsAccepted = value;
    _notify();
  }

  void confirmVoice(bool value) {
    if (!_canConfirm) return;
    evidence.voiceConfirmed =
        value && evidence.voiceSamplePlayed && evidence.stopVoicePlayed;
    _notify();
  }

  /// An intermediate human response; never grants admission on its own.
  void confirmOrdinaryVoice(bool value) {
    if (!_canConfirm) return;
    evidence.ordinaryVoiceConfirmed = value && evidence.voiceSamplePlayed;
    _notify();
  }

  void confirmHaptic(bool value) {
    if (!_canConfirm) return;
    evidence.hapticConfirmed = value && evidence.hapticPlayed;
    _notify();
  }

  void confirmAlignment(bool value) {
    if (!_canConfirm) return;
    alignmentAccepted = value && evidence.alignment.freshAt(now());
    evidence.alignmentConfirmed = alignmentAccepted;
    _notify();
  }

  void confirmStationary(bool value) {
    if (!_canConfirm) return;
    stationaryAccepted = value;
    if (!value) evidence.stationaryConfirmed = false;
    _notify();
  }

  bool get _canConfirm =>
      !_disposed && !loading && !busy && _foreground && userHasControl;

  Future<void> playVoice({bool stop = false}) => _run(
    (generation) async {
      _lastSpeechSampleStop = stop;
      _lastSpeechGuidance = false;
      _lastSpeechText = stop ? stopCue : copy.t(OnboardingText.example);
      _lastSpeechCritical = stop;
      final result = await gateway.speak(
        _lastSpeechText!,
        progress.language,
        critical: stop,
      );
      if (!_active(generation)) return;
      final played = result == OnboardingSpeechResult.played;
      if (stop) {
        evidence.stopVoicePlayed = played;
      } else {
        evidence.voiceSamplePlayed = played;
        evidence.ordinaryVoiceConfirmed = false;
      }
      evidence.voiceConfirmed = false;
      message = played ? OnboardingText.signalPlayed : _speechMessage(result);
    },
    speech: true,
    failure: OnboardingText.speechFailed,
  );

  Future<void> playHaptic() => _run((generation) async {
    final played = await gateway.stopHaptic();
    if (!_active(generation)) return;
    evidence.hapticPlayed = played;
    evidence.hapticConfirmed = false;
    message = played ? OnboardingText.signalPlayed : OnboardingText.unavailable;
  });

  Future<void> changeRate(double value) => _run((generation) async {
    await gateway.stop();
    await gateway.speechRate(value);
    if (!_active(generation)) return;
    rate = value;
    evidence.invalidateFeedback();
  });

  Future<void> listen(String text, {bool critical = false}) => _run(
    (generation) async {
      _lastSpeechSampleStop = null;
      _lastSpeechGuidance = false;
      _lastSpeechText = text;
      _lastSpeechCritical = critical;
      final result = await gateway.speak(
        text,
        progress.language,
        critical: critical,
      );
      if (_active(generation) && result != OnboardingSpeechResult.played) {
        message = _speechMessage(result);
      }
    },
    speech: true,
    recovery: true,
    failure: OnboardingText.speechFailed,
  );

  OnboardingText _speechMessage(OnboardingSpeechResult result) =>
      switch (result) {
        OnboardingSpeechResult.played => OnboardingText.signalPlayed,
        OnboardingSpeechResult.voiceUnavailable => OnboardingText.voiceMissing,
        OnboardingSpeechResult.engineUnavailable =>
          OnboardingText.speechEngineUnavailable,
        OnboardingSpeechResult.interrupted => OnboardingText.speechInterrupted,
        OnboardingSpeechResult.timedOut => OnboardingText.speechTimedOut,
        OnboardingSpeechResult.failed => OnboardingText.speechFailed,
      };

  Future<void> retrySpeech() => _lastSpeechGuidance
      ? guideAlignment()
      : _lastSpeechSampleStop != null
      ? playVoice(stop: _lastSpeechSampleStop!)
      : listen(
          _lastSpeechText ?? stepInstruction,
          critical: _lastSpeechCritical,
        );

  Future<void> openSpeechSettings() => _run(
    (generation) async {
      await gateway.stop();
      final opened = await gateway.openSpeechSettings();
      if (_active(generation) && !opened) {
        message = OnboardingText.speechSettingsUnavailable;
      }
    },
    recovery: true,
    failure: OnboardingText.speechSettingsUnavailable,
  );

  Future<void> stopSpeech() async {
    if (_disposed || !speaking || stoppingSpeech) return;
    final generation = ++_generation;
    final wasCoaching = coaching;
    coaching = false;
    if (wasCoaching) {
      evidence.alignment = const ProbeResult.unchecked();
      alignmentAccepted = evidence.alignmentConfirmed = false;
    }
    speaking = false;
    stoppingSpeech = true;
    message = null;
    _notify();
    try {
      await gateway.stop();
      if (_active(generation)) {
        message = wasCoaching
            ? OnboardingText.coachStopped
            : OnboardingText.speechStopped;
      }
    } catch (_) {
      if (_active(generation)) message = OnboardingText.speechFailed;
    } finally {
      if (_active(generation)) {
        busy = stoppingSpeech = false;
        _notify();
      }
    }
  }

  Future<void> requestCamera() => _run((generation) async {
    final revision = ++_permissionRevision;
    final status = sessionOnly
        ? CameraAccess.restricted
        : await gateway.cameraPermission(request: true);
    if (_active(generation) && revision == _permissionRevision) {
      evidence.invalidateDevice();
      evidence.cameraAccess = status;
    } else if (!_disposed && _foreground) {
      // A system dialog may resume the app before its request future completes.
      // Re-read the OS state instead of applying a result from an old session.
      await refreshCameraPermission();
    }
  }, failure: OnboardingText.cameraUnavailable);

  Future<void> openCameraSettings() => _run((generation) async {
    final opened = await gateway.openSettings().timeout(
      const Duration(seconds: 5),
    );
    if (!_active(generation)) return;
    if (!opened) {
      message = OnboardingText.cameraSettingsUnavailable;
      return;
    }
    await refreshCameraPermission();
  }, failure: OnboardingText.cameraSettingsUnavailable);

  Future<void> resume() async {
    if (_disposed) return;
    _foreground = true;
    await refreshCameraPermission();
  }

  Future<void> refreshCameraPermission() async {
    if (_disposed || loading || !_foreground) return;
    final generation = _generation;
    final revision = ++_permissionRevision;
    CameraAccess status;
    try {
      status = sessionOnly
          ? CameraAccess.restricted
          : await gateway.cameraPermission().timeout(
              const Duration(seconds: 5),
            );
    } catch (_) {
      status = CameraAccess.restricted;
    }
    if (!_active(generation) ||
        revision != _permissionRevision ||
        !_foreground) {
      return;
    }
    if (status != evidence.cameraAccess) evidence.invalidateDevice();
    evidence.cameraAccess = status;
    _notify();
  }

  Future<void> deviceCheck({bool stationary = false}) =>
      _run((generation) async {
        final revision = ++_permissionRevision;
        evidence.camera = const ProbeResult.unchecked();
        evidence.thermal = const ProbeResult.unchecked();
        evidence.stationaryConfirmed = false;
        final access = sessionOnly
            ? CameraAccess.restricted
            : await gateway.cameraPermission();
        if (!_active(generation) || revision != _permissionRevision) return;
        evidence.cameraAccess = access;
        if (access != CameraAccess.granted) {
          message = OnboardingText.cameraUnavailable;
          return;
        }
        final result = await gateway.checkCamera();
        if (!_active(generation) || revision != _permissionRevision) return;
        evidence.camera = result.camera;
        evidence.thermal = result.thermal;
        evidence.stationaryConfirmed =
            stationary && stationaryAccepted && result.camera.freshAt(now());
      });

  Future<void> alignmentCheck() => _run((generation) async {
    alignmentAccepted = false;
    evidence.alignmentConfirmed = false;
    evidence.alignment = const ProbeResult.unchecked();
    final result = sessionOnly
        ? ProbeResult(ProbeStatus.unavailable, 'alignmentUnavailable', now())
        : await gateway.checkAlignment();
    if (_active(generation)) evidence.alignment = result;
  });

  /// Explicit, bounded coaching: measure, say one hint, then measure again.
  /// Uses the same TTS queue as instruction playback; it never opens a camera.
  Future<void> guideAlignment() {
    if (!canGuideAlignment ||
        (step != OnboardingStep.alignment && !isQuickCheck)) {
      return Future<void>.value();
    }
    return _run(
      (generation) async {
        coaching = true;
        alignmentAccepted = evidence.alignmentConfirmed = false;
        evidence.alignment = const ProbeResult.unchecked();
        _notify();
        try {
          for (var attempt = 0; attempt < 4; attempt++) {
            final result = await gateway.checkAlignment().timeout(
              const Duration(seconds: 6),
            );
            if (!_active(generation)) return;
            final checkedAt = result.checkedAt;
            final recent =
                checkedAt != null &&
                !now().isBefore(checkedAt) &&
                now().difference(checkedAt) < const Duration(seconds: 6);
            final stable = recent && result.freshAt(now());
            // Reject malformed, stale and unknown results rather than turning
            // them into a successful coaching session.
            final hint = stable
                ? OnboardingText.coachReady
                : !recent || result.status != ProbeStatus.unavailable
                ? OnboardingText.alignmentUnavailable
                : switch (result.reason) {
                    'alignmentMoreUpright' => OnboardingText.coachUpright,
                    'alignmentMoreFlat' => OnboardingText.coachFlat,
                    'alignmentLevel' => OnboardingText.coachLevel,
                    'alignmentHoldStill' => OnboardingText.coachHold,
                    _ => OnboardingText.alignmentUnavailable,
                  };
            evidence.alignment =
                recent && (stable || result.status == ProbeStatus.unavailable)
                ? result
                : ProbeResult(
                    ProbeStatus.unavailable,
                    'alignmentUnavailable',
                    now(),
                  );
            message = hint;
            final lastAttempt = !stable && attempt == 3;
            _lastSpeechText = [
              copy.t(hint),
              if (lastAttempt) copy.t(OnboardingText.coachRetry),
            ].join('\n');
            _lastSpeechSampleStop = null;
            _lastSpeechCritical = false;
            _lastSpeechGuidance = true;
            _notify();
            final speech = await gateway
                .speak(_lastSpeechText!, progress.language)
                .timeout(const Duration(seconds: 20));
            if (!_active(generation)) return;
            if (speech != OnboardingSpeechResult.played) {
              evidence.alignment = const ProbeResult.unchecked();
              message = _speechMessage(speech);
              return;
            }
            if (stable || hint == OnboardingText.alignmentUnavailable) return;
            if (lastAttempt) {
              message = OnboardingText.coachRetry;
              return;
            }
          }
          message = OnboardingText.coachRetry;
        } on TimeoutException {
          if (!_active(generation)) return;
          await gateway.stop();
          if (!_active(generation)) return;
          evidence.alignment = const ProbeResult.unchecked();
          message = OnboardingText.coachRetry;
        } catch (_) {
          if (_active(generation)) {
            evidence.alignment = const ProbeResult.unchecked();
          }
          rethrow;
        } finally {
          if (_active(generation)) coaching = false;
        }
      },
      speech: true,
      failure: OnboardingText.alignmentUnavailable,
    );
  }

  Future<void> openSessionCheck() => _run((generation) async {
    if (!trainingComplete) return;
    await gateway.stop();
    if (await _commit(
      progress.copyWith(checkpoint: OnboardingStep.summary),
      generation,
    )) {
      step = OnboardingStep.summary;
      quickCheck = true;
    }
  });

  Future<void> checkSession() => _run((generation) async {
    if (!isQuickCheck ||
        !userHasControl ||
        !stationaryAccepted ||
        !evidence.criticalChannelVerified) {
      return;
    }
    final revision = ++_permissionRevision;
    evidence.invalidateDevice();
    alignmentAccepted = false;
    final access = await gateway.cameraPermission();
    if (!_active(generation) || revision != _permissionRevision) return;
    evidence.cameraAccess = access;
    if (access != CameraAccess.granted) return;
    final device = await gateway.checkCamera();
    if (!_active(generation) || revision != _permissionRevision) return;
    evidence.camera = device.camera;
    evidence.thermal = device.thermal;
    if (!device.camera.freshAt(now()) || !device.thermal.freshAt(now())) return;
    final alignment = await gateway.checkAlignment();
    if (!_active(generation) || revision != _permissionRevision) return;
    evidence.alignment = alignment;
    evidence.stationaryConfirmed =
        stationaryAccepted && device.camera.freshAt(now());
  }, failure: OnboardingText.cameraUnavailable);

  Future<void> practiceAction(PracticeAction action) async {
    if (busy ||
        !userHasControl ||
        loading ||
        !_foreground ||
        step != OnboardingStep.practice ||
        practiceFinished) {
      return;
    }
    if (action == PracticeAction.pause) {
      practicePaused = true;
      message = OnboardingText.practicePaused;
      await gateway.stop();
      _notify();
      return;
    }
    if (action == PracticeAction.resume && practicePaused) {
      practicePaused = false;
      if (practiceIndex == 3) practiceAnswered = true;
      message = practiceAnswered ? OnboardingText.correctAction : null;
      _notify();
      return;
    }
    if (practicePaused) return;
    final expected = switch (practiceIndex) {
      0 || 2 => PracticeAction.stop,
      1 => PracticeAction.check,
      _ => PracticeAction.pause,
    };
    practiceAnswered = action == expected;
    message = practiceAnswered
        ? OnboardingText.correctAction
        : switch (practiceIndex) {
            0 => OnboardingText.wrongStop,
            1 => OnboardingText.wrongSide,
            2 => OnboardingText.wrongLost,
            _ => OnboardingText.wrongPause,
          };
    _notify();
  }

  Future<void> nextExercise() {
    if (busy ||
        !userHasControl ||
        step != OnboardingStep.practice ||
        !practiceAnswered ||
        practicePaused ||
        practiceFinished) {
      return Future<void>.value();
    }
    return _run((generation) async {
      await gateway.stop();
      if (!_active(generation) ||
          step != OnboardingStep.practice ||
          !practiceAnswered ||
          practicePaused) {
        return;
      }
      final nextIndex = practiceIndex + 1;
      if (await _commit(
        progress.copyWith(completedExercises: nextIndex),
        generation,
      )) {
        practiceIndex = nextIndex;
        practiceAnswered = false;
      }
    });
  }

  Future<void> continueSetup() => trainingComplete
      ? openSessionCheck()
      : goTo(requiredStep ?? OnboardingStep.stationary);

  Future<void> restartPractice({bool vocabulary = false}) =>
      _run((generation) async {
        await gateway.stop();
        final modules = Map<OnboardingStep, ModuleStatus>.of(progress.modules)
          ..remove(OnboardingStep.practice);
        final target = vocabulary
            ? OnboardingStep.vocabulary
            : OnboardingStep.practice;
        if (await _commit(
          progress.copyWith(
            modules: modules,
            completedExercises: 0,
            checkpoint: target,
          ),
          generation,
        )) {
          step = target;
          quickCheck = false;
          practiceIndex = 0;
          practiceAnswered = practicePaused = false;
        }
      });

  Future<void> inspect(Future<void> Function() open) =>
      _run((generation) async {
        if (admission != Admission.inspectionOnly) return;
        await open();
      }, failure: OnboardingText.cameraUnavailable);

  Future<void> recover({bool withoutSaving = false}) =>
      _run((generation) async {
        sessionOnly = withoutSaving;
        final value = OnboardingProgress(language: progress.language);
        if (await _commit(value, generation)) {
          step = withoutSaving
              ? OnboardingStep.vocabulary
              : OnboardingStep.language;
          evidence.invalidateFeedback();
          evidence.invalidateDevice();
          evidence.userHasControl = true;
          practiceIndex = 0;
          practiceAnswered = practicePaused = quickCheck = false;
        }
      }, recovery: true);

  void suspend({bool background = false}) {
    if (background) _foreground = false;
    _generation++;
    _permissionRevision++;
    busy = false;
    speaking = stoppingSpeech = false;
    coaching = false;
    evidence.invalidateDevice();
    evidence.invalidateFeedback();
    alignmentAccepted = stationaryAccepted = false;
    practicePaused = step == OnboardingStep.practice && !practiceFinished;
    unawaited(gateway.stop());
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _freshnessTimer?.cancel();
    unawaited(gateway.stop());
    super.dispose();
  }
}
