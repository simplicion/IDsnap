import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 30, 30));
  return img.encodeJpg(im);
}

PlacedImage _placed(double left, double top, {bool border = true}) =>
    PlacedImage(
      jpeg: _jpeg(86, 54),
      left: left,
      top: top,
      width: 242.65,
      height: 153.01,
      border: border,
    );

String _latin1(Uint8List b) => latin1.decode(b, allowInvalid: true);

void main() {
  const a4w = 595.28;
  const a4h = 841.89;

  test('uncompressed sheet has exact page size and both images', () async {
    final bytes = await buildSheetPdf(
      SheetJob.fromPlaced(
        [_placed(176, 150), _placed(176, 400)],
        pageWidthPt: a4w,
        pageHeightPt: a4h,
        compress: false,
      ),
    );
    final text = _latin1(bytes);
    expect(text.startsWith('%PDF-'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
    expect(text, matches(RegExp(r'/MediaBox\s*\[0 0 595.28 841.89\]')));
    expect(RegExp(r'/Subtype\s*/Image').allMatches(text).length, 2);
  });

  test('watermark text is drawn when requested', () async {
    Future<String> build(String? mark) async => _latin1(
      await buildSheetPdf(
        SheetJob.fromPlaced(
          [_placed(10, 10)],
          pageWidthPt: a4w,
          pageHeightPt: a4h,
          watermark: mark,
          compress: false,
        ),
      ),
    );
    final withMark = await build('COPY — for bank KYC only');
    final without = await build(null);
    // Text is drawn as `[(COPY - for bank KYC only)]TJ` in Helvetica-Bold.
    expect(withMark, contains('(COPY'));
    expect(withMark, contains('KYC'));
    expect(withMark, contains('Helvetica-Bold'));
    expect(withMark, contains('/ca 0.12'));
    expect(without, isNot(contains('TJ')));
  });

  test('sanitizeWatermark keeps text Latin-1 safe', () {
    expect(sanitizeWatermark('COPY — for “bank” ₹'), 'COPY - for ?bank? ?');
    expect(sanitizeWatermark('a\nb'), 'a b');
    expect(sanitizeWatermark('x' * 200).length, 80);
  });

  group('SheetPdfBuilderImpl', () {
    const builder = SheetPdfBuilderImpl();

    test('builds a valid PDF in a background isolate', () async {
      final r = await builder.build(
        [_placed(176, 150), _placed(176, 400)],
        pageWidthPt: a4w,
        pageHeightPt: a4h,
        watermark: 'COPY',
      );
      expect(r.failureOrNull, isNull);
      expect(_latin1(r.valueOrNull!).startsWith('%PDF-'), isTrue);
    });

    test('invalid input fails with a typed failure', () async {
      final empty = await builder.build(
        const [],
        pageWidthPt: a4w,
        pageHeightPt: a4h,
      );
      expect(empty.failureOrNull?.code, FailureCode.conversionFailed);

      final badPage = await builder.build(
        [_placed(0, 0)],
        pageWidthPt: 0,
        pageHeightPt: a4h,
      );
      expect(badPage.failureOrNull?.code, FailureCode.conversionFailed);

      final zeroSize = await builder.build(
        [PlacedImage(jpeg: _jpeg(4, 4), left: 0, top: 0, width: 0, height: 10)],
        pageWidthPt: a4w,
        pageHeightPt: a4h,
      );
      expect(zeroSize.failureOrNull?.code, FailureCode.conversionFailed);

      final notJpeg = await builder.build(
        [
          PlacedImage(
            jpeg: Uint8List.fromList([1, 2, 3]),
            left: 0,
            top: 0,
            width: 10,
            height: 10,
          ),
        ],
        pageWidthPt: a4w,
        pageHeightPt: a4h,
      );
      expect(notJpeg.isOk, isFalse);
    });
  });
}
