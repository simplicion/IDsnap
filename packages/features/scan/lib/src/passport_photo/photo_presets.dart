import 'dart:math' as math;

import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

/// Unit a custom size was entered in.
enum SizeUnit {
  mm('mm'),
  inch('in'),
  px('px');

  const SizeUnit(this.label);
  final String label;
}

/// A photo size described by its *type and size* — never by a country or
/// document program (product rule: presets are term-specific).
@immutable
class PhotoPreset {
  const PhotoPreset({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.headRatio,
    required this.headMin,
    required this.headMax,
    this.topMarginRatio = 0.09,
    this.dpi = 300,
    this.maxKb,
    this.sizeText,
  });

  /// A user-defined size. [width]/[height] are in [unit]; pixel sizes are
  /// converted at [dpi] so the output has exactly that many pixels.
  factory PhotoPreset.custom({
    required double width,
    required double height,
    required SizeUnit unit,
    int? maxKb,
    int dpi = 300,
  }) {
    double toMm(double v) => switch (unit) {
      SizeUnit.mm => v,
      SizeUnit.inch => v * 25.4,
      SizeUnit.px => v / dpi * 25.4,
    };
    final text = '${_fmt(width)} × ${_fmt(height)} ${unit.label}';
    return PhotoPreset(
      id: 'custom',
      name: 'Custom',
      widthMm: toMm(width),
      heightMm: toMm(height),
      headRatio: 0.7,
      headMin: 0.55,
      headMax: 0.8,
      topMarginRatio: 0.1,
      dpi: dpi,
      maxKb: maxKb,
      sizeText: text,
    );
  }

  final String id;

  /// Type of photo, e.g. "Passport size".
  final String name;
  final double widthMm;
  final double heightMm;
  final int dpi;

  /// Target head height (chin to crown) as a fraction of the photo height,
  /// used for automatic framing.
  final double headRatio;

  /// Acceptable head-height range (fraction of photo height).
  final double headMin;
  final double headMax;

  /// Gap above the crown as a fraction of photo height.
  final double topMarginRatio;

  /// Optional file-size limit for upload forms.
  final int? maxKb;

  /// Overrides the generated size text (used for custom sizes).
  final String? sizeText;

  double get aspect => widthMm / heightMm;
  int get pixelWidth => (widthMm / 25.4 * dpi).round();
  int get pixelHeight => (heightMm / 25.4 * dpi).round();
  int? get maxBytes => maxKb == null ? null : maxKb! * 1024;

  String get sizeLabel {
    if (sizeText != null) return sizeText!;
    final mm = '${_fmt(widthMm)} × ${_fmt(heightMm)} mm';
    final inW = widthMm / 25.4;
    final inH = heightMm / 25.4;
    bool whole(double v) => (v - v.roundToDouble()).abs() < 0.01;
    if (whole(inW) && whole(inH)) {
      final mmRounded = '${widthMm.round()} × ${heightMm.round()} mm';
      return '${inW.round()} × ${inH.round()} in / $mmRounded';
    }
    return mm;
  }

  /// "Passport size (35 × 45 mm)", plus the file-size limit when set.
  String get label {
    final kb = maxKb == null ? '' : ', max $maxKb KB';
    return '$name ($sizeLabel$kb)';
  }

