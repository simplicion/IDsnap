import 'dart:math' as math;
import 'dart:typed_data';

import 'package:engine_imaging/src/geometry/lines.dart';
import 'package:engine_imaging/src/raster.dart';

/// Thin colour edges of a small working image.
class EdgeMap {
  EdgeMap(this.width, this.height, this.magnitude, this.angle, this.low);

  /// Marks non-edge pixels in [angle].
  static const noEdge = 255;

  final int width;
  final int height;

  /// Illumination-normalised colour gradient magnitude (before NMS).
  final Float32List magnitude;

  /// Gradient (edge-normal) direction in whole degrees within [0, 180) for
  /// edge pixels, [noEdge] elsewhere.
  final Uint8List angle;

  /// Hysteresis low threshold, in [magnitude] units.
  final double low;
}

/// Colour Canny: binomial blur → Di Zenzo multi-channel gradient (so a white
/// page on a light, differently tinted table still has an edge) normalised by
/// the local brightness (shadows keep their edges) → non-maximum suppression
/// → hysteresis with thresholds derived from the median gradient.
EdgeMap computeEdges(Rgb src) {
  final w = src.width;
  final h = src.height;
  final n = w * h;
  final r = Float32List(n);
  final g = Float32List(n);
  final b = Float32List(n);
  final d = src.data;
  for (var i = 0, p = 0; i < n; i++, p += 3) {
    r[i] = d[p].toDouble();
    g[i] = d[p + 1].toDouble();
    b[i] = d[p + 2].toDouble();
  }
  final tmp = Float32List(n);
  for (final plane in [r, g, b]) {
    _binomial5(plane, tmp, w, h);
  }
  final luma = Float32List(n);
  for (var i = 0; i < n; i++) {
    luma[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
  }
  final mean = _boxMean(luma, w, h, math.max(4, math.min(w, h) ~/ 12));

  final mag = Float32List(n);
  // Structure-tensor terms: the edge normal is ½·atan2(dirY, dirX).
  final dirX = Float32List(n);
  final dirY = Float32List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1, i = y * w + 1; x < w - 1; x++, i++) {
      final gxr =
          (r[i - w + 1] + 2 * r[i + 1] + r[i + w + 1]) -
          (r[i - w - 1] + 2 * r[i - 1] + r[i + w - 1]);
      final gyr =
          (r[i + w - 1] + 2 * r[i + w] + r[i + w + 1]) -
          (r[i - w - 1] + 2 * r[i - w] + r[i - w + 1]);
      final gxg =
          (g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1]) -
          (g[i - w - 1] + 2 * g[i - 1] + g[i + w - 1]);
      final gyg =
          (g[i + w - 1] + 2 * g[i + w] + g[i + w + 1]) -
          (g[i - w - 1] + 2 * g[i - w] + g[i - w + 1]);
      final gxb =
          (b[i - w + 1] + 2 * b[i + 1] + b[i + w + 1]) -
          (b[i - w - 1] + 2 * b[i - 1] + b[i + w - 1]);
      final gyb =
          (b[i + w - 1] + 2 * b[i + w] + b[i + w + 1]) -
          (b[i - w - 1] + 2 * b[i - w] + b[i - w + 1]);
      final gxx = gxr * gxr + gxg * gxg + gxb * gxb;
      final gyy = gyr * gyr + gyg * gyg + gyb * gyb;
      final gxy = gxr * gyr + gxg * gyg + gxb * gyb;
      final diff = gxx - gyy;
      final root = math.sqrt(diff * diff + 4 * gxy * gxy);
      final lambda = 0.5 * (gxx + gyy + root);
      if (lambda <= 0) continue;
      // /4: Sobel gain, so a unit step reads as ~1 grey level per channel.
      mag[i] = math.sqrt(lambda) * 0.25 * 128 / (mean[i] + 24);
      dirX[i] = diff;
      dirY[i] = 2 * gxy;
    }
  }

  // Non-maximum suppression along the quantised gradient direction.
  final nms = Float32List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1, i = y * w + 1; x < w - 1; x++, i++) {
      final m = mag[i];
      if (m <= 0) continue;
      // Quantise the normal without trigonometry: 2θ's quadrant.
      final dx = dirX[i];
      final dy = dirY[i];
      final int o;
      if (dx >= dy.abs()) {
        o = 1; // θ ≈ 0°
      } else if (dy > dx.abs()) {
        o = w + 1; // θ ≈ 45°
      } else if (-dx >= dy.abs()) {
        o = w; // θ ≈ 90°
      } else {
        o = w - 1; // θ ≈ 135°
      }
      if (m >= mag[i - o] && m > mag[i + o]) nms[i] = m;
    }
  }

  // Median-based adaptive thresholds.
  final median = _percentile(mag, 0.5);
  final strong = _percentile(nms, 0.97, positiveOnly: true);
  var high = math.max(3.5 * median, 3);
  if (strong > 0 && high > strong) high = strong;
  final low = 0.45 * high;

  final angle = Uint8List(n)..fillRange(0, n, EdgeMap.noEdge);
  final stack = Int32List(n);
  var sp = 0;
  for (var i = 0; i < n; i++) {
    if (nms[i] < high || angle[i] != EdgeMap.noEdge) continue;
    angle[i] = _deg(dirX[i], dirY[i]);
    stack[sp++] = i;
    while (sp > 0) {
      final j = stack[--sp];
      final x = j % w;
      final y = j ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 1 || yy >= h - 1) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 1 || xx >= w - 1) continue;
          final k = yy * w + xx;
          if (angle[k] == EdgeMap.noEdge && nms[k] >= low) {
            angle[k] = _deg(dirX[k], dirY[k]);
            stack[sp++] = k;
          }
        }
      }
    }
  }
  return EdgeMap(w, h, mag, angle, low);
}

