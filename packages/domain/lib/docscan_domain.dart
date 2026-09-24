/// DocScan domain: entities, ports (interfaces implemented by engines and the
/// data layer) and use cases. Pure Dart — no Flutter, no dart:io.
library;

export 'src/entities/conversion.dart';
export 'src/entities/crop_preset.dart';
export 'src/entities/document.dart';
export 'src/entities/geometry.dart';
export 'src/entities/ocr.dart';
export 'src/entities/options.dart';
export 'src/entities/scan.dart';
export 'src/entities/settings.dart';
export 'src/entities/vault.dart';
export 'src/ports/document_repository.dart';
export 'src/ports/document_scanner.dart';
export 'src/ports/face_locator.dart';
export 'src/ports/file_store.dart';
export 'src/ports/image_processor.dart';
export 'src/ports/pdf_engine.dart';
export 'src/ports/platform_io.dart';
export 'src/ports/roadmap_ports.dart';
export 'src/ports/text_recognizer.dart';
export 'src/usecases/auto_frame_photo.dart';
export 'src/usecases/commit_output.dart';
export 'src/usecases/save_scan_as_pdf.dart';
