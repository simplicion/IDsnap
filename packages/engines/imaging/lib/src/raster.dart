import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:image/image.dart' as img;

/// Packed 8-bit RGB pixels. All pixel work happens on raw buffers for speed.
class Rgb {
  Rgb(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height * 3);

  final int width;
  final int height;
  final Uint8List data;

  /// Rec. 601 luma as a single-channel buffer.
  Uint8List luma() {
    final out = Uint8List(width * height);
    for (var i = 0, p = 0; i < out.length; i++, p += 3) {
      out[i] = (77 * data[p] + 150 * data[p + 1] + 29 * data[p + 2]) >> 8;
    }
    return out;
  }

  static Rgb fromGray(Uint8List gray, int width, int height) {
    final out = Rgb(width, height);
    for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
      final v = gray[i];
      out.data[p] = v;
      out.data[p + 1] = v;
      out.data[p + 2] = v;
    }
    return out;
  }
}

/// Decodes [bytes], applies EXIF orientation and returns RGB pixels.
///
/// Throws [AppFailure] with `unsupportedFormat` (e.g. HEIC, which
/// package:image cannot decode) or `corruptFile`.
Rgb decodeRgb(Uint8List bytes) {
  final head = bytes.sublist(0, bytes.length < 32 ? bytes.length : 32);
  final format = DocumentFormat.sniff(head);
  if (format == DocumentFormat.heic) {
    throw const AppFailure(FailureCode.unsupportedFormat, detail: 'HEIC');
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e, st) {
    throw AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st);
  }
  if (decoded == null) {
    throw AppFailure(
      format.isImage || format == DocumentFormat.unknown
          ? FailureCode.corruptFile
          : FailureCode.unsupportedFormat,
    );
  }
  final ifd = decoded.exif.imageIfd;
  final oriented = ifd.hasOrientation && ifd.orientation != 1
      ? img.bakeOrientation(decoded)
      : decoded;
  return imageToRgb(oriented);
}

Rgb imageToRgb(img.Image image) {
  var src = image;
  if (src.numChannels == 4) {
    // Composite transparency onto white paper instead of black.
    src = img.Image(width: image.width, height: image.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(src, image.convert(format: img.Format.uint8));
  }
  if (src.format != img.Format.uint8 ||
      src.numChannels != 3 ||
      src.hasPalette) {
    src = src.convert(format: img.Format.uint8, numChannels: 3);
  }
  final bytes = src.getBytes(order: img.ChannelOrder.rgb);
  return Rgb(src.width, src.height, Uint8List.fromList(bytes));
}

img.Image rgbToImage(Rgb rgb) => img.Image.fromBytes(
  width: rgb.width,
  height: rgb.height,
  bytes: rgb.data.buffer,
  bytesOffset: rgb.data.offsetInBytes,
  numChannels: 3,
);

Uint8List encodeJpeg(Rgb rgb, int quality) =>
    img.encodeJpg(rgbToImage(rgb), quality: quality.clamp(1, 100));

Uint8List encodePng(Rgb rgb) => img.encodePng(rgbToImage(rgb));

/// Resizes with integer box pre-reduction (anti-aliasing) then bilinear.
Rgb resizeRgb(Rgb src, int width, int height) {
  if (width == src.width && height == src.height) return src;
  var s = src;
  final k = [
    s.width ~/ width,
    s.height ~/ height,
  ].reduce((a, b) => a < b ? a : b);
  if (k >= 2) s = _boxReduce(s, k);
  return _bilinear(s, width, height);
}

/// Scales so the longest edge is at most [maxDimension].
Rgb fitWithin(Rgb src, int maxDimension) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= maxDimension) return src;
  final scale = maxDimension / longest;
  return resizeRgb(
    src,
    (src.width * scale).round().clamp(1, maxDimension),
    (src.height * scale).round().clamp(1, maxDimension),
  );
}

Rgb _boxReduce(Rgb src, int k) {
  final w = src.width ~/ k;
  final h = src.height ~/ k;
  final out = Rgb(w, h);
  final area = k * k;
  final sw = src.width;
  final d = src.data;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = 0;
      var g = 0;
      var b = 0;
      for (var yy = 0; yy < k; yy++) {
        var p = ((y * k + yy) * sw + x * k) * 3;
        for (var xx = 0; xx < k; xx++, p += 3) {
          r += d[p];
          g += d[p + 1];
          b += d[p + 2];
        }
      }
      final o = (y * w + x) * 3;
      out.data[o] = r ~/ area;
      out.data[o + 1] = g ~/ area;
      out.data[o + 2] = b ~/ area;
    }
  }
  return out;
}

Rgb _bilinear(Rgb src, int width, int height) {
  final out = Rgb(width, height);
  final sx = src.width / width;
  final sy = src.height / height;
  final maxX = src.width - 1.0;
  final maxY = src.height - 1.0;
  for (var y = 0; y < height; y++) {
    var fy = (y + 0.5) * sy - 0.5;
    if (fy < 0) fy = 0;
    if (fy > maxY) fy = maxY;
    var o = y * width * 3;
    for (var x = 0; x < width; x++, o += 3) {
      var fx = (x + 0.5) * sx - 0.5;
      if (fx < 0) fx = 0;
      if (fx > maxX) fx = maxX;
      sampleBilinear(src, fx, fy, out.data, o);
    }
  }
  return out;
}

