import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/entities/options.dart';
import 'package:meta/meta.dart';

// Ports for roadmap features (docs/product/roadmap-vault-id-card.md). Kept
// separate from existing ports so no existing implementation or test fake
// has to change.

/// An image placed on a PDF page, in points from the top-left corner.
@immutable
class PlacedImage {
  const PlacedImage({
    required this.jpeg,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.border = true,
  });

  final Uint8List jpeg;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool border;
}

/// Builds single-page "sheet" PDFs with positioned images (ID card copies).
abstract interface class SheetPdfBuilder {
  /// [pageWidthPt]/[pageHeightPt] define the page; [watermark] draws a faint
  /// diagonal label across the page when non-null.
  Future<Result<Uint8List>> build(
    List<PlacedImage> images, {
    required double pageWidthPt,
    required double pageHeightPt,
    String? watermark,
  });
}

/// Device authentication gate (roadmap B2). This is an access gate, not
/// encryption — UI copy must not claim otherwise.
abstract interface class AppLock {
  Future<EngineCapability> capability();

  /// Shows the system biometric / device-credential prompt.
  /// `Ok(true)` = authenticated, `Ok(false)` = user cancelled.
  Future<Result<bool>> authenticate(String reason);
}

/// ZIP export/import of the whole library (roadmap B4).
abstract interface class LibraryArchiver {
  /// Writes a ZIP (category folders + manifest.json) and returns its bytes.
  Future<Result<Uint8List>> exportAll({void Function(double)? onProgress});

  /// Imports a ZIP produced by [exportAll]; returns documents added.
  Future<Result<int>> importArchive(
    String zipPath, {
    void Function(double)? onProgress,
  });
}

/// Local-only reminders for expiring documents (roadmap B4).
abstract interface class ReminderScheduler {
  Future<EngineCapability> capability();
  Future<Result<void>> requestPermission();

  /// Replaces any reminders for [document] (30 and 7 days before expiry).
  Future<Result<void>> scheduleExpiry(Document document);
  Future<Result<void>> cancel(String documentId);
}

/// Size-constrained signature cleanup for application kits (roadmap C).
abstract interface class SignatureProcessor {
  /// Removes background, tightens to the ink, fits [width]x[height] and
  /// compresses under [maxBytes] when possible.
  Future<Result<EncodedImage>> cleanSignature(
    Uint8List photo, {
    required int width,
    required int height,
    int? maxBytes,
  });
}
