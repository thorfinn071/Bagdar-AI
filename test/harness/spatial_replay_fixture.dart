import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const int spatialReplaySchemaVersion = 1;

enum SpatialScenarioCoverage { complete, partial }

enum SpatialExternalAvailability { available, missing }

class SpatialModelContract {
  final String modelId;
  final String modelHash;
  final String preprocessId;

  const SpatialModelContract({
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
  });

  factory SpatialModelContract.fromJson(Map<String, Object?> json) =>
      SpatialModelContract(
        modelId: _requiredString(json, 'modelId'),
        modelHash: _requiredSha256(json, 'modelHash'),
        preprocessId: _requiredString(json, 'preprocessId'),
      );
}

class SpatialSceneManifest {
  final String id;
  final String kind;
  final String framesPath;
  final String annotationsPath;
  final String framesSha256;
  final String annotationsSha256;
  final List<String> tags;
  final int annotationRevision;
  final bool requiredForRc;
  final SpatialScenarioCoverage coverage;

  SpatialSceneManifest({
    required this.id,
    required this.kind,
    required this.framesPath,
    required this.annotationsPath,
    required this.framesSha256,
    required this.annotationsSha256,
    required List<String> tags,
    required this.annotationRevision,
    required this.requiredForRc,
    required this.coverage,
  }) : tags = List.unmodifiable(tags);

  factory SpatialSceneManifest.fromJson(Map<String, Object?> json) {
    final hashes = _requiredMap(json, 'sha256');
    return SpatialSceneManifest(
      id: _requiredString(json, 'id'),
      kind: _requiredString(json, 'kind'),
      framesPath: _requiredSafeRelativePath(json, 'frames'),
      annotationsPath: _requiredSafeRelativePath(json, 'annotations'),
      framesSha256: _requiredSha256(hashes, 'frames'),
      annotationsSha256: _requiredSha256(hashes, 'annotations'),
      tags: _requiredStringList(json, 'tags'),
      annotationRevision: _requiredPositiveInt(json, 'annotationRevision'),
      requiredForRc: _requiredBool(json, 'requiredForRc'),
      coverage: _enumByName(
        SpatialScenarioCoverage.values,
        _requiredString(json, 'coverage'),
        'coverage',
      ),
    );
  }
}

class SpatialExternalCorpus {
  final String id;
  final String source;
  final String handling;
  final String consentClass;
  final bool requiredForRc;
  final SpatialExternalAvailability availability;
  final String? manifestPath;
  final String? manifestSha256;

  SpatialExternalCorpus({
    required this.id,
    required this.source,
    required this.handling,
    required this.consentClass,
    required this.requiredForRc,
    required this.availability,
    this.manifestPath,
    this.manifestSha256,
  }) {
    if (availability == SpatialExternalAvailability.available &&
        (manifestPath == null || manifestSha256 == null)) {
      throw const FormatException(
        'Available external corpus requires manifestPath and manifestSha256.',
      );
    }
  }

  factory SpatialExternalCorpus.fromJson(Map<String, Object?> json) {
    final availability = _enumByName(
      SpatialExternalAvailability.values,
      _requiredString(json, 'availability'),
      'availability',
    );
    return SpatialExternalCorpus(
        id: _requiredString(json, 'id'),
        source: _requiredString(json, 'source'),
        handling: _requiredString(json, 'handling'),
        consentClass: _requiredString(json, 'consentClass'),
        requiredForRc: _requiredBool(json, 'requiredForRc'),
        availability: availability,
        manifestPath: availability == SpatialExternalAvailability.available
            ? _requiredSafeRelativePath(json, 'manifestPath')
            : null,
        manifestSha256: availability == SpatialExternalAvailability.available
            ? _requiredSha256(json, 'manifestSha256')
            : null,
      );
  }
}

class SpatialReplayManifest {
  final String manifestPath;
  final int schemaVersion;
  final String corpusId;
  final int seed;
  final String generatorId;
  final String sourceType;
  final String sourceLicense;
  final String consentClass;
  final String handling;
  final String cameraMount;
  final String cameraParameters;
  final String coordinateMode;
  final DateTime timelineOriginUtc;
  final SpatialModelContract modelContract;
  final List<SpatialSceneManifest> scenes;
  final List<SpatialExternalCorpus> externalCorpora;

