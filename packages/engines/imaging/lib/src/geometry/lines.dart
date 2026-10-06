import 'dart:math' as math;

/// A 2-D line in Hessian normal form: `a·x + b·y = c` with `(a, b)` a unit
/// normal.
class Line2 {
  const Line2(this.a, this.b, this.c);

  /// The line through (x0, y0) and (x1, y1); null when the points coincide.
  static Line2? through(double x0, double y0, double x1, double y1) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return null;
    final a = -dy / len;
    final b = dx / len;
    return Line2(a, b, a * x0 + b * y0);
  }

  /// Total-least-squares fit to the points (xs[i], ys[i]) for which
  /// `use == null || use[i]`; null for fewer than two points.
  static Line2? fit(List<double> xs, List<double> ys, [List<bool>? use]) {
    var n = 0;
    var mx = 0.0;
    var my = 0.0;
    for (var i = 0; i < xs.length; i++) {
      if (use != null && !use[i]) continue;
      n++;
      mx += xs[i];
      my += ys[i];
    }
    if (n < 2) return null;
    mx /= n;
    my /= n;
    var sxx = 0.0;
    var syy = 0.0;
    var sxy = 0.0;
    for (var i = 0; i < xs.length; i++) {
      if (use != null && !use[i]) continue;
      final dx = xs[i] - mx;
      final dy = ys[i] - my;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    // Principal direction of the scatter; the normal is perpendicular.
    final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final a = -math.sin(theta);
    final b = math.cos(theta);
    return Line2(a, b, a * mx + b * my);
  }

  final double a;
  final double b;
  final double c;

  /// Signed distance of (x, y) from the line.
  double distance(double x, double y) => a * x + b * y - c;

  /// The same line with its normal pointing the other way.
  Line2 get flipped => Line2(-a, -b, -c);

  /// Normal direction in degrees, folded into [0, 180).
  double get normalDegrees {
    final d = math.atan2(b, a) * 180 / math.pi;
    return d < 0 ? d + 180 : (d >= 180 ? d - 180 : d);
  }

  /// Intersection with [o]; null when (nearly) parallel.
  (double, double)? intersect(Line2 o) {
    final det = a * o.b - b * o.a;
    if (det.abs() < 1e-9) return null;
    return ((c * o.b - b * o.c) / det, (a * o.c - c * o.a) / det);
  }

  /// Unsigned angle between the two lines, in degrees within [0, 90].
  double angleTo(Line2 o) {
    final cos = (a * o.a + b * o.b).abs().clamp(0.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }
}

/// Difference between two axial angles (degrees, period 180) in [0, 90].
double axialDiff(double d1, double d2) {
  var d = (d1 - d2).abs() % 180;
  if (d > 90) d = 180 - d;
  return d;
}
