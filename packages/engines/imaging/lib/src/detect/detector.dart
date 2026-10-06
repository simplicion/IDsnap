import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/detect/edges.dart';
import 'package:engine_imaging/src/detect/refine.dart';
import 'package:engine_imaging/src/geometry/lines.dart';
import 'package:engine_imaging/src/raster.dart';

/// Page detector for the in-app fallback path (gallery imports; the platform
/// scanners do their own detection). Pure Dart, safe to run in an isolate.
///
/// Pipeline:
/// 1. Downscale to ~[workSize] px.
/// 2. Colour Canny ([computeEdges]): multi-channel gradient normalised by
///    local brightness, median-based hysteresis thresholds.
/// 3. Orientation-constrained Hough transform → up to 24 straight edges.
/// 4. Every pair of roughly-parallel edges × every crossing pair forms a
///    candidate quadrilateral, filtered for convexity, size and angle sanity,
///    then scored by how much of each side is backed by edge pixels with a
///    matching direction (small gaps, e.g. a thumb or shadow, are tolerated).
/// 5. The winner's sides are refit on the full-resolution image (sub-pixel
///    step search along the normals + robust line fit) and re-intersected.
///
/// Confidence reflects the weakest side's support, the refit quality and
/// the size of the page. When nothing plausible is found the full frame is
/// returned with a low confidence, so the UI falls back to manual corners.
DetectedQuad detectPage(Rgb image, {int workSize = 512}) {
  final small = fitWithin(image, workSize);
  final w = small.width;
  final h = small.height;
  if (w < 24 || h < 24) return const DetectedQuad(Quad.full, 0);
  final edges = computeEdges(small);
  final lines = houghLines(edges);
  final best = _bestCandidate(edges, [for (final l in lines) l.line]);
  if (best == null) return const DetectedQuad(Quad.full, 0);

  // Work → full-resolution pixel-centre coordinates.
  final sx = image.width / w;
  final sy = image.height / h;
  final coarse = [
    for (final (x, y) in best.corners)
      ((x + 0.5) * sx - 0.5, (y + 0.5) * sy - 0.5),
  ];
  final scale = math.max(sx, sy);
  final refined = _refine(image, coarse, scale, best.border);

  var confidence = _confidence(best, w * h);
  confidence *= 0.7 + 0.3 * ((refined.inliers - 0.5) / 0.4).clamp(0.0, 1.0);
  confidence *= math.pow(0.85, refined.failedSides).toDouble();
  final corners = refined.corners;
  final fw = image.width.toDouble();
  final fh = image.height.toDouble();
  final margin = 0.01 * math.max(fw, fh);
  final outside = corners.any(
    (c) =>
        c.$1 < -margin ||
        c.$2 < -margin ||
        c.$1 > fw + margin ||
        c.$2 > fh + margin,
  );
  if (outside) confidence *= 0.8;
  // A side on the frame border means the page is cut off: offer the outline
  // as a suggestion, never as an automatic crop.
  if (best.border.contains(true)) confidence = math.min(confidence, 0.5);
  confidence = confidence.clamp(0.0, 1.0);
  if (confidence < _suggestFloor) return DetectedQuad(Quad.full, confidence);

  NPoint norm((double, double) c) =>
      NPoint((c.$1 + 0.5) / fw, (c.$2 + 0.5) / fh).clamp();
  final quad = Quad(
    norm(corners[0]),
    norm(corners[1]),
    norm(corners[2]),
    norm(corners[3]),
  );
  if (!quad.isConvex) return DetectedQuad(Quad.full, confidence * 0.5);
  return DetectedQuad(quad, confidence);
}

/// Below this the outline is not even worth suggesting.
const _suggestFloor = 0.25;

/// Support credited to a side lying on the frame border (page cut off).
const _borderSupport = 0.5;

class _Candidate {
  _Candidate(this.corners, this.support, this.border, this.score);

  /// Clockwise from the top-left, work-image pixel coordinates.
  final List<(double, double)> corners;

  /// Edge support per side (0..1), side i = corners[i] → corners[i + 1].
  final List<double> support;

  /// Whether each side lies on the frame border.
  final List<bool> border;
  final double score;

  double get minSupport => support.reduce(math.min);
  double get meanSupport => support.reduce((a, b) => a + b) / 4;

