import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

/// Pixel density assumed for [PdfPageSize.fit] pages (points = px * 72/150).
const double fitDpi = 150;

/// Builds a PDF with one page per JPEG. Pure Dart; safe to run in an isolate.
///
/// When [textLayers] is given, each page gets an invisible text layer
/// (PDF text rendering mode 3) so the PDF becomes searchable/selectable.
/// Only lines fully encodable in the built-in Helvetica font (Latin-1) are
/// written; other scripts are skipped because no Unicode font is embedded.
Future<Uint8List> buildImagePdf(
  List<Uint8List> jpegPages,
  PdfBuildOptions options, {
  List<OcrResult?>? textLayers,
}) async {
  final doc = pdf.PdfDocument();
  final font = pdf.PdfFont.helvetica(doc);

  for (var i = 0; i < jpegPages.length; i++) {
    final image = pdf.PdfImage.jpeg(doc, image: jpegPages[i]);
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final margin = options.marginPt;

    final double pageW;
    final double pageH;
    if (options.pageSize == PdfPageSize.fit) {
      pageW = imgW * 72 / fitDpi + margin * 2;
      pageH = imgH * 72 / fitDpi + margin * 2;
    } else {
      final landscape = imgW > imgH;
      final a = options.pageSize.widthPt;
      final b = options.pageSize.heightPt;
      pageW = landscape ? b : a;
      pageH = landscape ? a : b;
    }

    final box = fitRect(imgW, imgH, pageW - margin * 2, pageH - margin * 2);
    final x = margin + box.x;
    final y = margin + box.y;

    final page = pdf.PdfPage(doc, pageFormat: pdf.PdfPageFormat(pageW, pageH));
    final g = page.getGraphics()..drawImage(image, x, y, box.width, box.height);

    final layer = textLayers != null && i < textLayers.length
        ? textLayers[i]
        : null;
    if (layer != null) {
      for (final line in layer.lines) {
        final text = line.text.trim();
        if (text.isEmpty || !_encodable(font, text)) continue;
        final lineW = line.box.width * box.width;
        final lineH = line.box.height * box.height;
        if (lineW <= 0 || lineH <= 0) continue;
        final size = lineH * 0.85;
        final natural = font.stringMetrics(text).width * size;
        final scale = natural > 0 ? lineW / natural : 1.0;
        // PDF y grows upwards; OCR boxes are top-left based.
        final baseline = y + box.height * (1 - line.box.bottom) + lineH * 0.2;
        g.drawString(
          font,
          size,
          text,
          x + line.box.left * box.width,
          baseline,
          scale: scale,
          mode: pdf.PdfTextRenderingMode.invisible,
        );
      }
    }
  }
  return await doc.save();
}

/// Typesets plain text into paginated pages. A form feed (`\f`) forces a
/// page break — each `\f`-separated chunk starts on a new page (used for
/// one-slide-per-page PPTX → PDF). Characters the font cannot encode are
/// replaced with `?` unless [unicodeFont] (TTF bytes) is given.
Future<Uint8List> buildTextPdf(
  String text,
  TextPdfOptions options, {
  Uint8List? unicodeFont,
}) async {
  final pw.Font font;
  if (unicodeFont != null) {
    font = pw.Font.ttf(unicodeFont.buffer.asByteData());
  } else {
    font = options.monospace ? pw.Font.courier() : pw.Font.helvetica();
  }
  final format = options.pageSize == PdfPageSize.fit
      ? pdf.PdfPageFormat.a4
      : pdf.PdfPageFormat(options.pageSize.widthPt, options.pageSize.heightPt);

  final doc = pw.Document(title: options.title, creator: 'DocScan');
  final style = pw.TextStyle(
    font: font,
    fontSize: options.fontSize,
    lineSpacing: options.fontSize * 0.3,
  );
  final pageFormat = format.copyWith(
    marginLeft: 56,
    marginRight: 56,
    marginTop: 56,
    marginBottom: 56,
  );

  // '\f' (form feed) is a hard page break: each chunk starts a new page.
  for (final chunk in text.replaceAll('\r\n', '\n').split('\f')) {
    final lines = chunk
        .replaceAll('\t', '    ')
        .split('\n')
        .map((l) => unicodeFont == null ? _latin1Only(l) : l)
        .toList();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        maxPages: 5000,
        build: (context) => [
          for (final l in lines)
            pw.Text(l.isEmpty ? ' ' : l, style: style, softWrap: true),
        ],
      ),
    );
  }
  return await doc.save();
}

/// Rectangle for an image fitted into a box, centered, aspect preserved.
({double x, double y, double width, double height}) fitRect(
  double imgW,
  double imgH,
  double boxW,
  double boxH,
) {
  final scale = (boxW / imgW) < (boxH / imgH) ? boxW / imgW : boxH / imgH;
  final w = imgW * scale;
  final h = imgH * scale;
  return (x: (boxW - w) / 2, y: (boxH - h) / 2, width: w, height: h);
}

bool _encodable(pdf.PdfFont font, String s) =>
    s.runes.every((r) => r <= 0xFF && font.isRuneSupported(r));

String _latin1Only(String s) => String.fromCharCodes(
  s.runes.map((r) => r <= 0xFF && (r >= 0x20 || r == 0x09) ? r : 0x3F),
);

/// Builds a PDF where page `i` is exactly `sizes[i]` points and the JPEG
/// fills it. Used by compression to keep original page dimensions.
Future<Uint8List> buildSizedImagePdf(
  List<Uint8List> jpegs,
  List<({double w, double h})> sizes,
) async {
  final doc = pdf.PdfDocument();
  for (var i = 0; i < jpegs.length; i++) {
    final image = pdf.PdfImage.jpeg(doc, image: jpegs[i]);
    final s = sizes[i];
    pdf.PdfPage(
      doc,
      pageFormat: pdf.PdfPageFormat(s.w, s.h),
    ).getGraphics().drawImage(image, 0, 0, s.w, s.h);
  }
  return await doc.save();
}
