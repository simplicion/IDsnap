import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/target_size.dart';
import 'package:feature_tools/src/kits/models.dart';

/// Scores how plain a photo's border is (0..1). Injected by the app so the
/// feature stays independent of the imaging engine.
typedef BackgroundAnalyzer = Future<double?> Function(Uint8List jpeg);

/// Below this uniformity the UI shows "Background may not be plain".
const plainBackgroundThreshold = 0.75;

/// Produces kit outputs from user inputs using domain ports only. Every
/// output is measured from its real bytes before it's shown as ready.
class KitPipeline {
  KitPipeline({
    required this.files,
    required this.images,
    required this.pdf,
    this.signatures,
    this.faces,
    this.analyzeBackground,
  });

  final FileStore files;
  final ImageProcessor images;
  final PdfEngine pdf;
  final SignatureProcessor? signatures;
  final FaceLocator? faces;
  final BackgroundAnalyzer? analyzeBackground;

  /// Auto-frames (portrait presets), crops to the exact size, then
  /// compresses under the byte limit.
  Future<Result<KitOutput>> photo(PhotoItem item, String path) async {
    final bytes = await _read(path);
    if (bytes == null) return const Err(AppFailure(FailureCode.notFound));
    final info = await images.inspect(bytes);
    if (info case Err(:final failure)) return Err(failure);
    final details = info.valueOrNull!;

    NRect? rect;
    final locator = faces;
    if (item.preset.isPortrait && locator != null) {
      final face = (await locator.locateLargestFace(path)).valueOrNull;
      if (face != null) {
        rect = autoFramePortrait(
          face: face,
          preset: item.preset,
          imageWidth: details.width,
          imageHeight: details.height,
        );
      }
    }
    rect ??= NRect.centeredWithAspect(
      item.outputWidth / item.outputHeight,
      details.width,
      details.height,
    );

    final cropped = await images.crop(
      bytes,
      rect,
      outputWidth: item.outputWidth,
      outputHeight: item.outputHeight,
      quality: 95,
    );
    if (cropped case Err(:final failure)) return Err(failure);
    final compressed = await images.compress(
      Uint8List.fromList(cropped.valueOrNull!.bytes),
      ImageCompressionOptions(quality: 92, targetBytes: item.maxBytes),
    );
    if (compressed case Err(:final failure)) return Err(failure);
    final out = Uint8List.fromList(compressed.valueOrNull!.bytes);

    final measured = (await images.inspect(out)).valueOrNull;
    final w = measured?.width;
    final h = measured?.height;
    final sizeOk =
        w == item.outputWidth &&
        h == item.outputHeight &&
        (item.minPx == null || math.min(w!, h!) >= item.minPx!) &&
        (item.maxPx == null || math.max(w!, h!) <= item.maxPx!);

    var backgroundWarning = false;
    final analyzer = analyzeBackground;
    if (item.backgroundHint && analyzer != null) {
      final score = await analyzer(out);
      backgroundWarning = score != null && score < plainBackgroundThreshold;
    }

    return Ok(
      KitOutput(
        bytes: out,
        format: DocumentFormat.jpeg,
        width: w,
        height: h,
        backgroundWarning: backgroundWarning,
        checks: [
          KitCheck(w == null ? 'Size unknown' : '$w × $h px', passed: sizeOk),
          KitCheck(
            '${formatLimit(out.length)} (limit ${formatLimit(item.maxBytes)})',
            passed: out.length <= item.maxBytes,
          ),
          KitCheck('JPG format', passed: measured != null),
        ],
      ),
    );
  }

  /// Background removal, ink trimming and size limit for signatures.
  Future<Result<KitOutput>> signature(SignatureItem item, String path) async {
    final processor = signatures;
    if (processor == null) {
      return const Err(AppFailure(FailureCode.modelUnavailable));
    }
    final bytes = await _read(path);
    if (bytes == null) return const Err(AppFailure(FailureCode.notFound));
    final r = await processor.cleanSignature(
      bytes,
      width: item.width,
      height: item.height,
      maxBytes: item.maxBytes,
    );
    if (r case Err(:final failure)) return Err(failure);
    final out = Uint8List.fromList(r.valueOrNull!.bytes);
    final measured = (await images.inspect(out)).valueOrNull;
    return Ok(
      KitOutput(
        bytes: out,
        format: DocumentFormat.jpeg,
        width: measured?.width,
        height: measured?.height,
        checks: [
          KitCheck(
            measured == null
                ? 'Size unknown'
                : '${measured.width} × ${measured.height} px',
            passed:
                measured?.width == item.width &&
                measured?.height == item.height,
          ),
          KitCheck(
            '${formatLimit(out.length)} (limit ${formatLimit(item.maxBytes)})',
            passed: out.length <= item.maxBytes,
          ),
          KitCheck('JPG format', passed: measured != null),
        ],
      ),
    );
  }

