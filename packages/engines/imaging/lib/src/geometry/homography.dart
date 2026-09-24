import 'dart:math' as math;
import 'dart:typed_data';

/// A 3×3 projective transform stored row-major with h[8] == 1.
class Homography {
  Homography._(this.h);

  /// Solves the transform mapping each `from[i]` to `to[i]` (4 point pairs,
  /// as `[x, y]`) with an 8×8 Gaussian elimination (partial pivoting).
  ///
  /// Throws [ArgumentError] for degenerate (collinear) configurations.
  factory Homography.fromPoints(
    List<List<double>> from,
    List<List<double>> to,
  ) {
    if (from.length != 4 || to.length != 4) {
      throw ArgumentError('Exactly four point pairs are required');
    }
    final a = List.generate(8, (_) => Float64List(9));
    for (var i = 0; i < 4; i++) {
      final x = from[i][0];
      final y = from[i][1];
      final u = to[i][0];
      final v = to[i][1];
      a[2 * i].setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
      a[2 * i + 1].setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y, v]);
    }
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw ArgumentError('Degenerate point configuration');
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    final h = Float64List(9);
    for (var i = 0; i < 8; i++) {
      h[i] = a[i][8] / a[i][i];
    }
    h[8] = 1;
    return Homography._(h);
  }

  final Float64List h;

  /// Maps (x, y), returning `[u, v]`.
  List<double> map(double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    return [(h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w];
  }
}

double pointDistance(List<double> a, List<double> b) =>
    math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));