  SpatialReplayManifest({
    required this.manifestPath,
    required this.schemaVersion,
    required this.corpusId,
    required this.seed,
    required this.generatorId,
    required this.sourceType,
    required this.sourceLicense,
    required this.consentClass,
    required this.handling,
    required this.cameraMount,
    required this.cameraParameters,
    required this.coordinateMode,
    required this.timelineOriginUtc,
    required this.modelContract,
    required List<SpatialSceneManifest> scenes,
    required List<SpatialExternalCorpus> externalCorpora,
  }) : scenes = List.unmodifiable(scenes),
       externalCorpora = List.unmodifiable(externalCorpora) {
    if (schemaVersion != spatialReplaySchemaVersion) {
      throw FormatException(
        'Unsupported spatial replay schema $schemaVersion; '
        'expected $spatialReplaySchemaVersion.',
      );
    }
    if (!timelineOriginUtc.isUtc) {
      throw const FormatException('timelineOriginUtc must be UTC.');
    }
    if (scenes.isEmpty) {
      throw const FormatException('Spatial corpus must contain scenes.');
    }
    final ids = <String>{};
    for (final scene in scenes) {
      if (!ids.add(scene.id)) {
        throw FormatException('Duplicate spatial scene id: ${scene.id}.');
      }
    }
  }

  factory SpatialReplayManifest.load(String manifestPath) {
    final file = File(manifestPath);
    if (!file.existsSync()) {
      throw FileSystemException('Spatial manifest is missing', manifestPath);
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Spatial manifest root must be an object.');
    }
    return SpatialReplayManifest.fromJson(decoded, manifestPath: manifestPath);
  }

  factory SpatialReplayManifest.fromJson(
    Map<String, Object?> json, {
    required String manifestPath,
  }) {
    final source = _requiredMap(json, 'source');
    final camera = _requiredMap(json, 'camera');
    final rawOrigin = _requiredString(json, 'timelineOriginUtc');
    final origin = DateTime.tryParse(rawOrigin);
    if (origin == null) {
      throw FormatException('Invalid timelineOriginUtc: $rawOrigin.');
    }
    final rawScenes = _requiredList(json, 'scenes');
    final rawExternal = _requiredList(json, 'externalCorpora');
    return SpatialReplayManifest(
      manifestPath: manifestPath,
      schemaVersion: _requiredPositiveInt(json, 'schemaVersion'),
      corpusId: _requiredString(json, 'corpusId'),
      seed: _requiredPositiveInt(json, 'seed'),
      generatorId: _requiredString(json, 'generatorId'),
      sourceType: _requiredString(source, 'type'),
      sourceLicense: _requiredString(source, 'license'),
      consentClass: _requiredString(source, 'consentClass'),
      handling: _requiredString(json, 'handling'),
      cameraMount: _requiredString(camera, 'mount'),
      cameraParameters: _requiredString(camera, 'parameters'),
      coordinateMode: _requiredString(camera, 'coordinateMode'),
      timelineOriginUtc: origin.toUtc(),
      modelContract: SpatialModelContract.fromJson(
        _requiredMap(json, 'modelContract'),
      ),
      scenes: rawScenes
          .map((entry) => SpatialSceneManifest.fromJson(_asMap(entry, 'scene')))
          .toList(growable: false),
      externalCorpora: rawExternal
          .map(
            (entry) => SpatialExternalCorpus.fromJson(
              _asMap(entry, 'external corpus'),
            ),
          )
          .toList(growable: false),
    );
  }

  String get rootDirectory {
    final normalized = manifestPath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '.' : normalized.substring(0, slash);
  }

  String resolve(String relativePath) =>
      '$rootDirectory/${relativePath.replaceAll('\\', '/')}';
}

class SpatialSectorSample {
  final double observedFraction;
  final double occupancyProbability;
  final double traversabilityProbability;
  final double dropProbability;
  final double movingThreatRisk;
  final double unknownProbability;
  final double confidence;
  final List<String> sourceMask;
  final List<String> hazardIds;
  final int lastObservedOffsetMs;

  SpatialSectorSample({
    required this.observedFraction,
    required this.occupancyProbability,
    required this.traversabilityProbability,
    required this.dropProbability,
    required this.movingThreatRisk,
    required this.unknownProbability,
    required this.confidence,
    required List<String> sourceMask,
    required List<String> hazardIds,
    required this.lastObservedOffsetMs,
  }) : sourceMask = List.unmodifiable(sourceMask),
       hazardIds = List.unmodifiable(hazardIds);

