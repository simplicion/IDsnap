import 'dart:typed_data';

import 'package:engine_imaging/src/raster.dart';

/// Luma histogram percentiles, e.g. `(0.01, 0.99)` → (low, high) levels.
(int, int) percentiles(
  Uint8List gray,
  double lowFraction,
  double highFraction,
) {
  final hist = Int32List(256);
  for (final v in gray) {
    hist[v]++;
  }
  final lowTarget = gray.length * lowFraction;
  final highTarget = gray.length * highFraction;
  var acc = 0;
  var low = 0;
  var high = 255;
  var lowFound = false;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (!lowFound && acc >= lowTarget) {
      low = v;
      lowFound = true;
    }
    if (acc >= highTarget) {
      high = v;
      break;
    }
  }
  return (low, high);
}

/// Linear stretch lookup table mapping [low]..[high] to 0..255.
Uint8List stretchLut(int low, int high) {
  final lut = Uint8List(256);
  if (high - low < 16) {
    // Nearly flat image: stretching would only amplify noise.
    for (var i = 0; i < 256; i++) {
      lut[i] = i;
    }
    return lut;
  }
  for (var i = 0; i < 256; i++) {
    lut[i] = ((i - low) * 255 / (high - low)).round().clamp(0, 255);
  }
  return lut;
}

void applyLutRgb(Rgb image, Uint8List lut) {
  final d = image.data;
  for (var i = 0; i < d.length; i++) {
    d[i] = lut[d[i]];
  }
}

void applyLutGray(Uint8List gray, Uint8List lut) {
  for (var i = 0; i < gray.length; i++) {
    gray[i] = lut[gray[i]];
  }
}

/// Percentile contrast stretch on luma, applied equally to all channels so
/// colors keep their hue.
void stretchContrast(Rgb image, {double low = 0.01, double high = 0.99}) {
  final (lo, hi) = percentiles(image.luma(), low, high);
  applyLutRgb(image, stretchLut(lo, hi));
}

/// Brightness and contrast in -1..1. Returns null when both are zero.
Uint8List? adjustmentLut(double brightness, double contrast) {
  if (brightness == 0 && contrast == 0) return null;
  final gain = 1 + contrast.clamp(-1.0, 1.0);
  final offset = brightness.clamp(-1.0, 1.0) * 100;
  final lut = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    lut[i] = ((i - 128) * gain + 128 + offset).round().clamp(0, 255);
  }
  return lut;
}
