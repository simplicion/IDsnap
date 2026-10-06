import 'package:meta/meta.dart';

/// Output quality presets for scans and image-based PDFs.
enum QualityPreset {
  small('Small', 'Smaller files, good for email', 1600, 62),
  balanced('Balanced', 'Recommended', 2200, 78),
  high('High quality', 'Best for printing', 3000, 90);

  const QualityPreset(
    this.label,
    this.hint,
    this.maxDimension,
    this.jpegQuality,
  );

  final String label;
  final String hint;

  /// Longest edge of each page image in pixels.
  final int maxDimension;
  final int jpegQuality;
}

enum PdfPageSize {
  a4('A4', 595.28, 841.89),
  letter('Letter', 612, 792),
  legal('Legal', 612, 1008),
  fit('Fit to image', 0, 0);

  const PdfPageSize(this.label, this.widthPt, this.heightPt);

  final String label;
  final double widthPt;
  final double heightPt;
}

@immutable
class PdfBuildOptions {
  const PdfBuildOptions({
    this.pageSize = PdfPageSize.a4,
    this.marginPt = 0,
    this.title,
  });

  final PdfPageSize pageSize;
  final double marginPt;

  /// Stored in PDF metadata. Leave null to avoid embedding names.
  final String? title;
}

@immutable
class TextPdfOptions {
  const TextPdfOptions({
    this.pageSize = PdfPageSize.a4,
    this.fontSize = 11,
    this.monospace = false,
    this.title,
  });

  final PdfPageSize pageSize;
  final double fontSize;

  /// Use for CSV and code so columns stay aligned.
  final bool monospace;
  final String? title;
}

/// PDF compression works by re-rendering pages as JPEG. It is lossy and makes
/// text non-selectable — the UI must say so before running it.
enum PdfCompressionLevel {
  light('Light', 'Near-original quality', 150, 80),
  recommended('Recommended', 'Good balance of size and clarity', 110, 65),
  strong('Strong', 'Smallest file, lower image quality', 80, 45);

  const PdfCompressionLevel(this.label, this.hint, this.dpi, this.jpegQuality);

  final String label;
  final String hint;
  final int dpi;
  final int jpegQuality;
}

enum ImageOutputFormat {
  jpeg('JPG', 'jpg'),
  png('PNG', 'png');

  const ImageOutputFormat(this.label, this.extension);
  final String label;
  final String extension;
}

@immutable
class ImageCompressionOptions {
  const ImageCompressionOptions({
    this.quality = 75,
    this.maxDimension,
    this.format = ImageOutputFormat.jpeg,
    this.targetBytes,
  });

  /// 1–100 JPEG quality; ignored for PNG.
  final int quality;

  /// Downscale so the longest edge is at most this many pixels.
  final int? maxDimension;
  final ImageOutputFormat format;

  /// When set (JPEG only), search for the highest quality under this size —
  /// useful for upload forms that cap file size (e.g. 200 KB).
  final int? targetBytes;
}

@immutable
class ImageDetails {
  const ImageDetails({
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  final int width;
  final int height;
  final int sizeBytes;
}

@immutable
class EncodedImage {
  const EncodedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
  });

  final List<int> bytes;
  final int width;
  final int height;
  final ImageOutputFormat format;
}