  factory SpatialSectorSample.fromJson(
    Map<String, Object?> json,
  ) => SpatialSectorSample(
    observedFraction: _requiredProbability(json, 'observedFraction'),
    occupancyProbability: _requiredProbability(json, 'occupancyProbability'),
    traversabilityProbability: _requiredProbability(
      json,
      'traversabilityProbability',
    ),
    dropProbability: _requiredProbability(json, 'dropProbability'),
    movingThreatRisk: _requiredProbability(json, 'movingThreatRisk'),
    unknownProbability: _requiredProbability(json, 'unknownProbability'),
    confidence: _requiredProbability(json, 'confidence'),
    sourceMask: _requiredStringList(json, 'sourceMask'),
    hazardIds: _requiredStringList(json, 'hazardIds'),
    lastObservedOffsetMs: _requiredNonNegativeInt(json, 'lastObservedOffsetMs'),
  );
}

class SpatialReplayFrame {
  final String sceneId;
  final int frameIndex;
  final int capturedOffsetMs;
  final int evaluateOffsetMs;
  final int validUntilOffsetMs;
  final int sessionGeneration;
  final int frameId;
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final bool orientationValid;
  final bool sensingHealthy;
  final bool userMoving;
  final Map<String, SpatialSectorSample> sectors;

  SpatialReplayFrame({
    required this.sceneId,
    required this.frameIndex,
    required this.capturedOffsetMs,
    required this.evaluateOffsetMs,
    required this.validUntilOffsetMs,
    required this.sessionGeneration,
    required this.frameId,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    required this.orientationValid,
    required this.sensingHealthy,
    required this.userMoving,
    required Map<String, SpatialSectorSample> sectors,
  }) : sectors = Map.unmodifiable(sectors) {
    if (evaluateOffsetMs < capturedOffsetMs) {
      throw FormatException(
        '$sceneId frame $frameIndex evaluates before capture.',
      );
    }
    if (validUntilOffsetMs < capturedOffsetMs) {
      throw FormatException(
        '$sceneId frame $frameIndex expires before capture.',
      );
    }
    const requiredSectors = {'left', 'forward', 'right'};
    if (sectors.keys.toSet().difference(requiredSectors).isNotEmpty ||
        requiredSectors.difference(sectors.keys.toSet()).isNotEmpty) {
      throw FormatException(
        '$sceneId frame $frameIndex must define only left, forward, right.',
      );
    }
  }

  factory SpatialReplayFrame.fromJson(Map<String, Object?> json) {
    _requireSpatialSchema(json, 'frame');
    final sceneId = _requiredString(json, 'sceneId');
    final frameIndex = _requiredNonNegativeInt(json, 'frameIndex');
    final rawSectors = _requiredMap(json, 'sectors');
    return SpatialReplayFrame(
      sceneId: sceneId,
      frameIndex: frameIndex,
      capturedOffsetMs: _requiredNonNegativeInt(json, 'capturedOffsetMs'),
      evaluateOffsetMs: _requiredNonNegativeInt(json, 'evaluateOffsetMs'),
      validUntilOffsetMs: _requiredNonNegativeInt(json, 'validUntilOffsetMs'),
      sessionGeneration: _requiredPositiveInt(json, 'sessionGeneration'),
      frameId: _requiredPositiveInt(json, 'frameId'),
      modelId: _requiredString(json, 'modelId'),
      modelHash: _requiredSha256(json, 'modelHash'),
      preprocessId: _requiredString(json, 'preprocessId'),
      orientationValid: _requiredBool(json, 'orientationValid'),
      sensingHealthy: _requiredBool(json, 'sensingHealthy'),
      userMoving: _requiredBool(json, 'userMoving'),
      sectors: rawSectors.map(
        (key, value) => MapEntry(
          key,
          SpatialSectorSample.fromJson(_asMap(value, '$sceneId.$key')),
        ),
      ),
    );
  }
}

class SpatialTimelineExpectation {
  final int startOffsetMs;
  final int endOffsetMs;
  final List<String> expectedActions;
  final List<String> forbiddenActions;
  final List<String> expectedHealth;
  final List<String> expectedAlertEvents;
  final List<String> expectedShadowDirections;
  final bool? interruptCurrent;

