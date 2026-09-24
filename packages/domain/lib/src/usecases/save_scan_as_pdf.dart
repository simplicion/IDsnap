import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/conversion.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/entities/options.dart';
import 'package:docscan_domain/src/entities/scan.dart';
import 'package:docscan_domain/src/ports/file_store.dart';
import 'package:docscan_domain/src/ports/image_processor.dart';
import 'package:docscan_domain/src/ports/pdf_engine.dart';
import 'package:docscan_domain/src/ports/text_recognizer.dart';
import 'package:docscan_domain/src/usecases/commit_output.dart';

/// Scan → PDF (PRD P0 core journey): render every page with its edits,
/// optionally OCR it for a searchable text layer, build the PDF, then commit
/// through [CommitOutput] so success is only reported for a validated file.
class SaveScanAsPdf {
  SaveScanAsPdf({
    required this.files,
    required this.images,
    required this.pdf,
    required this.commit,
    this.ocr,
  });

  final FileStore files;
  final ImageProcessor images;
  final PdfEngine pdf;
  final CommitOutput commit;
  final TextRecognizer? ocr;

  Future<Result<Document>> call(
    ScanDraft draft, {
    required String name,
    QualityPreset preset = QualityPreset.balanced,
    PdfBuildOptions options = const PdfBuildOptions(),
    OcrScript? searchableScript,
    String? folderId,
    void Function(double progress)? onProgress,
  }) async {
    if (draft.pages.isEmpty) {
      return const Err(
        AppFailure(FailureCode.documentNotDetected, detail: 'No pages'),
      );
    }
    final total = draft.pages.length;
    // Rendering is ~70% of the work, OCR ~20%, PDF encode + commit ~10%.
    final rendered = <Uint8List>[];
    final layers = <OcrResult?>[];
    final tempImages = <String>[];

    try {
      for (var i = 0; i < total; i++) {
        final page = draft.pages[i];
        final Uint8List original;
        try {
          original = await files.read(page.originalPath);
        } on Object catch (e, st) {
          return Err(
            AppFailure(
              FailureCode.notFound,
              detail: 'Page ${i + 1}',
              cause: e,
              stackTrace: st,
            ),
          );
        }
        final out = await images.renderPage(
          original,
          page.edits,
          preset: preset,
        );
        if (out case Err(:final failure)) {
          return Err(
            AppFailure(
              failure.code,
              detail: 'Page ${i + 1}',
              cause: failure.cause,
            ),
          );
        }
        final jpeg = out.valueOrNull!;
        rendered.add(jpeg);

        OcrResult? layer;
        final recognizer = ocr;
        if (searchableScript != null && recognizer != null) {
          final tmp = await files.writeTemp(jpeg, 'jpg');
          tempImages.add(tmp);
          layer = (await recognizer.recognize(
            tmp,
            searchableScript,
          )).valueOrNull;
        }
        layers.add(layer);
        onProgress?.call((i + 1) / total * 0.9);
      }

      final bytes = await pdf.fromImages(
        rendered,
        options,
        textLayers: searchableScript == null ? null : layers,
      );
      if (bytes case Err(:final failure)) return Err(failure);
      final result = await commit(
        OutputFile(
          bytes: bytes.valueOrNull!,
          format: DocumentFormat.pdf,
          suggestedName: name,
          expectedPages: total,
        ),
        folderId: folderId,
      );
      onProgress?.call(1);
      return result;
    } finally {
      for (final t in tempImages) {
        await files.delete(t);
      }
    }
  }
}
