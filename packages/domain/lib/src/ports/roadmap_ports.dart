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

/// Optional session state an [AppLock] may also implement. Kept separate so
/// existing [AppLock] implementations and fakes keep compiling; callers use
/// the [AppLockSessionX] extension, which answers "no" for locks that don't
/// implement it.
abstract interface class AppLockSession {
  /// How recent an unlock must be to satisfy a nested gate.
  static const defaultRecentWindow = Duration(seconds: 5);

  /// True while a system prompt is on screen (from any caller).
  bool get isAuthenticating;

  /// True when the last successful authentication finished less than
  /// [within] ago. Lets a nested gate (authenticator reveal, folder lock)
  /// skip a second prompt right after App Lock unlocked the app.
  bool recentlyAuthenticated({Duration within = defaultRecentWindow});
}

/// Safe accessors for [AppLockSession] on any [AppLock].
extension AppLockSessionX on AppLock {
  bool get isAuthenticating => switch (this) {
    final AppLockSession s => s.isAuthenticating,
    _ => false,
  };

  bool recentlyAuthenticated({
    Duration within = AppLockSession.defaultRecentWindow,
  }) => switch (this) {
    final AppLockSession s => s.recentlyAuthenticated(within: within),
    _ => false,
  };
}

// LibraryArchiver (full backup) moved to ports/backup.dart.

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

  /// Transparent mode (PRD 3.3): paper becomes fully transparent, alpha
  /// follows ink darkness, and the result is tightly cropped to the ink.
  /// Returns a PNG no larger than [maxDimension] on its longest edge.
  /// `Err(documentNotDetected)` when no ink is found.
  Future<Result<EncodedImage>> extractTransparent(
    Uint8List photo, {
    int maxDimension = 1200,
  });
}
