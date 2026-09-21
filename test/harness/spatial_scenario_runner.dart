import 'dart:convert';

import 'package:bagdar/safety/alerts/alert_arbiter.dart';
import 'package:bagdar/safety/alerts/feedback_command.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';

import 'spatial_replay_fixture.dart';

enum SpatialRunMode { developer, releaseCandidate }

enum SpatialScenarioStatus { pass, fail, partial, missing }

class SpatialFrameResult {
  final int frameIndex;
  final int evaluateOffsetMs;
  final String action;
  final String health;
  final String alertEvent;
  final bool interruptCurrent;
  final String shadowDirection;
  final List<String> violations;

  SpatialFrameResult({
    required this.frameIndex,
    required this.evaluateOffsetMs,
    required this.action,
    required this.health,
    required this.alertEvent,
    required this.interruptCurrent,
    required this.shadowDirection,
    required List<String> violations,
  }) : violations = List.unmodifiable(violations);

  Map<String, Object?> toJson() => <String, Object?>{
    'frameIndex': frameIndex,
    'evaluateOffsetMs': evaluateOffsetMs,
    'action': action,
    'health': health,
    'alertEvent': alertEvent,
    'interruptCurrent': interruptCurrent,
    'shadowDirection': shadowDirection,
    'violations': [...violations]..sort(),
  };
}

class SpatialScenarioResult {
  final String sceneId;
  final bool requiredForRc;
  final SpatialScenarioStatus status;
  final List<String> violations;
  final List<SpatialFrameResult> frames;

  SpatialScenarioResult({
    required this.sceneId,
    required this.requiredForRc,
    required this.status,
    required List<String> violations,
    required List<SpatialFrameResult> frames,
  }) : violations = List.unmodifiable(violations),
       frames = List.unmodifiable(frames);

  bool blocks(SpatialRunMode mode) {
    if (status == SpatialScenarioStatus.fail) return true;
    if (mode == SpatialRunMode.releaseCandidate && requiredForRc) {
      return status != SpatialScenarioStatus.pass;
    }
    return false;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sceneId': sceneId,
    'requiredForRc': requiredForRc,
    'status': status.name,
    'violations': [...violations]..sort(),
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  };
}

class SpatialReplayMetrics {
  int unsafeGuidanceCount = 0;
  int guidanceIntoUnknownCount = 0;
  int staleActionEmissionCount = 0;
  int expectedActionMismatchCount = 0;
  int healthMismatchCount = 0;
  int alertMismatchCount = 0;

  Map<String, int> toJson() => <String, int>{
    'unsafeGuidanceCount': unsafeGuidanceCount,
    'guidanceIntoUnknownCount': guidanceIntoUnknownCount,
    'staleActionEmissionCount': staleActionEmissionCount,
    'expectedActionMismatchCount': expectedActionMismatchCount,
    'healthMismatchCount': healthMismatchCount,
    'alertMismatchCount': alertMismatchCount,
  };
}

class SpatialReplayReport {
  final String corpusId;
  final int schemaVersion;
  final int seed;
  final SpatialRunMode mode;
  final SpatialReplayMetrics metrics;
  final List<SpatialScenarioResult> scenarios;
  final List<String> missingExternalCorpora;
  final List<String> missingPrivateCorpora;
  final List<String> invalidExternalCorpora;
  final List<String> blockingReasons;

  SpatialReplayReport({
    required this.corpusId,
    required this.schemaVersion,
    required this.seed,
    required this.mode,
    required this.metrics,
    required List<SpatialScenarioResult> scenarios,
    required List<String> missingExternalCorpora,
    required List<String> missingPrivateCorpora,
    required List<String> invalidExternalCorpora,
    required List<String> blockingReasons,
  }) : scenarios = List.unmodifiable(scenarios),
       missingExternalCorpora = List.unmodifiable(missingExternalCorpora),
       missingPrivateCorpora = List.unmodifiable(missingPrivateCorpora),
       invalidExternalCorpora = List.unmodifiable(invalidExternalCorpora),
       blockingReasons = List.unmodifiable(blockingReasons);

  bool get passed => blockingReasons.isEmpty;

