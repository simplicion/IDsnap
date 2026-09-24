import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:drift/native.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

/// End-to-end pipelines with the REAL engines (imaging, PDFium, conversion,
/// data layer). Only ML Kit (OCR/scanner/faces) can't run on a desktop test
/// host; those are covered by unit tests and on-device QA.
void main() {
  late Directory root;
  late DataLayer data;
  late PdfEngineImpl pdf;
  const images = ImagingEngine();
  late ConversionEngineImpl convert;
  late CommitOutput commit;

  setUpAll(() async {
    await pdfrxInitialize();
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('docscan_e2e');
    data = await openDataLayer(
      rootOverride: root.path,
      executor: NativeDatabase.memory(),
    );
    pdf = PdfEngineImpl();
    convert = ConversionEngineImpl(files: data.files, pdf: pdf, images: images);
    commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: pdf,
      images: images,
    );
  });

  tearDown(() async {
    await data.close();
    await root.delete(recursive: true);
  });

  Future<String> writeInput(String name, List<int> bytes) async {
    final f = File('${root.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<List<Document>> run(
    String specId,
    List<(String path, String name, DocumentFormat format)> inputs,
  ) async {
    final out = await convert.convert(
      ConversionRequest(
        specId: specId,
        inputs: [
          for (final (path, name, format) in inputs)
            ConversionInput(path: path, name: name, format: format),
        ],
      ),
    );
    expect(out.failureOrNull, isNull, reason: '$specId failed');
    final docs = <Document>[];
    for (final file in out.valueOrNull!) {
      final c = await commit(file);
      expect(c.failureOrNull, isNull, reason: '$specId output invalid');
      docs.add(c.valueOrNull!);
    }
    return docs;
  }

  String abs(Document d) => data.files.absolute(d.relativePath);

  test(
    'photo of a page → detect → straighten → 2-page validated PDF',
    () async {
      final photo = _syntheticDocumentPhoto();
      final detected = await images.detectDocument(photo);
      final quad = detected.valueOrNull!;
      expect(quad.isConfident, isTrue, reason: 'page edges should be found');

      final p1 = await writeInput('p1.jpg', photo);
      final p2 = await writeInput('p2.jpg', photo);
      final save = SaveScanAsPdf(
        files: data.files,
        images: images,
        pdf: pdf,
        commit: commit,
      );
      final draft = ScanDraft(
        id: 'd',
        createdAt: DateTime.now(),
        pages: [
          ScanPage(
            id: 'a',
            originalPath: p1,
            edits: PageEdits(quad: quad.quad),
          ),
          ScanPage(
            id: 'b',
            originalPath: p2,
            edits: PageEdits(
              quad: quad.quad,
              filter: EnhancementFilter.blackWhite,
              quarterTurns: 1,
            ),
          ),
        ],
      );
      final progress = <double>[];
      final doc = await save(
        draft,
        name: 'Lease agreement',
        onProgress: progress.add,
      );
      expect(doc.failureOrNull, isNull);
      expect(doc.valueOrNull!.pageCount, 2);
      expect(doc.valueOrNull!.format, DocumentFormat.pdf);
      expect(progress.last, 1);
      expect((await pdf.pageCount(abs(doc.valueOrNull!))).valueOrNull, 2);
    },
  );

  test('TXT → PDF → TXT keeps the text (incl. ₹ via Unicode font)', () async {
    final font = await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes();
    pdf = PdfEngineImpl(unicodeFont: font);
    convert = ConversionEngineImpl(files: data.files, pdf: pdf, images: images);
    final txt = await writeInput('invoice.txt', []);
    await File(txt).writeAsString('Invoice 42\nTotal: ₹1,250\n\fSecond page');
    final pdfDocs = await run(ConversionIds.txtToPdf, [
      (txt, 'invoice', DocumentFormat.txt),
    ]);
    expect(pdfDocs.single.pageCount, 2, reason: r'\f starts a new page');
    final back = await run(ConversionIds.pdfToTxt, [
      (abs(pdfDocs.single), 'invoice', DocumentFormat.pdf),
    ]);
    final text = await File(abs(back.single)).readAsString();
    expect(text, contains('Invoice 42'));
    expect(text, contains('₹1,250'));
    expect(text, contains('Second page'));
  });

  test('Markdown → DOCX → TXT round-trip', () async {
    final md = await writeInput('notes.md', []);
    await File(md).writeAsString('# Physics\n\n- Newton\n- Ohm\n\nPlain text.');
    final docx = await run(ConversionIds.mdToDocx, [
      (md, 'notes', DocumentFormat.markdown),
    ]);
    expect(docx.single.format, DocumentFormat.docx);
    final txt = await run(ConversionIds.docxToTxt, [
      (abs(docx.single), 'notes', DocumentFormat.docx),
    ]);
    final text = await File(abs(txt.single)).readAsString();
    expect(text, contains('Physics'));
    expect(text, contains('Newton'));
    expect(text, contains('Plain text.'));
  });

  test('CSV → XLSX → CSV round-trip and DOCX → PDF', () async {
    final csv = await writeInput('marks.csv', []);
    await File(csv).writeAsString('Name,Marks\n"Rahul, K",91\nPriya,88\n');
    final xlsx = await run(ConversionIds.csvToXlsx, [
      (csv, 'marks', DocumentFormat.csv),
    ]);
    final back = await run(ConversionIds.xlsxToCsv, [
      (abs(xlsx.single), 'marks', DocumentFormat.xlsx),
    ]);
    final text = await File(abs(back.single)).readAsString();
    expect(text, contains('"Rahul, K",91'));

    final txt = await writeInput('letter.txt', []);
    await File(txt).writeAsString('Dear Sir,\nPlease find attached.');
    final docx = await run(ConversionIds.txtToDocx, [
      (txt, 'letter', DocumentFormat.txt),
    ]);
    final pdfOut = await run(ConversionIds.docxToPdf, [
      (abs(docx.single), 'letter', DocumentFormat.docx),
    ]);
    expect(pdfOut.single.pageCount, greaterThanOrEqualTo(1));
  });

  test(
    'images → PDF, then PDF → JPG, merge, split, rotate, compress',
    () async {
      final photo = _syntheticDocumentPhoto();
      final a = await writeInput('a.jpg', photo);
      final b = await writeInput('b.jpg', photo);
      final made = await run(ConversionIds.imagesToPdf, [
        (a, 'a', DocumentFormat.jpeg),
        (b, 'b', DocumentFormat.jpeg),
      ]);
      expect(made.single.pageCount, 2);
      final path = abs(made.single);

      final jpgs = await run(ConversionIds.pdfToJpg, [
        (path, 'scan', DocumentFormat.pdf),
      ]);
      expect(jpgs, hasLength(2));
      expect(jpgs.every((d) => d.format == DocumentFormat.jpeg), isTrue);

      final merged = (await pdf.merge([path, path])).valueOrNull!;
      final mergedDoc = (await commit(
        OutputFile(
          bytes: merged,
          format: DocumentFormat.pdf,
          suggestedName: 'merged',
          expectedPages: 4,
        ),
      )).valueOrNull!;
      final extracted = (await pdf.selectPages(abs(mergedDoc), [
        3,
        0,
      ])).valueOrNull!;
      final extractedPath = await data.files.writeTemp(extracted, 'pdf');
      expect((await pdf.pageCount(extractedPath)).valueOrNull, 2);

      final rotated = await pdf.rotatePages(path, {0: 1});
      expect(rotated.isOk, isTrue);

      final compressed = await pdf.compress(path, PdfCompressionLevel.strong);
      expect(compressed.isOk, isTrue);
      final compressedPath = await data.files.writeTemp(
        compressed.valueOrNull!,
        'pdf',
      );
      expect((await pdf.pageCount(compressedPath)).valueOrNull, 2);
    },
  );

  test(
    'image compression hits a 200 KB target; passport crop is exact',
    () async {
      final big = _noisyPhoto(2400, 3200);
      expect(big.length, greaterThan(200 * 1024));
      final small = await images.compress(
        big,
        const ImageCompressionOptions(targetBytes: 200 * 1024),
      );
      expect(small.valueOrNull!.bytes.length, lessThanOrEqualTo(200 * 1024));

      const face = NRect(0.4, 0.25, 0.2, 0.15);
      final frame = autoFramePortrait(
        face: face,
        preset: CropPreset.passportIntl,
        imageWidth: 2400,
        imageHeight: 3200,
      )!;
      final crop = await images.crop(
        big,
        frame,
        outputWidth: CropPreset.passportIntl.pixelWidth,
        outputHeight: CropPreset.passportIntl.pixelHeight,
      );
      final out = crop.valueOrNull!;
      expect((out.width, out.height), (413, 531));
      final c = await commit(
        OutputFile(
          bytes: Uint8List.fromList(out.bytes),
          format: DocumentFormat.jpeg,
          suggestedName: 'Passport photo',
        ),
      );
      expect(c.isOk, isTrue);
    },
  );

  test('corrupt and mislabeled inputs fail safely and save nothing', () async {
    final fake = await writeInput('fake.pdf', 'not a pdf'.codeUnits);
    final r = await convert.convert(
      ConversionRequest(
        specId: ConversionIds.pdfToTxt,
        inputs: [
          ConversionInput(path: fake, name: 'fake', format: DocumentFormat.pdf),
        ],
      ),
    );
    expect(r.isOk, isFalse);
    final bad = await commit(
      OutputFile(
        bytes: Uint8List.fromList('garbage'.codeUnits),
        format: DocumentFormat.pdf,
        suggestedName: 'bad',
      ),
    );
    expect(bad.failureOrNull?.code, FailureCode.outputValidationFailed);
    final docs = await data.documents.watch(const DocumentQuery()).first;
    expect(docs, isEmpty, reason: 'nothing may be saved on failure');
  });
}

