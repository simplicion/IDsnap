import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/sheet_pdf_builder.dart' show sanitizeWatermark;
import 'package:engine_pdf/src/stamp/pdf_syntax.dart';
import 'package:engine_pdf/src/stamp/stamp_geometry.dart';
import 'package:image/image.dart' as img;

/// Longest edge an embedded stamp image may have; larger PNGs are scaled.
const maxStampPixels = 2400;

/// A stamp input the user must fix (e.g. an unreadable signature image).
class StampInputException implements Exception {
  const StampInputException(this.message);
  final String message;
}

/// Sendable result of [stampIncrementalSync].
class StampOutcome {
  const StampOutcome.ok(Uint8List this.bytes) : error = null, badInput = false;
  const StampOutcome.unsupported(String this.error)
    : bytes = null,
      badInput = false;
  const StampOutcome.badInput(String this.error)
    : bytes = null,
      badInput = true;

  final Uint8List? bytes;

  /// Non-sensitive reason (no content, no paths).
  final String? error;

  /// True when the stamps themselves are invalid; a fallback won't help.
  final bool badInput;
}

/// Returns a user-safe problem with [stamps], or null when they are valid.
String? validateStamps(List<PdfStamp> stamps) {
  if (stamps.isEmpty) return 'Place at least one signature or date first.';
  for (final s in stamps) {
    if (s.pageIndex < 0) return 'A stamp is on a page that does not exist.';
    if (!s.left.isFinite || !s.top.isFinite) {
      return 'A stamp has no position.';
    }
    switch (s) {
      case PdfImageStamp(:final width, :final height, :final png):
        if (!(width > 0.5 && height > 0.5) ||
            !width.isFinite ||
            !height.isFinite) {
          return 'A signature is too small. Make it bigger and try again.';
        }
        if (png.isEmpty) return 'A signature image is empty.';
      case PdfTextStamp(:final text, :final fontSize):
        if (text.trim().isEmpty) return 'A text stamp is empty.';
        if (!(fontSize >= 2 && fontSize <= 200)) {
          return 'A text stamp has an invalid size.';
        }
    }
  }
  return null;
}

/// Appends [stamps] to [pdf] as an incremental update: the original bytes
/// are kept verbatim, so vector text stays selectable and existing digital
/// signatures stay valid. Never throws.
///
/// [expectedPages] is PDFium's page count; a mismatch with this parser's
/// page tree means the file is not understood well enough to edit.
StampOutcome stampIncrementalSync(
  Uint8List pdf,
  List<PdfStamp> stamps,
  int expectedPages,
) {
  try {
    return StampOutcome.ok(_stamp(pdf, stamps, expectedPages));
  } on StampInputException catch (e) {
    return StampOutcome.badInput(e.message);
  } on PdfSyntaxException catch (e) {
    return StampOutcome.unsupported(e.message);
    // Low-memory devices must fail softly, not crash.
    // ignore: avoid_catching_errors
  } on OutOfMemoryError {
    return const StampOutcome.unsupported('out of memory');
  } on Object catch (e) {
    return StampOutcome.unsupported(e.runtimeType.toString());
  }
}

