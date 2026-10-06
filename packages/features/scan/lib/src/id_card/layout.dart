import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';

/// ISO/IEC 7810 ID-1 card: 85.6 × 53.98 mm.
const double idCardWidthMm = 85.6;
const double idCardHeightMm = 53.98;
const double idCardAspect = idCardWidthMm / idCardHeightMm; // ≈ 1.586

const double _ptPerMm = 72 / 25.4;
const double idCardWidthPt = idCardWidthMm * _ptPerMm; // ≈ 242.65
const double idCardHeightPt = idCardHeightMm * _ptPerMm; // ≈ 153.01
const double idCardGapPt = 12 * _ptPerMm; // 12 mm ≈ 34.02

enum IdCardLayout {
  stacked('Stacked', 'Front above back, A4 portrait'),
  sideBySide('Side by side', 'Front beside back, A4 landscape');

  const IdCardLayout(this.label, this.hint);
  final String label;
  final String hint;
}

enum IdCardSizing {
  actual('Actual size', 'Prints at real card size'),
  fit('Fit page', 'Larger, easier to read');

  const IdCardSizing(this.label, this.hint);
  final String label;
  final String hint;
}

/// Page size and placed card images for the ID card sheet.
class IdCardSheetLayout {
  const IdCardSheetLayout({
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.images,
  });

  final double pageWidthPt;
  final double pageHeightPt;
  final List<PlacedImage> images;
}

/// Places [front] and [back] on one A4 page.
///
/// - [IdCardLayout.stacked]: A4 portrait, front above back.
/// - [IdCardLayout.sideBySide]: A4 landscape, front left of back.
/// - [IdCardSizing.actual]: each card at 85.6 × 53.98 mm.
/// - [IdCardSizing.fit]: the card group spans 80 % of the page width
///   (shrunk further if it would not fit the page height).
///
/// A card whose aspect is < 1 (a portrait/vertical card) is placed rotated,
/// i.e. with swapped dimensions. Cards are 12 mm apart and the group is
/// centered on the page.
IdCardSheetLayout layoutIdCards({
  required Uint8List front,
  required Uint8List back,
  IdCardLayout layout = IdCardLayout.stacked,
  IdCardSizing sizing = IdCardSizing.actual,
  double frontAspect = idCardAspect,
  double backAspect = idCardAspect,
}) {
  final a4w = PdfPageSize.a4.widthPt;
  final a4h = PdfPageSize.a4.heightPt;
  final stacked = layout == IdCardLayout.stacked;
  final pageW = stacked ? a4w : a4h;
  final pageH = stacked ? a4h : a4w;

  // Base (actual) size of each card, respecting orientation.
  (double, double) actual(double aspect) => aspect >= 1
      ? (idCardWidthPt, idCardHeightPt)
      : (idCardHeightPt, idCardWidthPt);
  var (fw, fh) = actual(frontAspect);
  var (bw, bh) = actual(backAspect);

  double groupW() => stacked ? math.max(fw, bw) : fw + idCardGapPt + bw;
  double groupH() => stacked ? fh + idCardGapPt + bh : math.max(fh, bh);

  if (sizing == IdCardSizing.fit) {
    // Scale cards (not the gap) so the group spans 80 % of the page width.
    final targetW = pageW * 0.8;
    final cardsW = stacked ? math.max(fw, bw) : fw + bw;
    final gapW = stacked ? 0.0 : idCardGapPt;
    var scale = (targetW - gapW) / cardsW;
    // Never overflow 90 % of the page height.
    final cardsH = stacked ? fh + bh : math.max(fh, bh);
    final gapH = stacked ? idCardGapPt : 0.0;
    final maxScaleH = (pageH * 0.9 - gapH) / cardsH;
    scale = math.min(scale, maxScaleH);
    fw *= scale;
    fh *= scale;
    bw *= scale;
    bh *= scale;
  }

  final left0 = (pageW - groupW()) / 2;
  final top0 = (pageH - groupH()) / 2;

  final PlacedImage frontImg;
  final PlacedImage backImg;
  if (stacked) {
    final gw = groupW();
    frontImg = PlacedImage(
      jpeg: front,
      left: left0 + (gw - fw) / 2,
      top: top0,
      width: fw,
      height: fh,
    );
    backImg = PlacedImage(
      jpeg: back,
      left: left0 + (gw - bw) / 2,
      top: top0 + fh + idCardGapPt,
      width: bw,
      height: bh,
    );
  } else {
    final gh = groupH();
    frontImg = PlacedImage(
      jpeg: front,
      left: left0,
      top: top0 + (gh - fh) / 2,
      width: fw,
      height: fh,
    );
    backImg = PlacedImage(
      jpeg: back,
      left: left0 + fw + idCardGapPt,
      top: top0 + (gh - bh) / 2,
      width: bw,
      height: bh,
    );
  }
  return IdCardSheetLayout(
    pageWidthPt: pageW,
    pageHeightPt: pageH,
    images: [frontImg, backImg],
  );
}

/// How far an image's aspect is from ID-1, ignoring orientation (0 = exact).
double idCardAspectDeviation(int width, int height) {
  if (width <= 0 || height <= 0) return double.infinity;
  final a = math.max(width, height) / math.min(width, height);
  return (a / idCardAspect - 1).abs();
}

/// True when a captured card looks badly cropped (> 8 % off ID-1).
bool idCardNeedsCornerCheck(int width, int height) =>
    idCardAspectDeviation(width, height) > 0.08;
