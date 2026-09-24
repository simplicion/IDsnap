import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/detect/detector.dart';
import 'package:engine_imaging/src/filters/enhance.dart';
import 'package:engine_imaging/src/geometry/warp.dart';
import 'package:engine_imaging/src/raster.dart';
import 'package:image/image.dart' as img;

/// Pure-Dart [ImageProcessor]. Every heavy call processes inside
/// [runHeavy] (a background isolate on mobile), so only bytes and immutable
/// parameters cross the isolate boundary. Inputs are never mutated.
///
/// Decoding is the slowest step with package:image (~2.6 s for 12 MP). Apps
/// should inject a native [decoder] (e.g. `dart:ui` with a target size): the
/// engine then decodes on the calling isolate — the native codec runs off the
/// UI thread — already downsampled, and ships raw RGBA to the worker. Without
/// a decoder, or when it returns null/throws, package:image is used.
///
/// Output cost scales with pixel count, so interactive previews should call
/// [renderPage] with [QualityPreset.small] and [thumbnail] with small sizes.
class ImagingEngine implements ImageProcessor {
  const ImagingEngine({this.decoder});

  /// Optional native decoder; see [RasterDecoder].
  final RasterDecoder? decoder;

  /// Decode budget for detection: plenty for a 320 px working image.
  static const detectDecodeSize = 640;

  /// Headroom over the output size so the perspective warp can still
  /// sample at full detail after a moderate crop.
  static int renderDecodeSize(QualityPreset preset) =>
      (preset.maxDimension * 1.25).ceil();

  @override
  Future<Result<DetectedQuad>> detectDocument(Uint8List imageBytes) async {
    final src = await _source(imageBytes, detectDecodeSize);
    return await _run(() => detectPage(src.toRgb()));
  }

  @override
  Future<Result<Uint8List>> renderPage(
    Uint8List original,
    PageEdits edits, {
    QualityPreset preset = QualityPreset.balanced,
  }) async {
    final src = await _source(original, renderDecodeSize(preset));
    return await _run(() => renderPageSync(src, edits, preset));
  }

  @override
  Future<Result<Uint8List>> thumbnail(
    Uint8List imageBytes, {
    int maxDimension = 480,
  }) async {
    final src = await _source(imageBytes, maxDimension);
    return await _run(
      () => encodeJpeg(fitWithin(src.toRgb(), maxDimension), 80),
    );
  }

  @override
  Future<Result<EncodedImage>> crop(
    Uint8List imageBytes,
    NRect rect, {
    int? outputWidth,
    int? outputHeight,
    int quarterTurns = 0,
    ImageOutputFormat format = ImageOutputFormat.jpeg,
    int quality = 92,
  }) async {
    // Full resolution: the crop may be a small region of the photo.
    final src = await _source(imageBytes, null);
    return await _run(
      () => cropSync(
        src,
        rect,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        quarterTurns: quarterTurns,
        format: format,
        quality: quality,
      ),
    );
  }

  @override
  Future<Result<EncodedImage>> compress(
    Uint8List imageBytes,
    ImageCompressionOptions options,
  ) async {
    final src = await _source(imageBytes, options.maxDimension);
    return await _run(() => compressSync(src, options));
  }

  /// Uses the native [decoder] when available; never throws.
  Future<RasterSource> _source(Uint8List bytes, int? maxDimension) async {
    final decode = decoder;
    if (decode != null) {
      try {
        final raster = await decode(bytes, maxDimension: maxDimension);
        if (raster != null) return RasterSource.decoded(raster);
      } on Object {
        // Unsupported by the native codec: fall back to package:image, which
        // reports a typed failure if it can't decode either.
      }
    }
    return RasterSource.encoded(bytes);
  }

  @override
  Future<Result<ImageDetails>> inspect(Uint8List imageBytes) async {
    try {
      return Ok(inspectSync(imageBytes));
    } on AppFailure catch (f) {
      return Err(f);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st));
    }
  }

  static Future<Result<T>> _run<T>(T Function() job) async {
    try {
      return Ok(await runHeavy(job));
    } on AppFailure catch (f) {
      return Err(f);
      // Large photos can exhaust the worker heap; report it as a typed,
      // recoverable failure instead of crashing.
      // ignore: avoid_catching_errors
    } on OutOfMemoryError catch (e, st) {
      return Err(
        AppFailure(FailureCode.memoryLimitExceeded, cause: e, stackTrace: st),
      );
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.unknown, cause: e, stackTrace: st));
    }
  }
}

// ── Synchronous implementations (run inside the worker isolate) ────────────

