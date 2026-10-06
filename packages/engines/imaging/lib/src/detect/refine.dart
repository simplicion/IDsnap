import 'dart:math' as math;
import 'dart:typed_data';

import 'package:engine_imaging/src/geometry/lines.dart';
import 'package:engine_imaging/src/raster.dart';

/// A side refit at full resolution, with the fraction of its samples that
/// agreed with the fitted line.
class RefinedSide {
  RefinedSide(this.line, this.inlierRatio);

  final Line2 line;
  final double inlierRatio;
}

/// Refines the side (x0, y0)→(x1, y1) of a coarse quad against the
/// full-resolution [img]: along ~48 normals it finds the strongest colour
/// step within ±[radius] px (sub-pixel, parabolic peak), then robustly fits
/// a line to those points (total least squares, MAD outlier rejection).
///
/// Returns null when too few samples support a line.
RefinedSide? refineSide(
  Rgb img,
  double x0,
  double y0,
  double x1,
  double y1, {
  required double radius,
  required double across,
}) {
  final coarse = Line2.through(x0, y0, x1, y1);
  if (coarse == null) return null;
  final nx = coarse.a;
  final ny = coarse.b;
  final tx = -ny;
  final ty = nx;
  final len = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
  final samples = (len / 4).clamp(12, 48).round();
  final steps = radius.ceil();
  final m = 2 * steps + 1;
  final prof = Float64List(m * 3);
  final grad = Float64List(m);
  final px = Float64List(3);
  final xs = <double>[];
  final ys = <double>[];
  final maxX = img.width - 1.0;
  final maxY = img.height - 1.0;

  for (var k = 0; k < samples; k++) {
    // Skip the ends: corners mix two edges.
    final u = 0.1 + 0.8 * k / (samples - 1);
    final qx = x0 + (x1 - x0) * u;
    final qy = y0 + (y1 - y0) * u;
    if (qx < 1 || qy < 1 || qx > maxX - 1 || qy > maxY - 1) continue;
    var valid = true;
    for (var s = 0; s < m && valid; s++) {
      final d = (s - steps).toDouble();
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      for (var j = -1; j <= 1; j++) {
        final sx = qx + nx * d + tx * j * across;
        final sy = qy + ny * d + ty * j * across;
        if (sx < 0 || sy < 0 || sx > maxX || sy > maxY) {
          valid = false;
          break;
        }
        _sample(img, sx, sy, px);
        r += px[0];
        g += px[1];
        b += px[2];
      }
      prof[s * 3] = r;
      prof[s * 3 + 1] = g;
      prof[s * 3 + 2] = b;
    }
    if (!valid) continue;
    var best = -1;
    var bestG = 0.0;
    for (var s = 1; s < m - 1; s++) {
      final dr = prof[(s + 1) * 3] - prof[(s - 1) * 3];
      final dg = prof[(s + 1) * 3 + 1] - prof[(s - 1) * 3 + 1];
      final db = prof[(s + 1) * 3 + 2] - prof[(s - 1) * 3 + 2];
      final v = math.sqrt(dr * dr + dg * dg + db * db);
      grad[s] = v;
    }
    // Light smoothing of the gradient profile against noise.
    for (var s = 2; s < m - 2; s++) {
      final v = 0.25 * grad[s - 1] + 0.5 * grad[s] + 0.25 * grad[s + 1];
      if (v > bestG) {
        bestG = v;
        best = s;
      }
    }
    // Minimum step: ~6 grey levels summed over the 3 tangential samples.
    if (best < 0 || bestG < 36) continue;
    final gm = grad[best - 1];
    final g0 = grad[best];
    final gp = grad[best + 1];
    final den = gm - 2 * g0 + gp;
    var off = den < 0 ? 0.5 * (gm - gp) / den : 0.0;
    if (off.abs() > 1) off = 0;
    final d = best - steps + off;
    xs.add(qx + nx * d);
    ys.add(qy + ny * d);
  }
  if (xs.length < math.max(6, samples * 0.3)) return null;

  final use = List<bool>.filled(xs.length, true);
  Line2? line = coarse;
  for (var iter = 0; iter < 3; iter++) {
    final fit = Line2.fit(xs, ys, use);
    if (fit == null) return null;
    line = fit;
    final res = [
      for (var i = 0; i < xs.length; i++) fit.distance(xs[i], ys[i]).abs(),
    ];
    final sorted = [
      for (var i = 0; i < xs.length; i++)
        if (use[i]) res[i],
    ]..sort();
    final mad = sorted[sorted.length ~/ 2];
    final limit = math.max(0.75, 3 * 1.4826 * mad);
    for (var i = 0; i < xs.length; i++) {
      use[i] = res[i] <= limit;
    }
  }
  final inliers = use.where((u) => u).length;
  if (inliers < math.max(5, samples * 0.25)) return null;
  return RefinedSide(line!, inliers / samples);
}

/// Bilinear RGB sample at (x, y) (pixel centres at integers) into [out].
void _sample(Rgb img, double x, double y, Float64List out) {
  final w = img.width;
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = x0 + 1 < w ? x0 + 1 : x0;
  final y1 = y0 + 1 < img.height ? y0 + 1 : y0;
  final fx = x - x0;
  final fy = y - y0;
  final d = img.data;
  final p00 = (y0 * w + x0) * 3;
  final p10 = (y0 * w + x1) * 3;
  final p01 = (y1 * w + x0) * 3;
  final p11 = (y1 * w + x1) * 3;
  for (var c = 0; c < 3; c++) {
    final top = d[p00 + c] + (d[p10 + c] - d[p00 + c]) * fx;
    final bottom = d[p01 + c] + (d[p11 + c] - d[p01 + c]) * fx;
    out[c] = top + (bottom - top) * fy;
  }
}
