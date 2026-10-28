import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/strings.dart';
import '../onboarding_controller.dart';
import '../onboarding_copy.dart';
import '../onboarding_state.dart';
import '../onboarding_store.dart';
import 'onboarding_voice_copy.dart';
import 'onboarding_voice_input.dart';
import 'onboarding_voice_parser.dart';

enum OnboardingVoicePhase {
  off,
  preparing,
  speaking,
  arming,
  listening,
  handling,
  suspended,
  unavailable,
  complete,
  checking,
  systemPermission,
}

/// Opt-in voice onboarding. All domain mutations stay in the existing
/// controller; ASR never writes progress or live readiness itself.
class OnboardingVoiceCoordinator extends ChangeNotifier {
  final OnboardingController controller;
  final OnboardingVoiceInput input;
  final Future<void> Function()? onInspect;
  final int maxEmptyTurns;

  /// Provisional rejection filter for this one backend, not a calibrated
  /// probability of correctness. Missing/low scores cannot advance training.
  final double minimumCommandConfidence;
  OnboardingVoicePhase phase = OnboardingVoicePhase.off;
  OnboardingVoiceQuestion? question;
  String? message;
  bool enabled = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _activating = false;
  bool _openingInspection = false;
  bool _paused = false;
  bool _skipHaptic = false;
  bool _forceSessionCheck = false;
  bool _again = false;
  bool _restartAfterController = false;
  int _owned = 0;
  int _generation = 0;
  int _sessionId = 0;
  int _turnId = 0;
  int _emptyTurns = 0;
  int _informationIndex = 0;
  int _controllerGeneration = 0;
  String _observed = '';
  String _stepIdentity = '';
  String? _feedback;
  Future<void>? _cycle;

  OnboardingVoiceCoordinator({
    required this.controller,
    required this.input,
    this.onInspect,
    this.maxEmptyTurns = 3,
    this.minimumCommandConfidence = 0.75,
  }) {
    _observed = _context;
    _controllerGeneration = controller.interactionGeneration;
    controller.addListener(_controllerChanged);
  }

  OnboardingVoiceCopy get copy =>
      OnboardingVoiceCopy(controller.progress.language);
  bool get supported =>
      !controller.sessionOnly ||
      controller.step.index <= OnboardingStep.practice.index;
  bool get canEnable =>
      supported &&
      !controller.loading &&
      !controller.busy &&
      controller.isForeground &&
      controller.loadStatus != ProgressLoadStatus.corrupt &&
      controller.loadStatus != ProgressLoadStatus.unsupported;
  bool get hasActiveTurn =>
      phase == OnboardingVoicePhase.listening ||
      phase == OnboardingVoicePhase.arming;
  String get status =>
      message ??
      copy.t(switch (phase) {
        OnboardingVoicePhase.off => VoiceCopy.off,
        OnboardingVoicePhase.preparing ||
        OnboardingVoicePhase.arming => VoiceCopy.preparing,
        OnboardingVoicePhase.speaking => VoiceCopy.speaking,
        OnboardingVoicePhase.listening => VoiceCopy.listening,
        OnboardingVoicePhase.handling => VoiceCopy.processing,
        OnboardingVoicePhase.suspended => VoiceCopy.suspended,
        OnboardingVoicePhase.unavailable => VoiceCopy.unavailable,
        OnboardingVoicePhase.complete => VoiceCopy.boundary,
        OnboardingVoicePhase.checking => VoiceCopy.checking,
        OnboardingVoicePhase.systemPermission => VoiceCopy.systemPermission,
      });