Uint8List _stamp(Uint8List pdf, List<PdfStamp> stamps, int expectedPages) {
  final file = PdfFile(pdf);
  if (file.trailer.containsKey('Encrypt')) {
    throw const PdfSyntaxException('encrypted');
  }
  final pages = file.pages();
  if (pages.length != expectedPages) {
    throw const PdfSyntaxException('page tree mismatch');
  }
  var next = asInt(file.trailer['Size']) ?? 0;
  if (next <= 0) throw const PdfSyntaxException('bad /Size');

  final out = PdfWriter()..raw(pdf);
  if (pdf.isNotEmpty && pdf.last != 0x0A && pdf.last != 0x0D) out.text('\n');
  final offsets = <int, (int, int)>{}; // number → (offset, generation)

  void object(int number, int generation, void Function() body) {
    offsets[number] = (out.length, generation);
    out.text('$number $generation obj\n');
    body();
    out.text('\nendobj\n');
  }

  void stream(int number, PdfDict dict, List<int> data) {
    object(number, 0, () {
      out
        ..value({...dict, 'Length': data.length})
        ..text('\nstream\n')
        ..raw(data)
        ..text('\nendstream');
    });
  }

  PdfRef? fontRef;
  final byPage = <int, List<PdfStamp>>{};
  for (final s in stamps) {
    if (s.pageIndex >= pages.length) {
      throw const StampInputException(
        'A stamp is on a page that does not exist.',
      );
    }
    byPage.putIfAbsent(s.pageIndex, () => []).add(s);
  }

  for (final pageIndex in byPage.keys.toList()..sort()) {
    final page = pages[pageIndex];
    final attrs = page.attributes;
    final geometry = PageGeometry.fromBoxes(
      _box(file.resolve(attrs['MediaBox']), file),
      _box(file.resolve(attrs['CropBox']), file),
      asInt(file.resolve(attrs['Rotate'])) ?? 0,
    );

    final resources = _dictCopy(file.resolve(attrs['Resources']));
    final xobjects = _dictCopy(file.resolve(resources['XObject']));
    final fonts = _dictCopy(file.resolve(resources['Font']));
    String? fontName;

    final ops = StringBuffer('Q\n');
    for (final s in byPage[pageIndex]!) {
      switch (s) {
        case PdfImageStamp(:final png, :final left, :final top):
          final image = _decodeStampPng(png);
          PdfRef? smask;
          if (image.alpha != null) {
            final n = next++;
            stream(n, {
              'Type': const PdfName('XObject'),
              'Subtype': const PdfName('Image'),
              'Width': image.width,
              'Height': image.height,
              'ColorSpace': const PdfName('DeviceGray'),
              'BitsPerComponent': 8,
              'Filter': const PdfName('FlateDecode'),
            }, zlib.encode(image.alpha!));
            smask = PdfRef(n, 0);
          }
          final n = next++;
          stream(n, {
            'Type': const PdfName('XObject'),
            'Subtype': const PdfName('Image'),
            'Width': image.width,
            'Height': image.height,
            'ColorSpace': const PdfName('DeviceRGB'),
            'BitsPerComponent': 8,
            'Filter': const PdfName('FlateDecode'),
            'SMask': ?smask,
          }, zlib.encode(image.rgb));
          final name = _uniqueName('IdsImg', xobjects);
          xobjects[name] = PdfRef(n, 0);
          final m = geometry.imageMatrix(left, top, s.width, s.height);
          ops.write('q ${_nums(m)} cm /$name Do Q\n');
        case PdfTextStamp(
          :final text,
          :final left,
          :final top,
          :final fontSize,
          :final colorArgb,
        ):
          if (fontRef == null) {
            final n = next++;
            object(n, 0, () {
              out.value({
                'Type': const PdfName('Font'),
                'Subtype': const PdfName('Type1'),
                'BaseFont': const PdfName('Helvetica'),
                'Encoding': const PdfName('WinAnsiEncoding'),
              });
            });
            fontRef = PdfRef(n, 0);
          }
          final fName = fontName ??= _uniqueName('IdsHelv', fonts);
          fonts[fName] = fontRef;
          final baseline = top + fontSize * PdfTextStamp.ascent;
          final m = geometry.textMatrix(left, baseline);
          final r = ((colorArgb >> 16) & 0xFF) / 255;
          final g = ((colorArgb >> 8) & 0xFF) / 255;
          final b = (colorArgb & 0xFF) / 255;
          ops.write(
            'q ${_nums(m)} cm BT /$fName ${formatPdfNumber(fontSize)} Tf '
            '${_nums([r, g, b])} rg 0 0 Td ${_pdfString(text)} Tj ET Q\n',
          );
      }
    }

    // Wrap the original content in q … Q so its graphics state (e.g. a
    // leftover transformation) can't move or hide the stamps.
    final pre = next++;
    stream(pre, const {}, 'q\n'.codeUnits);
    final post = next++;
    stream(post, const {}, ops.toString().codeUnits);

    final contents = <Object>[PdfRef(pre, 0)];
    final original = page.dict['Contents'];
    if (original is PdfRef) {
      final resolved = file.resolve(original);
      if (resolved is List<Object>) {
        contents.addAll(resolved);
      } else if (resolved is PdfStreamObject) {
        contents.add(original);
      }
    } else if (original is List<Object>) {
      contents.addAll(original);
    }
    contents.add(PdfRef(post, 0));

    if (xobjects.isNotEmpty) resources['XObject'] = xobjects;
    if (fonts.isNotEmpty) resources['Font'] = fonts;
    final newPage = {
      ...page.dict,
      'Resources': resources,
      'Contents': contents,
    };
    object(page.ref.number, page.ref.generation, () => out.value(newPage));
  }

  _writeXref(out, file, offsets, next);
  return out.takeBytes();
}