/// Perspective → filter → adjustments → rotation → JPEG.
Uint8List renderPageSync(
  RasterSource original,
  PageEdits edits,
  QualityPreset preset,
) {
  var src = original.toRgb();
  final maxDim = preset.maxDimension;
  final quad = edits.quad;
  Rgb page;
  if (quad != null && !quad.isFull) {
    if (!quad.isConvex) {
      throw const AppFailure(
        FailureCode.documentNotDetected,
        detail: 'Corners overlap',
      );
    }
    var size = warpSize(quad, src.width, src.height);
    final longest = math.max(size.width, size.height);
    final scale = math.min(1, maxDim / longest);
    if (scale < 0.95) {
      // Shrink the source first: box-reduction anti-aliases better than
      // sampling a large image sparsely during the warp.
      src = resizeRgb(
        src,
        math.max(1, (src.width * scale).round()),
        math.max(1, (src.height * scale).round()),
      );
      size = warpSize(quad, src.width, src.height);
    }
    page = warpPerspective(
      src,
      quad,
      math.min(size.width, maxDim),
      math.min(size.height, maxDim),
    );
  } else {
    page = fitWithin(src, maxDim);
  }
  page = applyFilter(page, edits.filter);
  page = applyAdjustments(page, edits.brightness, edits.contrast);
  page = rotateQuarterTurns(page, edits.quarterTurns);
  return encodeJpeg(page, preset.jpegQuality);
}

/// Rotation is applied first; [rect] is expressed in the rotated image.
EncodedImage cropSync(
  RasterSource source,
  NRect rect, {
  int? outputWidth,
  int? outputHeight,
  int quarterTurns = 0,
  ImageOutputFormat format = ImageOutputFormat.jpeg,
  int quality = 92,
}) {
  final src = rotateQuarterTurns(source.toRgb(), quarterTurns);
  final left = (rect.left.clamp(0.0, 1.0) * src.width).round();
  final top = (rect.top.clamp(0.0, 1.0) * src.height).round();
  final width = math.max(1, (rect.width.clamp(0.0, 1.0) * src.width).round());
  final height = math.max(
    1,
    (rect.height.clamp(0.0, 1.0) * src.height).round(),
  );
  var out = cropRgb(src, left, top, width, height);
  if (outputWidth != null || outputHeight != null) {
    final ow = outputWidth ?? (out.width * outputHeight! / out.height).round();
    final oh = outputHeight ?? (out.height * outputWidth! / out.width).round();
    out = resizeRgb(out, math.max(1, ow), math.max(1, oh));
  }
  return _encode(out, format, quality);
}

EncodedImage compressSync(
  RasterSource source,
  ImageCompressionOptions options,
) {
  var image = source.toRgb();
  final maxDim = options.maxDimension;
  if (maxDim != null) image = fitWithin(image, maxDim);
  final target = options.targetBytes;
  if (target == null || options.format == ImageOutputFormat.png) {
    return _encode(image, options.format, options.quality);
  }

  EncodedImage? smallest;
  for (var attempt = 0; attempt < 12; attempt++) {
    // Binary search the highest quality that fits.
    var lo = 20;
    var hi = math.min(95, math.max(20, options.quality));
    EncodedImage? fit;
    final atLo = _encode(image, ImageOutputFormat.jpeg, lo);
    if (smallest == null || atLo.bytes.length < smallest.bytes.length) {
      smallest = atLo;
    }
    if (atLo.bytes.length <= target) {
      fit = atLo;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        final e = _encode(image, ImageOutputFormat.jpeg, mid);
        if (e.bytes.length <= target) {
          fit = e;
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      return fit!;
    }
    if (image.width < 64 || image.height < 64) break;
    image = resizeRgb(
      image,
      math.max(1, (image.width * 0.85).round()),
      math.max(1, (image.height * 0.85).round()),
    );
  }
  return smallest!;
}

ImageDetails inspectSync(Uint8List bytes) {
  if (bytes.isEmpty) throw const AppFailure(FailureCode.corruptFile);
  final head = bytes.sublist(0, math.min(32, bytes.length));
  final format = DocumentFormat.sniff(head);
  if (format == DocumentFormat.heic) {
    throw const AppFailure(FailureCode.unsupportedFormat, detail: 'HEIC');
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    throw AppFailure(
      format == DocumentFormat.unknown || format.isImage
          ? FailureCode.corruptFile
          : FailureCode.unsupportedFormat,
    );
  }
  final info = decoder.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const AppFailure(FailureCode.corruptFile);
  }
  return ImageDetails(
    width: info.width,
    height: info.height,
    sizeBytes: bytes.length,
  );
}

EncodedImage _encode(Rgb image, ImageOutputFormat format, int quality) =>
    EncodedImage(
      bytes: format == ImageOutputFormat.png
          ? encodePng(image)
          : encodeJpeg(image, quality),
      width: image.width,
      height: image.height,
      format: format,
    );
