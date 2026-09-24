import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:docscan_domain/src/entities/options.dart';
import 'package:docscan_domain/src/entities/scan.dart';

/// On-device image pipeline. Implementations must run heavy work off the UI
/// isolate and must never modify their input bytes.
abstract interface class ImageProcessor {
  /// Finds the page outline. Low confidence means "ask the user".
  Future<Result<DetectedQuad>> detectDocument(Uint8List imageBytes);

  /// Applies [edits] (perspective, rotation, filter, adjustments) and encodes
  /// a JPEG whose longest edge is at most [preset].maxDimension.
  Future<Result<Uint8List>> renderPage(
    Uint8List original,
    PageEdits edits, {
    QualityPreset preset = QualityPreset.balanced,
  });

  /// Small JPEG preview, EXIF orientation applied.
  Future<Result<Uint8List>> thumbnail(
    Uint8List imageBytes, {
    int maxDimension = 480,
  });

  /// Axis-aligned crop, optionally resized to an exact pixel size.
  Future<Result<EncodedImage>> crop(
    Uint8List imageBytes,
    NRect rect, {
    int? outputWidth,
    int? outputHeight,
    int quarterTurns = 0,
    ImageOutputFormat format = ImageOutputFormat.jpeg,
    int quality = 92,
  });

  Future<Result<EncodedImage>> compress(
    Uint8List imageBytes,
    ImageCompressionOptions options,
  );

  Future<Result<ImageDetails>> inspect(Uint8List imageBytes);
}
