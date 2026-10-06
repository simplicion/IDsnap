import 'dart:math' as math;
import 'dart:ui';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

/// A stamp rectangle in PDF points from the page's displayed top-left
/// corner — the space [PdfStamp] uses.
@immutable
class StampRect {
  const StampRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  Offset get center => Offset(left + width / 2, top + height / 2);

  @override
  bool operator ==(Object other) =>
      other is StampRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'StampRect($left, $top, $width x $height)';
}

/// Maps between page points and the on-screen page view. The view shows
/// the whole page at a uniform scale (its aspect ratio matches the page).
@immutable
class PageViewport {
  const PageViewport({required this.page, required this.viewWidth});

  final PdfPageDimensions page;

  /// Width of the rendered page on screen, in logical pixels.
  final double viewWidth;

  /// Logical pixels per point.
  double get scale => page.width <= 0 ? 1 : viewWidth / page.width;

  double get viewHeight => page.height * scale;

  Rect toView(StampRect r) => Rect.fromLTWH(
    r.left * scale,
    r.top * scale,
    r.width * scale,
    r.height * scale,
  );

  StampRect toPoints(Rect v) => StampRect(
    v.left / scale,
    v.top / scale,
    v.width / scale,
    v.height / scale,
  );

  /// A drag of [viewDelta] logical pixels, in points.
  Offset deltaToPoints(Offset viewDelta) => viewDelta / scale;
}

/// Smallest stamp edge, in points (about 4 mm).
const minStampPoints = 12.0;

/// Keeps [r] fully on the page, shrinking it (aspect kept) if it's larger.
StampRect clampToPage(StampRect r, PdfPageDimensions page) {
  var w = r.width;
  var h = r.height;
  final fit = math.min(1, math.min(page.width / w, page.height / h)).toDouble();
  w *= fit;
  h *= fit;
  final left = r.left.clamp(0.0, math.max(0.0, page.width - w)).toDouble();
  final top = r.top.clamp(0.0, math.max(0.0, page.height - h)).toDouble();
  return StampRect(left, top, w, h);
}

/// Moves [r] by [deltaPoints], staying on the page.
StampRect moveStamp(StampRect r, Offset deltaPoints, PdfPageDimensions page) =>
    clampToPage(
      StampRect(
        r.left + deltaPoints.dx,
        r.top + deltaPoints.dy,
        r.width,
        r.height,
      ),
      page,
    );

/// Scales [r] about its centre by [factor], keeping the aspect ratio and
/// staying between [minStampPoints] and the page size.
StampRect scaleStamp(StampRect r, double factor, PdfPageDimensions page) {
  if (!factor.isFinite || factor <= 0) return r;
  final shortest = math.min(r.width, r.height);
  final minFactor = shortest <= 0 ? 1.0 : minStampPoints / shortest;
  final maxFactor = math.min(page.width / r.width, page.height / r.height);
  final f = factor.clamp(math.min(minFactor, maxFactor), maxFactor);
  final w = r.width * f;
  final h = r.height * f;
  final c = r.center;
  return clampToPage(StampRect(c.dx - w / 2, c.dy - h / 2, w, h), page);
}

/// Resizes [r] from its bottom-right corner to [newWidth] points, keeping
/// the top-left corner and the aspect ratio (corner handle).
StampRect resizeStamp(StampRect r, double newWidth, PdfPageDimensions page) {
  if (!newWidth.isFinite || r.width <= 0) return r;
  final ratio = r.width / r.height;
  final minWidth = ratio >= 1 ? minStampPoints * ratio : minStampPoints;
  final maxWidth = math.min(page.width - r.left, (page.height - r.top) * ratio);
  final w = newWidth.clamp(math.min(minWidth, maxWidth), maxWidth).toDouble();
  return clampToPage(StampRect(r.left, r.top, w, w / ratio), page);
}

/// Default placement for a new signature: 30 % of the page width, centred
/// horizontally, in the lower part of the page.
StampRect initialSignatureRect(PdfPageDimensions page, double aspectRatio) {
  final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 3.0;
  var w = page.width * 0.3;
  var h = w / ratio;
  if (h > page.height * 0.2) {
    h = page.height * 0.2;
    w = h * ratio;
  }
  return clampToPage(
    StampRect((page.width - w) / 2, page.height * 0.72, w, h),
    page,
  );
}

/// Box of a one-line text stamp at [fontSize] points.
StampRect textStampRect(
  double left,
  double top,
  String text,
  double fontSize,
) => StampRect(
  left,
  top,
  PdfTextStamp(
    pageIndex: 0,
    left: 0,
    top: 0,
    text: text,
    fontSize: fontSize,
  ).approximateWidth,
  fontSize * 1.2,
);

/// "25 Sep 2026" without locale data (the PDF font is Latin-1 only).
String formatStampDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
