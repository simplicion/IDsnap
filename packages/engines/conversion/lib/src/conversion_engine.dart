import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_conversion/src/ooxml/docx_reader.dart';
import 'package:engine_conversion/src/ooxml/docx_writer.dart';
import 'package:engine_conversion/src/ooxml/pptx_reader.dart';
import 'package:engine_conversion/src/ooxml/xlsx.dart';
import 'package:engine_conversion/src/specs.dart';
import 'package:engine_conversion/src/text/csv.dart';
import 'package:engine_conversion/src/text/html_text.dart';
import 'package:engine_conversion/src/text/markdown_text.dart';

typedef _Progress = void Function(double progress);

/// Form feed: `PdfEngine.fromText` starts a new page at this character.
const pageBreakChar = '\f';

/// Runs every conversion declared in [ConversionSpecs] on-device, composing
/// the domain ports. Inputs are read, never modified; outputs are returned
/// uncommitted so the caller commits them through `CommitOutput`.
class ConversionEngineImpl implements ConversionEngine {
  ConversionEngineImpl({
    required this.files,
    required this.pdf,
    required this.images,
    this.ocr,
    RedactedLogger? logger,
  }) : _log = logger ?? RedactedLogger('conversion');

  final FileStore files;
  final PdfEngine pdf;
  final ImageProcessor images;

  /// Optional: without it, OCR-only specs are hidden and scanned PDF pages
  /// yield empty text.
  final TextRecognizer? ocr;
  final RedactedLogger _log;

  @override
  List<ConversionSpec> get specs => [
    for (final s in ConversionSpecs.all)
      if (ocr != null || !ConversionSpecs.requiresOcr.contains(s.id)) s,
  ];

