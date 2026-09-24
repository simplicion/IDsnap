import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/geometry.dart';

/// On-device face detection used to auto-frame passport/ID photos.
abstract interface class FaceLocator {
  Future<EngineCapability> capability();

  /// Bounding box of the most prominent face in normalized coordinates of
  /// the image at [imagePath] (EXIF orientation applied), or `null` when no
  /// face is found.
  Future<Result<NRect?>> locateLargestFace(String imagePath);
}
