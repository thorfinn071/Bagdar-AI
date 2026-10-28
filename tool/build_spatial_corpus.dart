import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _root = 'test/fixtures/spatial_safety';
const _schemaVersion = 1;
const _annotationRevision = 3;
const _seed = 20260919;
const _generatorId = 'bagdar-procedural-relative-polar-v1';
const _modelId = 'procedural-relative-polar-v1';
const _preprocessId = 'relative-polar-normalized-v1';

void main(List<String> arguments) {
  final checkOnly = arguments.contains('--check');
  final generated = _generateCorpus();
  final mismatches = <String>[];

  for (final entry in generated.entries) {
    final file = File(entry.key);
    if (checkOnly) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        mismatches.add(entry.key);
      }
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  if (checkOnly && mismatches.isNotEmpty) {
    stderr.writeln(
      'Spatial corpus is not reproducible; mismatched files:\n'
      '${mismatches.map((path) => '  $path').join('\n')}',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    checkOnly
        ? 'Spatial corpus matches generator (${generated.length} files).'
        : 'Generated spatial corpus (${generated.length} files).',
  );
}

Map<String, String> _generateCorpus() {
  final modelHash = _digest('bagdar:$_modelId:$_preprocessId');
  final scenarios = <_Scenario>[
    _Scenario.single(
      id: 'center-obstacle',
      tags: const ['obstacle', 'center', 'procedural'],
      frame: _frame(
        sceneId: 'center-obstacle',
        userMoving: true,
        forward: _blocked('geometry:center-bin'),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
      ),
    ),
    _Scenario.single(
      id: 'unknown-center-stopped',
      tags: const ['unknown', 'center', 'stationary', 'procedural'],
      frame: _frame(
        sceneId: 'unknown-center-stopped',
        userMoving: false,
        forward: _unknown(),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'holdAndScan',
        expectedAlert: 'emitted',
      ),
    ),
    _Scenario.single(
      id: 'unknown-center-moving',
      tags: const ['unknown', 'center', 'moving', 'procedural'],
      frame: _frame(
        sceneId: 'unknown-center-moving',
        userMoving: true,
        forward: _unknown(),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
      ),
    ),
    _Scenario.single(
      id: 'center-blocked-left-observed',
      tags: const ['planner', 'shadow-left', 'procedural'],
      frame: _frame(
        sceneId: 'center-blocked-left-observed',
        userMoving: true,
        forward: _blocked('geometry:center'),
        right: _unknown(),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
      ),
    ),
    _Scenario.single(
      id: 'center-blocked-sides-unobserved',
      tags: const ['planner', 'unknown-sides', 'procedural'],
      frame: _frame(
        sceneId: 'center-blocked-sides-unobserved',
        userMoving: true,
        left: _unknown(),
        forward: _blocked('geometry:center'),
        right: _unknown(),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
      ),
    ),
    _Scenario(
      id: 'stable-left-shadow-correction',
      tags: const ['planner', 'hysteresis', 'shadow-left', 'procedural'],
      initialFeedback: 'none',
      frames: <Map<String, Object?>>[
        for (var index = 0; index < 3; index++)
          _frame(
            sceneId: 'stable-left-shadow-correction',
            frameIndex: index,
            frameId: index + 1,
            capturedOffsetMs: index * 300,
            evaluateOffsetMs: index * 300,
            validUntilOffsetMs: 900 + index * 300,
            forward: _shadowBlocked(
              'geometry:stable-center',
              observedOffsetMs: index * 300,
            ),
            right: _unknown(observedOffsetMs: index * 300),
            modelHash: modelHash,
          ),
      ],
      timeline: <Map<String, Object?>>[
        _expectation(
          startOffsetMs: 0,
          endOffsetMs: 100,
          expectedAction: 'holdAndScan',
          expectedAlert: 'emitted',
        ),
        _expectation(
          startOffsetMs: 200,
          endOffsetMs: 400,
          expectedAction: 'holdAndScan',
          expectedAlert: 'suppressed',
        ),
        _expectation(
          startOffsetMs: 500,
          endOffsetMs: 700,
          expectedAction: 'holdAndScan',
          expectedAlert: 'suppressed',
          expectedShadow: 'left',
        ),
      ],
    ),
    _Scenario.single(
      id: 'stale-depth-moving',
      tags: const ['degradation', 'stale-depth', 'moving', 'procedural'],
      frame: _frame(
        sceneId: 'stale-depth-moving',
        userMoving: true,
        evaluateOffsetMs: 2000,
        validUntilOffsetMs: 900,
        modelHash: modelHash,
      ),
      expectation: _expectation(
        startOffsetMs: 1500,
        endOffsetMs: 2500,
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
        expectedHealth: 'stale',
      ),
    ),
    _Scenario.single(
      id: 'critical-during-information',
      tags: const ['alert', 'preemption', 'procedural'],
      initialFeedback: 'information',
      frame: _frame(
        sceneId: 'critical-during-information',
        userMoving: true,
        forward: _blocked('geometry:appearing-obstacle'),
        modelHash: modelHash,
      ),
      expectation: _expectation(
        expectedAction: 'stopNow',
        expectedAlert: 'emitted',
        interruptCurrent: true,
      ),
    ),
    _Scenario(
      id: 'hazard-emerges-during-guidance',
      tags: const ['temporal', 'emerging-hazard', 'procedural'],
      initialFeedback: 'none',
      frames: <Map<String, Object?>>[
        _frame(
          sceneId: 'hazard-emerges-during-guidance',
          frameIndex: 0,
          frameId: 1,
          evaluateOffsetMs: 0,
          validUntilOffsetMs: 900,
          userMoving: true,
          modelHash: modelHash,
        ),
        _frame(
          sceneId: 'hazard-emerges-during-guidance',
          frameIndex: 1,
          frameId: 2,
          capturedOffsetMs: 300,
          evaluateOffsetMs: 300,
          validUntilOffsetMs: 1200,
          userMoving: true,
          forward: _blocked(
            'geometry:new-center-hazard',
            observedOffsetMs: 300,
          ),
          left: _safe(observedOffsetMs: 300),
          right: _safe(observedOffsetMs: 300),
          modelHash: modelHash,
        ),
      ],
      timeline: <Map<String, Object?>>[
        _expectation(
          startOffsetMs: 0,
          endOffsetMs: 100,
          expectedAction: 'continueForward',
          expectedAlert: 'suppressed',
        ),
        _expectation(
          startOffsetMs: 200,
          endOffsetMs: 500,
          expectedAction: 'stopNow',
          expectedAlert: 'emitted',
        ),
      ],
    ),
  ];

  final files = <String, String>{};
  final manifestScenes = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    final framesRelative = 'scenes/${scenario.id}/frames.jsonl';
    final annotationsRelative = 'scenes/${scenario.id}/annotations.json';
    final frames = '${scenario.frames.map(jsonEncode).join('\n')}\n';
    final annotations = _pretty(<String, Object?>{
      'schemaVersion': _schemaVersion,
      'sceneId': scenario.id,
      'annotationRevision': _annotationRevision,
      'initialFeedback': scenario.initialFeedback,
      'timeline': scenario.timeline,
    });
    files['$_root/$framesRelative'] = frames;
    files['$_root/$annotationsRelative'] = annotations;
    manifestScenes.add(<String, Object?>{
      'id': scenario.id,
      'kind': 'procedural',
      'frames': framesRelative,
      'annotations': annotationsRelative,
      'sha256': <String, Object?>{
        'frames': _digest(frames),
        'annotations': _digest(annotations),
      },
      'tags': scenario.tags,
      'annotationRevision': _annotationRevision,
      'requiredForRc': true,
      'coverage': 'complete',
    });
  }

  const blenderManifestRelative = 'blender-egocentric-v1/corpus-manifest.json';
  final blenderManifest = File('$_root/$blenderManifestRelative');
  final blenderAvailable = blenderManifest.existsSync();
  const temporalManifestRelative = 'blender-temporal-v2/corpus-manifest.json';
  final temporalManifest = File('$_root/$temporalManifestRelative');
  final temporalAvailable = temporalManifest.existsSync();
  const contextManifestRelative = 'blender-context-v3/corpus-manifest.json';
  final contextManifest = File('$_root/$contextManifestRelative');
  final contextAvailable = contextManifest.existsSync();
  files['$_root/manifest.json'] = _pretty(<String, Object?>{
    'schemaVersion': _schemaVersion,
    'corpusId': 'bagdar-spatial-canonical-v1',
    'seed': _seed,
    'generatorId': _generatorId,
    'timelineOriginUtc': '2026-09-19T00:00:00.000Z',
    'source': <String, Object?>{
      'type': 'procedural',
      'license': 'project-generated-test-fixture',
      'consentClass': 'not_applicable',
    },
    'handling': 'public',
    'camera': <String, Object?>{
      'mount': 'synthetic_chest_fixed',
      'parameters': 'normalized_fov_60deg',
      'coordinateMode': 'relative',
    },
    'modelContract': <String, Object?>{
      'modelId': _modelId,
      'modelHash': modelHash,
      'preprocessId': _preprocessId,
    },
    'scenes': manifestScenes,
    'externalCorpora': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'blender-egocentric-v1',
        'source': 'blender',
        'handling': 'public',
        'consentClass': 'not_applicable',
        'requiredForRc': true,
        'availability': blenderAvailable ? 'available' : 'missing',
        if (blenderAvailable) ...<String, Object?>{
          'manifestPath': blenderManifestRelative,
          'manifestSha256': sha256
              .convert(blenderManifest.readAsBytesSync())
              .toString(),
        },
      },
      <String, Object?>{
        'id': 'blender-temporal-v2',
        'source': 'blender',
        'handling': 'public',
        'consentClass': 'not_applicable',
        'requiredForRc': true,
        'availability': temporalAvailable ? 'available' : 'missing',
        if (temporalAvailable) ...<String, Object?>{
          'manifestPath': temporalManifestRelative,
          'manifestSha256': sha256
              .convert(temporalManifest.readAsBytesSync())
              .toString(),
        },
      },
      <String, Object?>{
        'id': 'blender-context-v3',
        'source': 'blender',
        'handling': 'public',
        'consentClass': 'not_applicable',
        'requiredForRc': true,
        'availability': contextAvailable ? 'available' : 'missing',
        if (contextAvailable) ...<String, Object?>{
          'manifestPath': contextManifestRelative,
          'manifestSha256': sha256
              .convert(contextManifest.readAsBytesSync())
              .toString(),
        },
      },
      <String, Object?>{
        'id': 'controlled-camera-v1',
        'source': 'recorded',
        'handling': 'private',
        'consentClass': 'explicit_required',
        'requiredForRc': false,
        'availability': 'missing',
      },
    ],
  });
  return files;
}

