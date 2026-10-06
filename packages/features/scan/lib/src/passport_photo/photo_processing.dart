import 'dart:math' as math;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:flutter/foundation.dart';

/// The captured still, with where the face is.
@immutable
class SourcePhoto {
  const SourcePhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.face,
  });

  final Uint8List bytes;

  /// Upright pixel size (EXIF applied).
  final int width;
  final int height;

  /// Detector face box normalized to the upright still, or `null`.
  final NRect? face;
}

/// The finished photo at the preset's exact pixel size.
@immutable
class ProcessedPhoto {
  const ProcessedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rect,
    required this.withinLimit,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Crop used, normalized to the source still.
  final NRect rect;

  /// `false` only when the preset has a size limit this file exceeds.
  final bool withinLimit;

  int get sizeBytes => bytes.length;
}

/// Light, global lift used by "Brighten background". It is a hint-level
/// tweak for off-white walls, not background replacement.
const brightenEdits = PageEdits(
  filter: EnhancementFilter.original,
  brightness: 0.08,
  contrast: 0.04,
);

/// Crop, optional brightening and size-limit compression, using domain
/// ports only (no engine code is duplicated or modified here).
class PassportPhotoProcessor {
  const PassportPhotoProcessor({
    required this.files,
    required this.images,
    this.faces,
  });

  final FileStore files;
  final ImageProcessor images;
  final FaceLocator? faces;

  /// Reads the still and finds the face in it. [fallbackFace] (from the
  /// live stream, normalized to the still) is used when the still-image
  /// detector finds nothing or isn't available.
  Future<Result<SourcePhoto>> load(String path, {NRect? fallbackFace}) async {
    final Uint8List bytes;
    try {
      bytes = await files.read(path);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    if (bytes.isEmpty) return const Err(AppFailure(FailureCode.emptyFile));
    final info = await images.inspect(bytes);
    if (info case Err(:final failure)) return Err(failure);
    final details = info.valueOrNull!;

    NRect? face;
    final locator = faces;
    if (locator != null) {
      final cap = await locator.capability();
      if (cap.available) {
        face = (await locator.locateLargestFace(path)).valueOrNull;
      }
    }
    return Ok(
      SourcePhoto(
        bytes: bytes,
        width: details.width,
        height: details.height,
        face: face ?? fallbackFace,
      ),
    );
  }

  /// Automatic crop for [preset]: head framed by `autoFramePortrait`, or a
  /// centred crop when no face is known.
  NRect autoRect(SourcePhoto source, PhotoPreset preset) {
    final face = source.face;
    final framed = face == null
        ? null
        : autoFramePortrait(
            face: face,
            preset: preset.toCropPreset(),
            imageWidth: source.width,
            imageHeight: source.height,
          );
    return framed ??
        NRect.centeredWithAspect(preset.aspect, source.width, source.height);
  }

  /// Produces the final JPEG for [rect].
  Future<Result<ProcessedPhoto>> render(
    SourcePhoto source,
    PhotoPreset preset,
    NRect rect, {
    bool brighten = false,
  }) async {
    final cropped = await images.crop(
      source.bytes,
      rect,
      outputWidth: preset.pixelWidth,
      outputHeight: preset.pixelHeight,
      quality: 95,
    );
    if (cropped case Err(:final failure)) return Err(failure);
    var out = Uint8List.fromList(cropped.valueOrNull!.bytes);

    if (brighten) {
      final lifted = await images.renderPage(
        out,
        brightenEdits,
        preset: QualityPreset.high,
      );
      if (lifted case Err(:final failure)) return Err(failure);
      out = lifted.valueOrNull!;
    }

    final limit = preset.maxBytes;
    if (limit != null && out.length > limit) {
      final compressed = await images.compress(
        out,
        ImageCompressionOptions(quality: 95, targetBytes: limit),
      );
      if (compressed case Err(:final failure)) return Err(failure);
      out = Uint8List.fromList(compressed.valueOrNull!.bytes);
    }

    final measured = (await images.inspect(out)).valueOrNull;
    return Ok(
      ProcessedPhoto(
        bytes: out,
        width: measured?.width ?? preset.pixelWidth,
        height: measured?.height ?? preset.pixelHeight,
        rect: rect,
        withinLimit: limit == null || out.length <= limit,
      ),
    );
  }
}

/// Maps a live-preview face box (mirrored for the front camera) to the
/// still, assuming both show the same field of view.
NRect unmirrorBox(NRect box, {required bool mirrored}) =>
    mirrored ? NRect(1 - box.right, box.top, box.width, box.height) : box;

/// Moves/scales a crop [rect] (normalized to an [imageWidth] × [imageHeight]
/// image), keeping the pixel [aspect] and staying inside the image.
/// [dx]/[dy] are in normalized image units; [scale] > 1 enlarges the crop.
NRect adjustCropRect(
  NRect rect, {
  required int imageWidth,
  required int imageHeight,
  required double aspect,
  double dx = 0,
  double dy = 0,
  double scale = 1,
}) {
  final iw = imageWidth.toDouble();
  final ih = imageHeight.toDouble();
  // Pixel space keeps the aspect exact.
  var h = rect.height * ih * scale;
  var w = h * aspect;
  final maxScale = [iw / w, ih / h, 1.0].reduce((a, b) => a < b ? a : b);
  w *= maxScale;
  h *= maxScale;
  const minPx = 64.0;
  if (h < minPx) {
    h = minPx;
    w = h * aspect;
  }
  final cx = (rect.left + rect.width / 2 + dx) * iw;
  final cy = (rect.top + rect.height / 2 + dy) * ih;
  final left = (cx - w / 2).clamp(0.0, math.max(0.0, iw - w));
  final top = (cy - h / 2).clamp(0.0, math.max(0.0, ih - h));
  return NRect(left / iw, top / ih, w / iw, h / ih);
}
