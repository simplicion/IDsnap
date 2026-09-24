import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/pdf_writer.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfEngine] backed by `package:pdf` (writing) and PDFium via `pdfrx`
/// (opening, rendering, text extraction, page assembly).
///
/// Requires `initPdfEngine()` (Flutter) or `pdfrxInitialize()` (Dart) first.
class PdfEngineImpl implements PdfEngine {
  PdfEngineImpl({this.unicodeFont, RedactedLogger? logger})
    : _log = logger ?? RedactedLogger('pdf');

  /// Optional TTF used by [fromText] for non-Latin text. Without it,
  /// unsupported characters become `?`.
  final Uint8List? unicodeFont;
  final RedactedLogger _log;

  // ── Writing ────────────────────────────────────────────────────────────

  @override
  Future<Result<Uint8List>> fromImages(
    List<Uint8List> jpegPages,
    PdfBuildOptions options, {
    List<OcrResult?>? textLayers,
  }) {
    if (jpegPages.isEmpty) {
      return Future.value(
        const Err(AppFailure(FailureCode.conversionFailed, detail: 'No pages')),
      );
    }
    return guard(
      () => Isolate.run(
        () => buildImagePdf(jpegPages, options, textLayers: textLayers),
      ),
      code: FailureCode.conversionFailed,
    );
  }

  /// Typesets [text] into paginated PDF. A form feed (`\f`) is a hard page
  /// break: each `\f`-separated chunk starts on a new page.
  @override
  Future<Result<Uint8List>> fromText(String text, TextPdfOptions options) {
    final font = unicodeFont;
    return guard(
      () => Isolate.run(() => buildTextPdf(text, options, unicodeFont: font)),
      code: FailureCode.conversionFailed,
    );
  }

  // ── Reading ────────────────────────────────────────────────────────────

  @override
  Future<Result<int>> pageCount(String path) =>
      _withDoc(path, (doc) async => doc.pages.length);

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) => _withDoc(path, (doc) async {
    _checkIndex(doc, index);
    final rgba = await _renderRgba(doc.pages[index], targetWidth: targetWidth);
    return await runHeavy(
      () => Uint8List.fromList(img.encodePng(rgba, level: 4)),
    );
  });

  @override
  Future<Result<List<String>>> extractText(String path) =>
      _withDoc(path, (doc) async {
        final out = <String>[];
        for (final page in doc.pages) {
          final text = await page.loadText();
          out.add(text?.fullText.trim() ?? '');
        }
        return out;
      });

  // ── Page assembly ──────────────────────────────────────────────────────

  @override
  Future<Result<Uint8List>> merge(List<String> paths) async {
    if (paths.isEmpty) {
      return const Err(
        AppFailure(FailureCode.conversionFailed, detail: 'No files'),
      );
    }
    final opened = <rx.PdfDocument>[];
    try {
      for (final p in paths) {
        final r = await _open(p);
        if (r case Err(:final failure)) return Err(failure);
        opened.add(r.valueOrNull!);
      }
      return await _assemble([for (final d in opened) ...d.pages]);
    } finally {
      for (final d in opened) {
        await d.dispose();
      }
    }
  }

  @override
  Future<Result<Uint8List>> selectPages(String path, List<int> pageIndices) =>
      _withDocResult(path, (doc) async {
        if (pageIndices.isEmpty) {
          return const Err(
            AppFailure(
              FailureCode.conversionFailed,
              detail: 'No pages selected',
            ),
          );
        }
        for (final i in pageIndices) {
          _checkIndex(doc, i);
        }
        return await _assemble([for (final i in pageIndices) doc.pages[i]]);
      });

  @override
  Future<Result<Uint8List>> rotatePages(
    String path,
    Map<int, int> quarterTurns,
  ) => _withDocResult(path, (doc) async {
    for (final i in quarterTurns.keys) {
      _checkIndex(doc, i);
    }
    return await _assemble([
      for (var i = 0; i < doc.pages.length; i++)
        switch ((quarterTurns[i] ?? 0) % 4) {
          0 => doc.pages[i],
          final t => doc.pages[i].rotatedBy(rx.PdfPageRotation.values[t]),
        },
    ]);
  });

  @override
  Future<Result<Uint8List>> compress(
    String path,
    PdfCompressionLevel level, {
    void Function(double progress)? onProgress,
  }) => _withDocResult(path, (doc) async {
    final jpegs = <Uint8List>[];
    final sizes = <({double w, double h})>[];
    final total = doc.pages.length;
    for (var i = 0; i < total; i++) {
      final page = doc.pages[i];
      final widthPx = (page.width / 72 * level.dpi).round().clamp(64, 6000);
      final rgba = await _renderRgba(page, targetWidth: widthPx);
      final quality = level.jpegQuality;
      jpegs.add(
        await runHeavy(
          () => Uint8List.fromList(img.encodeJpg(rgba, quality: quality)),
        ),
      );
      sizes.add((w: page.width, h: page.height));
      onProgress?.call((i + 1) / total * 0.95);
    }
    final bytes = await Isolate.run(() => buildSizedImagePdf(jpegs, sizes));
    onProgress?.call(1);
    _log.info('compressed', {'pages': total, 'level': level});
    return Ok(bytes);
  });

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<Result<rx.PdfDocument>> _open(String path) async {
    if (!File(path).existsSync()) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    try {
      final doc = await rx.PdfDocument.openFile(path);
      return Ok(doc);
    } on rx.PdfPasswordException catch (e, st) {
      return Err(
        AppFailure(FailureCode.passwordProtected, cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    }
  }

  Future<Result<T>> _withDoc<T>(
    String path,
    Future<T> Function(rx.PdfDocument doc) body,
  ) => _withDocResult(path, (doc) async => Ok(await body(doc)));

  Future<Result<T>> _withDocResult<T>(
    String path,
    Future<Result<T>> Function(rx.PdfDocument doc) body,
  ) async {
    final opened = await _open(path);
    if (opened case Err(:final failure)) return Err(failure);
    final doc = opened.valueOrNull!;
    try {
      return await body(doc);
    } on AppFailure catch (f) {
      return Err(f);
    } on Object catch (e, st) {
      _log.error('pdf_op_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(FailureCode.conversionFailed, cause: e, stackTrace: st),
      );
    } finally {
      await doc.dispose();
    }
  }

  Future<Result<Uint8List>> _assemble(List<rx.PdfPage> pages) async {
    final out = await rx.PdfDocument.createNew(sourceName: 'docscan-output');
    try {
      out.pages = pages;
      return Ok(await out.encodePdf());
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.conversionFailed, cause: e, stackTrace: st),
      );
    } finally {
      await out.dispose();
    }
  }

  static void _checkIndex(rx.PdfDocument doc, int index) {
    if (index < 0 || index >= doc.pages.length) {
      throw AppFailure(
        FailureCode.conversionFailed,
        detail: 'Page ${index + 1} does not exist',
      );
    }
  }

  /// Renders a page on a white background and converts BGRA → RGBA image.
  static Future<img.Image> _renderRgba(
    rx.PdfPage page, {
    required int targetWidth,
  }) async {
    final scale = targetWidth / page.width;
    final w = targetWidth;
    final h = (page.height * scale).round().clamp(1, 20000);
    final rendered = await page.render(
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (rendered == null) {
      throw const AppFailure(
        FailureCode.corruptFile,
        detail: 'Page could not be rendered',
      );
    }
    try {
      final pixels = Uint8List.fromList(rendered.pixels);
      return img.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
    } finally {
      rendered.dispose();
    }
  }
}
