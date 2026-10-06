import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';

/// A bundle of published upload constraints (roadmap Feature C). Kits are
/// data: requirement changes ship by editing the catalog, not the code.
@immutable
class ApplicationKit {
  const ApplicationKit({
    required this.id,
    required this.label,
    required this.description,
    required this.source,
    required this.reviewedOn,
    required this.items,
    this.category,
  });

  final String id;
  final String label;
  final String description;

  /// Where the limits come from (shown to the user).
  final String source;

  /// When a person last checked [source] (yyyy-MM-dd).
  final String reviewedOn;
  final List<KitItem> items;

  /// Vault category saved outputs are filed under.
  final DocumentCategory? category;

  KitItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// One output a kit produces.
sealed class KitItem {
  const KitItem({required this.id, required this.label, this.hint});

  final String id;
  final String label;
  final String? hint;
}

/// A cropped, auto-framed, size-limited photo.
final class PhotoItem extends KitItem {
  const PhotoItem({
    required super.id,
    required super.label,
    required this.preset,
    required this.maxBytes,
    super.hint,
    this.width,
    this.height,
    this.minPx,
    this.maxPx,
    this.backgroundHint = false,
  });

  final CropPreset preset;
  final int maxBytes;

  /// Exact output size; defaults to the preset at its DPI.
  final int? width;
  final int? height;

  /// Allowed range for each side, when the source publishes one.
  final int? minPx;
  final int? maxPx;

  /// Warn when the border doesn't look plain (visa photos).
  final bool backgroundHint;

  int get outputWidth => width ?? preset.pixelWidth;
  int get outputHeight => height ?? preset.pixelHeight;
}

/// A cleaned-up signature on white.
final class SignatureItem extends KitItem {
  const SignatureItem({
    required super.id,
    required super.label,
    required this.width,
    required this.height,
    required this.maxBytes,
    super.hint,
  });

  final int width;
  final int height;
  final int maxBytes;
}

/// Photos and/or PDFs combined into one PDF under a size limit.
final class DocumentItem extends KitItem {
  const DocumentItem({
    required super.id,
    required super.label,
    required this.maxBytes,
    super.hint,
    this.pageSize = PdfPageSize.a4,
    this.maxPages,
  });

  final int maxBytes;
  final PdfPageSize pageSize;
  final int? maxPages;
}

/// "50 KB", "2 MB".
String formatLimit(int bytes) {
  if (bytes >= 1024 * 1024 && bytes % (1024 * 1024) == 0) {
    return '${bytes ~/ (1024 * 1024)} MB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// Short constraint labels shown as chips on an item card.
List<String> constraintLabels(KitItem item) => switch (item) {
  PhotoItem(
    :final preset,
    :final outputWidth,
    :final outputHeight,
    :final maxBytes,
  ) =>
    [
      preset.sizeLabel,
      '$outputWidth×$outputHeight px',
      '≤ ${formatLimit(maxBytes)}',
      'JPG',
    ],
  SignatureItem(:final width, :final height, :final maxBytes) => [
    '$width×$height px',
    '≤ ${formatLimit(maxBytes)}',
    'JPG',
  ],
  DocumentItem(:final maxBytes, :final pageSize, :final maxPages) => [
    'PDF',
    '≤ ${formatLimit(maxBytes)}',
    if (pageSize != PdfPageSize.fit) pageSize.label,
    if (maxPages != null) 'Max $maxPages pages',
  ],
};

/// One verified property of a finished output.
@immutable
class KitCheck {
  const KitCheck(this.label, {required this.passed});

  final String label;
  final bool passed;
}

/// A finished kit output, measured from its actual bytes.
@immutable
class KitOutput {
  const KitOutput({
    required this.bytes,
    required this.format,
    required this.checks,
    this.width,
    this.height,
    this.pageCount,
    this.backgroundWarning = false,
    this.compressedPdf = false,
  });

  final Uint8List bytes;
  final DocumentFormat format;
  final List<KitCheck> checks;
  final int? width;
  final int? height;
  final int? pageCount;

  /// The photo border doesn't look like a plain background (hint only).
  final bool backgroundWarning;

  /// Pages were re-rendered as images to meet the size limit.
  final bool compressedPdf;

  bool get allPassed => checks.every((c) => c.passed);
}