  double get area => _area(corners).abs();
}

const _maxParallelDeg = 35.0;
const _minCrossDeg = 40.0;

_Candidate? _bestCandidate(EdgeMap e, List<Line2> found) {
  final w = e.width;
  final h = e.height;
  final minDim = math.min(w, h).toDouble();
  final minSep = 0.08 * minDim;
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  // Frame borders stand in for the edge of a page that is cut off.
  final real = found.length;
  final lines = [
    ...found,
    const Line2(1, 0, 0),
    Line2(1, 0, w - 1.0),
    const Line2(0, 1, 0),
    Line2(0, 1, h - 1.0),
  ];

  final pairs = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      if (i >= real && j >= real) continue;
      final li = lines[i];
      var lj = lines[j];
      if (li.angleTo(lj) > _maxParallelDeg) continue;
      if (li.a * lj.a + li.b * lj.b < 0) lj = lj.flipped;
      if ((li.distance(cx, cy) - lj.distance(cx, cy)).abs() < minSep) continue;
      pairs.add((i, j));
    }
  }

  final outlines = <(List<(double, double)>, double)>[];
  for (var p = 0; p < pairs.length; p++) {
    final (a1, a2) = pairs[p];
    for (var q = p + 1; q < pairs.length; q++) {
      final (b1, b2) = pairs[q];
      if ((a2 >= real ? 1 : 0) + (b2 >= real ? 1 : 0) > 1) continue;
      if (lines[a1].angleTo(lines[b1]) < _minCrossDeg ||
          lines[a1].angleTo(lines[b2]) < _minCrossDeg ||
          lines[a2].angleTo(lines[b1]) < _minCrossDeg ||
          lines[a2].angleTo(lines[b2]) < _minCrossDeg) {
        continue;
      }
      final corners = _corners(
        lines[a1],
        lines[a2],
        lines[b1],
        lines[b2],
        w,
        h,
        minSep,
      );
      if (corners != null) outlines.add((corners, _perimeter(corners)));
    }
  }
  // A score never exceeds the perimeter: visit the largest outlines first
  // and stop once none left can enter the shortlist.
  outlines.sort((x, y) => y.$2.compareTo(x.$2));
  const shortlist = 40;
  final coarse = <_Candidate>[];
  for (final (corners, perimeter) in outlines) {
    if (coarse.length >= shortlist && perimeter <= coarse.last.score) break;
    final c = _score(e, corners, 3);
    if (c == null) continue;
    var at = coarse.length;
    while (at > 0 && coarse[at - 1].score < c.score) {
      at--;
    }
    if (at >= shortlist) continue;
    coarse.insert(at, c);
    if (coarse.length > shortlist) coarse.removeLast();
  }
  if (coarse.isEmpty) return null;
  _Candidate? best;
  _Candidate? bestInFrame;
  for (final c in coarse) {
    final fine = _score(e, c.corners, 1);
    if (fine == null) continue;
    if (best == null || fine.score > best.score) best = fine;
    final whole = !fine.border.contains(true) && fine.minSupport >= 0.6;
    if (whole && (bestInFrame == null || fine.score > bestInFrame.score)) {
      bestInFrame = fine;
    }
  }
  // A fully outlined object beats a cut-off one leaning on the frame.
  return bestInFrame ?? best;
}