  String get _context => [
    controller.step,
    controller.progress.language,
    controller.progress.accessMode,
    controller.userHasControl,
    controller.practiceIndex,
    controller.practiceAnswered,
    controller.practicePaused,
    controller.limitsAccepted,
    controller.rate,
    controller.evidence.voiceSamplePlayed,
    controller.evidence.stopVoicePlayed,
    controller.evidence.ordinaryVoiceConfirmed,
    controller.evidence.voiceConfirmed,
    controller.evidence.hapticPlayed,
    controller.evidence.hapticConfirmed,
    controller.loadStatus,
    controller.isQuickCheck,
    controller.evidence.cameraAccess,
    controller.evidence.camera.status,
    controller.evidence.camera.reason,
    controller.evidence.camera.checkedAt,
    controller.evidence.thermal.status,
    controller.evidence.thermal.reason,
    controller.evidence.thermal.checkedAt,
    controller.evidence.alignment.status,
    controller.evidence.alignment.reason,
    controller.evidence.alignment.checkedAt,
    controller.alignmentAccepted,
    controller.stationaryAccepted,
    controller.evidence.stationaryConfirmed,
    controller.evidence.alignmentConfirmed,
    controller.admission,
    controller.requiredStep,
    controller.evidence.camera.freshAt(controller.now()),
    controller.evidence.thermal.freshAt(controller.now()),
    controller.evidence.alignment.freshAt(controller.now()),
  ].join('|');

  bool _currentContext(int generation, String expected) {
    if (!_live(generation)) return false;
    if (expected != _context) {
      _generation++;
      _again = true;
      _setPhase(OnboardingVoicePhase.suspended);
      return false;
    }
    return !controller.busy && !controller.speaking;
  }

  bool _live(int generation) =>
      !_disposed &&
      enabled &&
      _foreground &&
      controller.isForeground &&
      generation == _generation;

  void _setPhase(OnboardingVoicePhase value, {String? text}) {
    if (_disposed) return;
    phase = value;
    message = text;
    notifyListeners();
  }

  void _controllerChanged() {
    if (_disposed) return;
    final current = _context;
    final generationChanged =
        _controllerGeneration != controller.interactionGeneration;
    _controllerGeneration = controller.interactionGeneration;
    final changed = _observed != current;
    _observed = current;
    if (!enabled) return;
    if (!_foreground || !controller.isForeground || generationChanged) {
      _generation++;
      _again = false;
      _restartAfterController = false;
      unawaited(_cancelPending());
      _setPhase(OnboardingVoicePhase.suspended);
      return;
    }
    if (_owned > 0) return;
    if (changed || controller.busy || controller.speaking) {
      _generation++;
      unawaited(_cancelPending());
      _setPhase(OnboardingVoicePhase.suspended);
      _restartAfterController = controller.busy || controller.speaking;
      if (!_restartAfterController && !_activating) _schedule();
    } else if (_restartAfterController && !controller.busy && !_activating) {
      _restartAfterController = false;
      _schedule();
    }
  }

  Future<T> _own<T>(Future<T> Function() action) async {
    _owned++;
    try {
      return await action();
    } finally {
      _owned--;
      _observed = _context;
    }
  }

  Future<void> enable() => _activate(requestPermission: true);

  Future<void> _activate({required bool requestPermission}) async {
    if (_disposed || _activating || !canEnable || !_foreground) return;
    enabled = true;
    _activating = true;
    _again = false;
    _emptyTurns = 0;
    _sessionId = nextVoiceSessionId();
    final generation = ++_generation;
    _setPhase(OnboardingVoicePhase.preparing);
    try {
      final availability = await input.prepare(
        requestPermission: requestPermission,
      );
      if (!_live(generation)) return;
      if (availability != VoiceInputAvailability.ready) {
        await _finish(
          OnboardingVoicePhase.unavailable,
          copy.availability(availability),
        );
        return;
      }
      _feedback = copy.t(VoiceCopy.ready);
      _schedule();
    } catch (_) {
      if (_live(generation)) {
        await _finish(
          OnboardingVoicePhase.unavailable,
          copy.t(VoiceCopy.unavailable),
        );
      }
    } finally {
      _activating = false;
      // A system permission dialog may suspend/resume before its Future returns.
      // Re-read permission without requesting it again; never trust the old turn.
      if (!_disposed &&
          enabled &&
          _foreground &&
          controller.isForeground &&
          phase == OnboardingVoicePhase.suspended) {
        unawaited(_activate(requestPermission: false));
      }
    }
  }

