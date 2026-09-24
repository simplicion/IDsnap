import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/native_decoder.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_ocr/engine_ocr.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_scanner/engine_scanner.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Composition root: the only place that knows concrete implementations.
/// Everything else depends on domain ports through docscan_contracts.
Future<List<Override>> buildOverrides() async {
  await initPdfEngine();
  final data = await openDataLayer();

  const images = ImagingEngine(decoder: nativeDecode);
  final font = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final pdf = PdfEngineImpl(unicodeFont: font.buffer.asUint8List());
  // Both models are bundled (see android/app/build.gradle.kts and
  // ios/Podfile), so OCR never downloads anything at runtime.
  final ocr = MlKitTextRecognizer(
    bundledScripts: const {OcrScript.latin, OcrScript.devanagari},
  );
  final conversion = ConversionEngineImpl(
    files: data.files,
    pdf: pdf,
    images: images,
    ocr: ocr,
  );

  return [
    documentRepositoryProvider.overrideWithValue(data.documents),
    draftStoreProvider.overrideWithValue(data.drafts),
    settingsStoreProvider.overrideWithValue(data.settings),
    fileStoreProvider.overrideWithValue(data.files),
    imageProcessorProvider.overrideWithValue(images),
    pdfEngineProvider.overrideWithValue(pdf),
    textRecognizerProvider.overrideWithValue(ocr),
    documentScannerProvider.overrideWithValue(PlatformDocumentScanner()),
    mediaPickerProvider.overrideWithValue(PlatformMediaPicker()),
    shareServiceProvider.overrideWithValue(PlatformShareService()),
    conversionEngineProvider.overrideWithValue(conversion),
    faceLocatorProvider.overrideWithValue(MlKitFaceLocator()),
  ];
}