  /// The domain crop template used by `autoFramePortrait` and cropping.
  CropPreset toCropPreset() => CropPreset(
    id: id,
    label: name,
    widthMm: widthMm,
    heightMm: heightMm,
    dpi: dpi,
    headRatio: headRatio,
    topMarginRatio: topMarginRatio,
  );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static const passport = PhotoPreset(
    id: 'passport_35x45',
    name: 'Passport size',
    widthMm: 35,
    heightMm: 45,
    headRatio: 0.75,
    headMin: 0.71,
    headMax: 0.8,
  );
  static const square = PhotoPreset(
    id: 'square_2x2in',
    name: 'Square photo',
    widthMm: 50.8,
    heightMm: 50.8,
    headRatio: 0.6,
    headMin: 0.5,
    headMax: 0.69,
    topMarginRatio: 0.12,
  );
  static const stamp = PhotoPreset(
    id: 'stamp_20x25',
    name: 'Stamp size',
    widthMm: 20,
    heightMm: 25,
    headRatio: 0.62,
    headMin: 0.55,
    headMax: 0.72,
    topMarginRatio: 0.1,
  );
  static const id30x40 = PhotoPreset(
    id: 'id_30x40',
    name: 'ID photo',
    widthMm: 30,
    heightMm: 40,
    headRatio: 0.7,
    headMin: 0.62,
    headMax: 0.78,
    topMarginRatio: 0.1,
  );

  static const List<PhotoPreset> builtIn = [passport, square, stamp, id30x40];

  @override
  bool operator ==(Object other) =>
      other is PhotoPreset &&
      other.id == id &&
      other.widthMm == widthMm &&
      other.heightMm == heightMm &&
      other.maxKb == maxKb &&
      other.dpi == dpi;

  @override
  int get hashCode => Object.hash(id, widthMm, heightMm, maxKb, dpi);
}

/// Validates a custom size. Returns a friendly message, or `null` if valid.
String? validateCustomSize({
  required double? width,
  required double? height,
  required SizeUnit unit,
  int? maxKb,
}) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 'Enter a width and height greater than zero.';
  }
  final (min, max) = switch (unit) {
    SizeUnit.mm => (10.0, 200.0),
    SizeUnit.inch => (0.4, 8.0),
    SizeUnit.px => (100.0, 4000.0),
  };
  if (width < min || height < min || width > max || height > max) {
    return 'Use a size between ${PhotoPreset._fmt(min)} and '
        '${PhotoPreset._fmt(max)} ${unit.label}.';
  }
  final ratio = math.max(width, height) / math.min(width, height);
  if (ratio > 2) return 'That shape is too narrow for a portrait photo.';
  if (maxKb != null && (maxKb < 10 || maxKb > 5000)) {
    return 'Use a file-size limit between 10 and 5000 KB.';
  }
  return null;
}

/// Where the preset's photo, head oval and eye line sit on a live preview,
/// in coordinates normalized to the upright preview (0..1 on each axis).
@immutable
class GuideGeometry {
  const GuideGeometry({
    required this.frame,
    required this.oval,
    required this.eyeLineY,
    required this.headMin,
    required this.headMax,
  });

  /// The photo outline occupies up to [fill] of the preview on each axis,
  /// keeping the preset aspect in *pixels* for a preview of
  /// [previewAspect] (width / height).
  factory GuideGeometry.forPreset(
    PhotoPreset preset, {
    required double previewAspect,
    double fill = 0.8,
  }) {
    // Work in a preview that is `previewAspect` wide and 1 tall.
    var fw = previewAspect * fill;
    var fh = fw / preset.aspect;
    if (fh > fill) {
      fh = fill;
      fw = fh * preset.aspect;
    }
    final nfw = fw / previewAspect;
    final frame = NRect((1 - nfw) / 2, (1 - fh) / 2, nfw, fh);
    final headH = preset.headRatio * fh;
    final headTop = frame.top + preset.topMarginRatio * fh;
    // Heads are about 0.74 as wide as they are tall.
    final ovalW = headH * 0.74 / previewAspect;
    final oval = NRect(0.5 - ovalW / 2, headTop, ovalW, headH);
    return GuideGeometry(
      frame: frame,
      oval: oval,
      eyeLineY: headTop + headH * eyeLineFromCrown,
      headMin: preset.headMin,
      headMax: preset.headMax,
    );
  }

  /// Eyes sit a little under half-way from crown to chin.
  static const eyeLineFromCrown = 0.47;

  final NRect frame;
  final NRect oval;
  final double eyeLineY;
  final double headMin;
  final double headMax;
}
