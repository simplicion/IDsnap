import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/id_card/layout.dart';
import 'package:flutter_test/flutter_test.dart';

final _f = Uint8List.fromList([1]);
final _b = Uint8List.fromList([2]);

void _expectInside(IdCardSheetLayout l) {
  for (final i in l.images) {
    expect(i.left, greaterThanOrEqualTo(0));
    expect(i.top, greaterThanOrEqualTo(0));
    expect(i.left + i.width, lessThanOrEqualTo(l.pageWidthPt + 1e-9));
    expect(i.top + i.height, lessThanOrEqualTo(l.pageHeightPt + 1e-9));
  }
}

bool _overlap(PlacedImage a, PlacedImage b) =>
    a.left < b.left + b.width &&
    b.left < a.left + a.width &&
    a.top < b.top + b.height &&
    b.top < a.top + a.height;

void main() {
  test('ID-1 constants in points', () {
    expect(idCardWidthPt, closeTo(242.65, 0.01));
    expect(idCardHeightPt, closeTo(153.01, 0.01));
    expect(idCardGapPt, closeTo(34.02, 0.01));
    expect(idCardAspect, closeTo(1.586, 0.001));
  });

  test('stacked actual size: A4 portrait, real card size, centered', () {
    final l = layoutIdCards(front: _f, back: _b);
    expect(l.pageWidthPt, PdfPageSize.a4.widthPt);
    expect(l.pageHeightPt, PdfPageSize.a4.heightPt);
    final (front, back) = (l.images[0], l.images[1]);
    expect(front.jpeg, _f);
    expect(back.jpeg, _b);
    for (final i in l.images) {
      expect(i.width, closeTo(242.65, 0.01));
      expect(i.height, closeTo(153.01, 0.01));
      // Horizontally centered.
      expect(i.left + i.width / 2, closeTo(l.pageWidthPt / 2, 1e-9));
    }
    expect(back.top - (front.top + front.height), closeTo(idCardGapPt, 1e-9));
    // Group vertically centered.
    final groupTop = front.top;
    final groupBottom = back.top + back.height;
    expect((groupTop + groupBottom) / 2, closeTo(l.pageHeightPt / 2, 1e-9));
    expect(_overlap(front, back), isFalse);
    _expectInside(l);
  });

  test('side by side actual size: A4 landscape, centered, 12 mm gap', () {
    final l = layoutIdCards(
      front: _f,
      back: _b,
      layout: IdCardLayout.sideBySide,
    );
    expect(l.pageWidthPt, PdfPageSize.a4.heightPt);
    expect(l.pageHeightPt, PdfPageSize.a4.widthPt);
    final (front, back) = (l.images[0], l.images[1]);
    expect(back.left - (front.left + front.width), closeTo(idCardGapPt, 1e-9));
    expect(
      (front.left + back.left + back.width) / 2,
      closeTo(l.pageWidthPt / 2, 1e-9),
    );
    expect(front.top + front.height / 2, closeTo(l.pageHeightPt / 2, 1e-9));
    expect(_overlap(front, back), isFalse);
    _expectInside(l);
  });

  test('fit sizing spans 80% of page width and keeps ID-1 aspect', () {
    final stacked = layoutIdCards(
      front: _f,
      back: _b,
      sizing: IdCardSizing.fit,
    );
    final w = stacked.images.first.width;
    expect(w, closeTo(stacked.pageWidthPt * 0.8, 1e-9));
    expect(w / stacked.images.first.height, closeTo(idCardAspect, 1e-9));
    _expectInside(stacked);

    final side = layoutIdCards(
      front: _f,
      back: _b,
      layout: IdCardLayout.sideBySide,
      sizing: IdCardSizing.fit,
    );
    final (a, b) = (side.images[0], side.images[1]);
    expect(b.left + b.width - a.left, closeTo(side.pageWidthPt * 0.8, 1e-9));
    expect(a.width / a.height, closeTo(idCardAspect, 1e-9));
    expect(_overlap(a, b), isFalse);
    _expectInside(side);
  });

  test('portrait (vertical) cards are placed with swapped dimensions', () {
    final l = layoutIdCards(front: _f, back: _b, frontAspect: 0.63);
    expect(l.images[0].width, closeTo(idCardHeightPt, 1e-9));
    expect(l.images[0].height, closeTo(idCardWidthPt, 1e-9));
    expect(l.images[1].width, closeTo(idCardWidthPt, 1e-9));
    expect(_overlap(l.images[0], l.images[1]), isFalse);
    _expectInside(l);
  });

  test('corner check threshold is 8% in either orientation', () {
    expect(idCardNeedsCornerCheck(1586, 1000), isFalse);
    expect(idCardNeedsCornerCheck(1000, 1586), isFalse);
    expect(idCardNeedsCornerCheck(1700, 1000), isFalse); // ~7.2 %
    expect(idCardNeedsCornerCheck(1740, 1000), isTrue); // ~9.7 %
    expect(idCardNeedsCornerCheck(1000, 1000), isTrue);
    expect(idCardNeedsCornerCheck(0, 10), isTrue);
  });
}
