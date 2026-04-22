












class Hungarian {
  
  
  static const double kForbidden = 1e30;

  
  
  
  
  
  
  
  
  
  
  
  static List<int> solveMinCost(
    List<List<double>> cost, {
    double? maxAssignableCost,
  }) {
    final int rows = cost.length;
    if (rows == 0) return const <int>[];
    final int cols = cost[0].length;
    if (cols == 0) return List<int>.filled(rows, -1);

    
    final bool transposed = rows > cols;
    final int n = transposed ? cols : rows;
    final int m = transposed ? rows : cols;
    final src = transposed ? _transpose(cost, rows, cols) : cost;

    
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

      
      while (j0 != 0) {
        final int j1 = way[j0];
        p[j0] = p[j1];
        j0 = j1;
      }
    }

    
    
    final internalAssign = List<int>.filled(n, -1);
    for (int j = 1; j <= m; j++) {
      if (p[j] > 0) internalAssign[p[j] - 1] = j - 1;
    }

    
    final List<int> assignment = List<int>.filled(rows, -1);
    if (!transposed) {
      for (int i = 0; i < rows; i++) {
        assignment[i] = internalAssign[i];
      }
    } else {
      
      for (int col = 0; col < n; col++) {
        final row = internalAssign[col];
        if (row >= 0) assignment[row] = col;
      }
    }

    
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

  
  
  static double totalCost(List<List<double>> cost, List<int> assignment) {
    double total = 0.0;
    for (int i = 0; i < assignment.length; i++) {
      final j = assignment[i];
      if (j < 0) continue;
      total += cost[i][j];
    }
    
    return total.isNaN ? double.infinity : total;
  }

  
  
  
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