/// Corners of the quad bounded by lines A1, A2 (opposite) and B1, B2, or
/// null when it is not a plausible page outline.
List<(double, double)>? _corners(
  Line2 a1,
  Line2 a2,
  Line2 b1,
  Line2 b2,
  int w,
  int h,
  double minSide,
) {
  final p0 = a1.intersect(b1);
  final p1 = a1.intersect(b2);
  final p2 = a2.intersect(b2);
  final p3 = a2.intersect(b1);
  if (p0 == null || p1 == null || p2 == null || p3 == null) return null;
  var pts = [p0, p1, p2, p3];
  final mx = 0.1 * w;
  final my = 0.1 * h;
  for (final (x, y) in pts) {
    if (x < -mx || y < -my || x > w - 1 + mx || y > h - 1 + my) return null;
  }
  final signed = _area(pts);
  if (signed.abs() < 0.02 * w * h) return null;
  if (signed < 0) pts = pts.reversed.toList();
  // Convex with sane interior angles, and no degenerate sides.
  for (var i = 0; i < 4; i++) {
    final (ax, ay) = pts[(i + 3) % 4];
    final (bx, by) = pts[i];
    final (cx, cy) = pts[(i + 1) % 4];
    final ux = ax - bx;
    final uy = ay - by;
    final vx = cx - bx;
    final vy = cy - by;
    final lu = math.sqrt(ux * ux + uy * uy);
    final lv = math.sqrt(vx * vx + vy * vy);
    if (lu < minSide || lv < minSide) return null;
    final cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
    if (cross <= 0) return null;
    final angle = math.acos(((ux * vx + uy * vy) / (lu * lv)).clamp(-1.0, 1.0));
    if (angle < 40 * math.pi / 180 || angle > 140 * math.pi / 180) return null;
  }
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (pts[i].$1 + pts[i].$2 < pts[start].$1 + pts[start].$2) start = i;
  }
  return [for (var i = 0; i < 4; i++) pts[(start + i) % 4]];
}

double _perimeter(List<(double, double)> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final (ax, ay) = p[i];
    final (bx, by) = p[(i + 1) % p.length];
    s += math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
  }
  return s;
}

double _area(List<(double, double)> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final (ax, ay) = p[i];
    final (bx, by) = p[(i + 1) % p.length];
    s += ax * by - bx * ay;
  }
  return s / 2;
}

_Candidate? _score(EdgeMap e, List<(double, double)> corners, double step) {
  final support = List<double>.filled(4, 0);
  final border = List<bool>.filled(4, false);
  var supportedLength = 0.0;
  var ends = 1.0;
  for (var i = 0; i < 4; i++) {
    final (x0, y0) = corners[i];
    final (x1, y1) = corners[(i + 1) % 4];
    if (_onBorder(x0, y0, x1, y1, e.width, e.height)) {
      border[i] = true;
      support[i] = _borderSupport;
      supportedLength +=
          _borderSupport *
          math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
      continue;
    }
    final s = _sideSupport(e, x0, y0, x1, y1, step);
    if (s == null || s.$1 < 0.3) return null;
    support[i] = s.$1;
    supportedLength += s.$1 * s.$2;
    ends = math.min(ends, s.$3);
  }
  final minS = support.reduce(math.min);
  if (minS < 0.3) return null;
  // Supported perimeter favours the outermost outline (the page, not a
  // text block or a card's header band); weak sides and corners that no
  // edge runs into (a line overshooting the page) cost.
  final weakest = math.min(1, minS / 0.7);
  final cornerFit = 0.4 + 0.6 * math.min(1, ends / 0.5);
  return _Candidate(
    corners,
    support,
    border,
    supportedLength * weakest * weakest * cornerFit,
  );
}

bool _onBorder(double x0, double y0, double x1, double y1, int w, int h) {
  bool near(double a, double b) => (a - b).abs() < 0.5;
  return (near(x0, 0) && near(x1, 0)) ||
      (near(y0, 0) && near(y1, 0)) ||
      (near(x0, w - 1) && near(x1, w - 1)) ||
      (near(y0, h - 1) && near(y1, h - 1));
}

