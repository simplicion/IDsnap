import 'dart:math' as math;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/ocr/ocr_geometry.dart';
import 'package:docscan_domain/src/ocr/ocr_layout.dart';
import 'package:docscan_domain/src/ocr/ocr_quality.dart';
import 'package:docscan_domain/src/ports/ocr_image_preparer.dart';
import 'package:docscan_domain/src/ports/text_recognizer.dart';

/// OCR of one image with preprocessing and automatic retries:
///
/// 1. **Normalize** (via [preparer]): EXIF orientation baked in, huge photos
///    downscaled to [maxDimension].
/// 2. **Upright pass** with the chosen script (Latin first in Auto mode).
/// 3. **Orientation**: when the pass is poor (little or unsure text), try
///    90°/180°/270° — most likely first, using ML Kit's line angles — and
///    keep the best.
/// 4. **Scale**: when text is smaller than [minTextHeightPx], upscale so it
///    reaches about [targetTextHeightPx] and keep it if clearly better.
/// 5. **Enhance**: illumination/contrast normalization when asked to, or
///    when still poor in [OcrEnhance.auto].
/// 6. **Script** (Auto only): still poor → every other installed script on
///    the best image; the clearly best result wins.
///
/// The returned result is in reading order, its boxes are normalized to the
/// upright-as-shown input image and [OcrResult.quarterTurns] records the
/// rotation that made the text readable. Without a [preparer], only the
/// script logic runs (the file is recognized as is).
class RecognizeText {
  RecognizeText({
    required this.recognizer,
    this.preparer,
    this.minTextHeightPx = 20,
    this.targetTextHeightPx = 32,
    this.maxDimension = 4096,
  });

  final TextRecognizer recognizer;
  final OcrImagePreparer? preparer;
  final double minTextHeightPx;
  final double targetTextHeightPx;
  final int maxDimension;

  static const _cancelled = AppFailure(FailureCode.processingCancelled);
  static const _fatalPrepare = {
    FailureCode.notFound,
    FailureCode.emptyFile,
    FailureCode.processingCancelled,
    FailureCode.insufficientStorage,
  };

  /// Scripts Auto mode will use on this device, Latin first. Empty when no
  /// script is installed (the Err explains why).
  Future<Result<List<OcrScript>>> scriptsFor(OcrOptions options) async {
    final chosen = options.script;
    if (chosen != null) {
      final cap = await recognizer.capability(chosen);
      if (!cap.available) return Err(_modelMissing(chosen, cap.note));
      return Ok([chosen]);
    }
    final out = <OcrScript>[];
    String? note;
    for (final s in OcrScript.values) {
      final cap = await recognizer.capability(s);
      if (cap.available) {
        out.add(s);
      } else if (s == OcrScript.latin) {
        note = cap.note;
      }
    }
    if (out.isEmpty) return Err(_modelMissing(OcrScript.latin, note));
    return Ok(out);
  }