Map<String, Object?> _frame({
  required String sceneId,
  required String modelHash,
  int frameIndex = 0,
  int frameId = 1,
  int capturedOffsetMs = 0,
  int evaluateOffsetMs = 0,
  int validUntilOffsetMs = 900,
  bool orientationValid = true,
  bool sensingHealthy = true,
  bool userMoving = false,
  Map<String, Object?>? left,
  Map<String, Object?>? forward,
  Map<String, Object?>? right,
}) => <String, Object?>{
  'schemaVersion': _schemaVersion,
  'sceneId': sceneId,
  'frameIndex': frameIndex,
  'capturedOffsetMs': capturedOffsetMs,
  'evaluateOffsetMs': evaluateOffsetMs,
  'validUntilOffsetMs': validUntilOffsetMs,
  'sessionGeneration': 1,
  'frameId': frameId,
  'modelId': _modelId,
  'modelHash': modelHash,
  'preprocessId': _preprocessId,
  'orientationValid': orientationValid,
  'sensingHealthy': sensingHealthy,
  'userMoving': userMoving,
  'sectors': <String, Object?>{
    'left': left ?? _safe(observedOffsetMs: capturedOffsetMs),
    'forward': forward ?? _safe(observedOffsetMs: capturedOffsetMs),
    'right': right ?? _safe(observedOffsetMs: capturedOffsetMs),
  },
};