/// Fraction of the in-frame part of a side backed by direction-consistent
/// edge pixels within ±2 px, that in-frame length, and the weaker support
/// of its two ends; null when most of the side lies outside the frame.
(double, double, double)? _sideSupport(
  EdgeMap e,
  double x0,
  double y0,
  double x1,
  double y1,
  double step,
) {
  final w = e.width;
  final h = e.height;
  final dx = x1 - x0;
  final dy = y1 - y0;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return null;
  // Liang–Barsky clip to the frame (inset by 1 px).
  var t0 = 0.0;
  var t1 = 1.0;
  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  if (!clip(-dx, x0 - 1) ||
      !clip(dx, w - 2 - x0) ||
      !clip(-dy, y0 - 1) ||
      !clip(dy, h - 2 - y0)) {
    return null;
  }
  final inside = (t1 - t0) * len;
  if (inside < 0.5 * len) return null;
  final nx = -dy / len;
  final ny = dx / len;
  var nd = math.atan2(ny, nx) * 180 / math.pi;
  if (nd < 0) nd += 180;
  if (nd >= 180) nd -= 180;
  final n = math.max(2, (inside / step).round());
  // Direction tolerance as a lookup over the 180 edge-angle codes.
  final ok = Uint8List(256);
  for (var a = 0; a < 180; a++) {
    if (axialDiff(a.toDouble(), nd) <= 15) ok[a] = 1;
  }
  var hits = 0;
  // Support near each end (first / last 20 % of the side): a true corner
  // has edges running right into it.
  var headN = 0;
  var headHits = 0;
  var tailN = 0;
  var tailHits = 0;
  final ang = e.angle;
  for (var k = 0; k < n; k++) {
    final t = t0 + (t1 - t0) * (k + 0.5) / n;
    final head = t < 0.2;
    final tail = t > 0.8;
    if (head) headN++;
    if (tail) tailN++;
    final px = x0 + dx * t;
    final py = y0 + dy * t;
    for (var o = 0; o <= 4; o++) {
      // 0, +1, −1, +2, −2 px along the normal.
      final off = (o + 1) ~/ 2 * (o.isOdd ? 1 : -1);
      final x = (px + nx * off).round();
      final y = (py + ny * off).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      if (ok[ang[y * w + x]] == 1) {
        hits++;
        if (head) headHits++;
        if (tail) tailHits++;
        break;
      }
    }
  }
  // Ends cut off by the frame are neutral.
  final headS = t0 > 0 || headN == 0 ? 1.0 : headHits / headN;
  final tailS = t1 < 1 || tailN == 0 ? 1.0 : tailHits / tailN;
  return (hits / n, inside, math.min(headS, tailS));
}

double _confidence(_Candidate c, int pixels) {
  final minS = c.minSupport;
  final meanS = c.meanSupport;
  var conf =
      0.6 * ((minS - 0.4) / 0.4).clamp(0.0, 1.0) +
      0.4 * ((meanS - 0.5) / 0.4).clamp(0.0, 1.0);
  final a = c.area / pixels;
  if (a < 0.05) conf *= ((a - 0.02) / 0.03).clamp(0.0, 1.0);
  if (a > 0.97) conf *= 0.5;
  return conf;
}

class _Refined {
  _Refined(this.corners, this.inliers, this.failedSides);

  final List<(double, double)> corners;
  final double inliers;
  final int failedSides;
}

/// Refits each side at full resolution and re-intersects neighbours. Sides
/// that cannot be refit keep their coarse line.
_Refined _refine(
  Rgb img,
  List<(double, double)> coarse,
  double scale,
  List<bool> border,
) {
  final radius = 2.5 * scale + 3;
  final across = math.max(1, 0.6 * scale).toDouble();
  final sides = <Line2>[];
  var inliers = 0.0;
  var failed = 0;
  for (var i = 0; i < 4; i++) {
    final (x0, y0) = coarse[i];
    final (x1, y1) = coarse[(i + 1) % 4];
    if (border[i]) {
      // Snap to the outer edge of the frame (normalises to exactly 0 / 1).
      final vertical = (x1 - x0).abs() < (y1 - y0).abs();
      final far = vertical ? x0 > img.width / 2 : y0 > img.height / 2;
      final edge = far ? (vertical ? img.width : img.height) - 0.5 : -0.5;
      sides.add(vertical ? Line2(1, 0, edge) : Line2(0, 1, edge));
      continue;
    }
    final r = refineSide(img, x0, y0, x1, y1, radius: radius, across: across);
    final fallback = Line2.through(x0, y0, x1, y1)!;
    if (r == null || r.line.angleTo(fallback) > 5) {
      failed++;
      sides.add(fallback);
    } else {
      inliers += r.inlierRatio;
      sides.add(r.line);
    }
  }
  final out = <(double, double)>[];
  for (var i = 0; i < 4; i++) {
    final p = sides[(i + 3) % 4].intersect(sides[i]);
    final (cx, cy) = coarse[i];
    if (p == null ||
        math.sqrt(math.pow(p.$1 - cx, 2) + math.pow(p.$2 - cy, 2)) >
            3 * radius) {
      return _Refined(coarse, 0, 4);
    }
    out.add(p);
  }
  final refinable = border.where((b) => !b).length;
  final ok = refinable - failed;
  return _Refined(out, ok <= 0 ? 0 : inliers / ok, failed);
}
