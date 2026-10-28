import 'dart:convert';

/// Offline explanation only: no thresholds, state changes or clearance grants.
/// A category is a reported condition, not proof of its physical root cause.
const stopCauseLabels = <String, String>{
  'obstacleSignal': 'Сигнал препятствия',
  'dropSignal': 'Сигнал перепада',
  'movingThreatSignal': 'Сигнал движущейся угрозы',
  'bodyCoverage': 'Не подтверждён объём тела',
  'floorCoverage': 'Не подтверждён пол',
  'surfaceContinuity': 'Не подтверждена непрерывность поверхности',
  'freshness': 'Возраст, время или задержка',
  'sensingUnavailable': 'Недоступные или отклонённые данные',
  'identity': 'Несогласованные идентификаторы или геометрия',
  'metricCalibration': 'Не подтверждены метры или калибровка',
  'orientation': 'Недопустимая ориентация',
  'confidence': 'Недостаточная уверенность',
  'stopRetention': 'Удержание STOP и повторное подтверждение',
  'positiveEvidenceMissing': 'Нет положительного подтверждения коридора',
  'unclassified': 'Причина требует отдельного разбора',
};

const corridorReasonCategories = <String, String>{
  // "confirmedObstacle" is the candidate enum name. In relative mode it is
  // still a planner signal, never independent physical ground truth.
  'confirmedObstacle': 'obstacleSignal',
  'dropBoundary': 'dropSignal',
  'movingThreatIntersection': 'movingThreatSignal',
  'insufficientObservedWidth': 'bodyCoverage',
  'unknownArea': 'positiveEvidenceMissing',
  'surfaceNotContinuous': 'surfaceContinuity',
  'staleScene': 'freshness',
  'invalidOrientation': 'orientation',
  'unhealthySensing': 'sensingUnavailable',
};

const passageReasonCategories = <String, String>{
  'invalidPolicy': 'sensingUnavailable',
  'invalidRequest': 'sensingUnavailable',
  'invalidContext': 'identity',
  'missingCalibration': 'metricCalibration',
  'unverifiedCalibration': 'metricCalibration',
  'missingObservation': 'sensingUnavailable',
  'invalidIdentity': 'identity',
  'providerUnhealthy': 'sensingUnavailable',
  'nonMetricMeasurements': 'metricCalibration',
  'calibrationMismatch': 'metricCalibration',
  'modelMismatch': 'identity',
  'referenceFrameMismatch': 'identity',
  'transformMismatch': 'identity',
  'clockMismatch': 'freshness',
  'sessionMismatch': 'identity',
  'frameMismatch': 'identity',
  'invalidTimestamp': 'freshness',
  'futureObservation': 'freshness',
  'staleObservation': 'freshness',
  'pairSkew': 'freshness',
  'processingLatency': 'freshness',
  'missingSections': 'bodyCoverage',
  'tooManySections': 'sensingUnavailable',
  'invalidSection': 'sensingUnavailable',
  'missingMeasurements': 'sensingUnavailable',
  'insufficientConfidence': 'confidence',
  'unobservedBody': 'bodyCoverage',
  'unobservedFloor': 'floorCoverage',
  'conflictingMeasurements': 'sensingUnavailable',
  'blockedSection': 'obstacleSignal',
  'narrowPassage': 'obstacleSignal',
  'corridorOutsideOpening': 'obstacleSignal',
  'insufficientHeadroom': 'obstacleSignal',
  'floorRise': 'dropSignal',
  'floorDrop': 'dropSignal',
  'coverageGap': 'bodyCoverage',
};

const detectorReasonCategories = <String, String>{
  'detectorOff': 'sensingUnavailable',
  'noFrame': 'sensingUnavailable',
  'unaligned': 'identity',
  'stale': 'freshness',
  'lowCoverage': 'bodyCoverage',
  'lowConfidence': 'confidence',
  'degenerate': 'sensingUnavailable',
  'planeUnreliable': 'surfaceContinuity',
};

const _retentionRules = {
  'SPATIAL-P0-AWAIT-STATIONARY',
  'SPATIAL-P2-POST-STOP-SCAN',
  'SPATIAL-P2-UNCERTAIN-STOP-SCAN',
  'SPATIAL-P2-RECOVERY-PENDING',
};

