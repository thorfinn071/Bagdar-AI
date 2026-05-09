/// Minimum-cost rectangular assignment via the Kuhn–Munkres ("Hungarian")
/// algorithm with potentials. Complexity is O(n · m · min(n, m)) which, for
/// the tracker's typical workload of ≤ 20 tracks × ≤ 20 detections, runs
/// well under 0.1 ms on a mid-range CPU.
///
/// Used by the tracker (OPT-01) to replace greedy IoU matching. The greedy
/// scheme suffers from "track stealing" in crowded scenes: track A takes
/// detection 1 because its match score there is marginally higher, leaving
/// track B without an optimal partner. Hungarian finds the globally
/// minimum-cost assignment, eliminating the stealing.
///
/// The solver is implemented as a pure utility with no tracker coupling so
/// its correctness can be unit-tested in isolation.
class Hungarian {
  /// Sentinel used to mark forbidden cells. Any cost ≥ this value is
  /// treated as "do not assign"; the returned assignment drops such pairs.
  static const double kForbidden = 1e30;

  /// Solves a min-cost assignment on a rectangular cost matrix.
  ///
  /// * [cost] is indexed as `cost[row][col]`. All rows must have the same
  ///   length. Use [kForbidden] (or any value `>= kForbidden`) to mark a
  ///   cell as not allowed.
  /// * If [maxAssignableCost] is provided, any resulting assignment whose
  ///   original cost strictly exceeds this threshold is dropped (returned
  ///   as `-1` for that row). Forbidden cells are always dropped regardless.
  ///
  /// Returns a list of length `rows` where `result[i]` is the column index
  /// assigned to row `i`, or `-1` if row `i` was left unassigned.
  static List<int> solveMinCost(
    List<List<double>> cost, {
    double? maxAssignableCost,
  }) {
    final int rows = cost.length;
    if (rows == 0) return const <int>[];
    final int cols = cost[0].length;
    if (cols == 0) return List<int>.filled(rows, -1);

    // The classic algorithm requires #rows ≤ #cols. Transpose if needed.
    final bool transposed = rows > cols;
    final int n = transposed ? cols : rows;
    final int m = transposed ? rows : cols;
    final src = transposed ? _transpose(cost, rows, cols) : cost;

    // 1-indexed internal arrays so the textbook algorithm maps directly.
    final u = List<double>.filled(n + 1, 0.0);
    final v = List<double>.filled(m + 1, 0.0);
    final p = List<int>.filled(m + 1, 0);
    final way = List<int>.filled(m + 1, 0);

    for (int i = 1; i <= n; i++) {
      p[0] = i;
      int j0 = 0;
      final minv = List<double>.filled(m + 1, double.infinity);
      final used = List<bool>.filled(m + 1, false);

      do {
        used[j0] = true;
        final int i0 = p[j0];
        double delta = double.infinity;
        int j1 = -1;
        for (int j = 1; j <= m; j++) {
          if (used[j]) continue;
          final cur = src[i0 - 1][j - 1] - u[i0] - v[j];
          if (cur < minv[j]) {
            minv[j] = cur;
            way[j] = j0;
          }
          if (minv[j] < delta) {
            delta = minv[j];
            j1 = j;
          }
        }

        // No reachable column left — the remaining rows will stay
        // unmatched. Break out cleanly; any row whose `p[j] == i` after
        // the outer loop will be resolved via the original cost filter.
        if (j1 == -1) break;

        for (int j = 0; j <= m; j++) {
          if (used[j]) {
            u[p[j]] += delta;
            v[j] -= delta;
          } else {
            minv[j] -= delta;
          }
        }
        j0 = j1;
      } while (p[j0] != 0);

      // Backtrack the augmenting path.
      while (j0 != 0) {
        final int j1 = way[j0];
        p[j0] = p[j1];
        j0 = j1;
      }
    }

    // Invert: for each internal "row" (1..n), find which column it was
    // assigned to (if any).
    final internalAssign = List<int>.filled(n, -1);
    for (int j = 1; j <= m; j++) {
      if (p[j] > 0) internalAssign[p[j] - 1] = j - 1;
    }

    // Map back to the original orientation.
    final List<int> assignment = List<int>.filled(rows, -1);
    if (!transposed) {
      for (int i = 0; i < rows; i++) {
        assignment[i] = internalAssign[i];
      }
    } else {
      // In transposed mode, internalAssign[col] = row.
      for (int col = 0; col < n; col++) {
        final row = internalAssign[col];
        if (row >= 0) assignment[row] = col;
      }
    }

    // Drop forbidden / over-threshold assignments.
    for (int i = 0; i < rows; i++) {
      final j = assignment[i];
      if (j < 0) continue;
      final c = cost[i][j];
      if (c >= kForbidden) {
        assignment[i] = -1;
        continue;
      }
      if (maxAssignableCost != null && c > maxAssignableCost) {
        assignment[i] = -1;
      }
    }
    return assignment;
  }

  static List<List<double>> _transpose(
    List<List<double>> src,
    int rows,
    int cols,
  ) {
    final out = List<List<double>>.generate(
      cols,
      (_) => List<double>.filled(rows, 0.0, growable: false),
      growable: false,
    );
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        out[j][i] = src[i][j];
      }
    }
    return out;
  }

  /// Convenience: total cost of applying `assignment` to `cost`. Cells that
  /// map to `-1` contribute 0. Useful for tests and diagnostics.
  static double totalCost(List<List<double>> cost, List<int> assignment) {
    double total = 0.0;
    for (int i = 0; i < assignment.length; i++) {
      final j = assignment[i];
      if (j < 0) continue;
      total += cost[i][j];
    }
    // Guard against NaN infiltration in tests.
    return total.isNaN ? double.infinity : total;
  }

  /// Validates an assignment is a permutation restricted to the cost matrix
  /// (no duplicate columns, each within bounds or -1). Returns true if
  /// structurally valid. Intended for tests.
  static bool isValid(List<int> assignment, int cols) {
    final seen = <int>{};
    for (final j in assignment) {
      if (j == -1) continue;
      if (j < 0 || j >= cols) return false;
      if (!seen.add(j)) return false;
    }
    return true;
  }
}