void _writeXref(
  PdfWriter out,
  PdfFile file,
  Map<int, (int, int)> offsets,
  int nextNumber,
) {
  final oldSize = asInt(file.trailer['Size']) ?? 0;
  final keep = <String, Object>{
    for (final k in const ['Root', 'Info', 'ID'])
      if (file.trailer.containsKey(k)) k: file.trailer[k]!,
  };

  if (!file.usesXrefStream) {
    final start = out.length;
    out.text('xref\n');
    for (final run in _runs(offsets.keys)) {
      out.text('${run.first} ${run.length}\n');
      for (final n in run) {
        final (offset, gen) = offsets[n]!;
        out.text(
          '${offset.toString().padLeft(10, '0')} '
          '${gen.toString().padLeft(5, '0')} n\r\n',
        );
      }
    }
    out
      ..text('trailer\n')
      ..value({
        ...keep,
        'Size': math.max(oldSize, nextNumber),
        'Prev': file.startXref,
      })
      ..text('\nstartxref\n$start\n%%EOF\n');
    return;
  }

  // Cross-reference stream (W = [1 4 2]); it lists itself too.
  final xrefNumber = nextNumber;
  final start = out.length;
  final all = {...offsets, xrefNumber: (start, 0)};
  final runs = _runs(all.keys);
  final data = BytesBuilder(copy: false);
  for (final run in runs) {
    for (final n in run) {
      final (offset, gen) = all[n]!;
      data
        ..addByte(1)
        ..addByte((offset >> 24) & 0xFF)
        ..addByte((offset >> 16) & 0xFF)
        ..addByte((offset >> 8) & 0xFF)
        ..addByte(offset & 0xFF)
        ..addByte((gen >> 8) & 0xFF)
        ..addByte(gen & 0xFF);
    }
  }
  final bytes = data.takeBytes();
  out
    ..text('$xrefNumber 0 obj\n')
    ..value({
      ...keep,
      'Type': const PdfName('XRef'),
      'Size': math.max(oldSize, xrefNumber + 1),
      'Prev': file.startXref,
      'W': const [1, 4, 2],
      'Index': [
        for (final run in runs) ...[run.first, run.length],
      ],
      'Length': bytes.length,
    })
    ..text('\nstream\n')
    ..raw(bytes)
    ..text('\nendstream\nendobj\nstartxref\n$start\n%%EOF\n');
}

/// Consecutive runs of sorted object numbers.
List<List<int>> _runs(Iterable<int> numbers) {
  final sorted = numbers.toList()..sort();
  final runs = <List<int>>[];
  for (final n in sorted) {
    if (runs.isNotEmpty && runs.last.last == n - 1) {
      runs.last.add(n);
    } else {
      runs.add([n]);
    }
  }
  return runs;
}

List<double>? _box(Object value, PdfFile file) {
  if (value is! List<Object> || value.length != 4) return null;
  final out = <double>[];
  for (final v in value) {
    final d = asDouble(file.resolve(v));
    if (d == null) return null;
    out.add(d);
  }
  return out;
}

