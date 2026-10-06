import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/isolate_jobs.dart';
import 'package:engine_pdf/src/protect/pdf_protection_engine.dart';
import 'package:engine_pdf/src/stamp/incremental_stamper.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfEngine] backed by `package:pdf` (writing) and PDFium via `pdfrx`
/// (opening, rendering, text extraction, page assembly).
///
/// Requires `initPdfEngine()` (Flutter) or `pdfrxInitialize()` (Dart) first.
///
/// Isolate rule: CPU work goes through `isolate_jobs.dart` helpers, which
/// only ever receive plain data. Never pass a closure defined in this class
/// to `Isolate.run` — it would capture callbacks such as `onProgress`.
class PdfEngineImpl
    implements PdfEngine, PdfStamper, PdfProtector, ProtectedZipWriter {
  PdfEngineImpl({this.unicodeFont, RedactedLogger? logger})
    : _log = logger ?? RedactedLogger('pdf'),
      _protection = PdfProtectionEngine(logger: logger);

  /// Optional TTF used by [fromText] for non-Latin text. Without it,
  /// unsupported characters become `?`.
  final Uint8List? unicodeFont;
  final RedactedLogger _log;
  final PdfProtectionEngine _protection;

  /// Upper bound for a single PDFium operation (open/render/text).
  static const opTimeout = Duration(seconds: 60);

  // ── Writing ────────────────────────────────────────────────────────────

  @override
  Future<Result<Uint8List>> fromImages(
    List<Uint8List> jpegPages,
    PdfBuildOptions options, {
    List<OcrResult?>? textLayers,
  }) async {
    if (jpegPages.isEmpty) {
      return const Err(
        AppFailure(FailureCode.conversionFailed, detail: 'No pages'),
      );
    }
    return await _run(
      'from_images',
      () => runBuildImagePdf(jpegPages, options, textLayers),
    );
  }

  /// Typesets [text] into paginated PDF. A form feed (`\f`) is a hard page
  /// break: each `\f`-separated chunk starts on a new page.
  @override
  Future<Result<Uint8List>> fromText(String text, TextPdfOptions options) =>
      _run('from_text', () => runBuildTextPdf(text, options, unicodeFont));

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
    final frame = await _renderBgra(doc.pages[index], targetWidth);
    return await encodeBgraAsPng(frame.bgra, frame.width, frame.height);
  });

  @override
  Future<Result<List<String>>> extractText(String path) =>
      _withDoc(path, (doc) async {
        final out = <String>[];
        for (final page in doc.pages) {
          final text = await page.loadText().timeout(opTimeout);
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
    final total = doc.pages.length;
    if (total == 0) {
      return const Err(AppFailure(FailureCode.corruptFile, detail: 'No pages'));
    }
    final jpegs = <Uint8List>[];
    final widths = <double>[];
    final heights = <double>[];
    for (var i = 0; i < total; i++) {
      final page = doc.pages[i];
      final widthPx = (page.width / 72 * level.dpi).round().clamp(64, 6000);
      final frame = await _renderBgra(page, widthPx);
      jpegs.add(
        await encodeBgraAsJpeg(
          frame.bgra,
          frame.width,
          frame.height,
          level.jpegQuality,
        ),
      );
      widths.add(page.width);
      heights.add(page.height);
      onProgress?.call((i + 1) / total * 0.95);
    }
    final bytes = await runBuildSizedImagePdf(jpegs, widths, heights);
    onProgress?.call(1);
    _log.info('compressed', {'pages': total, 'level': level});
    return Ok(bytes);
  });

  // ── Stamping (PRD 3.3) ─────────────────────────────────────────────────

  @override
  Future<Result<List<PdfPageDimensions>>> pageDimensions(String path) =>
      _withDoc(
        path,
        (doc) async => [
          for (final p in doc.pages) PdfPageDimensions(p.width, p.height),
        ],
      );

  /// Tries, in order of fidelity: an incremental update of the original
  /// bytes; the same update on a PDFium re-save (for files this reader
  /// can't parse, e.g. encrypted-with-empty-password or broken xref); and,
  /// as a documented last resort, rasterising only the stamped pages.
  /// Every candidate is re-opened and its page count checked.
  @override
  Future<Result<StampedPdf>> stamp(String path, List<PdfStamp> stamps) async {
    final problem = validateStamps(stamps);
    if (problem != null) {
      return Err(
        AppFailure(
          FailureCode.conversionFailed,
          detail: problem,
          message: problem,
        ),
      );
    }
    return await _withDocResult(path, (doc) async {
      final count = doc.pages.length;
      for (final s in stamps) {
        _checkIndex(doc, s.pageIndex);
      }

      final original = await File(path).readAsBytes();
      final direct = await runStampIncremental(original, stamps, count);
      if (direct.badInput) return Err(_badStamp(direct.error));
      if (direct.bytes case final bytes? when await _verify(bytes, count)) {
        return Ok(
          StampedPdf(
            bytes: bytes,
            pageCount: count,
            method: StampMethod.incremental,
          ),
        );
      }
      _log.warn('stamp_incremental_unavailable', {'reason': direct.error});

      final rebuilt = await _assemble(doc.pages);
      if (rebuilt.valueOrNull case final base?) {
        final second = await runStampIncremental(base, stamps, count);
        if (second.bytes case final bytes? when await _verify(bytes, count)) {
          return Ok(
            StampedPdf(
              bytes: bytes,
              pageCount: count,
              method: StampMethod.rebuilt,
            ),
          );
        }
        _log.warn('stamp_rebuilt_unavailable', {'reason': second.error});
      }

      final raster = await _rasterStamp(doc, stamps);
      if (raster case Err(:final failure)) return Err(failure);
      final bytes = raster.valueOrNull!;
      if (!await _verify(bytes, count)) {
        return const Err(AppFailure(FailureCode.outputValidationFailed));
      }
      _log.info('stamp_rasterized', {'pages': count});
      return Ok(
        StampedPdf(
          bytes: bytes,
          pageCount: count,
          method: StampMethod.rasterized,
        ),
      );
    });
  }

  static AppFailure _badStamp(String? message) => AppFailure(
    FailureCode.corruptFile,
    detail: 'Signature image',
    message: message ?? 'The signature image could not be read.',
  );

  /// Re-opens [bytes] with PDFium and checks the page count.
  Future<bool> _verify(Uint8List bytes, int expectedPages) async {
    rx.PdfDocument? doc;
    try {
      doc = await rx.PdfDocument.openData(
        bytes,
        sourceName: 'stamp-verify',
      ).timeout(opTimeout);
      return doc.pages.length == expectedPages;
    } on Object {
      return false;
    } finally {
      await doc?.dispose();
    }
  }

  /// Last resort: re-renders only the stamped pages at 150 dpi with the
  /// stamps burned in. Text on those pages stops being selectable.
  Future<Result<Uint8List>> _rasterStamp(
    rx.PdfDocument doc,
    List<PdfStamp> stamps,
  ) async {
    final byPage = <int, List<PdfStamp>>{};
    for (final s in stamps) {
      byPage.putIfAbsent(s.pageIndex, () => []).add(s);
    }
    final indices = byPage.keys.toList()..sort();
    final jpegs = <Uint8List>[];
    final widths = <double>[];
    final heights = <double>[];
    try {
      for (final i in indices) {
        final page = doc.pages[i];
        final px = (page.width / 72 * 150).round().clamp(64, 4000);
        final frame = await _renderBgra(page, px);
        jpegs.add(
          await runCompositeStamps(
            frame.bgra,
            frame.width,
            frame.height,
            page.width,
            byPage[i]!,
          ),
        );
        widths.add(page.width);
        heights.add(page.height);
      }
    } on StampInputException catch (e) {
      return Err(_badStamp(e.message));
    }
    final imagePdf = await runBuildSizedImagePdf(jpegs, widths, heights);
    final rasterDoc = await rx.PdfDocument.openData(
      imagePdf,
      sourceName: 'stamp-raster',
    ).timeout(opTimeout);
    try {
      return await _assemble([
        for (var i = 0; i < doc.pages.length; i++)
          if (byPage.containsKey(i))
            rasterDoc.pages[indices.indexOf(i)]
          else
            doc.pages[i],
      ]);
    } finally {
      await rasterDoc.dispose();
    }
  }

  // ── Password protection (AES-256 PDF / AES-256 ZIP) ───────────────────

  @override
  Future<Result<bool>> needsPassword(String path) =>
      _protection.needsPassword(path);

  @override
  Future<Result<ProtectedFile>> protectPdf(
    String inputPath,
    PdfProtection protection, {
    required String outputPath,
    String? currentPassword,
  }) => _protection.protectPdf(
    inputPath,
    protection,
    outputPath: outputPath,
    currentPassword: currentPassword,
  );

  @override
  Future<Result<ProtectedFile>> removePdfPassword(
    String inputPath,
    String password, {
    required String outputPath,
  }) => _protection.removePdfPassword(
    inputPath,
    password,
    outputPath: outputPath,
  );

  @override
  Future<Result<ProtectedFile>> writeProtectedZip(
    List<ZipSource> sources,
    String password, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) => _protection.writeProtectedZip(
    sources,
    password,
    outputPath: outputPath,
    onProgress: onProgress,
  );

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<Result<Uint8List>> _run(
    String op,
    Future<Uint8List> Function() body,
  ) async {
    try {
      return Ok(await body());
      // Deliberate: report exhausted memory as a typed, recoverable failure.
      // ignore: avoid_catching_errors
    } on OutOfMemoryError catch (e, st) {
      return Err(
        AppFailure(FailureCode.memoryLimitExceeded, cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      _log.error('pdf_write_failed', {
        'op': op,
        'type': e.runtimeType.toString(),
      });
      return Err(
        AppFailure(FailureCode.conversionFailed, cause: e, stackTrace: st),
      );
    }
  }

  Future<Result<rx.PdfDocument>> _open(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    if (file.lengthSync() == 0) {
      return const Err(AppFailure(FailureCode.emptyFile));
    }
    try {
      final doc = await rx.PdfDocument.openFile(path).timeout(opTimeout);
      return Ok(doc);
    } on rx.PdfPasswordException catch (e, st) {
      return Err(
        AppFailure(FailureCode.passwordProtected, cause: e, stackTrace: st),
      );
    } on TimeoutException catch (e, st) {
      return Err(AppFailure(FailureCode.timeout, cause: e, stackTrace: st));
    } on Object catch (e, st) {
      _log.warn('pdf_open_failed', {'type': e.runtimeType.toString()});
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
    } on TimeoutException catch (e, st) {
      return Err(AppFailure(FailureCode.timeout, cause: e, stackTrace: st));
      // Deliberate: report exhausted memory as a typed, recoverable failure.
      // ignore: avoid_catching_errors
    } on OutOfMemoryError catch (e, st) {
      return Err(
        AppFailure(FailureCode.memoryLimitExceeded, cause: e, stackTrace: st),
      );
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

  /// Renders a page on white and returns a *copy* of the BGRA pixels, so the
  /// native buffer can be released before any isolate hop.
  static Future<({Uint8List bgra, int width, int height})> _renderBgra(
    rx.PdfPage page,
    int targetWidth,
  ) async {
    final scale = targetWidth / page.width;
    final w = targetWidth;
    final h = (page.height * scale).round().clamp(1, 20000);
    final rendered = await page
        .render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        )
        .timeout(opTimeout);
    if (rendered == null) {
      throw const AppFailure(
        FailureCode.corruptFile,
        detail: 'Page could not be rendered',
      );
    }
    try {
      return (
        bgra: Uint8List.fromList(rendered.pixels),
        width: rendered.width,
        height: rendered.height,
      );
    } finally {
      rendered.dispose();
    }
  }
}
