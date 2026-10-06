import 'dart:math' as math;

import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

const double _ptPerMm = 72 / 25.4;

/// Paper for a print sheet of identical photos.
enum PrintPaper {
  photo4x6('4 × 6 in photo paper', 101.6, 152.4),
  a4('A4 paper', 210, 297);

  const PrintPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

/// A page of photos in a grid (all positions in PDF points, top-left).
@immutable
class PrintSheetLayout {
  const PrintSheetLayout({
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.columns,
    required this.rows,
    required this.images,
  });

  final double pageWidthPt;
  final double pageHeightPt;
  final int columns;
  final int rows;
  final List<PlacedImage> images;

  int get capacity => columns * rows;
}

/// How many photos of [photoWidthMm] × [photoHeightMm] fit on [paper],
/// choosing portrait or landscape paper, whichever fits more.
({int columns, int rows, bool landscape}) printSheetCapacity(
  PrintPaper paper, {
  required double photoWidthMm,
  required double photoHeightMm,
  double marginMm = 5,
  double gapMm = 2,
}) {
  int fit(double avail, double size) =>
      math.max(0, ((avail + gapMm) / (size + gapMm)).floor());
  ({int columns, int rows}) grid(double pw, double ph) => (
    columns: fit(pw - 2 * marginMm, photoWidthMm),
    rows: fit(ph - 2 * marginMm, photoHeightMm),
  );
  final p = grid(paper.widthMm, paper.heightMm);
  final l = grid(paper.heightMm, paper.widthMm);
  return l.columns * l.rows > p.columns * p.rows
      ? (columns: l.columns, rows: l.rows, landscape: true)
      : (columns: p.columns, rows: p.rows, landscape: false);
}

/// Places up to [count] copies of [jpeg] (default: as many as fit) in a
/// centred grid with thin cut borders, at true print size.
PrintSheetLayout layoutPrintSheet({
  required Uint8List jpeg,
  required double photoWidthMm,
  required double photoHeightMm,
  required PrintPaper paper,
  int? count,
  double marginMm = 5,
  double gapMm = 2,
}) {
  final cap = printSheetCapacity(
    paper,
    photoWidthMm: photoWidthMm,
    photoHeightMm: photoHeightMm,
    marginMm: marginMm,
    gapMm: gapMm,
  );
  final pageWmm = cap.landscape ? paper.heightMm : paper.widthMm;
  final pageHmm = cap.landscape ? paper.widthMm : paper.heightMm;
  final total = cap.columns * cap.rows;
  final n = math.min(count ?? total, total);
  final usedRows = cap.columns == 0 ? 0 : (n / cap.columns).ceil();
  final usedCols = math.min(n, cap.columns);
  final gridW = usedCols * photoWidthMm + math.max(0, usedCols - 1) * gapMm;
  final gridH = usedRows * photoHeightMm + math.max(0, usedRows - 1) * gapMm;
  final left0 = (pageWmm - gridW) / 2;
  final top0 = (pageHmm - gridH) / 2;
  final images = <PlacedImage>[
    for (var i = 0; i < n; i++)
      PlacedImage(
        jpeg: jpeg,
        left: (left0 + (i % cap.columns) * (photoWidthMm + gapMm)) * _ptPerMm,
        top: (top0 + (i ~/ cap.columns) * (photoHeightMm + gapMm)) * _ptPerMm,
        width: photoWidthMm * _ptPerMm,
        height: photoHeightMm * _ptPerMm,
      ),
  ];
  return PrintSheetLayout(
    pageWidthPt: pageWmm * _ptPerMm,
    pageHeightPt: pageHmm * _ptPerMm,
    columns: cap.columns,
    rows: cap.rows,
    images: images,
  );
}