int _deg(double dirX, double dirY) {
  var t = 0.5 * math.atan2(dirY, dirX);
  if (t < 0) t += math.pi;
  return (t * 180 / math.pi).round() % 180;
}

/// In-place separable [1 4 6 4 1] / 16 blur with clamped borders.
void _binomial5(Float32List p, Float32List tmp, int w, int h) {
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final x1 = x > 0 ? x - 1 : 0;
      final x2 = x > 1 ? x - 2 : 0;
      final x3 = x < w - 1 ? x + 1 : w - 1;
      final x4 = x < w - 2 ? x + 2 : w - 1;
      tmp[row + x] =
          (p[row + x2] +
              4 * p[row + x1] +
              6 * p[row + x] +
              4 * p[row + x3] +
              p[row + x4]) /
          16;
    }
  }
  for (var y = 0; y < h; y++) {
    final y1 = (y > 0 ? y - 1 : 0) * w;
    final y2 = (y > 1 ? y - 2 : 0) * w;
    final y3 = (y < h - 1 ? y + 1 : h - 1) * w;
    final y4 = (y < h - 2 ? y + 2 : h - 1) * w;
    final row = y * w;
    for (var x = 0; x < w; x++) {
      p[row + x] =
          (tmp[y2 + x] +
              4 * tmp[y1 + x] +
              6 * tmp[row + x] +
              4 * tmp[y3 + x] +
              tmp[y4 + x]) /
          16;
    }
  }
}

/// Box mean of radius [rad] via an integral image.
Float32List _boxMean(Float32List src, int w, int h, int rad) {
  final iw = w + 1;
  final integral = Float64List(iw * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += src[y * w + x];
      integral[(y + 1) * iw + x + 1] = integral[y * iw + x + 1] + rowSum;
    }
  }
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - rad);
    final y1 = math.min(h, y + rad + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - rad);
      final x1 = math.min(w, x + rad + 1);
      final s =
          integral[y1 * iw + x1] -
          integral[y0 * iw + x1] -
          integral[y1 * iw + x0] +
          integral[y0 * iw + x0];
      out[y * w + x] = s / ((x1 - x0) * (y1 - y0));
    }
  }
  return out;
}