  SpatialTimelineExpectation({
    required this.startOffsetMs,
    required this.endOffsetMs,
    required List<String> expectedActions,
    required List<String> forbiddenActions,
    required List<String> expectedHealth,
    required List<String> expectedAlertEvents,
    required List<String> expectedShadowDirections,
    required this.interruptCurrent,
  }) : expectedActions = List.unmodifiable(expectedActions),
       forbiddenActions = List.unmodifiable(forbiddenActions),
       expectedHealth = List.unmodifiable(expectedHealth),
       expectedAlertEvents = List.unmodifiable(expectedAlertEvents),
       expectedShadowDirections = List.unmodifiable(expectedShadowDirections) {
    if (endOffsetMs < startOffsetMs) {
      throw const FormatException('Timeline range end precedes start.');
    }
    if (expectedActions.isEmpty || expectedHealth.isEmpty) {
      throw const FormatException(
        'Timeline expectations require actions and health.',
      );
    }
    final overlap = expectedActions.toSet().intersection(
      forbiddenActions.toSet(),
    );
    if (overlap.isNotEmpty) {
      throw FormatException(
        'Actions cannot be expected and forbidden: ${overlap.join(', ')}.',
      );
    }
  }

  factory SpatialTimelineExpectation.fromJson(Map<String, Object?> json) =>
      SpatialTimelineExpectation(
        startOffsetMs: _requiredNonNegativeInt(json, 'startOffsetMs'),
        endOffsetMs: _requiredNonNegativeInt(json, 'endOffsetMs'),
        expectedActions: _requiredStringList(json, 'expectedActions'),
        forbiddenActions: _requiredStringList(json, 'forbiddenActions'),
        expectedHealth: _requiredStringList(json, 'expectedHealth'),
        expectedAlertEvents: _requiredStringList(json, 'expectedAlertEvents'),
        expectedShadowDirections: _requiredStringList(
          json,
          'expectedShadowDirections',
        ),
        interruptCurrent: json['interruptCurrent'] == null
            ? null
            : _requiredBool(json, 'interruptCurrent'),
      );

  bool contains(int offsetMs) =>
      offsetMs >= startOffsetMs && offsetMs <= endOffsetMs;
}

class SpatialScenarioAnnotations {
  final String sceneId;
  final int annotationRevision;
  final String initialFeedback;
  final List<SpatialTimelineExpectation> timeline;

  SpatialScenarioAnnotations({
    required this.sceneId,
    required this.annotationRevision,
    required this.initialFeedback,
    required List<SpatialTimelineExpectation> timeline,
  }) : timeline = List.unmodifiable(timeline) {
    if (timeline.isEmpty) {
      throw FormatException('$sceneId annotation timeline is empty.');
    }
    final sorted = [...timeline]
      ..sort((a, b) => a.startOffsetMs.compareTo(b.startOffsetMs));
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index].startOffsetMs <= sorted[index - 1].endOffsetMs) {
        throw FormatException('$sceneId annotation timeline overlaps.');
      }
    }
  }

  factory SpatialScenarioAnnotations.fromJson(Map<String, Object?> json) {
    _requireSpatialSchema(json, 'annotations');
    return SpatialScenarioAnnotations(
      sceneId: _requiredString(json, 'sceneId'),
      annotationRevision: _requiredPositiveInt(json, 'annotationRevision'),
      initialFeedback: _requiredString(json, 'initialFeedback'),
      timeline: _requiredList(json, 'timeline')
          .map(
            (entry) => SpatialTimelineExpectation.fromJson(
              _asMap(entry, 'timeline entry'),
            ),
          )
          .toList(growable: false),
    );
  }

  SpatialTimelineExpectation expectationAt(int offsetMs) =>
      timeline.where((expectation) => expectation.contains(offsetMs)).single;
}

class SpatialReplayFixture {
  final SpatialReplayManifest manifest;

  const SpatialReplayFixture(this.manifest);

  factory SpatialReplayFixture.load(String manifestPath) =>
      SpatialReplayFixture(SpatialReplayManifest.load(manifestPath));

  bool sceneFilesExist(SpatialSceneManifest scene) =>
      File(manifest.resolve(scene.framesPath)).existsSync() &&
      File(manifest.resolve(scene.annotationsPath)).existsSync();

  List<String> validateSceneFiles(SpatialSceneManifest scene) {
    final violations = <String>[];
    final frames = File(manifest.resolve(scene.framesPath));
    final annotations = File(manifest.resolve(scene.annotationsPath));
    if (!frames.existsSync()) {
      violations.add('missing_frames:${scene.framesPath}');
    } else if (_sha256(frames) != scene.framesSha256) {
      violations.add('frames_hash_mismatch:${scene.framesPath}');
    }
    if (!annotations.existsSync()) {
      violations.add('missing_annotations:${scene.annotationsPath}');
    } else if (_sha256(annotations) != scene.annotationsSha256) {
      violations.add('annotations_hash_mismatch:${scene.annotationsPath}');
    }
    return violations;
  }

