import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/filters/threshold.dart';
import 'package:engine_imaging/src/raster.dart';

/// Lightweight page detector for the in-app fallback path (the platform
/// scanners do their own detection).
///
/// Pipeline: downscale to ~[workSize] px → luma → blur → Otsu → largest
/// connected component → corners by extreme projections (x+y, x−y) →
/// confidence from area, convexity and fill ratio. Works best for a light
/// page on a darker, contrasting background.
DetectedQuad detectPage(Rgb image, {int workSize = 320}) {
  final small = fitWithin(image, workSize);
  final w = small.width;
  final h = small.height;
  final gray = _blur3(_blur3(small.luma(), w, h), w, h);
  final t = otsuThreshold(gray);

  final bright = _analyze(gray, w, h, (v) => v > t);
  var best = bright;
  // A bright blob touching every border is probably the background (dark
  // page on a light desk): try the dark component too.
  if (bright == null || bright.bordersTouched == 4) {
    final dark = _analyze(gray, w, h, (v) => v <= t);
    if (dark != null && (best == null || dark.confidence > best.confidence)) {
      best = dark;
    }
  }
  if (best == null) return const DetectedQuad(Quad.full, 0);
  return DetectedQuad(best.quad, best.confidence);
}

class _Candidate {
  _Candidate(this.quad, this.confidence, this.bordersTouched);

  final Quad quad;
  final double confidence;
  final int bordersTouched;
}

_Candidate? _analyze(
  Uint8List gray,
  int w,
  int h,
  bool Function(int v) inMask,
) {
  final n = w * h;
  final labels = Int32List(n);
  final stack = Int32List(n);
  var bestLabel = 0;
  var bestArea = 0;
  var label = 0;
  for (var start = 0; start < n; start++) {
    if (labels[start] != 0 || !inMask(gray[start])) continue;
    label++;
    var area = 0;
    var sp = 0;
    stack[sp++] = start;
    labels[start] = label;
    while (sp > 0) {
      final i = stack[--sp];
      area++;
      final x = i % w;
      final y = i ~/ w;
      void visit(int j) {
        if (labels[j] == 0 && inMask(gray[j])) {
          labels[j] = label;
          stack[sp++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < w - 1) visit(i + 1);
      if (y > 0) visit(i - w);
      if (y < h - 1) visit(i + w);
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = label;
    }
  }
  if (bestLabel == 0 || bestArea < n * 0.02) return null;

  // Extreme projections: TL=min(x+y), BR=max(x+y), TR=max(x−y), BL=min(x−y).
  var minSum = 1 << 30;
  var maxSum = -(1 << 30);
  var minDiff = 1 << 30;
  var maxDiff = -(1 << 30);
  var tl = 0;
  var br = 0;
  var tr = 0;
  var bl = 0;
  var top = false;
  var bottom = false;
  var left = false;
  var right = false;
  for (var i = 0; i < n; i++) {
    if (labels[i] != bestLabel) continue;
    final x = i % w;
    final y = i ~/ w;
    final s = x + y;
    final d = x - y;
    if (s < minSum) (minSum, tl) = (s, i);
    if (s > maxSum) (maxSum, br) = (s, i);
    if (d > maxDiff) (maxDiff, tr) = (d, i);
    if (d < minDiff) (minDiff, bl) = (d, i);
    if (y == 0) top = true;
    if (y == h - 1) bottom = true;
    if (x == 0) left = true;
    if (x == w - 1) right = true;
  }
  NPoint pt(int i, double dx, double dy) =>
      NPoint(((i % w) + dx) / w, ((i ~/ w) + dy) / h).clamp();
  // Push each corner to the outer edge of its pixel.
  final quad = Quad(pt(tl, 0, 0), pt(tr, 1, 0), pt(br, 1, 1), pt(bl, 0, 1));
  final borders = [top, bottom, left, right].where((b) => b).length;

  final area = quad.area;
  final fill = area <= 0 ? 0.0 : (bestArea / n) / area;
  final convex = quad.isConvex;
  final areaScore = area >= 0.15 && area <= 0.98 ? 1.0 : 0.3;
  final fillScore = ((fill - 0.7) / 0.25).clamp(0.0, 1.0);
  var confidence = areaScore * fillScore * (convex ? 1.0 : 0.2);
  if (borders >= 3) confidence *= 0.5;
  return _Candidate(quad, confidence.clamp(0.0, 1.0), borders);
}

/// 3×3 box blur (edges clamped).
Uint8List _blur3(Uint8List src, int w, int h) {
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final y0 = y > 0 ? y - 1 : 0;
    final y1 = y < h - 1 ? y + 1 : h - 1;
    for (var x = 0; x < w; x++) {
      final x0 = x > 0 ? x - 1 : 0;
      final x1 = x < w - 1 ? x + 1 : w - 1;
      final s =
          src[y0 * w + x0] +
          src[y0 * w + x] +
          src[y0 * w + x1] +
          src[y * w + x0] +
          src[y * w + x] +
          src[y * w + x1] +
          src[y1 * w + x0] +
          src[y1 * w + x] +
          src[y1 * w + x1];
      out[y * w + x] = s ~/ 9;
    }
  }
  return out;
}