Map<String, Object?> _safe({int observedOffsetMs = 0}) => <String, Object?>{
  'observedFraction': 0.95,
  'occupancyProbability': 0.05,
  'traversabilityProbability': 0.90,
  'dropProbability': 0.02,
  'movingThreatRisk': 0.02,
  'unknownProbability': 0.05,
  'confidence': 0.90,
  'sourceMask': const ['depth', 'geometry'],
  'hazardIds': const <String>[],
  'lastObservedOffsetMs': observedOffsetMs,
};

Map<String, Object?> _unknown({int observedOffsetMs = 0}) => <String, Object?>{
  'observedFraction': 0.25,
  'occupancyProbability': 0.05,
  'traversabilityProbability': 0.10,
  'dropProbability': 0.02,
  'movingThreatRisk': 0.02,
  'unknownProbability': 0.90,
  'confidence': 0.20,
  'sourceMask': const ['geometry'],
  'hazardIds': const <String>[],
  'lastObservedOffsetMs': observedOffsetMs,
};

Map<String, Object?> _blocked(String hazardId, {int observedOffsetMs = 0}) =>
    <String, Object?>{
      'observedFraction': 0.95,
      'occupancyProbability': 0.90,
      'traversabilityProbability': 0.20,
      'dropProbability': 0.02,
      'movingThreatRisk': 0.02,
      'unknownProbability': 0.05,
      'confidence': 0.95,
      'sourceMask': const ['depth', 'geometry'],
      'hazardIds': <String>[hazardId],
      'lastObservedOffsetMs': observedOffsetMs,
    };

