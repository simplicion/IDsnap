/// PDF engine: writing with `package:pdf`, reading/rendering/manipulation with
/// `pdfrx` (PDFium). Implements the domain `PdfEngine` port.
library;

export 'src/init.dart';
export 'src/pdf_engine_impl.dart';
export 'src/pdf_writer.dart' show buildImagePdf, buildTextPdf;
export 'src/protect/pdf_protection_engine.dart'
    show PdfProtectionEngine, validatePdfPassword;
export 'src/protect/zip_archive_codec.dart' show ZipArchiveCodec;
export 'src/sheet_pdf_builder.dart';
