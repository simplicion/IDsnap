import 'dart:math' as math;

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/geometry/homography.dart';
import 'package:engine_imaging/src/raster.dart';

/// Quad corners in pixel coordinates of an image of [width] × [height].
List<List<double>> quadToPixels(Quad quad, int width, int height) => [
  for (final p in quad.points) [p.x * width, p.y * height],
];

/// Natural output size of a quad: the longer of each pair of opposite edges.
({int width, int height}) warpSize(Quad quad, int width, int height) {
  final p = quadToPixels(quad, width, height);
  final w = math.max(pointDistance(p[0], p[1]), pointDistance(p[3], p[2]));
  final h = math.max(pointDistance(p[0], p[3]), pointDistance(p[1], p[2]));
  return (width: math.max(1, w.round()), height: math.max(1, h.round()));
}

/// Perspective-corrects [quad] of [src] into an [outWidth] × [outHeight]
/// rectangle using an inverse homography and bilinear sampling.
Rgb warpPerspective(Rgb src, Quad quad, int outWidth, int outHeight) {
  final corners = quadToPixels(quad, src.width, src.height);
  // Map output pixel centers → source coordinates.
  final h = Homography.fromPoints([
    [0, 0],
    [outWidth.toDouble(), 0],
    [outWidth.toDouble(), outHeight.toDouble()],
    [0, outHeight.toDouble()],
  ], corners).h;
  final out = Rgb(outWidth, outHeight);
  final maxX = src.width - 1.0;
  final maxY = src.height - 1.0;
  for (var y = 0; y < outHeight; y++) {
    final cy = y + 0.5;
    // Numerators/denominator are linear in x: step incrementally.
    var nu = h[0] * 0.5 + h[1] * cy + h[2];
    var nv = h[3] * 0.5 + h[4] * cy + h[5];
    var dw = h[6] * 0.5 + h[7] * cy + h[8];
    var o = y * outWidth * 3;
    for (var x = 0; x < outWidth; x++, o += 3) {
      var sx = nu / dw - 0.5;
      var sy = nv / dw - 0.5;
      if (sx < 0) sx = 0;
      if (sx > maxX) sx = maxX;
      if (sy < 0) sy = 0;
      if (sy > maxY) sy = maxY;
      sampleBilinear(src, sx, sy, out.data, o);
      nu += h[0];
      nv += h[3];
      dw += h[6];
    }
  }
  return out;
}