  @override
  ConversionSpec? spec(String id) {
    for (final s in specs) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<Result<List<OutputFile>>> convert(
    ConversionRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final spec = this.spec(request.specId);
    if (spec == null) {
      return const Err(AppFailure(FailureCode.unsupportedFormat));
    }
    final inputs = request.inputs;
    if (inputs.isEmpty || (!spec.multipleInputs && inputs.length != 1)) {
      return const Err(
        AppFailure(
          FailureCode.unsupportedFormat,
          detail: 'Wrong number of files',
        ),
      );
    }
    for (final input in inputs) {
      if (!spec.inputs.contains(input.format)) {
        return Err(
          AppFailure(
            FailureCode.unsupportedFormat,
            detail: '${input.format.label} is not supported here',
          ),
        );
      }
    }
    final stopwatch = Stopwatch()..start();
    final result = await guard(
      () => _run(spec, request, onProgress ?? (_) {}),
      code: FailureCode.conversionFailed,
    );
    _log.info('convert', {
      'spec': spec.id,
      'inputs': inputs.length,
      'ok': result.isOk,
      'code': result.failureOrNull?.code,
      'ms': stopwatch.elapsedMilliseconds,
    });
    onProgress?.call(1);
    return result;
  }

  Future<List<OutputFile>> _run(
    ConversionSpec spec,
    ConversionRequest req,
    _Progress progress,
  ) async {
    final input = req.inputs.first;
    final name = input.name;
    final opts = req.options;
    final pageSize = _enumOption(
      PdfPageSize.values,
      opts[ConversionOptions.pageSize],
      PdfPageSize.a4,
    );
    final script = _enumOption(
      OcrScript.values,
      opts[ConversionOptions.ocrScript],
      OcrScript.latin,
    );

    switch (spec.id) {
      case ConversionIds.imagesToPdf:
        final preset = _enumOption(
          QualityPreset.values,
          opts[ConversionOptions.quality],
          QualityPreset.balanced,
        );
        final pages = <Uint8List>[];
        for (var i = 0; i < req.inputs.length; i++) {
          final bytes = await files.read(req.inputs[i].path);
          pages.add(
            _unwrap(
              await images.renderPage(
                bytes,
                const PageEdits(filter: EnhancementFilter.original),
                preset: preset,
              ),
            ),
          );
          progress((i + 1) / req.inputs.length * 0.9);
        }
        final out = _unwrap(
          await pdf.fromImages(pages, PdfBuildOptions(pageSize: pageSize)),
        );
        return [
          OutputFile(
            bytes: out,
            format: DocumentFormat.pdf,
            suggestedName: name,
            expectedPages: pages.length,
          ),
        ];

      case ConversionIds.pdfToJpg || ConversionIds.pdfToPng:
        final jpg = spec.id == ConversionIds.pdfToJpg;
        final width = _intOption(
          opts[ConversionOptions.renderWidth],
          1654,
          200,
          5000,
        );
        final quality = _intOption(
          opts[ConversionOptions.jpegQuality],
          88,
          1,
          100,
        );
        final count = _unwrap(await pdf.pageCount(input.path));
        final outputs = <OutputFile>[];
        for (var i = 0; i < count; i++) {
          final png = _unwrap(
            await pdf.renderPage(input.path, i, targetWidth: width),
          );
          final bytes = jpg
              ? Uint8List.fromList(
                  _unwrap(
                    await images.compress(
                      png,
                      ImageCompressionOptions(quality: quality),
                    ),
                  ).bytes,
                )
              : png;
          outputs.add(
            OutputFile(
              bytes: bytes,
              format: jpg ? DocumentFormat.jpeg : DocumentFormat.png,
              suggestedName: count == 1 ? name : '$name - page ${i + 1}',
            ),
          );
          progress((i + 1) / count);
        }
        return outputs;

      case ConversionIds.pdfToTxt:
        final pages = await _pdfPageTexts(input.path, script, progress);
        final text = [
          for (var i = 0; i < pages.length; i++)
            if (pages.length == 1)
              pages[i]
            else
              '--- Page ${i + 1} ---\n${pages[i]}',
        ].join('\n\n');
        return [_text(text, DocumentFormat.txt, name)];

      case ConversionIds.pdfToDocx:
        final pages = await _pdfPageTexts(input.path, script, progress);
        final docx = DocxBuilder();
        for (var i = 0; i < pages.length; i++) {
          if (i > 0) docx.pageBreak();
          final paras = pages[i].split(RegExp(r'\n\s*\n'));
          for (final p in paras) {
            if (p.trim().isNotEmpty) docx.paragraph(p.trim());
          }
          if (pages[i].trim().isEmpty) docx.paragraph('');
        }
        return [_bytes(docx.build(), DocumentFormat.docx, name)];

      case ConversionIds.imageToTxt:
        final result = await _ocrImage(input.path, script);
        progress(0.9);
        return [_text(result.text, DocumentFormat.txt, name)];

      case ConversionIds.imageToDocx:
        final result = await _ocrImage(input.path, script);
        progress(0.9);
        final docx = DocxBuilder();
        for (final block in result.blocks) {
          docx.paragraph(block.text);
        }
        if (docx.isEmpty) docx.paragraph('');
        return [_bytes(docx.build(), DocumentFormat.docx, name)];

      case ConversionIds.imagesToDocx:
        final docx = DocxBuilder();
        for (var i = 0; i < req.inputs.length; i++) {
          final raw = await files.read(req.inputs[i].path);
          final jpeg = _unwrap(
            await images.compress(
              raw,
              const ImageCompressionOptions(quality: 88, maxDimension: 2400),
            ),
          );
          if (i > 0) docx.pageBreak();
          docx.image(
            Uint8List.fromList(jpeg.bytes),
            widthPx: jpeg.width,
            heightPx: jpeg.height,
          );
          progress((i + 1) / req.inputs.length * 0.9);
        }
        return [_bytes(docx.build(), DocumentFormat.docx, name)];

      case ConversionIds.txtToPdf:
        final text = await files.readText(input.path);
        return [await _pdfFromText(text, name, pageSize)];

      case ConversionIds.mdToPdf:
        final text = markdownToPlainText(
          await files.readText(input.path),
          bullet: '-',
        );
        return [await _pdfFromText(text, name, pageSize)];

      case ConversionIds.csvToPdf:
        final table = csvToTable(parseCsv(await files.readText(input.path)));
        return [await _pdfFromText(table, name, pageSize, monospace: true)];

      case ConversionIds.htmlToTxt:
        final text = htmlToText(await files.readText(input.path));
        return [_text(text, DocumentFormat.txt, name)];

      case ConversionIds.htmlToPdf:
        final text = htmlToText(await files.readText(input.path));
        return [await _pdfFromText(text, name, pageSize)];

      case ConversionIds.txtToDocx:
        final text = await files.readText(input.path);
        final docx = DocxBuilder();
        text.replaceAll('\r\n', '\n').split('\n').forEach(docx.paragraph);
        return [_bytes(docx.build(), DocumentFormat.docx, name)];

      case ConversionIds.mdToDocx:
        final docx = DocxBuilder();
        for (final b in parseMarkdown(await files.readText(input.path))) {
          switch (b.kind) {
            case MdBlockKind.heading:
              docx.heading(b.text, level: b.level);
            case MdBlockKind.bullet:
              docx.bullet(b.text);
            case MdBlockKind.numbered:
              docx.paragraph('${b.level}. ${b.text}');
            case MdBlockKind.quote:
              docx.paragraph(b.text, style: DocxStyle.quote);
            case MdBlockKind.code:
              docx.paragraph(b.text, style: DocxStyle.code);
            case MdBlockKind.rule:
              docx.paragraph('');
            case MdBlockKind.paragraph:
              docx.paragraph(b.text);
          }
        }
        if (docx.isEmpty) docx.paragraph('');
        return [_bytes(docx.build(), DocumentFormat.docx, name)];

      case ConversionIds.csvToXlsx:
        final rows = parseCsv(await files.readText(input.path));
        return [
          _bytes(writeXlsx(rows, sheetName: name), DocumentFormat.xlsx, name),
        ];

      case ConversionIds.xlsxToCsv:
        final sheets = readXlsx(await files.read(input.path));
        if (sheets.isEmpty) throw const AppFailure(FailureCode.corruptFile);
        final all = opts[ConversionOptions.allSheets] == true;
        final chosen = all ? sheets : [sheets.first];
        return [
          for (final s in chosen)
            _text(
              writeCsv(s.rows),
              DocumentFormat.csv,
              chosen.length == 1 ? name : '$name - ${s.name}',
            ),
        ];

      case ConversionIds.xlsxToPdf:
        final sheets = readXlsx(await files.read(input.path));
        if (sheets.isEmpty) throw const AppFailure(FailureCode.corruptFile);
        final table = csvToTable(sheets.first.rows);
        return [
          await _pdfFromText(
            table.isEmpty ? '(empty sheet)' : table,
            name,
            pageSize,
            monospace: true,
          ),
        ];

      case ConversionIds.docxToTxt:
        final text = docxToPlainText(readDocx(await files.read(input.path)));
        return [_text(text, DocumentFormat.txt, name)];

      case ConversionIds.docxToPdf:
        final paras = readDocx(await files.read(input.path));
        final text = docxToPlainText(
          paras,
          pageBreak: pageBreakChar,
        ).replaceAll('• ', '- ');
        return [await _pdfFromText(text.isEmpty ? ' ' : text, name, pageSize)];

      case ConversionIds.pptxToTxt:
        final text = pptxToPlainText(
          readPptxSlides(await files.read(input.path)),
        );
        return [_text(text, DocumentFormat.txt, name)];

      case ConversionIds.pptxToPdf:
        final slides = readPptxSlides(await files.read(input.path));
        if (slides.isEmpty) throw const AppFailure(FailureCode.corruptFile);
        return [
          await _pdfFromText(
            pptxToPlainText(slides, separator: pageBreakChar),
            name,
            pageSize,
          ),
        ];

      case ConversionIds.jpgToPng || ConversionIds.pngToJpg:
        final toPng = spec.id == ConversionIds.jpgToPng;
        final out = _unwrap(
          await images.compress(
            await files.read(input.path),
            ImageCompressionOptions(
              quality: _intOption(
                opts[ConversionOptions.jpegQuality],
                92,
                1,
                100,
              ),
              format: toPng ? ImageOutputFormat.png : ImageOutputFormat.jpeg,
            ),
          ),
        );
        return [
          _bytes(
            Uint8List.fromList(out.bytes),
            toPng ? DocumentFormat.png : DocumentFormat.jpeg,
            name,
          ),
        ];
    }
    throw const AppFailure(FailureCode.unsupportedFormat);
  }

  /// Embedded text per page, with OCR for pages that have none.
  Future<List<String>> _pdfPageTexts(
    String path,
    OcrScript script,
    _Progress progress,
  ) async {
    final pages = List<String>.of(_unwrap(await pdf.extractText(path)));
    progress(0.3);
    final recognizer = ocr;
    if (recognizer != null) {
      final empty = [
        for (var i = 0; i < pages.length; i++)
          if (pages[i].trim().isEmpty) i,
      ];
      for (var k = 0; k < empty.length; k++) {
        final i = empty[k];
        final png = (await pdf.renderPage(
          path,
          i,
          targetWidth: 2000,
        )).valueOrNull;
        if (png == null) continue;
        final temp = await files.writeTemp(png, 'png');
        try {
          final result = await recognizer.recognize(temp, script);
          pages[i] = result.valueOrNull?.text ?? '';
        } finally {
          await files.delete(temp);
        }
        progress(0.3 + (k + 1) / empty.length * 0.6);
      }
    }
    return [for (final p in pages) p.trimRight()];
  }

  Future<OcrResult> _ocrImage(String path, OcrScript script) async {
    final recognizer = ocr;
    if (recognizer == null) {
      throw const AppFailure(FailureCode.modelUnavailable);
    }
    return _unwrap<OcrResult>(await recognizer.recognize(path, script));
  }

  Future<OutputFile> _pdfFromText(
    String text,
    String name,
    PdfPageSize pageSize, {
    bool monospace = false,
  }) async {
    final out = _unwrap(
      await pdf.fromText(
        text,
        TextPdfOptions(
          pageSize: pageSize == PdfPageSize.fit ? PdfPageSize.a4 : pageSize,
          monospace: monospace,
          fontSize: monospace ? 9 : 11,
        ),
      ),
    );
    return _bytes(out, DocumentFormat.pdf, name);
  }

  static OutputFile _text(String text, DocumentFormat format, String name) =>
      OutputFile(
        bytes: Uint8List.fromList(utf8.encode(text)),
        format: format,
        suggestedName: name,
      );

  static OutputFile _bytes(
    Uint8List bytes,
    DocumentFormat format,
    String name,
  ) => OutputFile(bytes: bytes, format: format, suggestedName: name);

  static T _unwrap<T>(Result<T> r) => switch (r) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  static T _enumOption<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) => raw is T ? raw : values.asNameMap()[raw] ?? fallback;

  static int _intOption(Object? raw, int fallback, int min, int max) {
    final v = raw is int ? raw : int.tryParse('$raw');
    return (v ?? fallback).clamp(min, max);
  }
}
