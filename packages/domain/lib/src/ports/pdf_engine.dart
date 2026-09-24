import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/entities/options.dart';

/// PDF creation, rendering and page manipulation. Every method that returns
/// bytes produces a *new* PDF; inputs are never modified.
abstract interface class PdfEngine {
  /// One page per image. When [textLayers] is given (same length as
  /// [jpegPages]), an invisible OCR text layer makes the PDF searchable.
  Future<Result<Uint8List>> fromImages(
    List<Uint8List> jpegPages,
    PdfBuildOptions options, {
    List<OcrResult?>? textLayers,
  });

  /// Typesets plain text (TXT, Markdown source, CSV) into paginated PDF.
  Future<Result<Uint8List>> fromText(String text, TextPdfOptions options);

  /// `Err(passwordProtected)` for encrypted files, `Err(corruptFile)` when
  /// PDFium cannot open it.
  Future<Result<int>> pageCount(String path);

  /// Renders one page (0-based) to PNG at [targetWidth] pixels wide.
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  });

  /// Embedded text per page. Image-only pages return empty strings — callers
  /// fall back to OCR.
  Future<Result<List<String>>> extractText(String path);

  Future<Result<Uint8List>> merge(List<String> paths);

  /// New PDF containing [pageIndices] (0-based) in the given order. Covers
  /// split, extract, delete and reorder.
  Future<Result<Uint8List>> selectPages(String path, List<int> pageIndices);

  /// Rotates pages clockwise by quarter turns (`{pageIndex: turns}`).
  Future<Result<Uint8List>> rotatePages(
    String path,
    Map<int, int> quarterTurns,
  );

  /// Re-renders every page as JPEG. Lossy; text stops being selectable.
  Future<Result<Uint8List>> compress(
    String path,
    PdfCompressionLevel level, {
    void Function(double progress)? onProgress,
  });
}