  Map<String, Object?> toJson() {
    final orderedScenarios = [...scenarios]
      ..sort((a, b) => a.sceneId.compareTo(b.sceneId));
    return <String, Object?>{
      'corpusId': corpusId,
      'schemaVersion': schemaVersion,
      'seed': seed,
      'mode': mode.name,
      'passed': passed,
      'metrics': metrics.toJson(),
      'missingExternalCorpora': [...missingExternalCorpora]..sort(),
      'missingPrivateCorpora': [...missingPrivateCorpora]..sort(),
      'invalidExternalCorpora': [...invalidExternalCorpora]..sort(),
      'blockingReasons': [...blockingReasons]..sort(),
      'scenarios': orderedScenarios
          .map((scenario) => scenario.toJson())
          .toList(growable: false),
    };
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Deterministic runner for the phone-independent relative spatial corpus.
///
/// It evaluates the same planner/arbiter path used by the first safety slice.
/// It does not claim camera, model, or device parity.
class SpatialScenarioRunner {
  final SpatialReplayFixture fixture;
  final SpatialRunMode mode;

  const SpatialScenarioRunner({required this.fixture, required this.mode});

  SpatialReplayReport runAll() {
    final metrics = SpatialReplayMetrics();
    final results = <SpatialScenarioResult>[];
    final blockingReasons = <String>[];
    final orderedScenes = [...fixture.manifest.scenes]
      ..sort((a, b) => a.id.compareTo(b.id));

    for (final scene in orderedScenes) {
      final result = _runScene(scene, metrics);
      results.add(result);
      if (result.blocks(mode)) {
        blockingReasons.add('${scene.id}:${result.status.name}');
      }
    }

    final missingExternal = <String>[];
    final missingPrivate = <String>[];
    final invalidExternal = <String>[];
    for (final corpus in fixture.manifest.externalCorpora) {
      if (corpus.availability == SpatialExternalAvailability.available) {
        final violations = fixture.validateExternalCorpus(corpus);
        if (violations.isNotEmpty) {
          invalidExternal.addAll(
            violations.map((value) => '${corpus.id}:$value'),
          );
          blockingReasons.addAll(
            violations.map((value) => 'external:${corpus.id}:$value'),
          );
        }
        continue;
      }
      if (corpus.handling == 'private') {
        missingPrivate.add(corpus.id);
      } else {
        missingExternal.add(corpus.id);
      }
      if (mode == SpatialRunMode.releaseCandidate && corpus.requiredForRc) {
        blockingReasons.add('external:${corpus.id}:missing');
      }
    }

    if (metrics.unsafeGuidanceCount != 0) {
      blockingReasons.add('unsafeGuidanceCount:${metrics.unsafeGuidanceCount}');
    }
    if (metrics.guidanceIntoUnknownCount != 0) {
      blockingReasons.add(
        'guidanceIntoUnknownCount:${metrics.guidanceIntoUnknownCount}',
      );
    }
    if (metrics.staleActionEmissionCount != 0) {
      blockingReasons.add(
        'staleActionEmissionCount:${metrics.staleActionEmissionCount}',
      );
    }

    return SpatialReplayReport(
      corpusId: fixture.manifest.corpusId,
      schemaVersion: fixture.manifest.schemaVersion,
      seed: fixture.manifest.seed,
      mode: mode,
      metrics: metrics,
      scenarios: results,
      missingExternalCorpora: missingExternal,
      missingPrivateCorpora: missingPrivate,
      invalidExternalCorpora: invalidExternal,
      blockingReasons: blockingReasons,
    );
  }

  SpatialScenarioResult _runScene(
    SpatialSceneManifest scene,
    SpatialReplayMetrics metrics,
  ) {
    final fileViolations = fixture.validateSceneFiles(scene);
    if (fileViolations.any((value) => value.startsWith('missing_'))) {
      return SpatialScenarioResult(
        sceneId: scene.id,
        requiredForRc: scene.requiredForRc,
        status: SpatialScenarioStatus.missing,
        violations: fileViolations,
        frames: const [],
      );
    }
    if (fileViolations.isNotEmpty) {
      return SpatialScenarioResult(
        sceneId: scene.id,
        requiredForRc: scene.requiredForRc,
        status: SpatialScenarioStatus.fail,
        violations: fileViolations,
        frames: const [],
      );
    }

    try {
      final frames = fixture.loadFrames(scene);
      final annotations = fixture.loadAnnotations(scene);
      final machine = GuidanceStateMachine();
      final arbiter = AlertArbiter();
      final sceneModel = LocalSceneModel.relative();
      final frameResults = <SpatialFrameResult>[];
      final sceneViolations = <String>[];
      if (annotations.initialFeedback == 'information') {
        arbiter.submitOnDemand(
          _informationCommand(fixture.manifest.timelineOriginUtc),
          now: fixture.manifest.timelineOriginUtc,
        );
      } else if (annotations.initialFeedback != 'none') {
        sceneViolations.add(
          'unsupported_initial_feedback:${annotations.initialFeedback}',
        );
      }

      for (final frame in frames) {
        final result = _runFrame(
          frame,
          annotations,
          sceneModel,
          machine,
          arbiter,
          metrics,
        );
        frameResults.add(result);
        sceneViolations.addAll(
          result.violations.map(
            (violation) => 'frame_${frame.frameIndex}:$violation',
          ),
        );
      }

      final status = sceneViolations.isNotEmpty
          ? SpatialScenarioStatus.fail
          : scene.coverage == SpatialScenarioCoverage.partial
          ? SpatialScenarioStatus.partial
          : SpatialScenarioStatus.pass;
      return SpatialScenarioResult(
        sceneId: scene.id,
        requiredForRc: scene.requiredForRc,
        status: status,
        violations: sceneViolations,
        frames: frameResults,
      );
    } on Object catch (error) {
      return SpatialScenarioResult(
        sceneId: scene.id,
        requiredForRc: scene.requiredForRc,
        status: SpatialScenarioStatus.fail,
        violations: ['fixture_error:$error'],
        frames: const [],
      );
    }
  }

  SpatialFrameResult _runFrame(
    SpatialReplayFrame frame,
    SpatialScenarioAnnotations annotations,
    LocalSceneModel sceneModel,
    GuidanceStateMachine machine,
    AlertArbiter arbiter,
    SpatialReplayMetrics metrics,
  ) {
    final origin = fixture.manifest.timelineOriginUtc;
    final capturedAt = origin.add(
      Duration(milliseconds: frame.capturedOffsetMs),
    );
    final evaluatedAt = origin.add(
      Duration(milliseconds: frame.evaluateOffsetMs),
    );
    final validUntil = origin.add(
      Duration(milliseconds: frame.validUntilOffsetMs),
    );
    final evidence = <SpatialEvidence>[];
    final hazards = <HazardTrackSnapshot>[];
    final movingThreats = <MovingThreatSnapshot>[];
    for (final entry in frame.sectors.entries) {
      final sample = entry.value;
      final sourceIds = sample.sourceMask.isEmpty
          ? const <String>['replay']
          : sample.sourceMask;
      for (final sourceId in sourceIds) {
        evidence.add(
          SpatialEvidence(
            elementId: entry.key,
            coordinateMode: SceneCoordinateMode.relative,
            sourceId: sourceId,
            source: _sourceKind(sourceId),
            observedAt: origin.add(
              Duration(milliseconds: sample.lastObservedOffsetMs),
            ),
            validUntil: validUntil,
            observedFraction: sample.observedFraction,
            confidence: sample.confidence,
            occupancyProbability: sample.occupancyProbability,
            traversabilityProbability: sample.traversabilityProbability,
            dropProbability: sample.dropProbability,
            movingThreatRisk: sample.movingThreatRisk,
            unknownProbability: sample.unknownProbability,
            hazardIds: sample.hazardIds,
          ),
        );
      }
      for (final hazardId in sample.hazardIds) {
        hazards.add(
          HazardTrackSnapshot(
            id: hazardId,
            elementId: entry.key,
            risk: _maximumRisk(sample),
            sourceMask: sample.sourceMask.toSet(),
            lastObservedAt: origin.add(
              Duration(milliseconds: sample.lastObservedOffsetMs),
            ),
          ),
        );
      }
      if (sample.movingThreatRisk > 0) {
        movingThreats.add(
          MovingThreatSnapshot(
            id: 'replay-moving:${frame.sceneId}:${entry.key}',
            elementId: entry.key,
            intersectionRisk: sample.movingThreatRisk,
            lastObservedAt: origin.add(
              Duration(milliseconds: sample.lastObservedOffsetMs),
            ),
          ),
        );
      }
    }
    final sceneUpdate = sceneModel.update(
      LocalSceneUpdate(
        coordinateMode: SceneCoordinateMode.relative,
        at: capturedAt,
        validUntil: validUntil,
        poseQuality: frame.orientationValid ? 0.9 : 0.2,
        sensorHealth: SceneSensorHealth(<String, SceneSensorState>{
          'replay': frame.sensingHealthy
              ? SceneSensorState.healthy
              : SceneSensorState.unavailable,
        }),
        evidence: evidence,
        hazardTracks: hazards,
        movingThreats: movingThreats,
      ),
    );
    final grid = RelativePolarGrid.fromSnapshot(
      sceneUpdate.snapshot,
      orientationValid: frame.orientationValid,
      userMoving: frame.userMoving,
    );
    final decision = machine.evaluate(grid, now: evaluatedAt);
    final alert = arbiter.submitAction(decision.action, now: evaluatedAt);
    final expectation = annotations.expectationAt(frame.evaluateOffsetMs);
    final health = _healthFor(grid, evaluatedAt);
    final shadow = decision.shadowCorrection?.name ?? 'none';
    final violations = <String>[];
    if (!sceneUpdate.accepted) {
      violations.add('scene_update_rejected:${sceneUpdate.reason}');
    }
    final action = decision.action.kind.name;
    final alertEvent = alert.type.name;

    if (decision.action.kind == SafetyActionKind.adjustLeft ||
        decision.action.kind == SafetyActionKind.adjustRight ||
        decision.action.isShadowOnly) {
      violations.add('directional_action_escaped_shadow');
      metrics.unsafeGuidanceCount++;
    }

    if (!expectation.expectedActions.contains(action)) {
      violations.add('unexpected_action:$action');
      metrics.expectedActionMismatchCount++;
    }
    if (expectation.forbiddenActions.contains(action)) {
      violations.add('forbidden_action:$action');
      metrics.unsafeGuidanceCount++;
    }
    if (!expectation.expectedHealth.contains(health)) {
      violations.add('unexpected_health:$health');
      metrics.healthMismatchCount++;
    }
    if (!expectation.expectedAlertEvents.contains(alertEvent)) {
      violations.add('unexpected_alert:$alertEvent');
      metrics.alertMismatchCount++;
    }
    if (!expectation.expectedShadowDirections.contains(shadow)) {
      violations.add('unexpected_shadow_direction:$shadow');
    }
    if (expectation.interruptCurrent != null &&
        alert.interruptCurrent != expectation.interruptCurrent) {
      violations.add('unexpected_interrupt:${alert.interruptCurrent}');
      metrics.alertMismatchCount++;
    }

    final targetUnknown = switch (decision.action.kind) {
      SafetyActionKind.adjustLeft =>
        grid.sector(RelativeSectorDirection.left).unknownProbability > 0.25,
      SafetyActionKind.adjustRight =>
        grid.sector(RelativeSectorDirection.right).unknownProbability > 0.25,
      _ => false,
    };
    final shadowTargetUnknown = switch (decision.shadowCorrection) {
      CorridorDirection.left =>
        grid.sector(RelativeSectorDirection.left).unknownProbability > 0.15,
      CorridorDirection.right =>
        grid.sector(RelativeSectorDirection.right).unknownProbability > 0.15,
      _ => false,
    };
    if (targetUnknown || shadowTargetUnknown) {
      metrics.guidanceIntoUnknownCount++;
    }
    final emitsExpired =
        decision.action.isExpiredAt(evaluatedAt) &&
        alert.type != AlertArbiterEventType.dropped &&
        alert.type != AlertArbiterEventType.suppressed;
    if (emitsExpired) metrics.staleActionEmissionCount++;

    return SpatialFrameResult(
      frameIndex: frame.frameIndex,
      evaluateOffsetMs: frame.evaluateOffsetMs,
      action: action,
      health: health,
      alertEvent: alertEvent,
      interruptCurrent: alert.interruptCurrent,
      shadowDirection: shadow,
      violations: violations,
    );
  }

  String _healthFor(RelativePolarGrid grid, DateTime now) {
    if (grid.isStaleAt(now)) return 'stale';
    if (!grid.sensingHealthy) return 'unavailable';
    if (!grid.orientationValid) return 'degraded';
    return 'healthy';
  }

  FeedbackCommand _informationCommand(DateTime now) => FeedbackCommand(
    actionId: 'replay-info',
    sceneRevision: 0,
    speechKey: 'core_health_status',
    earcon: FeedbackEarcon.none,
    hapticPattern: FeedbackHapticPattern.none,
    priority: SafetyPriority.p3Information,
    source: FeedbackCommandSource.onDemand,
    actionKind: null,
    direction: null,
    urgency: 0.2,
    canInterrupt: false,
    replaceKey: 'replay:information',
    createdAt: now,
    expiresAt: now.add(const Duration(seconds: 5)),
    ruleId: 'REPLAY-INITIAL-INFORMATION',
    hazardIds: const [],
  );

  SpatialEvidenceSource _sourceKind(String sourceId) => switch (sourceId) {
    'geometry' => SpatialEvidenceSource.geometry,
    'depth' => SpatialEvidenceSource.depth,
    'semantic' => SpatialEvidenceSource.semantic,
    'traversability' => SpatialEvidenceSource.traversability,
    'motion' => SpatialEvidenceSource.motion,
    'acoustic' => SpatialEvidenceSource.acoustic,
    _ => SpatialEvidenceSource.replay,
  };

  double _maximumRisk(SpatialSectorSample sample) {
    var result = sample.occupancyProbability;
    if (sample.dropProbability > result) result = sample.dropProbability;
    if (sample.movingThreatRisk > result) result = sample.movingThreatRisk;
    return result;
  }
}
