import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// Stable conversion identifiers (used in routes and requests).
abstract final class ConversionIds {
  static const imagesToPdf = 'images-to-pdf';
  static const pdfToJpg = 'pdf-to-jpg';
  static const pdfToPng = 'pdf-to-png';
  static const pdfToTxt = 'pdf-to-txt';
  static const pdfToDocx = 'pdf-to-docx';
  static const imageToTxt = 'image-to-txt';
  static const imageToDocx = 'image-to-docx';
  static const imagesToDocx = 'images-to-docx';
  static const txtToPdf = 'txt-to-pdf';
  static const mdToPdf = 'md-to-pdf';
  static const csvToPdf = 'csv-to-pdf';
  static const htmlToTxt = 'html-to-txt';
  static const htmlToPdf = 'html-to-pdf';
  static const txtToDocx = 'txt-to-docx';
  static const mdToDocx = 'md-to-docx';
  static const csvToXlsx = 'csv-to-xlsx';
  static const xlsxToCsv = 'xlsx-to-csv';
  static const xlsxToPdf = 'xlsx-to-pdf';
  static const docxToTxt = 'docx-to-txt';
  static const docxToPdf = 'docx-to-pdf';
  static const pptxToTxt = 'pptx-to-txt';
  static const pptxToPdf = 'pptx-to-pdf';
  static const jpgToPng = 'jpg-to-png';
  static const pngToJpg = 'png-to-jpg';
}

/// Option keys understood by [ConversionRequest.options].
abstract final class ConversionOptions {
  /// [PdfPageSize] name for PDF outputs. Default `a4`.
  static const pageSize = 'pageSize';

  /// [QualityPreset] name for images→PDF. Default `balanced`.
  static const quality = 'quality';

  /// [OcrScript] name used for OCR steps. Default `latin`.
  static const ocrScript = 'ocrScript';

  /// `int` 1–100 JPEG quality for JPG outputs. Default 88.
  static const jpegQuality = 'jpegQuality';

  /// `int` pixel width for PDF page renders. Default 1654 (A4 @ 200 dpi).
  static const renderWidth = 'renderWidth';

  /// `bool` for XLSX→CSV: one CSV per sheet instead of the first sheet only.
  static const allSheets = 'allSheets';
}

/// Formats the `image` decoder handles. HEIC is deliberately absent.
const Set<DocumentFormat> decodableImages = {
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.gif,
  DocumentFormat.bmp,
  DocumentFormat.tiff,
};

const _heicNote =
    'HEIC photos are not supported yet — export them as JPG first.';
const _ocrNote =
    'Text is recognized on-device; accuracy depends on image quality and '
    'the selected language. Review before sharing.';
const _layoutLost =
    'Fonts, colors, columns, tables and images are not carried over.';

/// The full, declared registry (PRD FR-09). Nothing converts unless listed.
abstract final class ConversionSpecs {
  static const imagesToPdf = ConversionSpec(
    id: ConversionIds.imagesToPdf,
    title: 'Images to PDF',
    inputs: decodableImages,
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.visual,
    category: ConversionCategory.toPdf,
    multipleInputs: true,
    limitations: [
      'Each image becomes one page; text in photos is not searchable.',
      _heicNote,
    ],
  );

  static const pdfToJpg = ConversionSpec(
    id: ConversionIds.pdfToJpg,
    title: 'PDF to JPG',
    inputs: {DocumentFormat.pdf},
    output: DocumentFormat.jpeg,
    fidelity: FidelityClass.visual,
    category: ConversionCategory.fromPdf,
    limitations: [
      'Creates one image per page.',
      'Text in the images cannot be selected or edited.',
    ],
  );

  static const pdfToPng = ConversionSpec(
    id: ConversionIds.pdfToPng,
    title: 'PDF to PNG',
    inputs: {DocumentFormat.pdf},
    output: DocumentFormat.png,
    fidelity: FidelityClass.visual,
    category: ConversionCategory.fromPdf,
    limitations: [
      'Creates one image per page; PNG files are larger than JPG.',
      'Text in the images cannot be selected or edited.',
    ],
  );

