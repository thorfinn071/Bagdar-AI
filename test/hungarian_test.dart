import 'package:bagdar/tracker/hungarian.dart';
import 'package:flutter_test/flutter_test.dart';



double _bruteForceMin(List<List<double>> cost) {
  final n = cost.length;
  final m = cost[0].length;
  final cols = List<int>.generate(m, (i) => i);
  double best = double.infinity;

  void permute(List<int> arr, int k) {
    if (k == arr.length) {
      double total = 0;
      for (int i = 0; i < n && i < arr.length; i++) {
        total += cost[i][arr[i]];
      }
      if (total < best) best = total;
      return;
    }
    for (int i = k; i < arr.length; i++) {
      final tmp = arr[k];
      arr[k] = arr[i];
      arr[i] = tmp;
      permute(arr, k + 1);
      final tmp2 = arr[k];
      arr[k] = arr[i];
      arr[i] = tmp2;
    }
  }

  permute(cols, 0);
  return best;
}

void main() {
  group('Hungarian.solveMinCost — basic correctness', () {
    test('empty matrix returns empty assignment', () {
      expect(Hungarian.solveMinCost(<List<double>>[]), isEmpty);
    });

    test('single cell assigns row 0 to col 0', () {
      final cost = <List<double>>[
        [0.3],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result, [0]);
      expect(Hungarian.totalCost(cost, result), closeTo(0.3, 1e-9));
    });

    test('2x2 picks the minimum diagonal', () {
      final cost = <List<double>>[
        [1.0, 2.0],
        [3.0, 4.0],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result, [0, 1]);
      expect(Hungarian.totalCost(cost, result), closeTo(5.0, 1e-9));
    });

    test('2x2 picks the anti-diagonal when cheaper', () {
      final cost = <List<double>>[
        [10.0, 1.0],
        [1.0, 10.0],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result, [1, 0]);
      expect(Hungarian.totalCost(cost, result), closeTo(2.0, 1e-9));
    });
  });

  group('Hungarian.solveMinCost — rectangular matrices', () {
    test('more cols than rows: every row assigned', () {
      final cost = <List<double>>[
        [2.0, 1.0, 5.0, 8.0],
        [4.0, 3.0, 2.0, 1.0],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result.length, 2);
      expect(Hungarian.isValid(result, 4), isTrue);
      expect(result.every((j) => j >= 0), isTrue);
      
      expect(Hungarian.totalCost(cost, result), closeTo(2.0, 1e-9));
    });

    test('more rows than cols: only `cols` rows assigned', () {
      final cost = <List<double>>[
        [1.0, 5.0],
        [4.0, 2.0],
        [9.0, 9.0],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result.length, 3);
      expect(Hungarian.isValid(result, 2), isTrue);
      expect(result.where((j) => j >= 0).length, 2);
      
      
      expect(result[2], -1);
    });
  });

  group('Hungarian.solveMinCost — anti-greedy scenarios', () {
    test('track-stealing is avoided (OPT-01 motivation)', () {
      
      
      
      
      
      
      
      
      final cost = <List<double>>[
        [0.40, 0.10],
        [0.05, 0.60],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result, [1, 0]);
      expect(Hungarian.totalCost(cost, result), closeTo(0.15, 1e-9));
    });

    test('matches brute-force optimum on random 5x5 matrices', () {
      final samples = <List<List<double>>>[
        [
          [0.2, 0.9, 0.5, 0.7, 0.1],
          [0.6, 0.3, 0.8, 0.4, 0.9],
          [0.1, 0.2, 0.3, 0.4, 0.5],
          [0.5, 0.4, 0.3, 0.2, 0.1],
          [0.9, 0.8, 0.7, 0.6, 0.5],
        ],
        [
          [0.1, 0.1, 0.1, 0.1, 0.1],
          [0.9, 0.9, 0.9, 0.9, 0.1],
          [0.9, 0.9, 0.9, 0.1, 0.9],
          [0.9, 0.9, 0.1, 0.9, 0.9],
          [0.9, 0.1, 0.9, 0.9, 0.9],
        ],
      ];
      for (final cost in samples) {
        final result = Hungarian.solveMinCost(cost);
        expect(Hungarian.isValid(result, cost[0].length), isTrue);
        expect(result.length, cost.length);
        expect(
          Hungarian.totalCost(cost, result),
          closeTo(_bruteForceMin(cost), 1e-9),
        );
      }
    });
  });

  group('Hungarian.solveMinCost — forbidden cells and thresholds', () {
    test('forbidden cells are never selected', () {
      final cost = <List<double>>[
        [Hungarian.kForbidden, 1.0],
        [0.5, Hungarian.kForbidden],
      ];
      final result = Hungarian.solveMinCost(cost);
      expect(result, [1, 0]);
    });

    test('assignment dropped when sole option is forbidden', () {
      final cost = <List<double>>[
        [0.1, 0.2],
        [Hungarian.kForbidden, Hungarian.kForbidden],
      ];
      final result = Hungarian.solveMinCost(cost);
      
      expect(result[1], -1);
      expect(result[0], anyOf(0, 1));
    });

    test(
        'maxAssignableCost drops assignments whose original cost exceeds the '
        'threshold', () {
      final cost = <List<double>>[
        [0.10, 0.90],
        [0.95, 0.05],
      ];
      final result = Hungarian.solveMinCost(cost, maxAssignableCost: 0.50);
      
      
      expect(result, [0, 1]);

      final tighter = Hungarian.solveMinCost(
        <List<double>>[
          [0.10, 0.95],
          [0.95, 0.12],
        ],
        maxAssignableCost: 0.20,
      );
      
      
      expect(tighter, [0, 1]);

      final strict = Hungarian.solveMinCost(
        <List<double>>[
          [0.10, 0.95],
          [0.95, 0.12],
        ],
        maxAssignableCost: 0.11,
      );
      
      expect(strict[0], 0);
      expect(strict[1], -1);
    });
  });
}
