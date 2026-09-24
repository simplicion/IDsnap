import 'package:docscan_core/docscan_core.dart';

/// Platform document camera (ML Kit on Android, VisionKit on iOS). Returns
/// absolute paths of captured page images, already edge-detected and cropped
/// by the platform where supported.
abstract interface class DocumentScanner {
  Future<EngineCapability> capability();

  /// `Err(captureCancelled)` when the user backs out.
  Future<Result<List<String>>> scan({int maxPages = 50});
}
