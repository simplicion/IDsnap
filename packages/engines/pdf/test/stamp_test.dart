import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_pdf/src/stamp/incremental_stamper.dart';
import 'package:engine_pdf/src/stamp/pdf_syntax.dart';
import 'package:engine_pdf/src/stamp/stamp_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

/// 40x40 PNG: transparent border, opaque black 20x20 centre.
Uint8List _signaturePng() {
  final im = img.Image(width: 40, height: 40, numChannels: 4);
  for (final p in im) {
    final inside = p.x >= 10 && p.x < 30 && p.y >= 10 && p.y < 30;
    p
      ..r = 0
      ..g = 0
      ..b = 0
      ..a = inside ? 255 : 0;
  }
  return img.encodePng(im);
}

/// A vector-text PDF built with package:pdf.
Future<Uint8List> _textPdf({
  int pages = 2,
  pdf.PdfVersion version = pdf.PdfVersion.pdf_1_5,
}) async {
  final doc = pw.Document(version: version);
  for (var i = 0; i < pages; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        build: (_) => pw.Text('Selectable text on page $i'),
      ),
    );
  }
  return await doc.save();
}

void main() {
  group('PageGeometry (points ↔ PDF user space)', () {
    test('unrotated page: top-left display maps to top of media box', () {
      final g = PageGeometry(x0: 0, y0: 0, x1: 600, y1: 800);
      expect(g.toUser(0, 0), (0.0, 800.0));
      expect(g.toUser(600, 800), (600.0, 0.0));
      expect((g.displayWidth, g.displayHeight), (600.0, 800.0));
      // Unit square → rect (10, 20, 100 x 50) from the top-left.
      expect(g.imageMatrix(10, 20, 100, 50), [100, 0, 0, 50, 10, 730]);
    });

    test('rotated pages swap display size and keep images upright', () {
      for (final rotate in [90, 180, 270]) {
        final g = PageGeometry(x0: 0, y0: 0, x1: 600, y1: 800, rotate: rotate);
        final swapped = rotate != 180;
        expect(g.displayWidth, swapped ? 800 : 600);
        expect(g.displayHeight, swapped ? 600 : 800);
        final m = g.imageMatrix(10, 20, 100, 50);
        // The image's top-left corner (s=0, t=1) lands on display (10, 20).
        final topLeft = (m[2] + m[4], m[3] + m[5]);
        expect(topLeft, g.toUser(10, 20), reason: 'rotate $rotate');
        // Its bottom-right corner (s=1, t=0) lands on display (110, 70).
        final bottomRight = (m[0] + m[4], m[1] + m[5]);
        expect(bottomRight, g.toUser(110, 70), reason: 'rotate $rotate');
      }
    });

    test('rotate 90: display top-left is the bottom-left of the page', () {
      final g = PageGeometry(x0: 0, y0: 0, x1: 600, y1: 800, rotate: 90);
      expect(g.toUser(0, 0), (0.0, 0.0));
      expect(g.toUser(800, 0), (0.0, 800.0));
    });

    test('crop box is intersected with the media box, like PDFium', () {
      final g = PageGeometry.fromBoxes([0, 0, 600, 800], [50, 60, 700, 500], 0);
      expect((g.x0, g.y0, g.x1, g.y1), (50.0, 60.0, 600.0, 500.0));
      expect(g.toUser(0, 0), (50.0, 500.0));
      final fallback = PageGeometry.fromBoxes(null, null, -90);
      expect(fallback.rotate, 270);
      expect(fallback.displayWidth, 792);
    });

    test('text matrix places the baseline at the given display point', () {
      final g = PageGeometry(x0: 0, y0: 0, x1: 600, y1: 800);
      expect(g.textMatrix(30, 100), [1, 0, 0, 1, 30, 700]);
    });
  });

  group('PDF syntax', () {
    test('parses and rewrites objects', () {
      final lexer = PdfLexer(
        Uint8List.fromList(
          r'<< /A 1 0 R /B [1 2.5 (x\)y) <0aff>] /C true /D null >>'.codeUnits,
        ),
      );
      final o = lexer.parseObject() as Map<String, Object>;
      expect(o['A'], const PdfRef(1, 0));
      expect((o['B']! as List).length, 4);
      expect(o['C'], true);
      final w = PdfWriter()..value(o);
      final again = PdfLexer(w.takeBytes()).parseObject() as Map;
      expect(again['A'], const PdfRef(1, 0));
      expect(formatPdfNumber(1.23456), '1.2346');
      expect(formatPdfNumber(-0.00001), '0');
    });

    test('reads the page tree of classic and xref-stream files', () async {
      for (final v in pdf.PdfVersion.values) {
        final file = PdfFile(await _textPdf(pages: 3, version: v));
        expect(file.pages().length, 3, reason: '$v');
        expect(file.usesXrefStream, v == pdf.PdfVersion.pdf_1_5);
      }
    });

    test('validateStamps explains what to fix', () {
      expect(validateStamps(const []), contains('at least one'));
      expect(
        validateStamps([
          PdfImageStamp(
            pageIndex: 0,
            left: 0,
            top: 0,
            width: 0,
            height: 10,
            png: _signaturePng(),
          ),
        ]),
        contains('too small'),
      );
      expect(
        validateStamps(const [
          PdfTextStamp(pageIndex: 0, left: 0, top: 0, text: '  '),
        ]),
        contains('empty'),
      );
    });
  });

  group('stamping (incremental update + PDFium verification)', () {
    final engine = PdfEngineImpl();
    late Directory dir;
    var ready = false;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('stamp_test');
      try {
        await pdfrxInitialize();
        ready = true;
      } on Object catch (e) {
        // Test diagnostics only.
        // ignore: avoid_print
        print('PDFium unavailable: $e');
      }
    });

    tearDownAll(() => dir.delete(recursive: true));

    Future<String> save(Uint8List bytes, String name) async {
      final f = File('${dir.path}/$name.pdf');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    /// Luma of the rendered page at display point (u, v) in points.
    Future<int> lumaAt(String path, int page, double u, double v) async {
      final dims = (await engine.pageDimensions(path)).valueOrNull![page];
      final png = (await engine.renderPage(
        path,
        page,
        targetWidth: 400,
      )).valueOrNull!;
      final image = img.decodePng(png)!;
      final k = image.width / dims.width;
      return image.getPixel((u * k).round(), (v * k).round()).luminance.toInt();
    }

    for (final version in pdf.PdfVersion.values) {
      test('keeps text selectable and page count ($version)', () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        final input = await _textPdf(version: version);
        final path = await save(input, 'in_${version.name}');
        final dims = (await engine.pageDimensions(path)).valueOrNull!;
        expect(dims.first.width, closeTo(595.28, 0.1));

        final r = await engine.stamp(path, [
          PdfImageStamp(
            pageIndex: 1,
            left: 300,
            top: 400,
            width: 120,
            height: 120,
            png: _signaturePng(),
          ),
          const PdfTextStamp(
            pageIndex: 1,
            left: 300,
            top: 540,
            text: 'Signed 25 Sep 2026',
          ),
        ]);
        expect(r.failureOrNull, isNull, reason: r.failureOrNull?.diagnostics);
        final out = r.valueOrNull!;
        expect(out.method, StampMethod.incremental);
        expect(out.pageCount, 2);
        expect(out.bytes.length, greaterThan(input.length));
        // The original bytes are kept verbatim.
        expect(out.bytes.sublist(0, input.length), input);

        final outPath = await save(out.bytes, 'out_${version.name}');
        expect((await engine.pageCount(outPath)).valueOrNull, 2);
        final text = (await engine.extractText(outPath)).valueOrNull!;
        expect(text[0], contains('Selectable text on page 0'));
        expect(text[1], contains('Selectable text on page 1'));
        expect(text[1], contains('Signed 25 Sep 2026'));

        // Opaque centre is drawn; the transparent border is not.
        expect(await lumaAt(outPath, 1, 360, 460), lessThan(60));
        expect(await lumaAt(outPath, 1, 305, 405), greaterThan(200));
        // Page 0 is untouched.
        expect(await lumaAt(outPath, 0, 360, 460), greaterThan(200));

        // A second signing round appends another update.
        final again = await engine.stamp(outPath, [
          PdfImageStamp(
            pageIndex: 0,
            left: 20,
            top: 20,
            width: 60,
            height: 60,
            png: _signaturePng(),
          ),
        ]);
        expect(again.valueOrNull?.method, StampMethod.incremental);
      });
    }

    test('rotated pages: the stamp appears where it was placed', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      final base = await save(await _textPdf(pages: 1), 'rot_base');
      for (final turns in [1, 2, 3]) {
        final rotated = await save(
          (await engine.rotatePages(base, {0: turns})).valueOrNull!,
          'rot_$turns',
        );
        final dims = (await engine.pageDimensions(rotated)).valueOrNull!.first;
        expect(dims.width > dims.height, turns.isOdd);
        final r = await engine.stamp(rotated, [
          PdfImageStamp(
            pageIndex: 0,
            left: 0,
            top: 0,
            width: 100,
            height: 100,
            png: _signaturePng(),
          ),
        ]);
        final out = await save(r.valueOrNull!.bytes, 'rot_out_$turns');
        // Centre of the square is at display (50, 50).
        expect(await lumaAt(out, 0, 50, 50), lessThan(60), reason: '$turns');
        expect(
          await lumaAt(out, 0, dims.width - 50, dims.height - 50),
          greaterThan(200),
          reason: '$turns',
        );
      }
    });

    test(
      'unparseable cross-reference falls back to a PDFium re-save',
      () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        final good = await _textPdf(version: pdf.PdfVersion.pdf_1_4);
        // Break startxref: PDFium repairs the file, this parser can't.
        final text = String.fromCharCodes(good);
        final at = text.lastIndexOf('startxref');
        final broken = Uint8List.fromList([
          ...good.sublist(0, at),
          ...'startxref\n9\n%%EOF\n'.codeUnits,
        ]);
        final path = await save(broken, 'broken');
        expect((await engine.pageCount(path)).valueOrNull, 2);
        final r = await engine.stamp(path, [
          PdfImageStamp(
            pageIndex: 0,
            left: 100,
            top: 100,
            width: 80,
            height: 80,
            png: _signaturePng(),
          ),
        ]);
        expect(r.failureOrNull, isNull, reason: r.failureOrNull?.diagnostics);
        expect(r.valueOrNull!.method, StampMethod.rebuilt);
        final out = await save(r.valueOrNull!.bytes, 'broken_out');
        final text0 = (await engine.extractText(out)).valueOrNull!;
        expect(text0[0], contains('Selectable text on page 0'));
      },
    );

    test('typed failures for bad stamps and pages', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      final path = await save(await _textPdf(pages: 1), 'bad');
      final badPng = await engine.stamp(path, [
        PdfImageStamp(
          pageIndex: 0,
          left: 1,
          top: 1,
          width: 10,
          height: 10,
          png: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
      expect(badPng.failureOrNull?.code, FailureCode.corruptFile);
      expect(badPng.failureOrNull?.recovery, contains('Create it again'));

      final badPage = await engine.stamp(path, const [
        PdfTextStamp(pageIndex: 4, left: 1, top: 1, text: 'x'),
      ]);
      expect(badPage.failureOrNull?.code, FailureCode.conversionFailed);

      final none = await engine.stamp(path, const []);
      expect(none.failureOrNull?.recovery, contains('at least one'));

      final missing = await engine.stamp('${dir.path}/nope.pdf', const [
        PdfTextStamp(pageIndex: 0, left: 1, top: 1, text: 'x'),
      ]);
      expect(missing.failureOrNull?.code, FailureCode.notFound);
    });

    test('raster fallback composites stamps at the right place', () {
      // 100x100 white page (BGRA) representing a 100 pt wide page.
      final bgra = Uint8List(100 * 100 * 4)..fillRange(0, 100 * 100 * 4, 255);
      final jpeg = compositeStampsOnRaster(bgra, 100, 100, 100, [
        PdfImageStamp(
          pageIndex: 0,
          left: 50,
          top: 50,
          width: 40,
          height: 40,
          png: _signaturePng(),
        ),
      ]);
      final out = img.decodeJpg(jpeg)!;
      expect(out.getPixel(70, 70).luminance, lessThan(60));
      expect(out.getPixel(52, 52).luminance, greaterThan(200));
      expect(out.getPixel(10, 10).luminance, greaterThan(200));
    });
  });
}