/// A white "page" with dark text-like bars, rotated ~10°, on a dark desk.
Uint8List _syntheticDocumentPhoto() {
  final im = img.Image(width: 1600, height: 1200);
  img.fill(im, color: img.ColorRgb8(45, 40, 38));
  const cx = 800.0;
  const cy = 600.0;
  const a = 10 * math.pi / 180;
  (int, int) rot(double x, double y) => (
    (cx + x * math.cos(a) - y * math.sin(a)).round(),
    (cy + x * math.sin(a) + y * math.cos(a)).round(),
  );
  final corners = [
    rot(-420, -520),
    rot(420, -520),
    rot(420, 520),
    rot(-420, 520),
  ];
  img.fillPolygon(
    im,
    vertices: [for (final (x, y) in corners) img.Point(x, y)],
    color: img.ColorRgb8(245, 243, 238),
  );
  for (var line = 0; line < 14; line++) {
    final y = -400.0 + line * 60;
    final (x1, y1) = rot(-340, y);
    final (x2, y2) = rot(300 - (line % 3) * 80, y);
    img.drawLine(
      im,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: img.ColorRgb8(30, 30, 30),
      thickness: 8,
    );
  }
  return img.encodeJpg(im, quality: 90);
}

Uint8List _noisyPhoto(int w, int h) {
  final r = math.Random(7);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = 120 + r.nextInt(100)
      ..g = 90 + r.nextInt(100)
      ..b = 60 + r.nextInt(100);
  }
  return img.encodeJpg(im, quality: 95);
}