  Future<Result<OcrResult>> call(
    String imagePath, {
    OcrOptions options = const OcrOptions(),
    OcrCancelToken? cancel,
  }) async {
    final scriptsR = await scriptsFor(options);
    if (scriptsR case Err(:final failure)) return Err(failure);
    final scripts = scriptsR.valueOrNull!;
    if (cancel?.isCancelled ?? false) return const Err(_cancelled);

    final prep = preparer;
    final temps = <OcrImage>[];
    try {
      var base = OcrImage(path: imagePath, width: 0, height: 0);
      if (prep != null) {
        final n = await prep.normalize(imagePath);
        if (n case Ok(:final value)) {
          base = value;
          temps.add(value);
        } else if (_fatalPrepare.contains(n.failureOrNull!.code)) {
          return Err(n.failureOrNull!);
        }
        // Otherwise our decoder can't read it (e.g. HEIC without a native
        // decoder): let the recognizer try the file directly; it reports its
        // own typed failure if it can't either.
      }
      final canVary = prep != null && base.width > 0;

      final first = await _pass(base, scripts.first, const OcrVariant());
      if (first case Err(:final failure)) return Err(failure);
      var best = first.valueOrNull!;

      Future<void> tryVariant(
        OcrVariant v, {
        double margin = 0.15,
        bool preferNew = false,
      }) async {
        if (cancel?.isCancelled ?? false) return;
        final img = await prep!.variant(base, v);
        if (img case Ok(:final value)) {
          temps.add(value);
          final c = await _pass(value, best.script, v);
          if (c case Ok(value: final cand)) {
            final better = preferNew
                ? cand.quality.score >= best.quality.score * 0.9
                : clearlyBetter(cand.quality, best.quality, margin: margin);
            if (better) best = cand;
          }
        }
      }

      // Orientation.
      if (canVary && options.autoRotate && best.quality.isPoor) {
        for (final t in rotationCandidates(best.result)) {
          await tryVariant(OcrVariant(quarterTurns: t));
          if (best.quality.isGood) break;
        }
      }
      if (cancel?.isCancelled ?? false) return const Err(_cancelled);

      // Scale: small text is the most common cause of missed words.
      if (canVary && options.autoScale) {
        final scale = _upscaleFactor(best, base);
        if (scale != null) {
          await tryVariant(
            OcrVariant(quarterTurns: best.variant.quarterTurns, scale: scale),
            margin: 0.05,
          );
        }
      }
      if (cancel?.isCancelled ?? false) return const Err(_cancelled);

      // Illumination / contrast.
      final enhance =
          options.enhance == OcrEnhance.always ||
          (options.enhance == OcrEnhance.auto && best.quality.isPoor);
      if (canVary && enhance) {
        await tryVariant(
          OcrVariant(
            quarterTurns: best.variant.quarterTurns,
            scale: best.variant.scale,
            enhance: true,
          ),
          preferNew: options.enhance == OcrEnhance.always,
        );
      }

      // Other scripts (Auto only).
      if (options.isAuto && best.quality.isPoor) {
        for (final s in scripts.skip(1)) {
          if (cancel?.isCancelled ?? false) return const Err(_cancelled);
          final c = await _pass(best.image, s, best.variant);
          if (c case Ok(
            value: final cand,
          ) when clearlyBetter(cand.quality, best.quality)) {
            best = cand;
          }
          if (best.quality.isGood) break;
        }
      }
      if (cancel?.isCancelled ?? false) return const Err(_cancelled);

      final ordered = best.result.copyWith(
        blocks: orderBlocksForReading(best.result.blocks),
      );
      return Ok(unrotateResult(ordered, best.variant.quarterTurns));
    } finally {
      for (final t in temps) {
        await prep?.release(t);
      }
    }
  }

  /// `null` when the text is already large enough (or can't be measured and
  /// the image is already large).
  double? _upscaleFactor(_Candidate best, OcrImage base) {
    final img = best.image;
    final h = medianLineHeightPx(
      best.result,
      imageWidth: img.width,
      imageHeight: img.height,
    );
    final double wanted;
    if (h == null || h <= 0) {
      // Nothing found at all: small text in a small image is a likely cause.
      if (base.longestEdge >= 1600) return null;
      wanted = 2;
    } else {
      if (h >= minTextHeightPx) return null;
      wanted = targetTextHeightPx / h;
    }
    final cap = maxDimension / math.max(1, base.longestEdge);
    final scale = math.min(math.min(wanted, 3), cap).toDouble();
    return scale >= 1.25 ? scale : null;
  }

  Future<Result<_Candidate>> _pass(
    OcrImage image,
    OcrScript script,
    OcrVariant variant,
  ) async {
    final r = await recognizer.recognize(image.path, script);
    return r.map(
      (result) => _Candidate(
        result: result,
        quality: assessOcr(result),
        image: image,
        script: script,
        variant: variant,
      ),
    );
  }

  static AppFailure _modelMissing(OcrScript s, String? note) => AppFailure(
    FailureCode.modelUnavailable,
    detail: s.shortLabel,
    message:
        note ??
        '${s.shortLabel} text recognition is not installed in this app. '
            'Choose another language.',
  );
}

class _Candidate {
  _Candidate({
    required this.result,
    required this.quality,
    required this.image,
    required this.script,
    required this.variant,
  });

  /// Boxes in the frame of [image] (i.e. rotated by variant.quarterTurns).
  final OcrResult result;
  final OcrQuality quality;
  final OcrImage image;
  final OcrScript script;
  final OcrVariant variant;
}