  void _schedule() {
    if (_disposed || !enabled || !_foreground || !controller.isForeground) {
      return;
    }
    if (_cycle != null) {
      _again = true;
      return;
    }
    _again = false;
    _cycle = _runCycle().whenComplete(() {
      _cycle = null;
      if (_again && !_disposed && enabled) _schedule();
    });
  }

  Future<bool> _speak(String text, int generation) async {
    if (!_live(generation)) return false;
    _setPhase(OnboardingVoicePhase.speaking);
    await _own(() => controller.listen(text));
    if (!_live(generation)) return false;
    if (controller.hasSpeechProblem) {
      await _finish(
        OnboardingVoicePhase.unavailable,
        copy.t(VoiceCopy.speechFailed),
        announce: false,
      );
      return false;
    }
    return true;
  }

  Future<void> _runCycle() async {
    final generation = _generation;
    try {
      await input.cancel();
      if (!_live(generation) || controller.busy || controller.loading) return;
      if (!supported) {
        await _finish(
          OnboardingVoicePhase.complete,
          copy.t(VoiceCopy.boundary),
        );
        return;
      }
      final identity = [
        controller.step,
        controller.progress.language,
        controller.progress.accessMode,
        controller.userHasControl,
        controller.interactionGeneration,
        controller.isQuickCheck,
      ].join('|');
      if (_stepIdentity != identity) {
        _stepIdentity = identity;
        _informationIndex = 0;
        _skipHaptic = false;
        _paused = false;
      }
      final prompt = await _prompt(generation);
      if (prompt == null || !_live(generation)) return;
      final feedback = _feedback;
      _feedback = null;
      final expectedContext = _context;
      if (!await _speak(
        [if (feedback != null) feedback, prompt].join('\n'),
        generation,
      )) {
        return;
      }
      if (!_currentContext(generation, expectedContext)) return;
      final turn = OnboardingVoiceTurn(
        sessionId: _sessionId,
        turnId: ++_turnId,
        language: controller.progress.language,
      );
      var ready = false;
      _setPhase(OnboardingVoicePhase.arming);
      final result = await input.listen(
        turn,
        onReady: () {
          if (_live(generation) &&
              expectedContext == _context &&
              phase == OnboardingVoicePhase.arming &&
              !controller.busy &&
              !controller.speaking) {
            ready = true;
            _setPhase(OnboardingVoicePhase.listening);
          }
        },
      );
      if (!_currentContext(generation, expectedContext)) return;
      await input.cancel();
      if (!_currentContext(generation, expectedContext)) return;
      _setPhase(OnboardingVoicePhase.handling);
      if (result.outcome == VoiceInputOutcome.interrupted ||
          result.outcome == VoiceInputOutcome.cancelled) {
        _setPhase(OnboardingVoicePhase.suspended);
        return;
      }
      if (result.outcome == VoiceInputOutcome.languageUnavailable) {
        await _finish(
          OnboardingVoicePhase.unavailable,
          copy.t(VoiceCopy.languageUnavailable),
        );
        return;
      }
      if (result.outcome == VoiceInputOutcome.unavailable ||
          result.outcome == VoiceInputOutcome.permissionDenied) {
        await _finish(
          OnboardingVoicePhase.unavailable,
          copy.t(
            result.outcome == VoiceInputOutcome.permissionDenied
                ? VoiceCopy.permissionDenied
                : VoiceCopy.unavailable,
          ),
        );
        return;
      }
      final valid =
          ready &&
          result.isFinal &&
          result.sessionId == turn.sessionId &&
          result.turnId == turn.turnId &&
          result.outcome == VoiceInputOutcome.recognized;
      var intent = valid
          ? OnboardingVoiceParser.parse(result.text, turn.language, question!)
          : OnboardingVoiceIntent.unknown;
      final confidence = result.confidence;
      if (intent != OnboardingVoiceIntent.disable &&
          (confidence == null ||
              !confidence.isFinite ||
              confidence > 1 ||
              confidence < minimumCommandConfidence)) {
        intent = OnboardingVoiceIntent.unknown;
      }
      if (intent == OnboardingVoiceIntent.unknown) {
        _emptyTurns++;
        if (_emptyTurns >= maxEmptyTurns) {
          await _finish(
            OnboardingVoicePhase.suspended,
            copy.t(VoiceCopy.timeout),
          );
          return;
        }
        _feedback = copy.t(VoiceCopy.unknown);
      } else {
        _emptyTurns = 0;
        await _dispatch(intent);
        if (controller.message == OnboardingText.saveError) {
          await _finish(
            OnboardingVoicePhase.suspended,
            controller.copy.t(OnboardingText.saveError),
          );
          return;
        }
      }
      if (_live(generation)) _again = true;
    } catch (_) {
      if (_live(generation)) {
        await _finish(
          OnboardingVoicePhase.unavailable,
          copy.t(VoiceCopy.unavailable),
        );
      }
    }
  }

