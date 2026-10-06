import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:meta/meta.dart';

// Digital signature & transparent stamp (PRD Phase 3.3). Kept in its own
// port so existing PdfEngine implementations and test fakes stay untouched.

/// Something drawn on top of an existing PDF page.
///
/// Coordinates are PDF points (1/72 in) measured from the top-left corner of
/// the page *as displayed*: after the page's `/Rotate` is applied and within
/// its crop box — the same space as the rendered page image and as
/// [PdfPageDimensions].
@immutable
sealed class PdfStamp {
  const PdfStamp({
    required this.pageIndex,
    required this.left,
    required this.top,
  });

  /// 0-based page index.
  final int pageIndex;
  final double left;
  final double top;
}

/// A transparent PNG (e.g. a signature) scaled into a rectangle.
final class PdfImageStamp extends PdfStamp {
  const PdfImageStamp({
    required super.pageIndex,
    required super.left,
    required super.top,
    required this.width,
    required this.height,
    required this.png,
  });

  final double width;
  final double height;

  /// PNG bytes; the alpha channel is preserved.
  final Uint8List png;
}

/// A single line of text (e.g. the signing date) in a standard font.
final class PdfTextStamp extends PdfStamp {
  const PdfTextStamp({
    required super.pageIndex,
    required super.left,
    required super.top,
    required this.text,
    this.fontSize = 12,
    this.colorArgb = 0xFF000000,
  });

  /// Latin-1 text; other characters are replaced with `?`.
  final String text;

  /// Font size in points. [top] is the top of the text line; the baseline
  /// sits at `top + fontSize * PdfTextStamp.ascent`.
  final double fontSize;
  final int colorArgb;

  /// Baseline offset as a fraction of the font size (Helvetica ascent).
  static const ascent = 0.78;

  /// Approximate advance width of [text] in points (Helvetica average).
  double get approximateWidth => text.length * fontSize * 0.55;
}

/// Displayed size of a page in points (rotation and crop box applied).
@immutable
class PdfPageDimensions {
  const PdfPageDimensions(this.width, this.height);

  final double width;
  final double height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  bool operator ==(Object other) =>
      other is PdfPageDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PdfPageDimensions($width x $height)';
}

/// How a stamped PDF was produced, from best to worst fidelity.
enum StampMethod {
  /// Original bytes kept; the stamps were appended as an incremental update.
  /// Text stays selectable and existing digital signatures stay intact.
  incremental,

  /// The PDF could not be parsed directly, so its pages were re-saved with
  /// PDFium first. Vector text stays selectable; bookmarks and forms may be
  /// dropped.
  rebuilt,

  /// Last resort: stamped pages were rendered to images. Text on those pages
  /// is no longer selectable.
  rasterized,
}

@immutable
class StampedPdf {
  const StampedPdf({
    required this.bytes,
    required this.pageCount,
    required this.method,
  });

  final Uint8List bytes;
  final int pageCount;
  final StampMethod method;
}

/// Overlays images and text on an existing PDF while keeping its content.
abstract interface class PdfStamper {
  /// Displayed page sizes in points, one per page.
  Future<Result<List<PdfPageDimensions>>> pageDimensions(String path);

  /// Returns a *new* PDF with [stamps] drawn on top. The input file is never
  /// modified. The output is re-opened and its page count checked before it
  /// is returned.
  Future<Result<StampedPdf>> stamp(String path, List<PdfStamp> stamps);
}

/// A signature saved for reuse.
@immutable
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.width,
    required this.height,
    this.isDefault = false,
  });

  final String id;

  /// PNG file name inside the signatures folder.
  final String fileName;
  final DateTime createdAt;
  final int width;
  final int height;
  final bool isDefault;

  double get aspectRatio => height == 0 ? 1 : width / height;

  SavedSignature copyWith({bool? isDefault}) => SavedSignature(
    id: id,
    fileName: fileName,
    createdAt: createdAt,
    width: width,
    height: height,
    isDefault: isDefault ?? this.isDefault,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedSignature &&
      other.id == id &&
      other.fileName == fileName &&
      other.createdAt == createdAt &&
      other.width == width &&
      other.height == height &&
      other.isDefault == isDefault;

  @override
  int get hashCode =>
      Object.hash(id, fileName, createdAt, width, height, isDefault);
}

/// Small on-device library of transparent signature PNGs.
abstract interface class SignatureLibrary {
  /// Maximum number of signatures kept.
  static const capacity = 5;

  /// Newest first; the default signature (if any) is marked.
  Future<Result<List<SavedSignature>>> list();

  /// Saves a transparent PNG. The first signature becomes the default.
  /// `Err(targetSizeUnreachable)` when the library is full.
  Future<Result<SavedSignature>> add(
    Uint8List png, {
    required int width,
    required int height,
  });

  Future<Result<Uint8List>> load(String id);

  Future<Result<void>> delete(String id);

  Future<Result<void>> setDefault(String id);
}
