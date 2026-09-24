/// On-device conversion registry and engine. Pure Dart; composes the domain
/// ports (FileStore, PdfEngine, ImageProcessor, TextRecognizer).
library;

export 'src/conversion_engine.dart';
export 'src/ooxml/docx_reader.dart'
    show DocxParagraph, docxToPlainText, readDocx;
export 'src/ooxml/docx_writer.dart' show DocxBuilder, DocxImageType, DocxStyle;
export 'src/ooxml/pptx_reader.dart' show pptxToPlainText, readPptxSlides;
export 'src/ooxml/xlsx.dart'
    show
        XlsxNumberKind,
        XlsxSheet,
        classifyNumberFormat,
        columnIndex,
        columnName,
        formatExcelSerial,
        readXlsx,
        writeXlsx;
export 'src/specs.dart';
export 'src/text/csv.dart';
export 'src/text/html_text.dart';
export 'src/text/markdown_text.dart';
