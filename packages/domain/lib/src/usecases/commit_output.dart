import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/conversion.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/ports/document_repository.dart';
import 'package:docscan_domain/src/ports/file_store.dart';
import 'package:docscan_domain/src/ports/image_processor.dart';
import 'package:docscan_domain/src/ports/pdf_engine.dart';

/// The only way new files enter the library: write to temp → validate by
/// reopening → atomically commit → record metadata. Success is reported only
/// after every step passed (PRD FR-05, FR-09; DESIGN "atomic output").
class CommitOutput {
  CommitOutput({
    required this.files,
    required this.repository,
    required this.pdf,
    required this.images,
    RedactedLogger? logger,
  }) : _log = logger ?? RedactedLogger('commit');

  final FileStore files;
  final DocumentRepository repository;
  final PdfEngine pdf;
  final ImageProcessor images;
  final RedactedLogger _log;

  Future<Result<Document>> call(OutputFile output, {String? folderId}) async {
    final ext = output.format.extension;
    final String temp;
    try {
      temp = await files.writeTemp(output.bytes, ext);
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }

    final validated = await _validate(temp, output);
    if (validated case Err(:final failure)) {
      await files.delete(temp);
      _log.warn('validation_failed', {
        'format': output.format,
        'code': failure.code,
      });
      return Err(failure);
    }
    final pageCount = validated.valueOrNull;

    // Rendered from the plaintext temp file: once committed, the library
    // copy is encrypted at rest (ADR-0010) and PDFium can't open it by path.
    final id = newId();
    final thumb = await _thumbnail(id, temp, output);

    final String relative;
    try {
      relative = await files.commit(temp, ext);
    } on Object catch (e, st) {
      await files.delete(temp);
      if (thumb != null) await files.delete(thumb);
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }

    final now = DateTime.now();
    final doc = Document(
      id: id,
      name: _cleanName(output.suggestedName),
      format: output.format,
      relativePath: relative,
      sizeBytes: output.bytes.length,
      pageCount: pageCount,
      folderId: folderId,
      thumbnailPath: thumb,
      createdAt: now,
      updatedAt: now,
    );
    final added = await repository.add(doc);
    if (added case Err(:final failure)) {
      await files.delete(relative);
      if (thumb != null) await files.delete(thumb);
      return Err(failure);
    }
    _log.info('committed', {
      'format': output.format,
      'pages': pageCount,
      'bytes': output.bytes.length,
    });
    return Ok(doc);
  }

  /// Returns the page count for PDFs, null otherwise.
  Future<Result<int?>> _validate(String temp, OutputFile output) async {
    const invalid = AppFailure(FailureCode.outputValidationFailed);
    if (output.bytes.isEmpty) return const Err(invalid);
    final head = output.bytes.sublist(0, output.bytes.length.clamp(0, 16));
    switch (output.format) {
      case DocumentFormat.pdf when output.passwordProtected:
        // Can't be opened without the password (never passed here): it must
        // be a PDF that PDFium recognises as encrypted.
        final count = await pdf.pageCount(temp);
        if (count.failureOrNull?.code != FailureCode.passwordProtected) {
          return const Err(invalid);
        }
        return Ok(output.expectedPages);
      case DocumentFormat.pdf:
        final count = await pdf.pageCount(temp);
        final n = count.valueOrNull;
        if (n == null || n < 1) return const Err(invalid);
        if (output.expectedPages != null && output.expectedPages != n) {
          return const Err(invalid);
        }
        return Ok(n);
      case DocumentFormat.jpeg || DocumentFormat.png:
        final info = await images.inspect(output.bytes);
        return info.isOk ? const Ok(null) : const Err(invalid);
      case DocumentFormat.docx ||
          DocumentFormat.xlsx ||
          DocumentFormat.pptx ||
          DocumentFormat.zip:
        return DocumentFormat.sniff(
                  head,
                  nameHint: 'x.${output.format.extension}',
                ) ==
                output.format
            ? const Ok(null)
            : const Err(invalid);
      case _ when output.format.isText:
        try {
          utf8.decode(output.bytes);
          return const Ok(null);
        } on FormatException {
          return const Err(invalid);
        }
      case _:
        return const Ok(null);
    }
  }

  Future<String?> _thumbnail(
    String id,
    String plainPath,
    OutputFile output,
  ) async {
    final Uint8List? source;
    if (output.format == DocumentFormat.pdf) {
      source = (await pdf.renderPage(
        plainPath,
        0,
        targetWidth: 360,
      )).valueOrNull;
    } else if (output.format.isImage) {
      source = output.bytes;
    } else {
      return null;
    }
    if (source == null) return null;
    final thumb = (await images.thumbnail(
      source,
      maxDimension: 360,
    )).valueOrNull;
    return thumb == null ? null : await files.writeThumbnail(id, thumb);
  }

  static String _cleanName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Document';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }
}
