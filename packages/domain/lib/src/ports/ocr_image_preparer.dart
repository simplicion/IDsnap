import 'package:docscan_core/docscan_core.dart';
import 'package:meta/meta.dart';

/// An image file ready for OCR: EXIF orientation applied and size bounded,
/// so recognizer boxes normalize against the true pixel size.
@immutable
class OcrImage {
  const OcrImage({
    required this.path,
    required this.width,
    required this.height,
    this.temporary = false,
  });

  final String path;
  final int width;
  final int height;

  /// Owned by the preparer; must be released with [OcrImagePreparer.release].
  final bool temporary;

  int get longestEdge => width > height ? width : height;
}

/// A derived image for another recognition attempt.
@immutable
class OcrVariant {
  const OcrVariant({
    this.quarterTurns = 0,
    this.scale = 1,
    this.enhance = false,
  });

  /// Clockwise quarter turns applied to the base image.
  final int quarterTurns;

  /// Resize factor relative to the base image (e.g. 2 to double small text).
  final double scale;

  /// Normalize illumination and stretch contrast (photos of paper).
  final bool enhance;
}

/// Prepares images for text recognition. Implementations do pixel work off
/// the UI isolate and only pass plain data (bytes, paths, sizes) around.
abstract interface class OcrImagePreparer {
  /// Applies EXIF orientation and scales the image into the recognizer's
  /// sweet spot (huge photos are downscaled). The result is a new temp file.
  Future<Result<OcrImage>> normalize(String imagePath);

  /// Derives [variant] from a [normalize]d [base]. New temp file.
  Future<Result<OcrImage>> variant(OcrImage base, OcrVariant variant);

  /// Deletes [image] when it is temporary. Never throws.
  Future<void> release(OcrImage image);
}