  static const pdfToTxt = ConversionSpec(
    id: ConversionIds.pdfToTxt,
    title: 'PDF to text',
    inputs: {DocumentFormat.pdf},
    output: DocumentFormat.txt,
    fidelity: FidelityClass.content,
    category: ConversionCategory.fromPdf,
    limitations: [
      'Reading order may differ for multi-column pages.',
      'Scanned pages are read with OCR when available. $_ocrNote',
    ],
  );

  static const pdfToDocx = ConversionSpec(
    id: ConversionIds.pdfToDocx,
    title: 'PDF to Word (text)',
    inputs: {DocumentFormat.pdf},
    output: DocumentFormat.docx,
    fidelity: FidelityClass.content,
    category: ConversionCategory.fromPdf,
    limitations: [
      'Creates an editable document with the text of each page. $_layoutLost',
      'Scanned pages are read with OCR when available. $_ocrNote',
    ],
  );

  static const imageToTxt = ConversionSpec(
    id: ConversionIds.imageToTxt,
    title: 'Image to text (OCR)',
    inputs: decodableImages,
    output: DocumentFormat.txt,
    fidelity: FidelityClass.content,
    category: ConversionCategory.images,
    limitations: [_ocrNote, 'Handwriting is not reliably recognized.'],
  );

  static const imageToDocx = ConversionSpec(
    id: ConversionIds.imageToDocx,
    title: 'Image to Word (OCR)',
    inputs: decodableImages,
    output: DocumentFormat.docx,
    fidelity: FidelityClass.content,
    category: ConversionCategory.images,
    limitations: [_ocrNote, 'Only the recognized text is kept. $_layoutLost'],
  );

  static const imagesToDocx = ConversionSpec(
    id: ConversionIds.imagesToDocx,
    title: 'Images to Word (as pictures)',
    inputs: decodableImages,
    output: DocumentFormat.docx,
    fidelity: FidelityClass.visual,
    category: ConversionCategory.images,
    multipleInputs: true,
    limitations: [
      'Images are placed as pictures, one per page — the text is NOT editable.',
      'Use "Image to Word (OCR)" for editable text.',
      _heicNote,
    ],
  );

