import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';

/// Rotation (degrees, clockwise) ML Kit must apply to a preview buffer so the
/// face is upright. Follows the ML Kit camera guidance:
///
/// - Android: compensate the sensor orientation by the device orientation,
///   in opposite directions for front and back cameras.
/// - iOS: ML Kit reads the orientation from the buffer; a buffer that is
///   already portrait needs no rotation, otherwise use the sensor angle.
int frameRotationDegrees({
  required bool android,
  required bool front,
  required int sensorOrientation,
  required int deviceOrientationDegrees,
  required int bufferWidth,
  required int bufferHeight,
}) {
  if (!android) {
    return bufferHeight >= bufferWidth ? 0 : sensorOrientation % 360;
  }
  final comp = front
      ? (sensorOrientation + deviceOrientationDegrees) % 360
      : (sensorOrientation - deviceOrientationDegrees + 360) % 360;
  return comp;
}

/// Size of the frame after [rotationDegrees] (what face boxes refer to).
({int width, int height}) uprightFrameSize(
  int width,
  int height,
  int rotationDegrees,
) => rotationDegrees % 180 == 0
    ? (width: width, height: height)
    : (width: height, height: width);

/// Normalizes a detector box (pixels in the upright frame) and mirrors it
/// horizontally when the preview is mirrored, so it lines up with what the
/// user sees. Returns `null` for degenerate boxes.
NRect? normalizeLiveBox({
  required double left,
  required double top,
  required double width,
  required double height,
  required int frameWidth,
  required int frameHeight,
  required bool mirror,
}) {
  if (frameWidth <= 0 || frameHeight <= 0 || width <= 0 || height <= 0) {
    return null;
  }
  var l = (left / frameWidth).clamp(0.0, 1.0);
  var r = ((left + width) / frameWidth).clamp(0.0, 1.0);
  final t = (top / frameHeight).clamp(0.0, 1.0);
  final b = ((top + height) / frameHeight).clamp(0.0, 1.0);
  if (mirror) {
    final ml = 1 - r;
    r = 1 - l;
    l = ml;
  }
  if (r <= l || b <= t) return null;
  return NRect(l, t, r - l, b - t);
}

/// Mean luminance (0..1) sampled on a coarse grid.
///
/// [bgra] selects 4-byte BGRA pixels (iOS); otherwise the first
/// `height * bytesPerRow` bytes are read as the Y (luma) plane of an
/// NV21/YUV buffer (Android). Returns `null` if the buffer is too small.
double? meanLuminance(
  Uint8List bytes, {
  required int width,
  required int height,
  required int bytesPerRow,
  required bool bgra,
  int samples = 24,
}) {
  if (width <= 0 || height <= 0 || bytesPerRow <= 0) return null;
  final pixelBytes = bgra ? 4 : 1;
  final need = (height - 1) * bytesPerRow + width * pixelBytes;
  if (bytes.length < need) return null;
  final stepX = math.max(1, width ~/ samples);
  final stepY = math.max(1, height ~/ samples);
  var sum = 0.0;
  var n = 0;
  for (var y = stepY ~/ 2; y < height; y += stepY) {
    final row = y * bytesPerRow;
    for (var x = stepX ~/ 2; x < width; x += stepX) {
      if (bgra) {
        final i = row + x * 4;
        // Rec. 601 luma from B, G, R.
        sum += 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
      } else {
        sum += bytes[row + x];
      }
      n++;
    }
  }
  return n == 0 ? null : sum / n / 255;
}
