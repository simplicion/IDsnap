/// On-device OCR engine (ML Kit Text Recognition). Implements the domain
/// `TextRecognizer` port and the `OcrImagePreparer` port (preprocessing via
/// the imaging engine's `ImageProcessor`).
library;

export 'src/imaging_ocr_preparer.dart';
export 'src/mlkit_text_recognizer.dart';