  static const txtToPdf = ConversionSpec(
    id: ConversionIds.txtToPdf,
    title: 'Text to PDF',
    inputs: {DocumentFormat.txt},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Uses a standard font; some non-Latin scripts may not display.',
    ],
  );

  static const mdToPdf = ConversionSpec(
    id: ConversionIds.mdToPdf,
    title: 'Markdown to PDF',
    inputs: {DocumentFormat.markdown},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Headings and lists become plain structured text.',
      'Styling, links and images are simplified.',
    ],
  );

  static const csvToPdf = ConversionSpec(
    id: ConversionIds.csvToPdf,
    title: 'CSV to PDF',
    inputs: {DocumentFormat.csv},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Printed as an aligned monospace table; long cells are shortened.',
      'Very wide tables may wrap.',
    ],
  );

  static const htmlToTxt = ConversionSpec(
    id: ConversionIds.htmlToTxt,
    title: 'HTML to text',
    inputs: {DocumentFormat.html},
    output: DocumentFormat.txt,
    fidelity: FidelityClass.content,
    category: ConversionCategory.text,
    limitations: ['Scripts, styles and images are removed. $_layoutLost'],
  );

  static const htmlToPdf = ConversionSpec(
    id: ConversionIds.htmlToPdf,
    title: 'HTML to PDF (text)',
    inputs: {DocumentFormat.html},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Only the page text is kept — this is not a web-page screenshot.',
      _layoutLost,
    ],
  );

  static const txtToDocx = ConversionSpec(
    id: ConversionIds.txtToDocx,
    title: 'Text to Word',
    inputs: {DocumentFormat.txt},
    output: DocumentFormat.docx,
    fidelity: FidelityClass.content,
    category: ConversionCategory.text,
    limitations: ['Each line break becomes a paragraph; no formatting.'],
  );

  static const mdToDocx = ConversionSpec(
    id: ConversionIds.mdToDocx,
    title: 'Markdown to Word',
    inputs: {DocumentFormat.markdown},
    output: DocumentFormat.docx,
    fidelity: FidelityClass.reconstructed,
    category: ConversionCategory.text,
    limitations: [
      'Headings and bullet lists are mapped to Word styles.',
      'Tables, links and images are simplified to text.',
    ],
  );

  static const csvToXlsx = ConversionSpec(
    id: ConversionIds.csvToXlsx,
    title: 'CSV to Excel',
    inputs: {DocumentFormat.csv},
    output: DocumentFormat.xlsx,
    fidelity: FidelityClass.native,
    category: ConversionCategory.text,
    limitations: [
      'Plain numbers are stored as numbers; everything else as text.',
    ],
  );

  static const xlsxToCsv = ConversionSpec(
    id: ConversionIds.xlsxToCsv,
    title: 'Excel to CSV',
    inputs: {DocumentFormat.xlsx},
    output: DocumentFormat.csv,
    fidelity: FidelityClass.content,
    category: ConversionCategory.text,
    limitations: [
      'Exports cell values only; formulas show their last saved result.',
      'Date-formatted cells are written as yyyy-MM-dd. Formatting and charts are lost.',
    ],
  );

  static const xlsxToPdf = ConversionSpec(
    id: ConversionIds.xlsxToPdf,
    title: 'Excel to PDF (values)',
    inputs: {DocumentFormat.xlsx},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Prints cell values of the first sheet as a plain table.',
      'Formatting, charts, merged cells and print areas are not kept.',
    ],
  );

  static const docxToTxt = ConversionSpec(
    id: ConversionIds.docxToTxt,
    title: 'Word to text',
    inputs: {DocumentFormat.docx},
    output: DocumentFormat.txt,
    fidelity: FidelityClass.content,
    category: ConversionCategory.text,
    limitations: [_layoutLost],
  );

  static const docxToPdf = ConversionSpec(
    id: ConversionIds.docxToPdf,
    title: 'Word to PDF (text only)',
    inputs: {DocumentFormat.docx},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'Only the text is converted; manual page breaks are kept. $_layoutLost',
      'For an exact copy, export to PDF from a word processor.',
    ],
  );

  static const pptxToTxt = ConversionSpec(
    id: ConversionIds.pptxToTxt,
    title: 'PowerPoint to text',
    inputs: {DocumentFormat.pptx},
    output: DocumentFormat.txt,
    fidelity: FidelityClass.content,
    category: ConversionCategory.text,
    limitations: ['Slide text only, in slide order. Speaker notes excluded.'],
  );

  static const pptxToPdf = ConversionSpec(
    id: ConversionIds.pptxToPdf,
    title: 'PowerPoint to PDF (text)',
    inputs: {DocumentFormat.pptx},
    output: DocumentFormat.pdf,
    fidelity: FidelityClass.content,
    category: ConversionCategory.toPdf,
    limitations: [
      'One page of text per slide, headed "Slide N" — not slide images.',
      _layoutLost,
    ],
  );

  static const jpgToPng = ConversionSpec(
    id: ConversionIds.jpgToPng,
    title: 'JPG to PNG',
    inputs: {DocumentFormat.jpeg},
    output: DocumentFormat.png,
    fidelity: FidelityClass.native,
    category: ConversionCategory.images,
    limitations: [
      'Converting does not restore detail lost to JPG compression.',
    ],
  );

  static const pngToJpg = ConversionSpec(
    id: ConversionIds.pngToJpg,
    title: 'PNG to JPG',
    inputs: {DocumentFormat.png},
    output: DocumentFormat.jpeg,
    fidelity: FidelityClass.native,
    category: ConversionCategory.images,
    limitations: [
      'Transparency becomes solid; JPG compression is slightly lossy.',
    ],
  );

  static const List<ConversionSpec> all = [
    imagesToPdf,
    txtToPdf,
    mdToPdf,
    csvToPdf,
    htmlToPdf,
    docxToPdf,
    xlsxToPdf,
    pptxToPdf,
    pdfToJpg,
    pdfToPng,
    pdfToTxt,
    pdfToDocx,
    imageToTxt,
    imageToDocx,
    imagesToDocx,
    jpgToPng,
    pngToJpg,
    htmlToTxt,
    txtToDocx,
    mdToDocx,
    csvToXlsx,
    xlsxToCsv,
    docxToTxt,
    pptxToTxt,
  ];

  /// Specs that cannot run without an OCR engine.
  static const Set<String> requiresOcr = {
    ConversionIds.imageToTxt,
    ConversionIds.imageToDocx,
  };
}