Map<String, Object?> _shadowBlocked(
  String hazardId, {
  int observedOffsetMs = 0,
}) => <String, Object?>{
  'observedFraction': 0.95,
  'occupancyProbability': 0.70,
  'traversabilityProbability': 0.20,
  'dropProbability': 0.02,
  'movingThreatRisk': 0.02,
  'unknownProbability': 0.05,
  'confidence': 0.90,
  'sourceMask': const ['depth', 'geometry'],
  'hazardIds': <String>[hazardId],
  'lastObservedOffsetMs': observedOffsetMs,
};

Map<String, Object?> _expectation({
  int startOffsetMs = 0,
  int endOffsetMs = 100,
  required String expectedAction,
  required String expectedAlert,
  String expectedHealth = 'healthy',
  String expectedShadow = 'none',
  bool interruptCurrent = false,
}) {
  final forbidden = switch (expectedAction) {
    'stopNow' => const ['continueForward', 'adjustLeft', 'adjustRight'],
    'holdAndScan' => const ['continueForward', 'adjustLeft', 'adjustRight'],
    'continueForward' => const ['adjustLeft', 'adjustRight'],
    _ => const <String>[],
  };
  return <String, Object?>{
    'startOffsetMs': startOffsetMs,
    'endOffsetMs': endOffsetMs,
    'expectedActions': <String>[expectedAction],
    'forbiddenActions': forbidden,
    'expectedHealth': <String>[expectedHealth],
    'expectedAlertEvents': <String>[expectedAlert],
    'expectedShadowDirections': <String>[expectedShadow],
    'interruptCurrent': interruptCurrent,
  };
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

String _pretty(Object value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

class _Scenario {
  final String id;
  final List<String> tags;
  final String initialFeedback;
  final List<Map<String, Object?>> frames;
  final List<Map<String, Object?>> timeline;

  const _Scenario({
    required this.id,
    required this.tags,
    required this.initialFeedback,
    required this.frames,
    required this.timeline,
  });

  factory _Scenario.single({
    required String id,
    required List<String> tags,
    required Map<String, Object?> frame,
    required Map<String, Object?> expectation,
    String initialFeedback = 'none',
  }) => _Scenario(
    id: id,
    tags: tags,
    initialFeedback: initialFeedback,
    frames: <Map<String, Object?>>[frame],
    timeline: <Map<String, Object?>>[expectation],
  );
}
