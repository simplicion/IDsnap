import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_imaging/engine_imaging.dart';

/// Decodes with the platform codec (Skia/Impeller, off the UI thread),
/// downsampling during decode and applying EXIF orientation. ~10× faster than
/// pure-Dart JPEG decoding for 12 MP photos. Returns null on failure so the
/// imaging engine can fall back to its own decoder.
Future<DecodedRaster?> nativeDecode(
  Uint8List encoded, {
  int? maxDimension,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final max = maxDimension;
        if (max == null || math.max(w, h) <= max) {
          return ui.TargetImageSize(width: w, height: h);
        }
        final scale = max / math.max(w, h);
        return ui.TargetImageSize(
          width: math.max(1, (w * scale).round()),
          height: math.max(1, (h * scale).round()),
        );
      },
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData();
    if (data == null) return null;
    return DecodedRaster(
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    buffer?.dispose();
  }
}
