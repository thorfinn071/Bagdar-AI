import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'test/fixtures/ncnn_contract/reference_outputs.json';

void main() {
  final fixture = File(_fixturePath);
  test('ONNX reference and NCNN maps have matching depth rank', () {
    expect(fixture.existsSync(), isTrue, reason: 'required fixture missing');
    final root = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    final cases = root['cases'] as List<dynamic>?;
    expect(cases, isNotNull, reason: 'fixture must contain a cases array');
    expect(cases, isNotEmpty, reason: 'fixture must contain recorded scenes');
    for (final rawCase in cases!) {
      final c = rawCase as Map<String, dynamic>;
      final name = c['name'] as String? ?? 'unnamed';
      final reference = _numbers(c['reference']);
      final native = _numbers(c['native']);
      expect(native.length, reference.length, reason: '$name map length');
      expect(
        reference.length,
        greaterThanOrEqualTo(64),
        reason: '$name sample count',
      );
      final rho = _spearman(reference, native);
      expect(
        rho,
        greaterThanOrEqualTo(0.90),
        reason: '$name Spearman rho=$rho',
      );
    }
  });
}

List<double> _numbers(Object? value) {
  final list = value as List<dynamic>?;
  if (list == null) return const <double>[];
  return list.map((v) => (v as num).toDouble()).toList(growable: false);
}

double _spearman(List<double> a, List<double> b) {
  final validA = <double>[];
  final validB = <double>[];
  for (int i = 0; i < math.min(a.length, b.length); i++) {
    if (a[i].isFinite && b[i].isFinite) {
      validA.add(a[i]);
      validB.add(b[i]);
    }
  }
  if (validA.length < 16) return double.nan;
  return _pearson(_ranks(validA), _ranks(validB));
}

List<double> _ranks(List<double> values) {
  final order = List<int>.generate(values.length, (i) => i)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final ranks = List<double>.filled(values.length, 0);
  int start = 0;
  while (start < order.length) {
    var end = start + 1;
    while (end < order.length && values[order[end]] == values[order[start]]) {
      end++;
    }
    final averageRank = (start + end - 1) / 2.0;
    for (int i = start; i < end; i++) {
      ranks[order[i]] = averageRank;
    }
    start = end;
  }
  return ranks;
}

double _pearson(List<double> a, List<double> b) {
  final meanA = a.reduce((x, y) => x + y) / a.length;
  final meanB = b.reduce((x, y) => x + y) / b.length;
  var numerator = 0.0;
  var denomA = 0.0;
  var denomB = 0.0;
  for (int i = 0; i < a.length; i++) {
    final da = a[i] - meanA;
    final db = b[i] - meanB;
    numerator += da * db;
    denomA += da * da;
    denomB += db * db;
  }
  final denom = math.sqrt(denomA * denomB);
  return denom == 0 ? double.nan : numerator / denom;
}
