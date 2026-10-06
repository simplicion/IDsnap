import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/ports/file_store.dart';
import 'package:docscan_domain/src/ports/pdf_engine.dart';
import 'package:docscan_domain/src/usecases/recognize_text.dart';

/// OCR for a list of photos and/or PDFs, page by page.
///
/// * PDF pages that already have a text layer use it (no OCR) unless
///   [call]'s `forceOcr` is set; image-only pages are rendered one at a time
///   to a temp PNG, recognized, and the temp file deleted before the next
///   page, so memory stays flat for long documents.
/// * A page that fails (damaged page, decode error, timeout…) is reported in
///   its [OcrPage.failure] and the job continues. Only failures that would
///   repeat on every page (model missing, storage full) stop the job.
/// * [OcrCancelToken] is checked between pages and recognition passes; a
///   cancelled job returns the pages finished so far with `cancelled: true`.
class RecognizeDocument {
  RecognizeDocument({
    required this.recognize,
    required this.pdf,
    required this.files,
    this.renderWidth = 2400,
  });

  final RecognizeText recognize;
  final PdfEngine pdf;
  final FileStore files;

  /// Pixel width PDF pages are rendered at for OCR (~290 dpi for A4).
  final int renderWidth;

  static const _jobStoppers = {
    FailureCode.modelUnavailable,
    FailureCode.insufficientStorage,
    FailureCode.offlineDependencyUnavailable,
  };

  Future<Result<OcrDocumentResult>> call(
    List<OcrSource> sources, {
    OcrOptions options = const OcrOptions(),
    OcrCancelToken? cancel,
    bool forceOcr = false,
    void Function(OcrProgress progress)? onProgress,
    void Function(OcrPage page)? onPage,
  }) async {
    if (sources.isEmpty) {
      return const Err(AppFailure(FailureCode.notFound, detail: 'No files'));
    }
    // Fail fast when the chosen script is not installed.
    final scripts = await recognize.scriptsFor(options);
    if (scripts case Err(:final failure)) return Err(failure);

    final pages = <OcrPage>[];
    void emit(OcrPage p) {
      pages.add(p);
      onPage?.call(p);
    }

    // Plan: count pages up front so progress is honest.
    final plans = <_Plan>[];
    for (final (i, s) in sources.indexed) {
      switch (s) {
        case OcrImageSource():
          plans.add(_Plan(i, s, 1));
        case OcrPdfSource():
          final count = await pdf.pageCount(s.path);
          switch (count) {
            case Ok(:final value):
              plans.add(_Plan(i, s, value));
            case Err(:final failure):
              plans.add(_Plan(i, s, 0, failure: failure));
          }
      }
    }
    final total = plans.fold<int>(
      0,
      (a, p) => a + (p.pages == 0 ? 1 : p.pages),
    );
    var done = 0;
    void progress(String label) =>
        onProgress?.call(OcrProgress(done: done, total: total, label: label));

    for (final plan in plans) {
      final s = plan.source;
      if (plan.failure != null || plan.pages == 0) {
        emit(
          OcrPage(
            sourceIndex: plan.index,
            pageIndex: 0,
            label: s.name,
            failure: (plan.failure ?? const AppFailure(FailureCode.emptyFile))
                .withDetail(s.name),
          ),
        );
        done++;
        progress(s.name);
        continue;
      }

      List<String>? embedded;
      if (s is OcrPdfSource && !forceOcr) {
        // Missing text layer is not an error: every page is OCR'd instead.
        embedded = (await pdf.extractText(s.path)).valueOrNull;
      }

      for (var p = 0; p < plan.pages; p++) {
        if (cancel?.isCancelled ?? false) {
          return Ok(OcrDocumentResult(pages: pages, cancelled: true));
        }
        final label = s is OcrPdfSource
            ? (plan.pages == 1 ? s.name : '${s.name} · page ${p + 1}')
            : s.name;
        progress(label);

        final text = embedded != null && p < embedded.length
            ? embedded[p]
            : null;
        final OcrPage page;
        if (text != null && text.trim().isNotEmpty) {
          page = OcrPage(
            sourceIndex: plan.index,
            pageIndex: p,
            label: label,
            embeddedText: text,
          );
        } else {
          final r = s is OcrPdfSource
              ? await _pdfPage(s.path, p, options, cancel)
              : await recognize(s.path, options: options, cancel: cancel);
          if (r case Err(:final failure)) {
            if (failure.code == FailureCode.processingCancelled) {
              return Ok(OcrDocumentResult(pages: pages, cancelled: true));
            }
            if (_jobStoppers.contains(failure.code)) return Err(failure);
          }
          page = OcrPage(
            sourceIndex: plan.index,
            pageIndex: p,
            label: label,
            result: r.valueOrNull,
            failure: r.failureOrNull?.withDetail(label),
          );
        }
        emit(page);
        done++;
        progress(label);
      }
    }
    return Ok(OcrDocumentResult(pages: pages));
  }

  /// Renders one page to a temp file, recognizes it, deletes the file.
  Future<Result<OcrResult>> _pdfPage(
    String path,
    int index,
    OcrOptions options,
    OcrCancelToken? cancel,
  ) async {
    final png = await pdf.renderPage(path, index, targetWidth: renderWidth);
    if (png case Err(:final failure)) return Err(failure);
    final String temp;
    try {
      temp = await files.writeTemp(png.valueOrNull!, 'png');
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }
    try {
      return await recognize(temp, options: options, cancel: cancel);
    } finally {
      await files.delete(temp);
    }
  }
}

class _Plan {
  _Plan(this.index, this.source, this.pages, {this.failure});

  final int index;
  final OcrSource source;
  final int pages;
  final AppFailure? failure;
}