  List<String> _information() {
    final c = controller.copy;
    final paragraphs = switch (controller.step) {
      OnboardingStep.limits => [
        c.t(OnboardingText.limit1),
        c.t(OnboardingText.limit2),
        c.t(OnboardingText.limit3),
        c.t(OnboardingText.limit4),
      ],
      OnboardingStep.privacy => [
        copy.t(VoiceCopy.privacy),
        c.t(OnboardingText.privacyLocal),
        c.t(OnboardingText.privacyRecord),
        c.t(OnboardingText.privacyOptional),
      ],
      OnboardingStep.vocabulary => [
        '${controller.stopCue} ${c.t(OnboardingText.stopMeaning)}',
        '${controller.sideCue} ${c.t(OnboardingText.sideMeaning)}',
        '${controller.lostCue} ${c.t(OnboardingText.lostMeaning)}',
        c.t(OnboardingText.pauseMeaning),
      ],
      _ => <String>[],
    };
    // One short piece per answer window. No paragraph is silently skipped.
    final parts = <String>[];
    for (final paragraph in paragraphs) {
      var part = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        if (part.isNotEmpty && part.length + word.length > 95) {
          parts.add(part);
          part = '';
        }
        part = part.isEmpty ? word : '$part $word';
      }
      if (part.isNotEmpty) parts.add(part);
    }
    return parts;
  }

  Future<String?> _prompt(int generation) async {
    final c = controller;
    if (_paused || c.practicePaused) {
      question = OnboardingVoiceQuestion.paused;
    } else if (!c.userHasControl && c.step != OnboardingStep.language) {
      question = OnboardingVoiceQuestion.handoff;
    } else if (c.isQuickCheck) {
      if (!c.evidence.criticalChannelVerified) {
        return _feedbackPrompt(generation);
      }
      return _checksPrompt();
    } else {
      switch (c.step) {
        case OnboardingStep.language:
          question = OnboardingVoiceQuestion.language;
        case OnboardingStep.access:
          question = OnboardingVoiceQuestion.access;
        case OnboardingStep.limits:
        case OnboardingStep.privacy:
        case OnboardingStep.vocabulary:
          final parts = _information();
          if (_informationIndex < parts.length) {
            question = OnboardingVoiceQuestion.information;
            return '${parts[_informationIndex]}\n${copy.question(question!)}';
          }
          if (c.step == OnboardingStep.limits) {
            question = OnboardingVoiceQuestion.limits;
          } else {
            question = OnboardingVoiceQuestion.information;
          }
        case OnboardingStep.feedback:
          return _feedbackPrompt(generation);
        case OnboardingStep.practice:
          if (c.practiceFinished) {
            question = OnboardingVoiceQuestion.practiceDone;
          } else {
            question = OnboardingVoiceQuestion.practice;
            if (c.practiceAnswered) return copy.t(VoiceCopy.correctHint);
            if (!await _speak(
              c.copy.t(OnboardingText.trainingLabel),
              generation,
            )) {
              return null;
            }
            await _own(
              () => c.listen(c.practiceCue, critical: c.practiceIndex == 0),
            );
            if (!_live(generation)) return null;
            if (c.hasSpeechProblem) {
              await _finish(
                OnboardingVoicePhase.unavailable,
                copy.t(VoiceCopy.speechFailed),
                announce: false,
              );
              return null;
            }
          }
        case OnboardingStep.camera:
        case OnboardingStep.device:
        case OnboardingStep.alignment:
        case OnboardingStep.stationary:
        case OnboardingStep.summary:
          return _checksPrompt();
      }
    }
    return copy.question(question!);
  }

  Future<String?> _feedbackPrompt(int generation) async {
    final c = controller;
    if (!c.evidence.ordinaryVoiceConfirmed) {
      _setPhase(OnboardingVoicePhase.speaking);
      await _own(() => c.playVoice());
      question = OnboardingVoiceQuestion.ordinaryVoice;
    } else if (!c.evidence.voiceConfirmed) {
      _setPhase(OnboardingVoicePhase.speaking);
      await _own(() => c.playVoice(stop: true));
      question = OnboardingVoiceQuestion.stopVoice;
    } else if (!c.evidence.hapticConfirmed && !_skipHaptic) {
      await _own(() => c.playHaptic());
      question = OnboardingVoiceQuestion.haptic;
    } else {
      question = OnboardingVoiceQuestion.feedbackDone;
    }
    if (!_live(generation)) return null;
    if (c.hasSpeechProblem) {
      await _finish(
        OnboardingVoicePhase.unavailable,
        copy.t(VoiceCopy.speechFailed),
        announce: false,
      );
      return null;
    }
    return copy.question(question!);
  }

  String _checksPrompt() {
    final c = controller;
    final evidence = c.evidence;
    final now = c.now();
    final cameraFresh = evidence.camera.freshAt(now);
    final thermalFresh = evidence.thermal.freshAt(now);
    final alignmentFresh = evidence.alignment.freshAt(now);
    final deviceReport = [
      c.copy.t(OnboardingText.cameraFrames),
      c.copy.probeDescription(evidence.camera, now),
      c.copy.t(OnboardingText.temperature),
      c.copy.probeDescription(evidence.thermal, now),
    ].join('. ');
    final alignmentReport = c.copy.probeDescription(evidence.alignment, now);
    String ask(OnboardingVoiceQuestion value, [String prefix = '']) {
      question = value;
      final instruction =
          value == OnboardingVoiceQuestion.summaryReady && onInspect == null
          ? copy.t(VoiceCopy.inspectionUnavailable)
          : copy.question(value);
      return [if (prefix.isNotEmpty) prefix, instruction].join('\n');
    }

    String cameraQuestion() => evidence.cameraAccess == CameraAccess.granted
        ? ask(OnboardingVoiceQuestion.cameraGranted)
        : ask(
            OnboardingVoiceQuestion.camera,
            c.copy.cameraAccessDescription(evidence.cameraAccess),
          );
    if (c.isQuickCheck) {
      if (evidence.cameraAccess != CameraAccess.granted) {
        return cameraQuestion();
      }
      if (!c.stationaryAccepted) return ask(OnboardingVoiceQuestion.standing);
      if (c.admission == Admission.inspectionOnly && !_forceSessionCheck) {
        return ask(OnboardingVoiceQuestion.summaryReady);
      }
      if (cameraFresh &&
          thermalFresh &&
          evidence.stationaryConfirmed &&
          alignmentFresh &&
          !evidence.alignmentConfirmed) {
        return ask(OnboardingVoiceQuestion.alignmentConfirm);
      }
      return ask(
        OnboardingVoiceQuestion.sessionCheck,
        '$deviceReport. $alignmentReport',
      );
    }
    switch (c.step) {
      case OnboardingStep.camera:
        return cameraQuestion();
      case OnboardingStep.device:
        if (evidence.cameraAccess != CameraAccess.granted) {
          return cameraQuestion();
        }
        if (!c.stationaryAccepted) return ask(OnboardingVoiceQuestion.standing);
        return ask(
          cameraFresh && thermalFresh
              ? OnboardingVoiceQuestion.deviceDone
              : OnboardingVoiceQuestion.device,
          deviceReport,
        );
      case OnboardingStep.alignment:
        if (!c.stationaryAccepted) return ask(OnboardingVoiceQuestion.standing);
        if (!alignmentFresh) {
          return ask(OnboardingVoiceQuestion.alignment, alignmentReport);
        }
        return ask(
          evidence.alignmentConfirmed
              ? OnboardingVoiceQuestion.alignmentDone
              : OnboardingVoiceQuestion.alignmentConfirm,
        );
      case OnboardingStep.stationary:
        if (evidence.cameraAccess != CameraAccess.granted) {
          return cameraQuestion();
        }
        if (!c.stationaryAccepted) return ask(OnboardingVoiceQuestion.standing);
        return ask(
          cameraFresh && thermalFresh && evidence.stationaryConfirmed
              ? OnboardingVoiceQuestion.stationaryDone
              : OnboardingVoiceQuestion.stationaryCheck,
          deviceReport,
        );
      case OnboardingStep.summary:
        return c.admission == Admission.inspectionOnly
            ? ask(OnboardingVoiceQuestion.summaryReady)
            : ask(
                OnboardingVoiceQuestion.summaryBlocked,
                c.requiredStep == null
                    ? ''
                    : c.copy.nextRequiredStep(c.requiredStep!),
              );
      default:
        throw StateError('Unexpected hardware prompt');
    }
  }

  Future<void> _dispatch(OnboardingVoiceIntent intent) => _own(() async {
    final c = controller;
    final generation = _generation;
    switch (intent) {
      case OnboardingVoiceIntent.requestCamera:
      case OnboardingVoiceIntent.cameraSettings:
        if (!await _speak(copy.t(VoiceCopy.permissionIntro), generation)) {
          return;
        }
        _setPhase(OnboardingVoicePhase.systemPermission);
        if (intent == OnboardingVoiceIntent.requestCamera) {
          await c.requestCamera();
        } else {
          await c.openCameraSettings();
          if (c.message == OnboardingText.cameraSettingsUnavailable) {
            _feedback = copy.t(VoiceCopy.settingsUnavailable);
          }
        }
      case OnboardingVoiceIntent.defer:
        await c.later();
      case OnboardingVoiceIntent.standing:
        c.confirmStationary(true);
      case OnboardingVoiceIntent.notStanding:
        c.confirmStationary(false);
        c.confirmAlignment(false);
        _feedback = copy.t(VoiceCopy.notStanding);
      case OnboardingVoiceIntent.runDevice:
      case OnboardingVoiceIntent.runStationary:
        if (c.userHasControl &&
            c.stationaryAccepted &&
            c.evidence.cameraAccess == CameraAccess.granted) {
          _setPhase(OnboardingVoicePhase.checking);
          await c.deviceCheck(
            stationary: intent == OnboardingVoiceIntent.runStationary,
          );
        }
      case OnboardingVoiceIntent.runAlignment:
        if (c.canGuideAlignment) {
          _setPhase(OnboardingVoicePhase.checking);
          await c.guideAlignment();
        }
      case OnboardingVoiceIntent.aligned:
        c.confirmAlignment(true);
      case OnboardingVoiceIntent.notAligned:
        c.confirmAlignment(false);
        _feedback = copy.t(VoiceCopy.alignmentRejected);
      case OnboardingVoiceIntent.runSession:
        if (c.canCheckSession) {
          _setPhase(OnboardingVoicePhase.checking);
          await c.checkSession();
          _forceSessionCheck = false;
        }
      case OnboardingVoiceIntent.continueSetup:
        await c.continueSetup();
        _forceSessionCheck = c.isQuickCheck;
      case OnboardingVoiceIntent.practiceAgain:
        await c.restartPractice();
      case OnboardingVoiceIntent.inspect:
        await openInspection();
      case OnboardingVoiceIntent.disable:
        await disable();
      case OnboardingVoiceIntent.repeat:
      case OnboardingVoiceIntent.help:
        break;
      case OnboardingVoiceIntent.back:
        if (_informationIndex > 0) {
          _informationIndex--;
        } else {
          await c.back();
        }
      case OnboardingVoiceIntent.slower:
      case OnboardingVoiceIntent.faster:
        await c.changeRate(
          (c.rate + (intent == OnboardingVoiceIntent.slower ? -0.25 : 0.25))
              .clamp(0.5, 2.0),
        );
        _skipHaptic = false;
      case OnboardingVoiceIntent.pause:
        if (c.step == OnboardingStep.practice && !c.practiceFinished) {
          await c.practiceAction(PracticeAction.pause);
        } else {
          _paused = true;
        }
      case OnboardingVoiceIntent.resume:
        _paused = false;
        if (c.practicePaused) await c.practiceAction(PracticeAction.resume);
      case OnboardingVoiceIntent.russian:
      case OnboardingVoiceIntent.kazakh:
      case OnboardingVoiceIntent.english:
        final language = switch (intent) {
          OnboardingVoiceIntent.russian => AppLanguage.ru,
          OnboardingVoiceIntent.kazakh => AppLanguage.kk,
          _ => AppLanguage.en,
        };
        if (language != c.progress.language) await c.selectLanguage(language);
        if (c.progress.language == language &&
            c.message != OnboardingText.saveError) {
          await c.next();
        }
      case OnboardingVoiceIntent.voice:
      case OnboardingVoiceIntent.largeText:
      case OnboardingVoiceIntent.helper:
        await c.selectMode(switch (intent) {
          OnboardingVoiceIntent.voice => AccessMode.voice,
          OnboardingVoiceIntent.largeText => AccessMode.largeText,
          _ => AccessMode.helper,
        });
        if (c.userHasControl && c.message != OnboardingText.saveError) {
          await c.next();
        }
      case OnboardingVoiceIntent.handoff:
        await c.transferControl();
        if (c.step == OnboardingStep.access && c.userHasControl) await c.next();
      case OnboardingVoiceIntent.acceptLimits:
        c.acceptLimits(true);
        if (c.canContinue) await c.next();
      case OnboardingVoiceIntent.declineLimits:
        c.acceptLimits(false);
        _informationIndex = 0;
        _feedback = copy.t(VoiceCopy.negative);
      case OnboardingVoiceIntent.heard:
      case OnboardingVoiceIntent.notHeard:
        final heard = intent == OnboardingVoiceIntent.heard;
        if (question == OnboardingVoiceQuestion.ordinaryVoice) {
          c.confirmOrdinaryVoice(heard);
        } else if (question == OnboardingVoiceQuestion.stopVoice) {
          c.confirmVoice(heard);
        }
        _feedback = copy.t(heard ? VoiceCopy.accepted : VoiceCopy.negative);
      case OnboardingVoiceIntent.felt:
      case OnboardingVoiceIntent.notFelt:
        c.confirmHaptic(intent == OnboardingVoiceIntent.felt);
        _feedback = copy.t(
          c.evidence.hapticConfirmed ? VoiceCopy.accepted : VoiceCopy.negative,
        );
      case OnboardingVoiceIntent.skipHaptic:
        if (c.evidence.criticalChannelVerified) _skipHaptic = true;
      case OnboardingVoiceIntent.stop:
      case OnboardingVoiceIntent.move:
      case OnboardingVoiceIntent.check:
        await c.practiceAction(switch (intent) {
          OnboardingVoiceIntent.stop => PracticeAction.stop,
          OnboardingVoiceIntent.move => PracticeAction.move,
          _ => PracticeAction.check,
        });
        _feedback = c.message == null ? null : c.copy.t(c.message!);
      case OnboardingVoiceIntent.next:
        if (question == OnboardingVoiceQuestion.information) {
          _informationIndex++;
          if (_informationIndex >= _information().length &&
              c.step != OnboardingStep.limits) {
            await c.next();
          }
        } else if (c.step == OnboardingStep.practice && !c.practiceFinished) {
          if (c.practiceAnswered && !c.practicePaused) await c.nextExercise();
        } else if (c.canContinue) {
          await c.next();
        }
      case OnboardingVoiceIntent.unknown:
        break;
    }
  });

  Future<void> _cancelPending() async {
    try {
      await input.cancel();
    } catch (_) {
      if (_disposed) return;
      enabled = false;
      _again = false;
      _generation++;
      _setPhase(
        OnboardingVoicePhase.unavailable,
        text: copy.t(VoiceCopy.cancelFailed),
      );
    }
  }

  Future<bool> _finish(
    OnboardingVoicePhase end,
    String text, {
    bool announce = true,
  }) async {
    enabled = false;
    _again = false;
    _generation++;
    try {
      await input.cancel();
    } catch (_) {
      if (!_disposed) {
        _setPhase(
          OnboardingVoicePhase.unavailable,
          text: copy.t(VoiceCopy.cancelFailed),
        );
      }
      return false;
    }
    if (_disposed) return false;
    if (controller.speaking) await _own(controller.stopSpeech);
    if (_disposed) return false;
    _setPhase(end, text: text);
    if (announce &&
        _foreground &&
        controller.isForeground &&
        !controller.busy) {
      await _own(() => controller.listen(text));
    }
    return true;
  }

  Future<void> disable() async {
    await _finish(OnboardingVoicePhase.off, copy.t(VoiceCopy.off));
  }

  /// Used by both voice and screen controls so the onboarding recognizer never
  /// overlaps the camera screen's own microphone owner. Admission is checked
  /// again after the handoff speech, through the original controller.
  Future<void> openInspection() async {
    if (_disposed || _openingInspection || controller.busy) return;
    if (onInspect == null || controller.admission != Admission.inspectionOnly) {
      _feedback = copy.t(
        onInspect == null
            ? VoiceCopy.inspectionUnavailable
            : VoiceCopy.summaryBlocked,
      );
      return;
    }
    _openingInspection = true;
    try {
      final announce = enabled;
      final inputClosed = await _finish(
        OnboardingVoicePhase.complete,
        copy.t(VoiceCopy.inspectionHandoff),
        announce: announce,
      );
      if (!inputClosed || _disposed || !controller.isForeground) return;
      if (controller.admission != Admission.inspectionOnly ||
          (announce && controller.hasSpeechProblem)) {
        await _finish(
          OnboardingVoicePhase.suspended,
          copy.t(VoiceCopy.summaryBlocked),
        );
        return;
      }
      await _own(() => controller.inspect(onInspect!));
    } finally {
      _openingInspection = false;
    }
  }

  void suspend() {
    if (_disposed) return;
    _foreground = false;
    _generation++;
    _again = false;
    if (enabled) _setPhase(OnboardingVoicePhase.suspended);
    unawaited(_cancelPending());
  }

  Future<void> resume() async {
    if (_disposed) return;
    _foreground = true;
    if (enabled && !_activating) await _activate(requestPermission: false);
  }

  @override
  void dispose() {
    _disposed = true;
    enabled = false;
    _generation++;
    _again = false;
    controller.removeListener(_controllerChanged);
    unawaited(input.dispose());
    super.dispose();
  }
}