PdfDict _dictCopy(Object value) =>
    value is Map<String, Object> ? {...value} : <String, Object>{};

String _uniqueName(String base, PdfDict taken) {
  for (var i = 0; ; i++) {
    final name = '$base$i';
    if (!taken.containsKey(name)) return name;
  }
}

String _nums(List<double> values) => values.map(formatPdfNumber).join(' ');

/// A literal string for the WinAnsi-encoded standard font.
String _pdfString(String text) {
  final clean = sanitizeWatermark(text);
  final b = StringBuffer('(');
  for (final c in clean.codeUnits) {
    if (c == 0x28 || c == 0x29 || c == 0x5C) b.write(r'\');
    b.writeCharCode(c);
  }
  b.write(')');
  return b.toString();
}

/// Decoded stamp image: RGB plus optional 8-bit alpha (null when opaque).
({int width, int height, Uint8List rgb, Uint8List? alpha}) _decodeStampPng(
  Uint8List png,
) {
  img.Image? decoded;
  try {
    decoded = img.decodePng(png);
  } on Object {
    decoded = null;
  }
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    throw const StampInputException(
      'The signature image could not be read. Create it again.',
    );
  }
  var image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final longest = math.max(image.width, image.height);
  if (longest > maxStampPixels) {
    final k = maxStampPixels / longest;
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * k).round()),
      height: math.max(1, (image.height * k).round()),
      interpolation: img.Interpolation.average,
    );
  }
  final w = image.width;
  final h = image.height;
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  final rgb = Uint8List(w * h * 3);
  final alpha = Uint8List(w * h);
  var opaque = true;
  for (var i = 0, p = 0, q = 0; i < w * h; i++, p += 4, q += 3) {
    rgb[q] = rgba[p];
    rgb[q + 1] = rgba[p + 1];
    rgb[q + 2] = rgba[p + 2];
    alpha[i] = rgba[p + 3];
    if (rgba[p + 3] != 255) opaque = false;
  }
  return (width: w, height: h, rgb: rgb, alpha: opaque ? null : alpha);
}

/// Raster fallback: draws [stamps] (all on one page) onto a rendered page.
///
/// [bgra] is the page rendered at [width] x [height] px from PDFium;
/// [pageWidthPt] converts stamp points to pixels. Returns a JPEG.
Uint8List compositeStampsOnRaster(
  Uint8List bgra,
  int width,
  int height,
  double pageWidthPt,
  List<PdfStamp> stamps,
) {
  final page = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bgra.buffer,
    bytesOffset: bgra.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  ).convert(numChannels: 3);
  final k = width / pageWidthPt;
  for (final s in stamps) {
    switch (s) {
      case PdfImageStamp(:final png):
        final decoded = img.decodePng(png);
        if (decoded == null) {
          throw const StampInputException(
            'The signature image could not be read. Create it again.',
          );
        }
        final w = math.max(1, (s.width * k).round());
        final h = math.max(1, (s.height * k).round());
        final scaled = img.copyResize(
          decoded.convert(numChannels: 4),
          width: w,
          height: h,
          interpolation: img.Interpolation.average,
        );
        img.compositeImage(
          page,
          scaled,
          dstX: (s.left * k).round(),
          dstY: (s.top * k).round(),
        );
      case PdfTextStamp(:final text, :final fontSize, :final colorArgb):
        final px = fontSize * k;
        final font = px >= 36
            ? img.arial48
            : px >= 18
            ? img.arial24
            : img.arial14;
        img.drawString(
          page,
          sanitizeWatermark(text),
          font: font,
          x: (s.left * k).round(),
          y: (s.top * k).round(),
          color: img.ColorRgb8(
            (colorArgb >> 16) & 0xFF,
            (colorArgb >> 8) & 0xFF,
            colorArgb & 0xFF,
          ),
        );
    }
  }
  return img.encodeJpg(page, quality: 88);
}
