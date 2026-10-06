import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_conversion/src/ooxml/zip_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFiles extends Mock implements FileStore {}

class MockPdf extends Mock implements PdfEngine {}

class MockImages extends Mock implements ImageProcessor {}

class MockOcr extends Mock implements TextRecognizer {}

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const PageEdits());
    registerFallbackValue(const PdfBuildOptions());
    registerFallbackValue(const TextPdfOptions());
    registerFallbackValue(const ImageCompressionOptions());
    registerFallbackValue(OcrScript.latin);
    registerFallbackValue(QualityPreset.balanced);
  });

  late MockFiles files;
  late MockPdf pdf;
  late MockImages images;
  late MockOcr ocr;
  late ConversionEngineImpl engine;

  ConversionInput input(String name, DocumentFormat f) =>
      ConversionInput(path: '/in/$name.${f.extension}', name: name, format: f);

  setUp(() {
    files = MockFiles();
    pdf = MockPdf();
    images = MockImages();
    ocr = MockOcr();
    engine = ConversionEngineImpl(
      files: files,
      pdf: pdf,
      images: images,
      ocr: ocr,
    );
    when(() => files.delete(any())).thenAnswer((_) async {});
    // Pre-flight defaults: inputs exist, are non-empty, PDFs open.
    when(() => files.exists(any())).thenAnswer((_) async => true);
    when(() => files.size(any())).thenAnswer((_) async => 1024);
    when(() => pdf.pageCount(any())).thenAnswer((_) async => const Ok(2));
    when(() => files.read(any())).thenAnswer((_) async => Uint8List(0));
  });

  group('registry', () {
    test('ids are unique and every lossy spec declares limitations', () {
      final ids = ConversionSpecs.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final s in ConversionSpecs.all) {
        expect(s.inputs, isNotEmpty, reason: s.id);
        expect(s.worksOffline, isTrue, reason: s.id);
        if (s.fidelity != FidelityClass.native) {
          expect(s.limitations, isNotEmpty, reason: s.id);
        }
      }
    });

    test('OCR-only specs are hidden without a recognizer', () {
      final noOcr = ConversionEngineImpl(
        files: files,
        pdf: pdf,
        images: images,
      );
      expect(noOcr.spec(ConversionIds.imageToTxt), isNull);
      expect(noOcr.spec(ConversionIds.pdfToTxt), isNotNull);
      expect(engine.spec(ConversionIds.imageToTxt), isNotNull);
    });
  });

  group('validation', () {
    test('unknown spec is unsupportedFormat', () async {
      final r = await engine.convert(
        const ConversionRequest(specId: 'nope', inputs: []),
      );
      expect(r.failureOrNull?.code, FailureCode.unsupportedFormat);
    });

    test('wrong input format is rejected before any work', () async {
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.docxToTxt,
          inputs: [input('a', DocumentFormat.pdf)],
        ),
      );
      expect(r.failureOrNull?.code, FailureCode.unsupportedFormat);
      verifyZeroInteractions(files);
    });

    test('single-input spec rejects multiple inputs', () async {
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.txtToPdf,
          inputs: [
            input('a', DocumentFormat.txt),
            input('b', DocumentFormat.txt),
          ],
        ),
      );
      expect(r.failureOrNull?.code, FailureCode.unsupportedFormat);
    });

    test('corrupt DOCX surfaces corruptFile', () async {
      when(
        () => files.read(any()),
      ).thenAnswer((_) async => bytes(utf8.encode('garbage')));
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.docxToTxt,
          inputs: [input('d', DocumentFormat.docx)],
        ),
      );
      expect(r.failureOrNull?.code, FailureCode.corruptFile);
    });
  });

  group('PDF → text', () {
    test(
      'uses embedded text and falls back to OCR for image-only pages',
      () async {
        when(
          () => pdf.extractText('/in/scan.pdf'),
        ).thenAnswer((_) async => const Ok(['Typed page', '  ']));
        when(
          () => pdf.renderPage('/in/scan.pdf', 1, targetWidth: 2000),
        ).thenAnswer((_) async => Ok(bytes([1, 2, 3])));
        when(
          () => files.writeTemp(any(), 'png'),
        ).thenAnswer((_) async => '/tmp/p1.png');
        when(
          () => ocr.recognize('/tmp/p1.png', OcrScript.devanagari),
        ).thenAnswer(
          (_) async => const Ok(
            OcrResult(
              script: OcrScript.devanagari,
              blocks: [
                OcrBlock([OcrLine('नमस्ते scanned', NRect.full)]),
              ],
            ),
          ),
        );
        final progress = <double>[];

        final r = await engine.convert(
          ConversionRequest(
            specId: ConversionIds.pdfToTxt,
            inputs: [input('scan', DocumentFormat.pdf)],
            options: const {ConversionOptions.ocrScript: 'devanagari'},
          ),
          onProgress: progress.add,
        );

        final out = r.valueOrNull!.single;
        expect(out.format, DocumentFormat.txt);
        expect(out.suggestedName, 'scan');
        expect(
          utf8.decode(out.bytes),
          '--- Page 1 ---\nTyped page\n\n--- Page 2 ---\nनमस्ते scanned',
        );
        verifyNever(
          () => pdf.renderPage(
            '/in/scan.pdf',
            0,
            targetWidth: any(named: 'targetWidth'),
          ),
        );
        verify(() => files.delete('/tmp/p1.png')).called(1);
        expect(progress.last, 1);
      },
    );

    test('PDF → DOCX puts each page after a page break', () async {
      when(
        () => pdf.extractText(any()),
      ).thenAnswer((_) async => const Ok(['One\n\nTwo', 'Three']));
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.pdfToDocx,
          inputs: [input('p', DocumentFormat.pdf)],
        ),
      );
      final paras = readDocx(r.valueOrNull!.single.bytes);
      expect(paras.map((p) => p.text), ['One', 'Two', 'Three']);
      expect(paras.last.pageBreakBefore, isTrue);
    });
  });

  group('images', () {
    test(
      'images → PDF renders each image unfiltered and sets expected pages',
      () async {
        when(() => files.read(any())).thenAnswer((_) async => bytes([9]));
        when(
          () => images.renderPage(any(), any(), preset: any(named: 'preset')),
        ).thenAnswer((_) async => Ok(bytes([0xFF, 0xD8])));
        when(
          () => pdf.fromImages(any(), any()),
        ).thenAnswer((_) async => Ok(bytes(utf8.encode('%PDF'))));

        final r = await engine.convert(
          ConversionRequest(
            specId: ConversionIds.imagesToPdf,
            inputs: [
              input('a', DocumentFormat.jpeg),
              input('b', DocumentFormat.png),
            ],
            options: const {ConversionOptions.pageSize: 'letter'},
          ),
        );

        expect(r.valueOrNull!.single.expectedPages, 2);
        final edits = verify(
          () => images.renderPage(
            any(),
            captureAny(),
            preset: any(named: 'preset'),
          ),
        ).captured;
        expect(
          edits.cast<PageEdits>().every(
            (e) => e.filter == EnhancementFilter.original && e.quad == null,
          ),
          isTrue,
        );
        final opts =
            verify(() => pdf.fromImages(any(), captureAny())).captured.single
                as PdfBuildOptions;
        expect(opts.pageSize, PdfPageSize.letter);
      },
    );

    test('images → DOCX embeds pictures on separate pages', () async {
      when(() => files.read(any())).thenAnswer((_) async => bytes([1]));
      when(() => images.compress(any(), any())).thenAnswer(
        (_) async => const Ok(
          EncodedImage(
            bytes: [0xFF, 0xD8, 0xFF],
            width: 1000,
            height: 1400,
            format: ImageOutputFormat.jpeg,
          ),
        ),
      );
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.imagesToDocx,
          inputs: [
            input('a', DocumentFormat.jpeg),
            input('b', DocumentFormat.jpeg),
          ],
        ),
      );
      final archive = ZipDecoder().decodeBytes(r.valueOrNull!.single.bytes);
      expect(archive.findFile('word/media/image1.jpeg'), isNotNull);
      expect(archive.findFile('word/media/image2.jpeg'), isNotNull);
    });

    test('PDF → JPG outputs one named file per page', () async {
      when(() => pdf.pageCount(any())).thenAnswer((_) async => const Ok(2));
      when(
        () => pdf.renderPage(
          any(),
          any(),
          targetWidth: any(named: 'targetWidth'),
        ),
      ).thenAnswer((_) async => Ok(bytes([0x89])));
      when(() => images.compress(any(), any())).thenAnswer(
        (_) async => const Ok(
          EncodedImage(
            bytes: [0xFF],
            width: 1,
            height: 1,
            format: ImageOutputFormat.jpeg,
          ),
        ),
      );
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.pdfToJpg,
          inputs: [input('doc', DocumentFormat.pdf)],
        ),
      );
      final outs = r.valueOrNull!;
      expect(outs.map((o) => o.suggestedName), [
        'doc - page 1',
        'doc - page 2',
      ]);
      expect(outs.every((o) => o.format == DocumentFormat.jpeg), isTrue);
    });

    test('image → TXT fails clearly when OCR fails', () async {
      when(() => ocr.recognize(any(), any())).thenAnswer(
        (_) async => const Err(AppFailure(FailureCode.modelUnavailable)),
      );
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.imageToTxt,
          inputs: [input('i', DocumentFormat.png)],
        ),
      );
      expect(r.failureOrNull?.code, FailureCode.modelUnavailable);
    });
  });

  group('office & text', () {
    test('XLSX → CSV exports all sheets when asked', () async {
      final xlsx = writeXlsx([
        ['a', '1'],
      ]);
      when(() => files.read(any())).thenAnswer((_) async => xlsx);
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.xlsxToCsv,
          inputs: [input('book', DocumentFormat.xlsx)],
          options: const {ConversionOptions.allSheets: true},
        ),
      );
      final out = r.valueOrNull!.single;
      expect(utf8.decode(out.bytes), 'a,1');
      expect(out.suggestedName, 'book');
    });

    test('CSV → PDF uses a monospace table', () async {
      when(() => files.readText(any())).thenAnswer((_) async => 'x,y\n1,2');
      when(
        () => pdf.fromText(any(), any()),
      ).thenAnswer((_) async => Ok(bytes([1])));
      await engine.convert(
        ConversionRequest(
          specId: ConversionIds.csvToPdf,
          inputs: [input('t', DocumentFormat.csv)],
        ),
      );
      final captured = verify(
        () => pdf.fromText(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], 'x | y\n--+--\n1 | 2');
      expect((captured[1] as TextPdfOptions).monospace, isTrue);
    });

    test('Markdown → DOCX maps headings and bullets to styles', () async {
      when(
        () => files.readText(any()),
      ).thenAnswer((_) async => '# Title\n\n- item\n\nBody');
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.mdToDocx,
          inputs: [input('m', DocumentFormat.markdown)],
        ),
      );
      final paras = readDocx(r.valueOrNull!.single.bytes);
      expect(paras.map((p) => (p.text, p.headingLevel, p.isBullet)), [
        ('Title', 1, false),
        ('item', 0, true),
        ('Body', 0, false),
      ]);
    });

    test('PPTX → PDF puts each slide on its own page via form feeds', () async {
      final pptx = buildPackage({
        'ppt/slides/slide1.xml': '<sld><p><t>Hello</t></p></sld>',
        'ppt/slides/slide2.xml': '<sld><p><t>World</t></p></sld>',
      });
      when(() => files.read(any())).thenAnswer((_) async => pptx);
      when(
        () => pdf.fromText(any(), any()),
      ).thenAnswer((_) async => Ok(bytes([1])));
      await engine.convert(
        ConversionRequest(
          specId: ConversionIds.pptxToPdf,
          inputs: [input('deck', DocumentFormat.pptx)],
        ),
      );
      final text =
          verify(() => pdf.fromText(captureAny(), any())).captured.single
              as String;
      expect(text, 'Slide 1\nHello\fSlide 2\nWorld');
    });

    test('DOCX → PDF turns manual page breaks into form feeds', () async {
      final docx =
          (DocxBuilder()
                ..paragraph('Page one')
                ..paragraph('Still one')
                ..pageBreak()
                ..paragraph('Page two'))
              .build();
      when(() => files.read(any())).thenAnswer((_) async => docx);
      when(
        () => pdf.fromText(any(), any()),
      ).thenAnswer((_) async => Ok(bytes([1])));
      await engine.convert(
        ConversionRequest(
          specId: ConversionIds.docxToPdf,
          inputs: [input('w', DocumentFormat.docx)],
        ),
      );
      final text =
          verify(() => pdf.fromText(captureAny(), any())).captured.single
              as String;
      expect(text, 'Page one\n\nStill one\n\fPage two');
      expect('\f'.allMatches(text).length, 1);
    });

    test('HTML → TXT strips markup', () async {
      when(
        () => files.readText(any()),
      ).thenAnswer((_) async => '<p>Hi &amp; bye</p><script>x()</script>');
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.htmlToTxt,
          inputs: [input('h', DocumentFormat.html)],
        ),
      );
      expect(utf8.decode(r.valueOrNull!.single.bytes), 'Hi & bye');
    });
  });

  group('production audit 2026-09: no silent empty output', () {
    Future<Result<List<OutputFile>>> pdfToTxt(ConversionEngineImpl e) =>
        e.convert(
          ConversionRequest(
            specId: ConversionIds.pdfToTxt,
            inputs: [input('scan', DocumentFormat.pdf)],
          ),
        );

    test('missing file → notFound before any work', () async {
      when(() => files.exists(any())).thenAnswer((_) async => false);
      final r = await pdfToTxt(engine);
      expect(r.failureOrNull?.code, FailureCode.notFound);
      verifyNever(() => pdf.extractText(any()));
    });

    test('zero-byte file → emptyFile', () async {
      when(() => files.size(any())).thenAnswer((_) async => 0);
      expect(
        (await pdfToTxt(engine)).failureOrNull?.code,
        FailureCode.emptyFile,
      );
    });

    test(
      'password-protected PDF → passwordProtected from pre-flight',
      () async {
        when(() => pdf.pageCount(any())).thenAnswer(
          (_) async => const Err(AppFailure(FailureCode.passwordProtected)),
        );
        expect(
          (await pdfToTxt(engine)).failureOrNull?.code,
          FailureCode.passwordProtected,
        );
      },
    );

    test(
      'scanned PDF without OCR engine → scannedPdfNeedsOcr + runOcr',
      () async {
        final noOcr = ConversionEngineImpl(
          files: files,
          pdf: pdf,
          images: images,
        );
        when(
          () => pdf.extractText(any()),
        ).thenAnswer((_) async => const Ok(['', '  ']));
        final f = (await pdfToTxt(noOcr)).failureOrNull!;
        expect(f.code, FailureCode.scannedPdfNeedsOcr);
        expect(f.nextAction, FailureAction.runOcr);
      },
    );

    test(
      'render failure during OCR fallback propagates (not silent)',
      () async {
        when(
          () => pdf.extractText(any()),
        ).thenAnswer((_) async => const Ok(['']));
        when(
          () => pdf.renderPage(
            any(),
            any(),
            targetWidth: any(named: 'targetWidth'),
          ),
        ).thenAnswer(
          (_) async => const Err(AppFailure(FailureCode.memoryLimitExceeded)),
        );
        final f = (await pdfToTxt(engine)).failureOrNull!;
        expect(f.code, FailureCode.memoryLimitExceeded);
        expect(f.detail, 'Page 1');
      },
    );

    test('OCR error propagates typed with page detail', () async {
      when(
        () => pdf.extractText(any()),
      ).thenAnswer((_) async => const Ok(['']));
      when(
        () => pdf.renderPage(
          any(),
          any(),
          targetWidth: any(named: 'targetWidth'),
        ),
      ).thenAnswer((_) async => Ok(Uint8List(3)));
      when(
        () => files.writeTemp(any(), any()),
      ).thenAnswer((_) async => '/t.png');
      when(() => ocr.recognize(any(), any())).thenAnswer(
        (_) async => const Err(AppFailure(FailureCode.modelUnavailable)),
      );
      final f = (await pdfToTxt(engine)).failureOrNull!;
      expect(f.code, FailureCode.modelUnavailable);
      verify(() => files.delete('/t.png')).called(1);
    });

    test(
      'no text even after OCR → noTextFound (never an empty file)',
      () async {
        when(
          () => pdf.extractText(any()),
        ).thenAnswer((_) async => const Ok(['']));
        when(
          () => pdf.renderPage(
            any(),
            any(),
            targetWidth: any(named: 'targetWidth'),
          ),
        ).thenAnswer((_) async => Ok(Uint8List(3)));
        when(
          () => files.writeTemp(any(), any()),
        ).thenAnswer((_) async => '/t.png');
        when(
          () => ocr.recognize(any(), any()),
        ).thenAnswer((_) async => const Ok(OcrResult.empty));
        expect(
          (await pdfToTxt(engine)).failureOrNull?.code,
          FailureCode.noTextFound,
        );
      },
    );

    test('a PDF renamed to .jpg is rejected with a clear reason', () async {
      when(
        () => files.read(any()),
      ).thenAnswer((_) async => Uint8List.fromList('%PDF-1.7'.codeUnits));
      final r = await engine.convert(
        ConversionRequest(
          specId: ConversionIds.imageToTxt,
          inputs: [input('photo', DocumentFormat.jpeg)],
        ),
      );
      final f = r.failureOrNull!;
      expect(f.code, FailureCode.unsupportedFormat);
      expect(f.recovery, contains('actually a PDF'));
    });
  });
}