/// Input is a copied telemetry row. Labels affect scoring only, after diagnosis.
/// Missing telemetry stays null; lack of a reported cause never means clear.
Map<String, Object?> diagnoseStopFrame(Map<String, Object?> input) {
  final facts = <Map<String, String>>[];
  void add(String category, String source, String code) =>
      facts.add({'category': category, 'source': source, 'code': code});
  void reasons(String key, Map<String, String> mapping) {
    final values = input[key] as List?;
    if (values == null) return;
    for (final code in values.cast<String>().toSet()) {
      add(mapping[code] ?? 'unclassified', key, code);
    }
  }

  reasons('corridorRejections', corridorReasonCategories);
  reasons('passageReasons', passageReasonCategories);
  reasons('producerPassageReasons', passageReasonCategories);
  final depth = input['depthInput'] as Map?;
  if (depth != null) {
    if (depth['units'] != null && depth['units'] != 'metricMeters') {
      add('metricCalibration', 'depthInput.units', depth['units'] as String);
    }
    if (depth['providerHealthy'] == false) {
      add('sensingUnavailable', 'depthInput.providerHealthy', 'false');
    }
    for (final check in [
      'modelMatchesCalibration',
      'transformMatchesCalibration',
      'referenceFrameMatchesCalibration',
    ]) {
      if (depth[check] == false) add('identity', 'depthInput.$check', 'false');
    }
  }
  final detectorReason = input['detectorRejectReason'] as String?;
  if (detectorReason != null &&
      !{'none', 'emptyCorridor'}.contains(detectorReason)) {
    add(
      detectorReasonCategories[detectorReason] ?? 'unclassified',
      'detectorRejectReason',
      detectorReason,
    );
  }
  final health = input['providerHealth'];
  if (health != null && health != 'healthy') {
    add('sensingUnavailable', 'providerHealth', health as String);
  }
  if (input['runtimeAccepted'] == false) {
    add(
      'sensingUnavailable',
      'runtimeStatus',
      input['runtimeStatus'] as String,
    );
  }
  if ((input['unknownBodyCells'] as num?) case final n? when n > 0) {
    add('bodyCoverage', 'unknownBodyCells', '$n');
  }
  if ((input['minimumFloorObservedFraction'] as num?) case final n?
      when n < 1) {
    add('floorCoverage', 'minimumFloorObservedFraction', '$n');
  }
  if (input['positiveCorridor'] == false) {
    add('positiveEvidenceMissing', 'positiveCorridor', 'false');
  }
  if (_retentionRules.contains(input['ruleId'])) {
    add('stopRetention', 'ruleId', input['ruleId'] as String);
  }
  if (input['ruleId'] == 'SPATIAL-P1-UNVERIFIED-OBSTRUCTION') {
    add('positiveEvidenceMissing', 'ruleId', input['ruleId'] as String);
  }
  final isStop = input['action'] == 'stopNow';
  if (isStop && facts.isEmpty) {
    add('unclassified', 'action', 'stop_without_reported_condition');
  }
  final categories = facts.map((f) => f['category']!).toSet().toList()..sort();

  // Never score altered fault inputs against the original scene's label.
  final scoreable =
      input['sampleKind'] == 'knownSyntheticReplay' &&
      input['runtimeAccepted'] == true &&
      input['action'] != null;
  final label = input['scoringOnly'] as Map?;
  final hazard = label?['physicalHazard'];
  final passable = label?['referencePassable'];
  final outcome = !scoreable || label == null
      ? 'unscored'
      : hazard == true
      ? isStop
            ? 'hazardStop'
            : input['action'] == 'continueForward'
            ? 'hazardContinue'
            : 'hazardOtherAction'
      : hazard == false && passable == true
      ? isStop
            ? 'falseStop'
            : input['action'] == 'continueForward'
            ? 'passableContinue'
            : 'passableOtherAction'
      : 'unscored';
  return {
    ...input,
    'reportedConditions': facts,
    'categories': categories,
    'outcome': outcome,
  };
}

/// Summaries stay separate by corpus, runtime variant and sample kind. Modes
/// and fault trials must not inflate an independent-frame denominator.
Map<String, Object?> summarizeStopDiagnostics(List<Map<String, Object?>> rows) {
  final groups = <String, List<Map<String, Object?>>>{};
  final identities = <String>{};
  for (final row in rows) {
    final identity = jsonEncode([
      row['corpus'],
      row['sceneId'],
      row['frameId'],
      row['variant'],
      row['sampleKind'],
    ]);
    if (!identities.add(identity)) {
      throw StateError('Duplicate diagnostic decision $identity');
    }
    final key = jsonEncode([row['corpus'], row['variant'], row['sampleKind']]);
    groups.putIfAbsent(key, () => []).add(row);
  }
  return {
    'decisionRows': rows.length,
    'groups': [for (final group in groups.values) _summarizeGroup(group)],
    'counting':
        'Conditions overlap; counts are decision rows, not unique causal attributions. '
        'Scoring is separate per corpus/variant; fault controls are unscored.',
  };
}

