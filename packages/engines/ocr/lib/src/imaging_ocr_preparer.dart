import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// [OcrImagePreparer] built on the imaging engine's public [ImageProcessor]
/// port (which does its pixel work in a background isolate and only moves
/// bytes and plain parameters) and the [FileStore] for temp files.
///
/// * [normalize]: images that are already upright (no EXIF rotation) and not
///   larger than [maxDimension] are used as is — no re-encode. Others are
///   re-encoded once with EXIF orientation baked in and the longest edge
///   capped at [maxDimension] (ML Kit gains nothing above ~4k px and slows
///   down; 12–50 MP photos also risk running out of memory).
/// * [variant]: rotation and resize through `crop`, illumination/contrast
///   normalization through `renderPage` with the "Auto enhance" filter.
class ImagingOcrPreparer implements OcrImagePreparer {
  ImagingOcrPreparer({
    required this.images,
    required this.files,
    this.maxDimension = 4096,
    this.jpegQuality = 92,
  });

  final ImageProcessor images;
  final FileStore files;
  final int maxDimension;
  final int jpegQuality;

  @override
  Future<Result<OcrImage>> normalize(String imagePath) async {
    final Uint8List bytes;
    try {
      bytes = await files.read(imagePath);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    if (bytes.isEmpty) return const Err(AppFailure(FailureCode.emptyFile));

    final info = await images.inspect(bytes);
    if (info case Ok(:final value)
        when value.width > 0 &&
            value.height > 0 &&
            value.width <= maxDimension &&
            value.height <= maxDimension &&
            exifOrientation(bytes) <= 1) {
      return Ok(
        OcrImage(path: imagePath, width: value.width, height: value.height),
      );
    }

    final out = await images.compress(
      bytes,
      ImageCompressionOptions(quality: jpegQuality, maxDimension: maxDimension),
    );
    if (out case Err(:final failure)) return Err(failure);
    return await _store(out.valueOrNull!);
  }

  @override
  Future<Result<OcrImage>> variant(OcrImage base, OcrVariant v) async {
    final Uint8List bytes;
    try {
      bytes = await files.read(base.path);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    final odd = v.quarterTurns.isOdd;
    final rotatedWidth = odd ? base.height : base.width;
    final targetWidth = v.scale == 1
        ? null
        : (rotatedWidth * v.scale).round().clamp(1, maxDimension);

    if (!v.enhance) {
      final r = await images.crop(
        bytes,
        NRect.full,
        quarterTurns: v.quarterTurns,
        outputWidth: targetWidth,
        quality: jpegQuality,
      );
      if (r case Err(:final failure)) return Err(failure);
      return await _store(r.valueOrNull!);
    }

    final enhanced = await images.renderPage(
      bytes,
      PageEdits(quarterTurns: v.quarterTurns),
      preset: QualityPreset.high,
    );
    if (enhanced case Err(:final failure)) return Err(failure);
    final jpeg = enhanced.valueOrNull!;
    if (targetWidth != null) {
      final r = await images.crop(
        jpeg,
        NRect.full,
        outputWidth: targetWidth,
        quality: jpegQuality,
      );
      if (r case Err(:final failure)) return Err(failure);
      return await _store(r.valueOrNull!);
    }
    final info = await images.inspect(jpeg);
    if (info case Err(:final failure)) return Err(failure);
    final d = info.valueOrNull!;
    return await _write(jpeg, d.width, d.height);
  }

  @override
  Future<void> release(OcrImage image) async {
    if (!image.temporary) return;
    try {
      await files.delete(image.path);
    } on Object {
      // Temp files are also swept by FileStore.clearTemp().
    }
  }

  Future<Result<OcrImage>> _store(EncodedImage e) => _write(
    e.bytes is Uint8List ? e.bytes as Uint8List : Uint8List.fromList(e.bytes),
    e.width,
    e.height,
  );

  Future<Result<OcrImage>> _write(Uint8List bytes, int w, int h) async {
    try {
      final path = await files.writeTemp(bytes, 'jpg');
      return Ok(OcrImage(path: path, width: w, height: h, temporary: true));
    } on Object catch (e, st) {
      return Err(
        AppFailure(FailureCode.insufficientStorage, cause: e, stackTrace: st),
      );
    }
  }
}

/// EXIF orientation tag (1–8) of a JPEG, `1` when absent or not a JPEG.
/// Reads only the APP1 header; never throws.
int exifOrientation(Uint8List b) {
  try {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return 1;
    var i = 2;
    while (i + 4 <= b.length) {
      if (b[i] != 0xFF) return 1;
      final marker = b[i + 1];
      if (marker == 0xDA || marker == 0xD9) return 1; // image data / end
      final len = (b[i + 2] << 8) | b[i + 3];
      if (len < 2) return 1;
      if (marker == 0xE1 &&
          i + 10 <= b.length &&
          b[i + 4] == 0x45 && // E
          b[i + 5] == 0x78 && // x
          b[i + 6] == 0x69 && // i
          b[i + 7] == 0x66) {
        // f
        return _tiffOrientation(b, i + 10, i + 2 + len);
      }
      i += 2 + len;
    }
  } on Object {
    return 1;
  }
  return 1;
}

int _tiffOrientation(Uint8List b, int tiff, int end) {
  if (tiff + 8 > end || end > b.length) return 1;
  final little = b[tiff] == 0x49; // "II"
  int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => little
      ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
      : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > end) return 1;
  final count = u16(ifd);
  for (var k = 0; k < count; k++) {
    final e = ifd + 2 + k * 12;
    if (e + 12 > end) return 1;
    if (u16(e) == 0x0112) {
      final v = u16(e + 8);
      return v >= 1 && v <= 8 ? v : 1;
    }
  }
  return 1;
}