/// Writes the bilinear sample at (fx, fy) into [dst] at [offset].
///
/// Coordinates must already be clamped to the image. Uses 8-bit fixed-point
/// weights: this is the hottest loop in the pipeline.
@pragma('vm:prefer-inline')
void sampleBilinear(Rgb src, double fx, double fy, Uint8List dst, int offset) {
  final x0 = fx.toInt();
  final y0 = fy.toInt();
  final w = src.width;
  final dx = x0 + 1 < w ? 3 : 0;
  final dy = y0 + 1 < src.height ? w * 3 : 0;
  final ax = ((fx - x0) * 256).toInt();
  final ay = ((fy - y0) * 256).toInt();
  final bx = 256 - ax;
  final by = 256 - ay;
  final d = src.data;
  final p00 = (y0 * w + x0) * 3;
  final p01 = p00 + dy;
  var top = d[p00] * bx + d[p00 + dx] * ax;
  var bottom = d[p01] * bx + d[p01 + dx] * ax;
  dst[offset] = (top * by + bottom * ay + 32768) >> 16;
  top = d[p00 + 1] * bx + d[p00 + dx + 1] * ax;
  bottom = d[p01 + 1] * bx + d[p01 + dx + 1] * ax;
  dst[offset + 1] = (top * by + bottom * ay + 32768) >> 16;
  top = d[p00 + 2] * bx + d[p00 + dx + 2] * ax;
  bottom = d[p01 + 2] * bx + d[p01 + dx + 2] * ax;
  dst[offset + 2] = (top * by + bottom * ay + 32768) >> 16;
}

/// Rotates clockwise by [quarterTurns] × 90°.
Rgb rotateQuarterTurns(Rgb src, int quarterTurns) {
  final t = quarterTurns % 4;
  if (t == 0) return src;
  final w = src.width;
  final h = src.height;
  final out = t == 2 ? Rgb(w, h) : Rgb(h, w);
  final d = src.data;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final int nx;
      final int ny;
      switch (t) {
        case 1:
          nx = h - 1 - y;
          ny = x;
        case 2:
          nx = w - 1 - x;
          ny = h - 1 - y;
        default:
          nx = y;
          ny = w - 1 - x;
      }
      final s = (y * w + x) * 3;
      final o = (ny * out.width + nx) * 3;
      out.data[o] = d[s];
      out.data[o + 1] = d[s + 1];
      out.data[o + 2] = d[s + 2];
    }
  }
  return out;
}

/// Crops a pixel rectangle (clamped to bounds).
Rgb cropRgb(Rgb src, int left, int top, int width, int height) {
  final l = left.clamp(0, src.width - 1);
  final t = top.clamp(0, src.height - 1);
  final w = width.clamp(1, src.width - l);
  final h = height.clamp(1, src.height - t);
  final out = Rgb(w, h);
  for (var y = 0; y < h; y++) {
    final s = ((t + y) * src.width + l) * 3;
    out.data.setRange(y * w * 3, (y + 1) * w * 3, src.data, s);
  }
  return out;
}

/// Pixels produced by an injected native decoder (see `RasterDecoder`).
class DecodedRaster {
  const DecodedRaster({
    required this.rgba,
    required this.width,
    required this.height,
  });

  /// RGBA8888, row-major, no padding, EXIF orientation already applied.
  final Uint8List rgba;
  final int width;
  final int height;
}

/// Decodes [encoded] natively (e.g. `dart:ui` `instantiateImageCodec` with a
/// target size). Must apply EXIF orientation and, when [maxDimension] is
/// given, downsample so the longest edge is at most [maxDimension]. Returns
/// null when the format is unsupported so the engine can fall back.
typedef RasterDecoder =
    Future<DecodedRaster?> Function(Uint8List encoded, {int? maxDimension});

/// Image input that can cross an isolate boundary: either encoded bytes
/// (decoded with package:image in the worker) or pre-decoded RGBA.
class RasterSource {
  const RasterSource.encoded(Uint8List this.encoded)
    : rgba = null,
      width = 0,
      height = 0;

  RasterSource.decoded(DecodedRaster raster)
    : encoded = null,
      rgba = raster.rgba,
      width = raster.width,
      height = raster.height;

  final Uint8List? encoded;
  final Uint8List? rgba;
  final int width;
  final int height;

  bool get isDecoded => rgba != null;

  /// Converts to packed RGB, compositing any transparency onto white.
  Rgb toRgb() {
    final bytes = encoded;
    if (bytes != null) return decodeRgb(bytes);
    final src = rgba!;
    if (width <= 0 || height <= 0 || src.length < width * height * 4) {
      throw const AppFailure(FailureCode.corruptFile);
    }
    final out = Rgb(width, height);
    final d = out.data;
    for (var i = 0, p = 0, o = 0; i < width * height; i++, p += 4, o += 3) {
      final a = src[p + 3];
      if (a == 255) {
        d[o] = src[p];
        d[o + 1] = src[p + 1];
        d[o + 2] = src[p + 2];
      } else {
        final bg = 255 * (255 - a);
        d[o] = (src[p] * a + bg) ~/ 255;
        d[o + 1] = (src[p + 1] * a + bg) ~/ 255;
        d[o + 2] = (src[p + 2] * a + bg) ~/ 255;
      }
    }
    return out;
  }
}
