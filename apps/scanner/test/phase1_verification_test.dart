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
import 'package:feature_tools/feature_tools.dart';
import 'package:feature_tools/src/kits/kit_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

/// PRD Phase 1 acceptance checks, run with the REAL PDF, imaging and
/// conversion engines (PDFium on the test host):
/// (a) PDF compress-to-target fits the limit or fails with a typed,
///     explanatory failure — never an oversized file;
/// (b) PDF → TXT on an image-only PDF says "no text layer, run OCR" instead
///     of "Output could not be verified".
void main() {
  late Directory root;
  late DataLayer data;
  late PdfEngineImpl pdf;
  const images = ImagingEngine();

  setUpAll(pdfrxInitialize);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('idsnap_phase1');
    data = await openDataLayer(
      rootOverride: root.path,
      executor: NativeDatabase.memory(),
    );
    pdf = PdfEngineImpl();
  });

  tearDown(() async {
    await data.close();
    // Windows keeps a file locked while a timed-out job still holds it;
    // a leftover temp dir must not mask the real test result.
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS temp cleaner removes it later.
    }
  });

  /// A multi-page PDF of large, noisy photos (worst case for compression).
  Future<String> imageOnlyPdf(int pages) async {
    final built = await pdf.fromImages([
      for (var i = 0; i < pages; i++) _noisyPhoto(1600, 2200, seed: i),
    ], const PdfBuildOptions());
    final f = File('${root.path}/scanned_$pages.pdf');
    await f.writeAsBytes(built.valueOrNull!);
    return f.path;
  }

  KitPipeline pipeline() =>
      KitPipeline(files: data.files, images: images, pdf: pdf);

  group('(a) PDF compress to a target size', () {
    // Real PDFium re-rendering of six large photo pages takes ~30 s on a
    // desktop host, more under load; the 30 s default is too tight.
    const slow = Timeout(Duration(minutes: 4));

    test(
      'a large multi-page image PDF ends up at or under the target',
      () async {
        final path = await imageOnlyPdf(6);
        final original = File(path).lengthSync();
        const target = 1024 * 1024; // 1 MB, a typical portal limit
        expect(
          original,
          greaterThan(target),
          reason: 'input must be oversized',
        );

        final r = await pipeline().document(
          const DocumentItem(id: 'docs', label: 'Documents', maxBytes: target),
          [(path: path, format: DocumentFormat.pdf)],
        );

        expect(r.failureOrNull, isNull, reason: r.failureOrNull?.recovery);
        final out = r.valueOrNull!;
        expect(out.bytes.length, lessThanOrEqualTo(target));
        expect(out.compressedPdf, isTrue);
        expect(out.pageCount, 6);
        final outPath = await data.files.writeTemp(out.bytes, 'pdf');
        expect((await pdf.pageCount(outPath)).valueOrNull, 6);
      },
      timeout: slow,
    );

    test('an unreachable target fails with a typed, explanatory failure '
        '(no oversized output)', () async {
      final path = await imageOnlyPdf(6);
      const target = 20 * 1024; // 20 KB for 6 photo pages: impossible
      final r = await pipeline().document(
        const DocumentItem(id: 'docs', label: 'Documents', maxBytes: target),
        [(path: path, format: DocumentFormat.pdf)],
      );

      expect(r.valueOrNull, isNull);
      final f = r.failureOrNull!;
      expect(f.code, isNot(FailureCode.unknown));
      expect(f.code, isNot(FailureCode.outputValidationFailed));
      expect(f.recovery, contains('20 KB'));
      expect(f.recovery, contains('fewer pages'));
    }, timeout: slow);
  });

  group('(b) PDF → TXT on an image-only PDF', () {
    Future<Result<List<OutputFile>>> toText(
      ConversionEngineImpl engine,
      String path,
    ) => engine.convert(
      ConversionRequest(
        specId: ConversionIds.pdfToTxt,
        inputs: [
          ConversionInput(path: path, name: 'scan', format: DocumentFormat.pdf),
        ],
      ),
    );

    test('the PDF really has no text layer', () async {
      final path = await imageOnlyPdf(2);
      final pages = (await pdf.extractText(path)).valueOrNull!;
      expect(pages, hasLength(2));
      expect(pages.every((p) => p.trim().isEmpty), isTrue);
    });

    test('without OCR: "This PDF is scanned" + Extract text (OCR)', () async {
      final path = await imageOnlyPdf(2);
      final engine = ConversionEngineImpl(
        files: data.files,
        pdf: pdf,
        images: images,
      );
      final f = (await toText(engine, path)).failureOrNull!;
      expect(f.code, FailureCode.scannedPdfNeedsOcr);
      expect(f.nextAction, FailureAction.runOcr);
      expect(f.title, 'This PDF is scanned');
      expect(f.recovery, contains('without a text layer'));
      expect(f.title, isNot(FailureCode.outputValidationFailed.title));
    });

    test('with OCR that finds nothing: explicit "No text found"', () async {
      final path = await imageOnlyPdf(2);
      final engine = ConversionEngineImpl(
        files: data.files,
        pdf: pdf,
        images: images,
        ocr: _BlankOcr(),
      );
      final f = (await toText(engine, path)).failureOrNull!;
      expect(f.code, FailureCode.noTextFound);
      expect(f.recovery, contains('No readable text'));
      expect(f.title, isNot(FailureCode.outputValidationFailed.title));
    });
  });
}

class _BlankOcr implements TextRecognizer {
  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<OcrResult>> recognize(
    String imagePath,
    OcrScript script,
  ) async => Ok(OcrResult(script: script, blocks: const []));
}

Uint8List _noisyPhoto(int w, int h, {required int seed}) {
  final r = math.Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = 120 + r.nextInt(100)
      ..g = 90 + r.nextInt(100)
      ..b = 60 + r.nextInt(100);
  }
  return img.encodeJpg(im, quality: 95);
}