  List<String> validateExternalCorpus(SpatialExternalCorpus corpus) {
    if (corpus.availability != SpatialExternalAvailability.available) {
      return const <String>[];
    }
    final relative = corpus.manifestPath!;
    final file = File(manifest.resolve(relative));
    if (!file.existsSync()) {
      return <String>['missing_external_manifest:$relative'];
    }
    if (_sha256(file) != corpus.manifestSha256) {
      return <String>['external_manifest_hash_mismatch:$relative'];
    }
    return const <String>[];
  }

  List<SpatialReplayFrame> loadFrames(SpatialSceneManifest scene) {
    final file = File(manifest.resolve(scene.framesPath));
    final frames = <SpatialReplayFrame>[];
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('${scene.id} frame line must be an object.');
      }
      frames.add(SpatialReplayFrame.fromJson(decoded));
    }
    if (frames.isEmpty) {
      throw FormatException('${scene.id} contains no replay frames.');
    }
    frames.sort((a, b) => a.evaluateOffsetMs.compareTo(b.evaluateOffsetMs));
    for (var index = 0; index < frames.length; index++) {
      final frame = frames[index];
      if (frame.sceneId != scene.id) {
        throw FormatException(
          '${scene.id} contains frame for ${frame.sceneId}.',
        );
      }
      if (frame.frameIndex != index) {
        throw FormatException(
          '${scene.id} frame indexes must be contiguous from zero.',
        );
      }
      if (index > 0 && frame.frameId <= frames[index - 1].frameId) {
        throw FormatException(
          '${scene.id} frame IDs must increase monotonically.',
        );
      }
      if (frame.sessionGeneration != frames.first.sessionGeneration) {
        throw FormatException('${scene.id} mixes camera session generations.');
      }
      if (frame.modelId != manifest.modelContract.modelId ||
          frame.modelHash != manifest.modelContract.modelHash ||
          frame.preprocessId != manifest.modelContract.preprocessId) {
        throw FormatException(
          '${scene.id} frame $index model/preprocess identity mismatch.',
        );
      }
    }
    return List.unmodifiable(frames);
  }

  SpatialScenarioAnnotations loadAnnotations(SpatialSceneManifest scene) {
    final decoded = jsonDecode(
      File(manifest.resolve(scene.annotationsPath)).readAsStringSync(),
    );
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('${scene.id} annotations must be an object.');
    }
    final annotations = SpatialScenarioAnnotations.fromJson(decoded);
    if (annotations.sceneId != scene.id) {
      throw FormatException(
        '${scene.id} has annotations for ${annotations.sceneId}.',
      );
    }
    if (annotations.annotationRevision != scene.annotationRevision) {
      throw FormatException('${scene.id} annotation revision mismatch.');
    }
    return annotations;
  }

  String _sha256(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<String, Object?>) return value;
  throw FormatException('$field must be an object.');
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) =>
    _asMap(json[key], key);

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List) return value.cast<Object?>();
  throw FormatException('$key must be an array.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$key must be a non-empty string.');
}

String _requiredSha256(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw FormatException('$key must be a lowercase SHA-256 digest.');
  }
  return value;
}

String _requiredSafeRelativePath(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key).replaceAll('\\', '/');
  final segments = value.split('/');
  if (value.startsWith('/') ||
      value.contains(':') ||
      segments.any((segment) => segment.isEmpty || segment == '..')) {
    throw FormatException('$key must be a safe relative path.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('$key must be a positive integer.');
}

int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw FormatException('$key must be a non-negative integer.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('$key must be a boolean.');
}

double _requiredProbability(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    final result = value.toDouble();
    if (result.isFinite && result >= 0 && result <= 1) return result;
  }
  throw FormatException('$key must be a finite probability from 0 to 1.');
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final values = _requiredList(json, key);
  final result = <String>[];
  for (final value in values) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must contain only non-empty strings.');
    }
    result.add(value);
  }
  return result;
}

T _enumByName<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$field has unsupported value: $name.');
}

void _requireSpatialSchema(Map<String, Object?> json, String subject) {
  final version = _requiredPositiveInt(json, 'schemaVersion');
  if (version != spatialReplaySchemaVersion) {
    throw FormatException(
      '$subject uses unsupported schema $version; '
      'expected $spatialReplaySchemaVersion.',
    );
  }
}
