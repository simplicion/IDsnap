import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/ports/file_store.dart';
import 'package:docscan_domain/src/ports/pdf_engine.dart';
import 'package:meta/meta.dart';

/// What pre-flight learned about an input file.
@immutable
class InputReport {
  const InputReport({
    required this.format,
    required this.sizeBytes,
    this.pageCount,
    this.textPages,
  });

  final DocumentFormat format;
  final int sizeBytes;

  /// PDFs only.
  final int? pageCount;

  /// PDFs only (when requested): pages that already have a text layer.
  final int? textPages;

  /// True for a PDF whose pages are all images without a text layer.
  bool get isScannedPdf =>
      format == DocumentFormat.pdf && textPages != null && textPages == 0;
}

/// Pre-flight validation before any heavy engine work (production audit
/// 2026-09): the file exists, is readable, is not empty, its *content*
/// matches the expected format, and PDFs open (not encrypted/corrupt).
///
/// Returns a typed [AppFailure] with a next action instead of letting a
/// heavy operation fail later with a generic error.
class InspectInput {
  const InspectInput({required this.files, required this.pdf});

  final FileStore files;
  final PdfEngine pdf;

  Future<Result<InputReport>> call(
    String path, {
    required Set<DocumentFormat> accepts,
    String? nameHint,
    bool detectTextLayer = false,
  }) async {
    final int size;
    try {
      if (!await files.exists(path)) {
        return const Err(AppFailure(FailureCode.notFound));
      }
      size = await files.size(path);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    if (size == 0) return const Err(AppFailure(FailureCode.emptyFile));

    final DocumentFormat format;
    try {
      final bytes = await files.read(path);
      final head = bytes.length > 64 ? bytes.sublist(0, 64) : bytes;
      format = DocumentFormat.sniff(head, nameHint: nameHint ?? path);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }

    final ok =
        accepts.contains(format) ||
        (format.isText && accepts.any((f) => f.isText));
    if (!ok) {
      return Err(
        AppFailure(
          format == DocumentFormat.heic
              ? FailureCode.unsupportedFormat
              : format == DocumentFormat.unknown
              ? FailureCode.corruptFile
              : FailureCode.unsupportedFormat,
          message: format == DocumentFormat.unknown
              ? "This file isn't a valid ${_labels(accepts)}."
              : '${format.label} files are not supported here. '
                    'Choose a ${_labels(accepts)}.',
        ),
      );
    }

    if (format != DocumentFormat.pdf) {
      return Ok(InputReport(format: format, sizeBytes: size));
    }
    final count = await pdf.pageCount(path);
    if (count case Err(:final failure)) return Err(failure);
    final pages = count.valueOrNull!;
    if (pages < 1) {
      return const Err(AppFailure(FailureCode.corruptFile, detail: 'No pages'));
    }
    int? textPages;
    if (detectTextLayer) {
      final text = await pdf.extractText(path);
      if (text case Err(:final failure)) return Err(failure);
      textPages = text.valueOrNull!.where((t) => t.trim().isNotEmpty).length;
    }
    return Ok(
      InputReport(
        format: format,
        sizeBytes: size,
        pageCount: pages,
        textPages: textPages,
      ),
    );
  }

  static String _labels(Set<DocumentFormat> formats) {
    final labels = <String>{
      for (final f in formats)
        if (f.isImage) 'image' else f.label,
    }.toList();
    return labels.length <= 2
        ? labels.join(' or ')
        : '${labels.take(labels.length - 1).join(', ')} or ${labels.last}';
  }
}
