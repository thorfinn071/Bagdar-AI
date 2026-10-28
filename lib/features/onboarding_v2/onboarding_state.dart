import '../../models/strings.dart';

const onboardingSchema = 1;
const onboardingContentVersion = 1;

enum OnboardingStep {
  language,
  access,
  limits,
  feedback,
  privacy,
  vocabulary,
  practice,
  camera,
  device,
  alignment,
  stationary,
  summary,
}

enum AccessMode { voice, largeText, helper }

enum ModuleStatus { notStarted, completed, blocked }

enum CameraAccess {
  notRequested,
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

enum ProbeStatus { notChecked, available, unavailable }

enum Admission { trainingRequired, recheckRequired, inspectionOnly }

/// Only user progress is persisted. Live/device evidence never survives a run.
class OnboardingProgress {
  final AppLanguage language;
  final AccessMode accessMode;
  final OnboardingStep checkpoint;
  final Map<OnboardingStep, ModuleStatus> modules;
  final int completedExercises;

  OnboardingProgress({
    this.language = AppLanguage.ru,
    this.accessMode = AccessMode.voice,
    this.checkpoint = OnboardingStep.language,
    Map<OnboardingStep, ModuleStatus> modules = const {},
    int? completedExercises,
  }) : modules = Map.unmodifiable(modules),
       completedExercises =
           completedExercises ??
           (modules[OnboardingStep.practice] == ModuleStatus.completed ? 4 : 0);

  bool complete(OnboardingStep step) => modules[step] == ModuleStatus.completed;

  OnboardingProgress copyWith({
    AppLanguage? language,
    AccessMode? accessMode,
    OnboardingStep? checkpoint,
    Map<OnboardingStep, ModuleStatus>? modules,
    int? completedExercises,
  }) => OnboardingProgress(
    language: language ?? this.language,
    accessMode: accessMode ?? this.accessMode,
    checkpoint: checkpoint ?? this.checkpoint,
    modules: modules ?? this.modules,
    completedExercises: completedExercises ?? this.completedExercises,
  );

  OnboardingProgress selectLanguage(AppLanguage next) {
    if (next == language) return this;
    final nextModules = Map<OnboardingStep, ModuleStatus>.of(modules)
      ..remove(OnboardingStep.feedback)
      ..remove(OnboardingStep.vocabulary)
      ..remove(OnboardingStep.practice);
    return copyWith(
      language: next,
      modules: nextModules,
      completedExercises: 0,
    );
  }

  Map<String, Object> toJson() => {
    'schema': onboardingSchema,
    'contentVersion': onboardingContentVersion,
    'language': language.name,
    'accessMode': accessMode.name,
    'checkpoint': checkpoint.name,
    'completedExercises': completedExercises,
    'modules': {
      for (final entry in modules.entries) entry.key.name: entry.value.name,
    },
  };

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != onboardingSchema ||
        json['contentVersion'] != onboardingContentVersion) {
      throw const FormatException('unsupported_onboarding_version');
    }
    final rawModules = json['modules'];
    if (rawModules is! Map<String, dynamic>) {
      throw const FormatException('invalid_modules');
    }
    final exercises = json['completedExercises'];
    if (json.containsKey('completedExercises') &&
        (exercises is! int || exercises < 0 || exercises > 4)) {
      throw const FormatException('invalid_exercises');
    }
    return OnboardingProgress(
      language: AppLanguage.values.byName(json['language'] as String),
      accessMode: AccessMode.values.byName(json['accessMode'] as String),
      checkpoint: OnboardingStep.values.byName(json['checkpoint'] as String),
      completedExercises: exercises as int?,
      modules: {
        for (final entry in rawModules.entries)
          OnboardingStep.values.byName(entry.key): ModuleStatus.values.byName(
            entry.value as String,
          ),
      },
    );
  }
}

class ProbeResult {
  final ProbeStatus status;
  final String reason;
  final DateTime? checkedAt;
  const ProbeResult(this.status, this.reason, [this.checkedAt]);
  const ProbeResult.unchecked() : this(ProbeStatus.notChecked, 'notChecked');

  bool freshAt(DateTime now) =>
      status == ProbeStatus.available &&
      checkedAt != null &&
      !now.isBefore(checkedAt!) &&
      now.difference(checkedAt!) < const Duration(minutes: 2);
}

class OnboardingEvidence {
  // The helper may configure the app, but cannot supply personal confirmations.
  // This belongs to the current session and is never persisted as readiness.
  bool userHasControl = true;
  CameraAccess cameraAccess = CameraAccess.notRequested;
  ProbeResult camera = const ProbeResult.unchecked();
  ProbeResult alignment = const ProbeResult.unchecked();
  ProbeResult thermal = const ProbeResult.unchecked();
  bool voiceSamplePlayed = false;
  bool ordinaryVoiceConfirmed = false;
  bool stopVoicePlayed = false;
  bool hapticPlayed = false;
  bool voiceConfirmed = false;
  bool hapticConfirmed = false;
  bool stationaryConfirmed = false;
  bool alignmentConfirmed = false;

  bool get criticalChannelVerified =>
      (voiceSamplePlayed && stopVoicePlayed && voiceConfirmed) ||
      (hapticPlayed && hapticConfirmed);

  void invalidateDevice() {
    cameraAccess = CameraAccess.notRequested;
    camera = const ProbeResult.unchecked();
    alignment = const ProbeResult.unchecked();
    thermal = const ProbeResult.unchecked();
    stationaryConfirmed = false;
    alignmentConfirmed = false;
  }

  void invalidateFeedback() {
    ordinaryVoiceConfirmed = false;
    voiceSamplePlayed = stopVoicePlayed = hapticPlayed = false;
    voiceConfirmed = hapticConfirmed = false;
  }
}

/// A separate, deliberately narrow admission scope. Setup cannot authorize
/// generic assistive navigation. AiCameraScreen still owns runtime health.
class OnboardingSessionGate {
  static const requiredSetup = [
    OnboardingStep.language,
    OnboardingStep.access,
    OnboardingStep.limits,
    OnboardingStep.feedback,
    OnboardingStep.privacy,
    OnboardingStep.vocabulary,
    OnboardingStep.practice,
  ];

  bool trainingComplete(OnboardingProgress progress) =>
      requiredSetup.every(progress.complete);

  Admission evaluate(
    OnboardingProgress progress,
    OnboardingEvidence evidence,
    DateTime now,
  ) {
    if (!trainingComplete(progress)) {
      return Admission.trainingRequired;
    }
    if (nextRequiredStep(progress, evidence, now) != null) {
      return Admission.recheckRequired;
    }
    return Admission.inspectionOnly;
  }

  OnboardingStep? nextRequiredStep(
    OnboardingProgress progress,
    OnboardingEvidence evidence,
    DateTime now,
  ) {
    if (!evidence.userHasControl) return OnboardingStep.access;
    for (final step in requiredSetup) {
      if (!progress.complete(step)) return step;
    }
    if (!evidence.criticalChannelVerified) return OnboardingStep.feedback;
    if (evidence.cameraAccess != CameraAccess.granted) {
      return OnboardingStep.camera;
    }
    if (!evidence.camera.freshAt(now) || !evidence.thermal.freshAt(now)) {
      return OnboardingStep.device;
    }
    if (!evidence.alignment.freshAt(now) || !evidence.alignmentConfirmed) {
      return OnboardingStep.alignment;
    }
    if (!evidence.stationaryConfirmed) return OnboardingStep.stationary;
    return null;
  }

  bool get mayStartGenericAssistive => false;
}