  /// Combines photos and PDFs (in the given order) into one PDF, then tries
  /// stronger compression until it fits. Refuses rather than producing an
  /// unreadable or oversized file.
  Future<Result<KitOutput>> document(
    DocumentItem item,
    List<({String path, DocumentFormat format})> inputs, {
    void Function(double progress)? onProgress,
  }) async {
    if (inputs.isEmpty) {
      return const Err(
        AppFailure(FailureCode.notFound, detail: 'Choose at least one file'),
      );
    }
    final temps = <String>[];
    try {
      // Group consecutive photos into one PDF chunk; keep PDFs as-is.
      final parts = <String>[];
      final pending = <Uint8List>[];
      Future<AppFailure?> flushImages() async {
        if (pending.isEmpty) return null;
        final built = await pdf.fromImages(
          List.of(pending),
          PdfBuildOptions(pageSize: item.pageSize),
        );
        pending.clear();
        if (built case Err(:final failure)) return failure;
        final temp = await files.writeTemp(built.valueOrNull!, 'pdf');
        temps.add(temp);
        parts.add(temp);
        return null;
      }

      for (final (i, input) in inputs.indexed) {
        if (input.format == DocumentFormat.pdf) {
          final failure = await flushImages();
          if (failure != null) return Err(failure);
          parts.add(input.path);
        } else if (input.format.isImage) {
          final bytes = await _read(input.path);
          if (bytes == null) return const Err(AppFailure(FailureCode.notFound));
          final page = await images.renderPage(
            bytes,
            const PageEdits(filter: EnhancementFilter.original),
          );
          if (page case Err(:final failure)) return Err(failure);
          pending.add(page.valueOrNull!);
        } else {
          return const Err(AppFailure(FailureCode.unsupportedFormat));
        }
        onProgress?.call((i + 1) / inputs.length * 0.5);
      }
      final failure = await flushImages();
      if (failure != null) return Err(failure);

      Uint8List combined;
      String combinedPath;
      if (parts.length == 1) {
        combinedPath = parts.single;
        combined = await files.read(combinedPath);
      } else {
        final merged = await pdf.merge(parts);
        if (merged case Err(:final failure)) return Err(failure);
        combined = merged.valueOrNull!;
        combinedPath = await files.writeTemp(combined, 'pdf');
        temps.add(combinedPath);
      }

      final count = await pdf.pageCount(combinedPath);
      if (count case Err(:final failure)) return Err(failure);
      final pages = count.valueOrNull!;
      final maxPages = item.maxPages;
      if (maxPages != null && pages > maxPages) {
        return Err(
          NoticeFailure(
            'This kit allows up to $maxPages pages; you selected $pages. '
            'Remove some pages and try again.',
          ),
        );
      }
      onProgress?.call(0.6);

      var compressed = false;
      if (combined.length > item.maxBytes) {
        final fitted = await compressPdfToTarget(
          pdf,
          combinedPath,
          item.maxBytes,
          onStep: (f) => onProgress?.call(0.6 + f * 0.4),
        );
        if (fitted case Err(:final failure)) return Err(failure);
        combined = fitted.valueOrNull!.bytes;
        compressed = true;
      }
      onProgress?.call(1);

      return Ok(
        KitOutput(
          bytes: combined,
          format: DocumentFormat.pdf,
          pageCount: pages,
          compressedPdf: compressed,
          checks: [
            KitCheck(
              '${formatLimit(combined.length)} '
              '(limit ${formatLimit(item.maxBytes)})',
              passed: combined.length <= item.maxBytes,
            ),
            KitCheck(
              maxPages == null
                  ? '$pages ${pages == 1 ? 'page' : 'pages'}'
                  : '$pages of max $maxPages pages',
              passed: maxPages == null || pages <= maxPages,
            ),
            const KitCheck('PDF format', passed: true),
          ],
        ),
      );
    } finally {
      for (final t in temps) {
        await files.delete(t);
      }
    }
  }

  Future<Uint8List?> _read(String path) async {
    try {
      final bytes = await files.read(path);
      return bytes.isEmpty ? null : bytes;
    } on Object {
      return null;
    }
  }
}
