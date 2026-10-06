import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_pdf/src/pdf_writer.dart' show fitRect;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

Uint8List _jpeg(int w, int h, {int shade = 200}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

int _countPages(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;

void main() {
  final engine = PdfEngineImpl();

  group('writing (package:pdf)', () {
    test('fitRect preserves aspect and centers', () {
      final r = fitRect(200, 100, 100, 100);
      expect(r.width, 100);
      expect(r.height, 50);
      expect(r.y, 25);
    });

    test('fromImages builds one page per image', () async {
      final r = await engine.fromImages([
        _jpeg(300, 400),
        _jpeg(400, 300),
        _jpeg(200, 200),
      ], const PdfBuildOptions());
      final bytes = r.valueOrNull!;
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(_countPages(bytes), 3);
    });

    test('fromImages with fit and a text layer', () async {
      const layer = OcrResult(
        script: OcrScript.latin,
        blocks: [
          OcrBlock([
            OcrLine('Hello searchable world', NRect(0.1, 0.1, 0.8, 0.05)),
            OcrLine('नमस्ते', NRect(0.1, 0.3, 0.3, 0.05)),
          ]),
        ],
      );
      final r = await engine.fromImages(
        [_jpeg(600, 800)],
        const PdfBuildOptions(pageSize: PdfPageSize.fit),
        textLayers: [layer],
      );
      expect(r.isOk, isTrue);
      expect(_countPages(r.valueOrNull!), 1);
    });

    test('fromImages rejects empty input', () async {
      final r = await engine.fromImages([], const PdfBuildOptions());
      expect(r.failureOrNull?.code, FailureCode.conversionFailed);
    });

    test('fromText paginates long text and survives non-Latin chars', () async {
      final text = List.generate(
        400,
        (i) => 'Line $i — ünïcödé ✓ हिंदी',
      ).join('\n');
      final r = await engine.fromText(text, const TextPdfOptions());
      final bytes = r.valueOrNull!;
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(_countPages(bytes), greaterThan(1));
    });

    test('fromText treats form feed as a hard page break', () async {
      final r = await engine.fromText(
        'Slide 1\nTitle\fSlide 2\fSlide 3',
        const TextPdfOptions(),
      );
      expect(_countPages(r.valueOrNull!), 3);
    });

    test('fromText monospace', () async {
      final r = await engine.fromText(
        'a,b,c\n1,2,3',
        const TextPdfOptions(monospace: true),
      );
      expect(_countPages(r.valueOrNull!), 1);
    });
  });

  group('reading & assembly (PDFium via pdfrx)', () {
    late Directory dir;
    var pdfiumReady = false;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('pdf_engine_test');
      try {
        await pdfrxInitialize();
        pdfiumReady = true;
      } on Object catch (e) {
        // Test diagnostics only; not app logging.
        // ignore: avoid_print
        print('PDFium unavailable in this environment: $e');
      }
    });

    tearDownAll(() => dir.delete(recursive: true));

    Future<String> writePdf(String name, int pages) async {
      final bytes = (await engine.fromImages(
        [for (var i = 0; i < pages; i++) _jpeg(300 + i * 10, 400)],
        const PdfBuildOptions(),
        textLayers: [
          for (var i = 0; i < pages; i++)
            OcrResult(
              script: OcrScript.latin,
              blocks: [
                OcrBlock([
                  OcrLine('Page marker $i', const NRect(0.1, 0.1, 0.6, 0.05)),
                ]),
              ],
            ),
        ],
      )).valueOrNull!;
      final f = File('${dir.path}/$name.pdf');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    Future<String> save(Uint8List bytes, String name) async {
      final f = File('${dir.path}/$name.pdf');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    // Production audit 2026-09: the UI passes an onProgress callback that
    // captures Riverpod/Flutter objects. If any engine closure handed to
    // Isolate.run captures it, the call fails with "Illegal argument in
    // isolate message" → "Compress PDF: Conversion failed". A captured
    // ReceivePort reproduces exactly that condition on any host.
    test('compress and render work with an unsendable onProgress', () async {
      if (!pdfiumReady) return markTestSkipped('PDFium unavailable');
      final path = await writePdf('isolate', 2);
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      final progress = <double>[];
      final compressed = await engine.compress(
        path,
        PdfCompressionLevel.recommended,
        onProgress: (p) {
          unsendable.sendPort; // captured like a notifier/ref would be
          progress.add(p);
        },
      );
      expect(
        compressed.failureOrNull,
        isNull,
        reason: '${compressed.failureOrNull?.diagnostics}',
      );
      expect(progress.last, 1);
      final png = await engine.renderPage(path, 0, targetWidth: 300);
      expect(png.failureOrNull, isNull);
    });

    test('empty and corrupt files fail with typed reasons', () async {
      if (!pdfiumReady) return markTestSkipped('PDFium unavailable');
      final empty = File('${dir.path}/empty.pdf')..writeAsBytesSync([]);
      expect(
        (await engine.pageCount(empty.path)).failureOrNull?.code,
        FailureCode.emptyFile,
      );
      final junk = File('${dir.path}/junk.pdf')
        ..writeAsBytesSync(List.filled(500, 42));
      expect(
        (await engine.compress(
          junk.path,
          PdfCompressionLevel.light,
        )).failureOrNull?.code,
        FailureCode.corruptFile,
      );
    });

    test(
      'pageCount, merge, select, rotate, extractText, render, compress',
      () async {
        if (!pdfiumReady) {
          markTestSkipped('PDFium could not be initialized on this host');
          return;
        }
        final a = await writePdf('a', 2);
        final b = await writePdf('b', 3);
        expect((await engine.pageCount(a)).valueOrNull, 2);

        final merged = await save(
          (await engine.merge([a, b])).valueOrNull!,
          'm',
        );
        expect((await engine.pageCount(merged)).valueOrNull, 5);

        final picked = await save(
          (await engine.selectPages(merged, [4, 0])).valueOrNull!,
          's',
        );
        expect((await engine.pageCount(picked)).valueOrNull, 2);

        final text = (await engine.extractText(picked)).valueOrNull!;
        expect(text[0], contains('Page marker 2'));
        expect(text[1], contains('Page marker 0'));

        final rotated = await save(
          (await engine.rotatePages(picked, {0: 1})).valueOrNull!,
          'r',
        );
        expect((await engine.pageCount(rotated)).valueOrNull, 2);

        final png = (await engine.renderPage(
          a,
          0,
          targetWidth: 200,
        )).valueOrNull!;
        final decoded = img.decodePng(png)!;
        expect(decoded.width, 200);

        final progress = <double>[];
        final compressed = await save(
          (await engine.compress(
            merged,
            PdfCompressionLevel.strong,
            onProgress: progress.add,
          )).valueOrNull!,
          'c',
        );
        expect((await engine.pageCount(compressed)).valueOrNull, 5);
        expect(progress.last, 1);
      },
    );

    test('invalid inputs map to typed failures', () async {
      if (!pdfiumReady) {
        markTestSkipped('PDFium could not be initialized on this host');
        return;
      }
      final junk = File('${dir.path}/junk.pdf')..writeAsStringSync('not a pdf');
      expect(
        (await engine.pageCount(junk.path)).failureOrNull?.code,
        FailureCode.corruptFile,
      );
      expect(
        (await engine.pageCount('${dir.path}/missing.pdf')).failureOrNull?.code,
        FailureCode.notFound,
      );
      final a = await writePdf('x', 1);
      expect(
        (await engine.selectPages(a, [3])).failureOrNull?.code,
        FailureCode.conversionFailed,
      );
    });
  });
}
