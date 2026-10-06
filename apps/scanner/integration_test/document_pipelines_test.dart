import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_ocr/engine_ocr.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device regression suite for the production failures:
///  1. Compress PDF      → "Conversion failed"
///  2. Image → text OCR  → "Something went wrong"
///  3. PDF → text        → "Output could not be verified"
/// Runs the REAL ML Kit, PDFium and engines on an Android device/emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late DataLayer data;
  late PdfEngineImpl pdf;
  late MlKitTextRecognizer ocr;
  late ConversionEngineImpl convert;
  late CommitOutput commit;
  const images = ImagingEngine();

  setUpAll(() async {
    await initPdfEngine();
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('docscan_it');
    data = await openDataLayer(rootOverride: root.path);
    pdf = PdfEngineImpl();
    ocr = MlKitTextRecognizer(
      bundledScripts: const {OcrScript.latin, OcrScript.devanagari},
    );
    convert = ConversionEngineImpl(
      files: data.files,
      pdf: pdf,
      images: images,
      ocr: ocr,
    );
    commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: pdf,
      images: images,
    );
  });

  tearDown(() async {
    await ocr.close();
    await data.close();
    await root.delete(recursive: true);
  });

  Future<String> textImage() async {
    final png = await renderTextPage(const [
      'INVOICE 2026',
      'DocScan offline test',
      'Total amount 1250',
    ]);
    final f = File('${root.path}/page.png');
    await f.writeAsBytes(png);
    return f.path;
  }

  Future<String> scannedPdf() async {
    final png = await File(await textImage()).readAsBytes();
    final jpeg = await images.renderPage(
      png,
      const PageEdits(filter: EnhancementFilter.original),
    );
    final bytes = await pdf.fromImages([
      jpeg.valueOrNull!,
      jpeg.valueOrNull!,
    ], const PdfBuildOptions());
    final f = File('${root.path}/scanned.pdf');
    await f.writeAsBytes(bytes.valueOrNull!);
    return f.path;
  }

  testWidgets('OCR reads text from a photo (image → text)', (tester) async {
    final r = await ocr.recognize(await textImage(), OcrScript.latin);
    expect(r.failureOrNull, isNull, reason: 'OCR failed: ${r.failureOrNull}');
    expect(r.valueOrNull!.text.toUpperCase(), contains('INVOICE'));
  });

  testWidgets('scanned PDF → TXT uses OCR and produces a valid file', (
    tester,
  ) async {
    final out = await convert.convert(
      ConversionRequest(
        specId: ConversionIds.pdfToTxt,
        inputs: [
          ConversionInput(
            path: await scannedPdf(),
            name: 'scan',
            format: DocumentFormat.pdf,
          ),
        ],
      ),
    );
    expect(out.failureOrNull, isNull, reason: '${out.failureOrNull}');
    final saved = await commit(out.valueOrNull!.single);
    expect(saved.failureOrNull, isNull, reason: '${saved.failureOrNull}');
    final text = await File(
      data.files.absolute(saved.valueOrNull!.relativePath),
    ).readAsString();
    expect(text.toUpperCase(), contains('INVOICE'));
  });

  testWidgets('compress PDF with a UI-style progress callback', (tester) async {
    final path = await scannedPdf();
    // UI callbacks capture framework objects that cannot cross isolates
    // (ports, native handles). This mirrors the Riverpod job notifier.
    final uiObject = ReceivePort();
    final progress = <double>[];
    final r = await pdf.compress(
      path,
      PdfCompressionLevel.recommended,
      onProgress: (p) {
        uiObject.sendPort; // captured, like a notifier/ref would be
        progress.add(p);
      },
    );
    uiObject.close();
    expect(r.failureOrNull, isNull, reason: '${r.failureOrNull}');
    expect(progress.last, 1);
    final saved = await commit(
      OutputFile(
        bytes: r.valueOrNull!,
        format: DocumentFormat.pdf,
        suggestedName: 'compressed',
        expectedPages: 2,
      ),
    );
    expect(saved.failureOrNull, isNull, reason: '${saved.failureOrNull}');
  });

  testWidgets('render page and PDF → JPG work on device', (tester) async {
    final path = await scannedPdf();
    final png = await pdf.renderPage(path, 0, targetWidth: 800);
    expect(png.failureOrNull, isNull, reason: '${png.failureOrNull}');
    final out = await convert.convert(
      ConversionRequest(
        specId: ConversionIds.pdfToJpg,
        inputs: [
          ConversionInput(path: path, name: 'scan', format: DocumentFormat.pdf),
        ],
      ),
    );
    expect(out.valueOrNull, hasLength(2), reason: '${out.failureOrNull}');
  });

  testWidgets('text PDF → TXT keeps embedded text', (tester) async {
    final bytes = await pdf.fromText(
      'Hello from a text PDF',
      const TextPdfOptions(),
    );
    final f = File('${root.path}/text.pdf');
    await f.writeAsBytes(bytes.valueOrNull!);
    final out = await convert.convert(
      ConversionRequest(
        specId: ConversionIds.pdfToTxt,
        inputs: [
          ConversionInput(path: f.path, name: 't', format: DocumentFormat.pdf),
        ],
      ),
    );
    expect(out.failureOrNull, isNull, reason: '${out.failureOrNull}');
    expect(
      String.fromCharCodes(out.valueOrNull!.single.bytes),
      contains('Hello'),
    );
  });
}

/// Draws black text lines on a white A4-ish canvas and returns PNG bytes.
Future<Uint8List> renderTextPage(List<String> lines) async {
  const w = 1240.0;
  const h = 1754.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  var y = 160.0;
  for (final line in lines) {
    final tp =
        TextPainter(
            text: TextSpan(
              text: line,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 64,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )
          ..layout(maxWidth: w - 160)
          ..paint(canvas, Offset(80, y));
    y += tp.height + 60;
  }
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
