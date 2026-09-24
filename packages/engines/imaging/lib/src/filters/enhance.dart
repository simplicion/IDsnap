import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/filters/illumination.dart';
import 'package:engine_imaging/src/filters/threshold.dart';
import 'package:engine_imaging/src/filters/tone.dart';
import 'package:engine_imaging/src/raster.dart';

/// Applies an [EnhancementFilter] and returns a new image (never mutates
/// [src]).
Rgb applyFilter(Rgb src, EnhancementFilter filter) {
  switch (filter) {
    case EnhancementFilter.original:
      return src;
    case EnhancementFilter.noShadow:
      return normalizeIllumination(src);
    case EnhancementFilter.enhanced:
      final out = normalizeIllumination(src);
      stretchContrast(out, low: 0.02);
      return out;
    case EnhancementFilter.grayscale:
      final gray = src.luma();
      final (lo, hi) = percentiles(gray, 0.01, 0.99);
      applyLutGray(gray, stretchLut(lo, hi));
      return Rgb.fromGray(gray, src.width, src.height);
    case EnhancementFilter.blackWhite:
      final gray = normalizeGray(src.luma(), src.width, src.height);
      return Rgb.fromGray(
        adaptiveThreshold(gray, src.width, src.height),
        src.width,
        src.height,
      );
  }
}

/// Brightness/contrast adjustments; returns [src] untouched when neutral.
Rgb applyAdjustments(Rgb src, double brightness, double contrast) {
  final lut = adjustmentLut(brightness, contrast);
  if (lut == null) return src;
  final out = Rgb(src.width, src.height, Uint8List.fromList(src.data));
  applyLutRgb(out, lut);
  return out;
}
