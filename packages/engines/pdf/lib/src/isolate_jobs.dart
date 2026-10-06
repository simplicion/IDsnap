import 'dart:isolate';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/pdf_writer.dart';
import 'package:engine_pdf/src/stamp/incremental_stamper.dart';
import 'package:image/image.dart' as img;

// ISOLATE BOUNDARY (production audit 2026-09).
//
// Every closure handed to Isolate.run is created *inside these top-level
// functions*, so its captured context holds only the plain-data parameters.
// A closure created inside an instance or async method captures that
// method's whole context — including UI callbacks such as `onProgress`,
// which reference Riverpod/Flutter objects that cannot be sent to another
// isolate ("Illegal argument in isolate message"). That was the root cause
// of "Compress PDF → Conversion failed" on devices.
//
// Rule: never call Isolate.run/runHeavy with a closure defined elsewhere.

/// Encodes a BGRA frame from PDFium as PNG.
Future<Uint8List> encodeBgraAsPng(Uint8List bgra, int width, int height) =>
    Isolate.run(() => _png(bgra, width, height));

/// Encodes a BGRA frame from PDFium as JPEG at [quality].
Future<Uint8List> encodeBgraAsJpeg(
  Uint8List bgra,
  int width,
  int height,
  int quality,
) => Isolate.run(() => _jpeg(bgra, width, height, quality));

/// Builds an image-per-page PDF (scans, images → PDF).
Future<Uint8List> runBuildImagePdf(
  List<Uint8List> jpegPages,
  PdfBuildOptions options,
  List<OcrResult?>? textLayers,
) => Isolate.run(
  () => buildImagePdf(jpegPages, options, textLayers: textLayers),
);

/// Typesets text into a paginated PDF.
Future<Uint8List> runBuildTextPdf(
  String text,
  TextPdfOptions options,
  Uint8List? unicodeFont,
) => Isolate.run(() => buildTextPdf(text, options, unicodeFont: unicodeFont));

/// Rebuilds a PDF from JPEG pages at their original page sizes (compress).
Future<Uint8List> runBuildSizedImagePdf(
  List<Uint8List> jpegs,
  List<double> widths,
  List<double> heights,
) => Isolate.run(
  () => buildSizedImagePdf(jpegs, [
    for (var i = 0; i < jpegs.length; i++) (w: widths[i], h: heights[i]),
  ]),
);

/// Appends stamps to a PDF as an incremental update (PRD 3.3).
Future<StampOutcome> runStampIncremental(
  Uint8List pdf,
  List<PdfStamp> stamps,
  int expectedPages,
) => Isolate.run(() => stampIncrementalSync(pdf, stamps, expectedPages));

/// Raster fallback: composites one page's stamps onto its rendered pixels.
Future<Uint8List> runCompositeStamps(
  Uint8List bgra,
  int width,
  int height,
  double pageWidthPt,
  List<PdfStamp> stamps,
) => Isolate.run(
  () => compositeStampsOnRaster(bgra, width, height, pageWidthPt, stamps),
);

img.Image _fromBgra(Uint8List bgra, int width, int height) =>
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bgra.buffer,
      bytesOffset: bgra.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );

Uint8List _png(Uint8List bgra, int width, int height) =>
    Uint8List.fromList(img.encodePng(_fromBgra(bgra, width, height), level: 4));

Uint8List _jpeg(Uint8List bgra, int width, int height, int quality) {
  // JPEG has no alpha; pages are rendered on white so dropping it is safe.
  final rgb = _fromBgra(bgra, width, height).convert(numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(rgb, quality: quality));
}
