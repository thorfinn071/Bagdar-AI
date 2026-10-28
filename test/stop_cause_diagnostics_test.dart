import 'dart:convert';

import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/planning/corridor_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/model_benchmark/stop_cause_diagnostics.dart';

Map<String, Object?> _input({String variant = 'normal'}) => {
  'corpus': 'unit-fixture',
  'sceneId': 'scene',
  'frameId': 1,
  'variant': variant,
  'sampleKind': 'knownSyntheticReplay',
  'runtimeAccepted': true,
  'runtimeStatus': 'accepted',
  'action': 'stopNow',
  'ruleId': 'SPATIAL-P0-AWAIT-STATIONARY',
  'providerHealth': 'healthy',
  'corridorRejections': ['unknownArea'],
  'passageReasons': ['unobservedBody', 'unobservedFloor'],
  'unknownBodyCells': 460,
  'minimumFloorObservedFraction': 0.0,
  'groundSurfaceObservedFraction': .99,
  'positiveCorridor': false,
  'scoringOnly': {'physicalHazard': false, 'referencePassable': true},
};

Map _group(List<Map<String, Object?>> rows) =>
    (summarizeStopDiagnostics(rows)['groups'] as List).single as Map;

void main() {
  test('every current runtime reason has an explicit diagnostic mapping', () {
    expect(
      corridorReasonCategories.keys.toSet(),
      CorridorRejectionReason.values.map((v) => v.name).toSet(),
    );
    expect(
      passageReasonCategories.keys.toSet(),
      PassageClearanceReason.values.map((v) => v.name).toSet(),
    );
    expect(
      detectorReasonCategories.keys.toSet(),
      ObstacleRejectReason.values
          .where(
            (v) =>
                v != ObstacleRejectReason.none &&
                v != ObstacleRejectReason.emptyCorridor,
          )
          .map((v) => v.name)
          .toSet(),
    );
    expect(
      {
        ...corridorReasonCategories.values,
        ...passageReasonCategories.values,
        ...detectorReasonCategories.values,
      }.difference(stopCauseLabels.keys.toSet()),
      isEmpty,
    );
  });

  test(
    'retention never masks simultaneous body and floor coverage failures',
    () {
      final row = diagnoseStopFrame(_input());
      expect(
        row['categories'],
        containsAll([
          'bodyCoverage',
          'floorCoverage',
          'positiveEvidenceMissing',
          'stopRetention',
        ]),
      );
      expect(row['outcome'], 'falseStop');
      // A good patch of ground does not certify the full requested floor.
      expect(
        (row['reportedConditions'] as List).cast<Map>().any(
          (f) =>
              f['source'] == 'minimumFloorObservedFraction' &&
              f['code'] == '0.0',
        ),
        true,
      );
    },
  );

  test(
    'labels change scoring only and relative collision signals stay signals',
    () {
      final original = {
        ..._input(),
        'corridorRejections': ['confirmedObstacle'],
      };
      final before = jsonEncode(original);
      final passable = diagnoseStopFrame(original);
      final hazard = diagnoseStopFrame({
        ...original,
        'scoringOnly': {'physicalHazard': true, 'referencePassable': false},
      });
      expect(jsonEncode(original), before);
      expect(passable['reportedConditions'], hazard['reportedConditions']);
      expect(passable['categories'], contains('obstacleSignal'));
      expect(passable['outcome'], 'falseStop');
      expect(hazard['outcome'], 'hazardStop');
    },
  );

  test('fault interventions cannot inherit passable scoring', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'sampleKind': 'syntheticFaultControl',
    });
    expect(row['outcome'], 'unscored');
    final group = _group([row]);
    expect(group['passableFrames'], 0);
    expect(group['falseStopRate'], isNull);
  });

  test('missing labels are unscored and missing telemetry stays null', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'scoringOnly': null,
      'unknownBodyCells': null,
      'minimumFloorObservedFraction': null,
      'corridorRejections': null,
      'passageReasons': null,
    });
    expect(row['outcome'], 'unscored');
    expect(row['unknownBodyCells'], isNull);
    expect(row['minimumFloorObservedFraction'], isNull);
    expect(row['categories'], isNot(contains('floorCoverage')));
    expect(_group([row])['falseStopRate'], isNull);
  });

  test('rejected input cannot score an old decision as a false stop', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'runtimeAccepted': false,
      'runtimeStatus': 'rejectedStale',
      'providerHealth': 'unavailable',
    });
    expect(row['outcome'], 'unscored');
    expect(row['categories'], contains('sensingUnavailable'));
    expect(_group([row])['rejectedRows'], 1);
  });

  test('stale and nonmetric evidence remain separate and retain raw codes', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'passageReasons': ['staleObservation', 'nonMetricMeasurements'],
      'replayAgeUs': 100001,
    });
    expect(row['categories'], containsAll(['freshness', 'metricCalibration']));
    expect(row['replayAgeUs'], 100001);
    expect(
      (row['reportedConditions'] as List).cast<Map>().any(
        (f) =>
            f['source'] == 'passageReasons' && f['code'] == 'staleObservation',
      ),
      true,
    );
  });

  test('raw depth identity explains a coarse unhealthy producer verdict', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'producerPassageReasons': ['providerUnhealthy'],
      'depthInput': {
        'units': 'metricMeters',
        'modelMatchesCalibration': false,
        'transformMatchesCalibration': true,
        'referenceFrameMatchesCalibration': true,
      },
    });
    expect(row['categories'], containsAll(['identity', 'sensingUnavailable']));
    expect(
      (row['reportedConditions'] as List).cast<Map>().any(
        (f) => f['source'] == 'depthInput.modelMatchesCalibration',
      ),
      true,
    );
  });

  test('new or unexplained reasons remain visible as unclassified', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'passageReasons': ['future_new_reason'],
    });
    expect(row['categories'], contains('unclassified'));
    final unexplained = diagnoseStopFrame({
      'action': 'stopNow',
      'sampleKind': 'syntheticFaultControl',
    });
    expect(unexplained['categories'], ['unclassified']);
  });

  test(
    'duplicate conditions count once per frame but preserve both sources',
    () {
      final row = diagnoseStopFrame({
        ..._input(),
        'producerPassageReasons': ['unobservedBody', 'unobservedBody'],
      });
      expect(
        (_group([row])['conditionsOnFalseStops'] as Map)['bodyCoverage'],
        1,
      );
      expect(
        (row['reportedConditions'] as List)
            .cast<Map>()
            .where((f) => f['code'] == 'unobservedBody')
            .length,
        2,
      );
    },
  );

  test('variants have separate denominators and duplicate decisions fail', () {
    final a = diagnoseStopFrame(_input(variant: 'control'));
    final b = diagnoseStopFrame(_input(variant: 'candidate'));
    final report = summarizeStopDiagnostics([a, b]);
    expect((report['groups'] as List).length, 2);
    expect(
      (report['groups'] as List).cast<Map>().every(
        (g) => g['passableFrames'] == 1,
      ),
      true,
    );
    expect(() => summarizeStopDiagnostics([a, a]), throwsStateError);
  });

  test('hazard non-stops are not counted as stops or passable results', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'action': 'holdAndScan',
      'scoringOnly': {'physicalHazard': true, 'referencePassable': false},
    });
    final group = _group([row]);
    expect(group['hazardStops'], 0);
    expect(group['hazardOtherActions'], 1);
    expect(group['passableFrames'], 0);
  });

  test('clear telemetry has no invented blocker or false stop', () {
    final row = diagnoseStopFrame({
      ..._input(),
      'action': 'continueForward',
      'ruleId': 'SPATIAL-P3-CONTINUE',
      'positiveCorridor': true,
      'corridorRejections': <String>[],
      'passageReasons': <String>[],
      'unknownBodyCells': 0,
      'minimumFloorObservedFraction': 1.0,
    });
    expect(row['categories'], isEmpty);
    expect(row['outcome'], 'passableContinue');
    expect(_group([row])['falseStopRate'], 0);
  });

  test('summary and readable report reproduce without mutation', () {
    final rows = [diagnoseStopFrame(_input())];
    final before = jsonEncode(rows);
    final report = {'summary': summarizeStopDiagnostics(rows), 'frames': rows};
    final first = stopDiagnosticsMarkdown(report);
    expect(stopDiagnosticsMarkdown(report), first);
    expect(jsonEncode(rows), before);
    expect(first, contains('null'));
    expect(first, contains('1 / 1'));
  });
}