Map<String, Object?> _summarizeGroup(List<Map<String, Object?>> rows) {
  int count(String value) => rows.where((r) => r['outcome'] == value).length;
  final falseStops = rows.where((r) => r['outcome'] == 'falseStop').toList();
  final passable =
      falseStops.length +
      count('passableContinue') +
      count('passableOtherAction');
  final hazards =
      count('hazardStop') +
      count('hazardContinue') +
      count('hazardOtherAction');
  return {
    'corpus': rows.first['corpus'],
    'variant': rows.first['variant'],
    'sampleKind': rows.first['sampleKind'],
    'decisionRows': rows.length,
    'sceneCount': rows.map((r) => r['sceneId']).toSet().length,
    'stopRows': rows.where((r) => r['action'] == 'stopNow').length,
    'rejectedRows': rows.where((r) => r['runtimeAccepted'] == false).length,
    'unscoredRows': count('unscored'),
    'passableFrames': passable,
    'falseStops': falseStops.length,
    'falseStopRate': passable == 0 ? null : falseStops.length / passable,
    'hazardFrames': hazards,
    'hazardStops': count('hazardStop'),
    'hazardContinues': count('hazardContinue'),
    'hazardOtherActions': count('hazardOtherAction'),
    'conditionsOnFalseStops': {
      for (final key in stopCauseLabels.keys)
        key: falseStops
            .where((r) => (r['categories'] as List).contains(key))
            .length,
    },
    'scenes': [
      for (final scene in rows.map((r) => r['sceneId']).toSet())
        {
          'sceneId': scene,
          'decisionRows': rows.where((r) => r['sceneId'] == scene).length,
          'falseStops': falseStops.where((r) => r['sceneId'] == scene).length,
          'conditions':
              rows
                  .where((r) => r['sceneId'] == scene)
                  .expand((r) => (r['categories'] as List).cast<String>())
                  .toSet()
                  .toList()
                ..sort(),
        },
    ],
  };
}

String stopDiagnosticsMarkdown(Map<String, Object?> report) {
  final summary = report['summary'] as Map;
  final out = StringBuffer(
    '# Диагностика STOP\n\n'
    'Текущая реализация на известных синтетических сценах. '
    'Повторный inference, новый holdout, iPhone/Android и ходьба не проверялись. '
    'Доставка — shadow; условия безопасности не менялись.\n\n'
    'Категории показывают сообщённые условия, а не доказанную физическую '
    'причину. Один кадр может иметь несколько условий. Относительный сигнал '
    'препятствия не считается независимым подтверждением опасности.\n\n'
    '| Корпус / вариант | Кадры | Ложные STOP / свободные | STOP / опасные | '
    'CONTINUE на опасных | Без оценки |\n|---|---:|---:|---:|---:|---:|\n',
  );
  for (final g in (summary['groups'] as List).cast<Map>()) {
    out.writeln(
      '| ${g['corpus']} / ${g['variant']} | ${g['decisionRows']} | '
      '${g['falseStops']} / ${g['passableFrames']} | '
      '${g['hazardStops']} / ${g['hazardFrames']} | '
      '${g['hazardContinues']} | ${g['unscoredRows']} |',
    );
  }
  out.writeln('\n## Условия на ложных STOP\n');
  for (final g in (summary['groups'] as List).cast<Map>()) {
    if (g['falseStops'] == 0) continue;
    out.writeln('**${g['corpus']} / ${g['variant']}**\n');
    final counts =
        (g['conditionsOnFalseStops'] as Map).entries
            .where((e) => e.value as int > 0)
            .toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    for (final e in counts) {
      out.writeln(
        '- ${stopCauseLabels[e.key]}: ${e.value}/${g['falseStops']}.',
      );
    }
    out.writeln();
  }
  out.writeln(
    '## Покадровый разбор\n\n'
    'Полные значения и исходные коды — в `frames.jsonl`. '
    'Пропущенные измерения сохраняются как null. '
    'Время решений задаёт replay; это не задержка телефона.\n\n'
    '| Сцена / кадр / вариант | Действие | Оценка | Сообщённые условия |\n'
    '|---|---|---|---|',
  );
  for (final r in (report['frames'] as List).cast<Map>()) {
    final categories = (r['categories'] as List).cast<String>();
    out.writeln(
      '| ${r['sceneId']} / ${r['frameId']} / ${r['variant']} | '
      '${r['action'] ?? 'нет решения'} | ${r['outcome']} | '
      '${categories.map((c) => stopCauseLabels[c]!).join('; ')} |',
    );
  }
  return out.toString();
}
