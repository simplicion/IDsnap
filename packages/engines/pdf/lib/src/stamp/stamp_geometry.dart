import 'dart:math' as math;

/// Maps the *displayed* page space used by stamps (points, top-left origin,
/// `/Rotate` and the crop box applied — what PDFium renders) to PDF user
/// space (points, bottom-left origin, unrotated).
///
/// For a display point (u, v):
///
/// | Rotate | x        | y        |
/// |--------|----------|----------|
/// | 0      | x0 + u   | y1 − v   |
/// | 90     | x0 + v   | y0 + u   |
/// | 180    | x1 − u   | y0 + v   |
/// | 270    | x1 − v   | y1 − u   |
///
/// where [x0, y0, x1, y1] is the visible box (crop box ∩ media box).
class PageGeometry {
  PageGeometry({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    int rotate = 0,
  }) : rotate = normalizeRotation(rotate);

  /// Builds the geometry the way PDFium does: the crop box intersected with
  /// the media box (the media box alone when the crop box is missing or
  /// empty). Missing media boxes default to US Letter.
  factory PageGeometry.fromBoxes(
    List<double>? mediaBox,
    List<double>? cropBox,
    int rotate,
  ) {
    var media = _normalize(mediaBox) ?? const [0.0, 0.0, 612.0, 792.0];
    final crop = _normalize(cropBox);
    if (crop != null) {
      final ix0 = math.max(media[0], crop[0]);
      final iy0 = math.max(media[1], crop[1]);
      final ix1 = math.min(media[2], crop[2]);
      final iy1 = math.min(media[3], crop[3]);
      if (ix1 > ix0 && iy1 > iy0) media = [ix0, iy0, ix1, iy1];
    }
    return PageGeometry(
      x0: media[0],
      y0: media[1],
      x1: media[2],
      y1: media[3],
      rotate: rotate,
    );
  }

  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// 0, 90, 180 or 270 (clockwise when displayed).
  final int rotate;

  static int normalizeRotation(int degrees) {
    final quarter = ((degrees / 90).round()) % 4;
    return (quarter < 0 ? quarter + 4 : quarter) * 90;
  }

  static List<double>? _normalize(List<double>? box) {
    if (box == null || box.length != 4) return null;
    final a = math.min(box[0], box[2]);
    final b = math.min(box[1], box[3]);
    final c = math.max(box[0], box[2]);
    final d = math.max(box[1], box[3]);
    if (c - a <= 0 || d - b <= 0) return null;
    return [a, b, c, d];
  }

  bool get _swapped => rotate == 90 || rotate == 270;

  double get displayWidth => _swapped ? y1 - y0 : x1 - x0;
  double get displayHeight => _swapped ? x1 - x0 : y1 - y0;

  /// Affine coefficients of display → user: x = a·u + c·v + e,
  /// y = b·u + d·v + f.
  ({double a, double b, double c, double d, double e, double f}) get _map =>
      switch (rotate) {
        90 => (a: 0, b: 1, c: 1, d: 0, e: x0, f: y0),
        180 => (a: -1, b: 0, c: 0, d: 1, e: x1, f: y0),
        270 => (a: 0, b: -1, c: -1, d: 0, e: x1, f: y1),
        _ => (a: 1, b: 0, c: 0, d: -1, e: x0, f: y1),
      };

  /// Display point → user space.
  (double, double) toUser(double u, double v) {
    final m = _map;
    return (m.a * u + m.c * v + m.e, m.b * u + m.d * v + m.f);
  }

  /// `cm` operands that map an image's unit square onto the display rect
  /// ([left], [top], [width], [height]) so the image appears upright.
  List<double> imageMatrix(
    double left,
    double top,
    double width,
    double height,
  ) {
    // Image space (s, t) has t = 1 at the top edge: u = left + s·w,
    // v = top + h − t·h.
    final m = _map;
    final bottom = top + height;
    return [
      m.a * width,
      m.b * width,
      -m.c * height,
      -m.d * height,
      m.a * left + m.c * bottom + m.e,
      m.b * left + m.d * bottom + m.f,
    ];
  }

  /// `cm` operands for text whose baseline starts at display ([left],
  /// [baseline]); one text-space unit is one point.
  List<double> textMatrix(double left, double baseline) {
    final m = _map;
    return [
      m.a,
      m.b,
      -m.c,
      -m.d,
      m.a * left + m.c * baseline + m.e,
      m.b * left + m.d * baseline + m.f,
    ];
  }
}
