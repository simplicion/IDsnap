import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/ocr.dart';

/// On-device OCR. Must not send images anywhere.
abstract interface class TextRecognizer {
  Future<EngineCapability> capability(OcrScript script);

  /// Recognizes text in the image at [imagePath].
  Future<Result<OcrResult>> recognize(String imagePath, OcrScript script);
}
