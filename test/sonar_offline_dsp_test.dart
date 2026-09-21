import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bagdar/services/sonar_offline_dsp.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'test/fixtures/sonar_dsp/fixtures.json';

void main() {
  final fixture = _loadFixture();

  test('versioned waveform fixtures pass the offline reference DSP', () {
    expect(fixture['schemaVersion'], 1);
    expect(fixture['generatorId'], 'bagdar-sonar-waveform-recipes-v1');
    final reference = _numbers(fixture['reference']);
    final captureSamples = fixture['captureSamples'] as int;
    final cases = fixture['cases'] as List<dynamic>;
    for (var index = 0; index < cases.length; index++) {
      final recipe = (cases[index] as Map).cast<String, dynamic>();
      final input = _synthesize(
        recipe,
        reference: reference,
        captureSamples: captureSamples,
        sequence: index,
      );
      final result = const SonarOfflineDsp().process(input);
      if (recipe['expected'] == 'accepted') {
        expect(result.accepted, isTrue, reason: recipe['id'] as String);
        expect(
          result.echoLagSamples,
          recipe['expectedEchoLag'],
          reason: recipe['id'] as String,
        );
        expect(result.rangeM, greaterThan(0));
      } else {
        expect(result.accepted, isFalse, reason: recipe['id'] as String);
        expect(result.reason, recipe['expectedReason']);
      }
    }
  });

  test('direct-path peak is cancelled and never reported as an obstacle', () {
    final recipe = ((fixture['cases'] as List<dynamic>).last as Map)
        .cast<String, dynamic>();
    final result = const SonarOfflineDsp().process(
      _synthesize(
        recipe,
        reference: _numbers(fixture['reference']),
        captureSamples: fixture['captureSamples'] as int,
        sequence: 0,
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.directPathLagSamples, recipe['directLag']);
    expect(result.echoLagSamples, isNull);
  });

  test('strong late multipath never replaces a supported nearer echo', () {
    final recipe = ((fixture['cases'] as List<dynamic>)[1] as Map)
        .cast<String, dynamic>();
    final result = const SonarOfflineDsp().process(
      _synthesize(
        recipe,
        reference: _numbers(fixture['reference']),
        captureSamples: fixture['captureSamples'] as int,
        sequence: 1,
      ),
    );
    expect(result.accepted, isTrue);
    expect(result.echoLagSamples, 48);
    expect(result.peaks.any((peak) => peak.lagSamples == 104), isTrue);
  });

  test('malformed capability identity fails closed', () {
    final input = SonarOfflineDspInput(
      identity: SonarWaveformIdentity(
        sequence: 1,
        capturedAt: DateTime.utc(2026, 9, 21),
        sampleRateHz: 44100,
        inputRoute: 'unknown',
        outputRoute: 'speaker:2',
      ),
      reference: List<double>.filled(16, 1),
      recorded: List<double>.filled(64, 0),
    );
    final result = const SonarOfflineDsp().process(input);
    expect(result.accepted, isFalse);
    expect(result.reason, 'invalid_identity');
  });

  test('out-of-order sequence resets the offline DSP session', () {
    final recipe = ((fixture['cases'] as List<dynamic>).first as Map)
        .cast<String, dynamic>();
    final reference = _numbers(fixture['reference']);
    final captureSamples = fixture['captureSamples'] as int;
    final session = SonarOfflineDspSession();
    expect(
      session
          .process(
            _synthesize(
              recipe,
              reference: reference,
              captureSamples: captureSamples,
              sequence: 3,
            ),
          )
          .accepted,
      isTrue,
    );
    final rejected = session.process(
      _synthesize(
        recipe,
        reference: reference,
        captureSamples: captureSamples,
        sequence: 2,
      ),
    );
    expect(rejected.accepted, isFalse);
    expect(rejected.reason, 'out_of_order_reset');
  });
}

Map<String, dynamic> _loadFixture() =>
    (jsonDecode(File(_fixturePath).readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<double> _numbers(Object? value) => (value as List<dynamic>)
    .map((entry) => (entry as num).toDouble())
    .toList(growable: false);

SonarOfflineDspInput _synthesize(
  Map<String, dynamic> recipe, {
  required List<double> reference,
  required int captureSamples,
  required int sequence,
}) {
  final recorded = List<double>.filled(captureSamples, 0);
  void addComponent(int lag, double amplitude) {
    for (var index = 0; index < reference.length; index++) {
      recorded[lag + index] += reference[index] * amplitude;
    }
  }

  addComponent(
    recipe['directLag'] as int,
    (recipe['directAmplitude'] as num).toDouble(),
  );
  for (final rawEcho in recipe['echoes'] as List<dynamic>) {
    final echo = (rawEcho as Map).cast<String, dynamic>();
    addComponent(echo['lag'] as int, (echo['amplitude'] as num).toDouble());
  }
  final noiseAmplitude = (recipe['noiseAmplitude'] as num).toDouble();
  final random = math.Random(recipe['noiseSeed'] as int);
  for (var index = 0; index < recorded.length; index++) {
    recorded[index] += (random.nextDouble() * 2 - 1) * noiseAmplitude;
  }
  return SonarOfflineDspInput(
    identity: SonarWaveformIdentity(
      sequence: sequence,
      capturedAt: DateTime.utc(
        2026,
        9,
        21,
      ).add(Duration(milliseconds: sequence)),
      sampleRateHz: sonarReferenceSampleRateHz,
      inputRoute: 'fixture-mic:1',
      outputRoute: 'fixture-speaker:2',
    ),
    reference: reference,
    recorded: recorded,
  );
}