/// Approximate [q]-quantile of the values via a 0.25-wide histogram.
double _percentile(Float32List v, double q, {bool positiveOnly = false}) {
  const bins = 4096;
  final hist = Int32List(bins);
  var count = 0;
  for (final x in v) {
    if (positiveOnly && x <= 0) continue;
    final bin = (x * 4).toInt();
    hist[bin < bins ? bin : bins - 1]++;
    count++;
  }
  if (count == 0) return 0;
  final target = (count * q).ceil();
  var acc = 0;
  for (var i = 0; i < bins; i++) {
    acc += hist[i];
    if (acc >= target) return (i + 0.5) / 4;
  }
  return bins / 4;
}

/// A straight edge found by the Hough transform, refit to its pixels.
class HoughLine {
  HoughLine(this.line, this.votes, this.run);

  final Line2 line;
  final int votes;

  /// Longest contiguous supported stretch, in px.
  final int run;
}

/// Orientation-constrained Hough transform: each edge pixel votes only for
/// normals within ±[spread]° of its own gradient direction. Peaks are
/// suppressed greedily, then each line is refit (total least squares) to the
/// edge pixels that agree with it in position and direction.
List<HoughLine> houghLines(EdgeMap e, {int maxLines = 24, int spread = 5}) {
  final w = e.width;
  final h = e.height;
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  final rMax = (math.sqrt(w * w + h * h) / 2).ceil() + 1;
  final nr = 2 * rMax + 1;
  final cosT = Float64List(180);
  final sinT = Float64List(180);
  for (var t = 0; t < 180; t++) {
    cosT[t] = math.cos(t * math.pi / 180);
    sinT[t] = math.sin(t * math.pi / 180);
  }
  final acc = Int32List(180 * nr);
  final ang = e.angle;
  var edges = 0;
  for (var y = 0; y < h; y++) {
    final dy = y - cy;
    for (var x = 0; x < w; x++) {
      final a = ang[y * w + x];
      if (a == EdgeMap.noEdge) continue;
      edges++;
      final dx = x - cx;
      for (var k = -spread; k <= spread; k++) {
        var t = a + k;
        if (t < 0) t += 180;
        if (t >= 180) t -= 180;
        final rho = (dx * cosT[t] + dy * sinT[t]).round() + rMax;
        acc[t * nr + rho]++;
      }
    }
  }
  if (edges == 0) return const [];

  final minVotes = math.max(12, (0.05 * math.min(w, h)).round());
  final peaks = <(int, int, int)>[];
  for (var t = 0; t < 180; t++) {
    for (var ri = 1; ri < nr - 1; ri++) {
      final v = acc[t * nr + ri];
      if (v < minVotes) continue;
      var isMax = true;
      for (var dt = -2; dt <= 2 && isMax; dt++) {
        var tt = t + dt;
        var flip = false;
        if (tt < 0) {
          tt += 180;
          flip = true;
        } else if (tt >= 180) {
          tt -= 180;
          flip = true;
        }
        for (var dr = -3; dr <= 3; dr++) {
          if (dt == 0 && dr == 0) continue;
          var rr = ri + dr;
          if (flip) rr = nr - 1 - rr;
          if (rr < 0 || rr >= nr) continue;
          if (acc[tt * nr + rr] > v) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) peaks.add((v, t, ri - rMax));
    }
  }
  peaks.sort((p, q) => q.$1.compareTo(p.$1));

  final chosen = <(int, int, int)>[];
  for (final p in peaks) {
    var dup = false;
    for (final q in chosen) {
      var dt = (p.$2 - q.$2).abs();
      var rq = q.$3;
      if (dt > 90) {
        dt = 180 - dt;
        rq = -rq;
      }
      if (dt <= 4 && (p.$3 - rq).abs() <= 8) {
        dup = true;
        break;
      }
    }
    if (dup) continue;
    chosen.add(p);
    if (chosen.length >= 4 * maxLines) break;
  }

  // Rank by the longest contiguous straight run rather than raw votes: page
  // edges are unbroken segments, while wood grain, fabric and text rows add
  // up many short fragments along the same line.
  final ranked = <HoughLine>[];
  for (final (votes, t, rho) in chosen) {
    final a = cosT[t];
    final b = sinT[t];
    final coarse = Line2(a, b, rho + a * cx + b * cy);
    final line = _refit(e, coarse) ?? coarse;
    ranked.add(HoughLine(line, votes, _longestRun(e, line)));
  }
  ranked.sort((p, q) => q.run.compareTo(p.run));
  // Directional textures (wood grain, stripes) yield many parallel lines;
  // cap each direction so a page's crossing edges still make the cut.
  final out = <HoughLine>[];
  for (final l in ranked) {
    final d = l.line.normalDegrees;
    final similar = out
        .where((o) => axialDiff(o.line.normalDegrees, d) <= 6)
        .length;
    if (similar >= 6) continue;
    out.add(l);
    if (out.length >= maxLines) break;
  }
  return out;
}

/// Longest run (px) along [line] of direction-consistent edge pixels within
/// ±1 px, bridging gaps of up to 3 px.
int _longestRun(EdgeMap e, Line2 line) {
  final w = e.width;
  final h = e.height;
  final nd = line.normalDegrees;
  final tx = -line.b;
  final ty = line.a;
  final fx = line.a * line.c;
  final fy = line.b * line.c;
  final reach = math.sqrt(w * w + h * h).ceil();
  var best = 0;
  var run = 0;
  var gap = 0;
  for (var s = -reach; s <= reach; s++) {
    final px = fx + tx * s;
    final py = fy + ty * s;
    if (px < 0 || py < 0 || px > w - 1 || py > h - 1) {
      run = 0;
      gap = 0;
      continue;
    }
    var hit = false;
    for (var o = -1; o <= 1 && !hit; o++) {
      final x = (px + line.a * o).round();
      final y = (py + line.b * o).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      final a = e.angle[y * w + x];
      hit = a != EdgeMap.noEdge && axialDiff(a.toDouble(), nd) <= 12;
    }
    if (hit) {
      run += gap + 1;
      gap = 0;
      if (run > best) best = run;
    } else if (run > 0) {
      gap++;
      if (gap > 3) {
        run = 0;
        gap = 0;
      }
    }
  }
  return best;
}

/// Refits [line] to nearby edge pixels with a matching direction.
Line2? _refit(EdgeMap e, Line2 line) {
  final w = e.width;
  final h = e.height;
  final xs = <double>[];
  final ys = <double>[];
  final nd = line.normalDegrees;
  // Walk the band |distance| ≤ 2 px row- or column-wise.
  final steep = line.a.abs() > line.b.abs(); // near-vertical line
  if (steep) {
    for (var y = 0; y < h; y++) {
      final x0 = ((line.c - line.b * y) / line.a).round();
      for (var x = x0 - 2; x <= x0 + 2; x++) {
        if (x < 0 || x >= w) continue;
        final a = e.angle[y * w + x];
        if (a != EdgeMap.noEdge && axialDiff(a.toDouble(), nd) <= 8) {
          xs.add(x.toDouble());
          ys.add(y.toDouble());
        }
      }
    }
  } else {
    for (var x = 0; x < w; x++) {
      final y0 = ((line.c - line.a * x) / line.b).round();
      for (var y = y0 - 2; y <= y0 + 2; y++) {
        if (y < 0 || y >= h) continue;
        final a = e.angle[y * w + x];
        if (a != EdgeMap.noEdge && axialDiff(a.toDouble(), nd) <= 8) {
          xs.add(x.toDouble());
          ys.add(y.toDouble());
        }
      }
    }
  }
  if (xs.length < 8) return null;
  final fit = Line2.fit(xs, ys);
  if (fit == null) return null;
  // Keep the refit only when it stays close to the Hough estimate.
  if (fit.angleTo(line) > 3) return null;
  return fit;
}
