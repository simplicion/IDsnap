import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

/// [SheetPdfBuilder] with `package:pdf`: one page, images at exact rects
/// (points, top-left origin), optional thin border and diagonal watermark.
///
/// Heavy work runs in `Isolate.run` with a [SheetJob] tear-off that holds
/// only plain data — never a closure capturing callbacks or native handles.
class SheetPdfBuilderImpl implements SheetPdfBuilder {
  const SheetPdfBuilderImpl();

  @override
  Future<Result<Uint8List>> build(
    List<PlacedImage> images, {
    required double pageWidthPt,
    required double pageHeightPt,
    String? watermark,
  }) async {
    final problem = validateSheet(images, pageWidthPt, pageHeightPt);
    if (problem != null) {
      return Err(AppFailure(FailureCode.conversionFailed, detail: problem));
    }
    final job = SheetJob.fromPlaced(
      images,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      watermark: watermark,
    );
    return await guard(
      () async => await Isolate.run(job.run),
      code: FailureCode.conversionFailed,
    );
  }
}

/// Returns a user-safe reason when the sheet can't be built, else null.
String? validateSheet(
  List<PlacedImage> images,
  double pageWidthPt,
  double pageHeightPt,
) {
  if (!(pageWidthPt > 0 && pageHeightPt > 0)) return 'Invalid page size';
  if (images.isEmpty) return 'No images to place';
  for (final i in images) {
    if (i.jpeg.isEmpty) return 'An image is empty';
    if (!(i.width > 0 && i.height > 0)) return 'An image has no size';
    if (i.left.isNaN || i.top.isNaN) return 'An image has no position';
  }
  return null;
}

/// Latin-1-safe watermark text for the built-in Helvetica font.
String sanitizeWatermark(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.trim().runes) {
    if (rune == 0x2014 || rune == 0x2013) {
      buffer.write('-');
    } else if (rune == 0x2018 || rune == 0x2019) {
      buffer.write("'");
    } else if (rune < 0x20 || (rune >= 0x7F && rune < 0xA0)) {
      buffer.write(' ');
    } else if (rune > 0xFF) {
      buffer.write('?');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  final s = buffer.toString().replaceAll(RegExp(' +'), ' ');
  return s.length > 80 ? s.substring(0, 80) : s;
}

/// Plain-data description of a sheet; sendable to a background isolate.
class SheetJob {
  const SheetJob({
    required this.jpegs,
    required this.rects,
    required this.borders,
    required this.pageWidthPt,
    required this.pageHeightPt,
    this.watermark,
    this.compress = true,
  });

  factory SheetJob.fromPlaced(
    List<PlacedImage> images, {
    required double pageWidthPt,
    required double pageHeightPt,
    String? watermark,
    bool compress = true,
  }) => SheetJob(
    jpegs: [for (final i in images) i.jpeg],
    rects: [
      for (final i in images) ...[i.left, i.top, i.width, i.height],
    ],
    borders: [for (final i in images) i.border],
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    watermark: watermark,
    compress: compress,
  );

  final List<Uint8List> jpegs;

  /// Flattened `[left, top, width, height]` per image.
  final List<double> rects;
  final List<bool> borders;
  final double pageWidthPt;
  final double pageHeightPt;
  final String? watermark;
  final bool compress;

  Future<Uint8List> run() => buildSheetPdf(this);
}

/// Builds the sheet PDF. Pure Dart; safe in an isolate.
Future<Uint8List> buildSheetPdf(SheetJob job) async {
  final doc = pw.Document(compress: job.compress);
  final mark = job.watermark == null ? '' : sanitizeWatermark(job.watermark!);
  final w = job.pageWidthPt;
  final h = job.pageHeightPt;
  const grey = pdf.PdfColor(0.62, 0.64, 0.68);

  doc.addPage(
    pw.Page(
      pageFormat: pdf.PdfPageFormat(w, h),
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.SizedBox(width: w, height: h),
          for (var i = 0; i < job.jpegs.length; i++)
            pw.Positioned(
              left: job.rects[i * 4],
              top: job.rects[i * 4 + 1],
              child: pw.Container(
                width: job.rects[i * 4 + 2],
                height: job.rects[i * 4 + 3],
                decoration: job.borders[i]
                    ? pw.BoxDecoration(
                        border: pw.Border.all(color: grey, width: 0.5),
                      )
                    : null,
                child: pw.Image(
                  pw.MemoryImage(job.jpegs[i]),
                  fit: pw.BoxFit.fill,
                ),
              ),
            ),
          if (mark.isNotEmpty)
            pw.Positioned.fill(
              child: pw.Center(
                child: pw.Transform.rotate(
                  angle: math.atan2(h, w),
                  child: pw.Opacity(
                    opacity: 0.12,
                    child: pw.Text(
                      mark,
                      style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: math.min(w, h) / 14,
                        color: pdf.PdfColors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  return await doc.save();
}
