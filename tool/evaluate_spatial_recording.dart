import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'import_spatial_recording.dart' as recording_import;

/// Offline, shadow-only metrics over user-supplied labels and decisions.
/// This does not verify ground truth, run a model, or deliver any alert.
void main(List<String> arguments) {
  try {
    final manifestPath = _valueAfter(arguments, '--manifest');
    if (manifestPath == null) {
      stderr.writeln(
        'Usage: dart run tool/evaluate_spatial_recording.dart '
        '--manifest <recording-manifest.json> [--output <report.json>]',
      );
      exitCode = 64;
      return;
    }
    final report = evaluateSpatialRecording(manifestPath);
    final rendered = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    final outputPath = _valueAfter(arguments, '--output');
    if (outputPath == null) {
      stdout.write(rendered);
    } else {
      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(rendered);
      stdout.writeln(
        'Wrote offline recording report to ${output.absolute.path}.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('Recording evaluation rejected: $error');
    exitCode = 1;
  }
}

Map<String, Object?> evaluateSpatialRecording(String manifestPath) {
  // Import validates consent, provenance hashes, frame ordering, pairing,
  // relative paths, and the bounded frame-pairs artifact before evaluation.
  final receipt = recording_import.validateSpatialRecordingManifest(
    manifestPath,
  );
  if (receipt['schemaVersion'] != 2) {
    throw const FormatException(
      'Offline evaluation requires recording schema v2.',
    );
  }
  final artifacts = receipt['derivedArtifacts'] as List<dynamic>;
  String artifactPath(String kind, String extension) {
    final matching = artifacts
        .cast<Map<String, Object?>>()
        .where((item) => item['kind'] == kind)
        .toList();
    if (matching.length != 1) {
      throw FormatException('Exactly one $kind artifact is required.');
    }
    final path = matching.single['path'] as String;
    if (!path.toLowerCase().endsWith(extension)) {
      throw FormatException('$kind must be $extension.');
    }
    return '${File(manifestPath).parent.path}${Platform.pathSeparator}$path';
  }

  final pairs = _readJsonl(artifactPath('frame-pairs', '.jsonl'));
  final annotations = _readObject(artifactPath('event-annotations', '.json'));
  final decisions = _readJsonl(artifactPath('shadow-decisions', '.jsonl'));
  final frameCount = pairs.length;
  if (decisions.length != frameCount) {
    throw const FormatException(
      'One explicit shadow decision per frame is required.',
    );
  }

  final labelledPassable = List<bool>.filled(frameCount, false);
  final criticalFrame = List<bool>.filled(frameCount, false);
  final revision = _string(annotations, 'annotationRevision');
  if (_integer(annotations, 'schemaVersion') != 1) {
    throw const FormatException('Unsupported event annotation schema.');
  }
  _onlyKeys(annotations, <String>{
    'schemaVersion',
    'annotationRevision',
    'criticalEvents',
    'passableIntervals',
  }, 'annotations');
  final eventData = _list(annotations, 'criticalEvents');
  final passableData = _list(annotations, 'passableIntervals');
  if (eventData.isEmpty && passableData.isEmpty) {
    throw const FormatException('Annotations have no labelled intervals.');
  }

  final events = <_CriticalEvent>[];
  final eventIds = <String>{};
  for (final value in eventData) {
    final item = _object(value, 'critical event');
    _onlyKeys(item, <String>{
      'hazardId',
      'hazardClass',
      'startFrameIndex',
      'endFrameIndex',
      'latestStopTimestampUs',
    }, 'critical event');
    final id = _string(item, 'hazardId');
    if (!eventIds.add(id)) {
      throw const FormatException('Duplicate critical hazard ID.');
    }
    final start = _integer(item, 'startFrameIndex');
    final end = _integer(item, 'endFrameIndex');
    _validRange(start, end, frameCount);
    final onsetUs = _integer(pairs[start], 'rgbTimestampUs');
    final deadlineUs = _integer(item, 'latestStopTimestampUs');
    if (deadlineUs < onsetUs) {
      throw const FormatException('Critical alert deadline precedes onset.');
    }
    for (var frame = start; frame <= end; frame++) {
      criticalFrame[frame] = true;
    }
    events.add(_CriticalEvent(start, end, onsetUs, deadlineUs));
    _string(item, 'hazardClass');
  }

  for (final value in passableData) {
    final item = _object(value, 'passable interval');
    _onlyKeys(item, <String>{
      'startFrameIndex',
      'endFrameIndex',
    }, 'passable interval');
    final start = _integer(item, 'startFrameIndex');
    final end = _integer(item, 'endFrameIndex');
    _validRange(start, end, frameCount);
    for (var frame = start; frame <= end; frame++) {
      if (criticalFrame[frame] || labelledPassable[frame]) {
        throw const FormatException('Overlapping or contradictory labels.');
      }
      labelledPassable[frame] = true;
    }
  }

  final actions = <String>[];
  final decisionTimesUs = <int>[];
  String? runId;
  String? modelId;
  String? modelHash;
  String? preprocessId;
  const validActions = <String>{
    'stopNow',
    'holdAndScan',
    'continueForward',
    'none',
  };
  for (var index = 0; index < frameCount; index++) {
    final row = decisions[index];
    _onlyKeys(row, <String>{
      'frameIndex',
      'sessionGeneration',
      'frameId',
      'decisionTimestampUs',
      'action',
      'delivery',
      'runId',
      'modelId',
      'modelHash',
      'preprocessId',
    }, 'shadow decision');
    if (_integer(row, 'frameIndex') != index ||
        _integer(row, 'sessionGeneration') !=
            _integer(pairs[index], 'sessionGeneration') ||
        _integer(row, 'frameId') != _integer(pairs[index], 'frameId')) {
      throw FormatException('Decision/frame mismatch at index $index.');
    }
    final decisionUs = _integer(row, 'decisionTimestampUs');
    if (decisionUs < _integer(pairs[index], 'rgbTimestampUs')) {
      throw FormatException('Decision before capture at index $index.');
    }
    final action = _string(row, 'action');
    if (!validActions.contains(action) ||
        _string(row, 'delivery') != 'shadow') {
      throw FormatException('Non-shadow or unknown action at index $index.');
    }
    final currentRunId = _string(row, 'runId');
    final currentModelId = _string(row, 'modelId');
    final currentModelHash = _string(row, 'modelHash');
    final currentPreprocessId = _string(row, 'preprocessId');
    runId ??= currentRunId;
    modelId ??= currentModelId;
    modelHash ??= currentModelHash;
    preprocessId ??= currentPreprocessId;
    if (runId != currentRunId ||
        modelId != currentModelId ||
        modelHash != currentModelHash ||
        preprocessId != currentPreprocessId) {
      throw const FormatException('Mixed prediction-run identity.');
    }
    actions.add(action);
    decisionTimesUs.add(decisionUs);
  }

  var onTimeStops = 0;
  var lateStops = 0;
  var missedStops = 0;
  final alertLatenciesUs = <int>[];
  for (final event in events) {
    int? firstStopUs;
    for (var frame = event.start; frame <= event.end; frame++) {
      if (actions[frame] == 'stopNow') {
        final at = decisionTimesUs[frame];
        firstStopUs = firstStopUs == null ? at : math.min(firstStopUs, at);
      }
    }
    if (firstStopUs == null) {
      missedStops++;
    } else {
      alertLatenciesUs.add(firstStopUs - event.onsetUs);
      if (firstStopUs <= event.deadlineUs) {
        onTimeStops++;
      } else {
        lateStops++;
      }
    }
  }
  alertLatenciesUs.sort();

  var passableFrames = 0;
  var falseStopFrames = 0;
  var degradedPassableFrames = 0;
  var degradedFalseStopFrames = 0;
  var unsafeContinueFrames = 0;
  var unlabelledFrames = 0;
  for (var frame = 0; frame < frameCount; frame++) {
    if (labelledPassable[frame]) {
      passableFrames++;
      if (pairs[frame]['depthStatus'] == 'missing') {
        degradedPassableFrames++;
      }
      if (actions[frame] == 'stopNow') {
        falseStopFrames++;
        if (pairs[frame]['depthStatus'] == 'missing') {
          degradedFalseStopFrames++;
        }
      }
    } else if (criticalFrame[frame]) {
      if (actions[frame] == 'continueForward') unsafeContinueFrames++;
    } else {
      unlabelledFrames++;
    }
  }

  return <String, Object?>{
    'schemaVersion': 1,
    'recordingId': receipt['recordingId'],
    'manifestSha256': receipt['manifestSha256'],
    'annotationRevision': revision,
    'predictionRun': <String, Object>{
      'runId': runId!,
      'modelId': modelId!,
      'modelHash': modelHash!,
      'preprocessId': preprocessId!,
    },
    'capture': receipt['capture'],
    'evidence': <String, Object?>{
      'tier': 'declared-recorded-offline-replay',
      'deviceModelClaim':
          (receipt['capture'] as Map<String, Object>)['deviceModel'],
      'groundTruthIndependentlyVerified': false,
      'namedDeviceRuntimeTested': false,
      'userAlertsEnabled': false,
    },
    'metrics': <String, Object?>{
      'frameCount': frameCount,
      'criticalEvents': events.length,
      'onTimeStops': onTimeStops,
      'lateStops': lateStops,
      'missedStops': missedStops,
      'detectedCriticalRecall': events.isEmpty
          ? null
          : (onTimeStops + lateStops) / events.length,
      'onTimeCriticalRecall': events.isEmpty
          ? null
          : onTimeStops / events.length,
      'passableFrames': passableFrames,
      'falseStopFrames': falseStopFrames,
      'falseStopRate': passableFrames == 0
          ? null
          : falseStopFrames / passableFrames,
      'degradedPassableFrames': degradedPassableFrames,
      'degradedFalseStopFrames': degradedFalseStopFrames,
      'unsafeContinueFrames': unsafeContinueFrames,
      'unlabelledFrames': unlabelledFrames,
      'alertLatencyP50Us': _nearestRank(alertLatenciesUs, 0.5),
      'alertLatencyP90Us': _nearestRank(alertLatenciesUs, 0.9),
    },
    'status': 'evaluated_offline_shadow',
  };
}

class _CriticalEvent {
  final int start;
  final int end;
  final int onsetUs;
  final int deadlineUs;

  const _CriticalEvent(this.start, this.end, this.onsetUs, this.deadlineUs);
}

int? _nearestRank(List<int> sorted, double fraction) {
  if (sorted.isEmpty) return null;
  return sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
}

List<Map<String, dynamic>> _readJsonl(String path) {
  final file = File(path);
  if (file.lengthSync() > 16 * 1024 * 1024) {
    throw const FormatException('JSONL artifact exceeds 16 MiB.');
  }
  final lines = file.readAsLinesSync();
  if (lines.isEmpty) throw const FormatException('JSONL artifact is empty.');
  return <Map<String, dynamic>>[
    for (var i = 0; i < lines.length; i++)
      _object(jsonDecode(lines[i]), 'JSONL line ${i + 1}'),
  ];
}

Map<String, dynamic> _readObject(String path) {
  final file = File(path);
  if (file.lengthSync() > 1024 * 1024) {
    throw const FormatException('Annotations exceed 1 MiB.');
  }
  return _object(jsonDecode(file.readAsStringSync()), 'annotations');
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$label must be an object.');
}

List<dynamic> _list(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is List) return result;
  throw FormatException('$key must be a list.');
}

String _string(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is String && result.trim().isNotEmpty) return result;
  throw FormatException('$key must be a non-empty string.');
}

int _integer(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is int) return result;
  throw FormatException('$key must be an integer.');
}

void _validRange(int start, int end, int frameCount) {
  if (start < 0 || end < start || end >= frameCount) {
    throw const FormatException('Annotation frame range is invalid.');
  }
}

void _onlyKeys(Map<String, dynamic> value, Set<String> allowed, String label) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('Unexpected $label field.');
  }
}

String? _valueAfter(List<String> arguments, String option) {
  final index = arguments.indexOf(option);
  if (index < 0) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw ArgumentError('Missing value after $option.');
  }
  return arguments[index + 1];
}
