import 'dart:math' as math;

import 'package:docscan_domain/src/entities/crop_preset.dart';
import 'package:docscan_domain/src/entities/geometry.dart';

/// Computes a crop rectangle that frames a face the way photo-ID rules
/// typically require: head (chin to crown) filling [CropPreset.headRatio] of
/// the photo height, horizontally centered, with a small margin above.
///
/// [face] is a detector box (roughly brow-to-chin), normalized to an image of
/// [imageWidth] × [imageHeight] pixels. Returns `null` when the preset isn't a
/// portrait preset. The result keeps the preset aspect ratio in *pixels* and
/// is clamped inside the image (shrinking if the photo is too tight).
NRect? autoFramePortrait({
  required NRect face,
  required CropPreset preset,
  required int imageWidth,
  required int imageHeight,
}) {
  final headRatio = preset.headRatio;
  if (headRatio == null) return null;

  // Work in pixels so the aspect ratio is exact.
  final faceTop = face.top * imageHeight;
  final faceH = face.height * imageHeight;
  final faceCx = (face.left + face.width / 2) * imageWidth;

  // Detector boxes stop around the brow; the full head (to the crown) is
  // about 1.3× taller, extending upward.
  const crownFactor = 1.3;
  final headH = faceH * crownFactor;
  final headTop = faceTop + faceH - headH;

  var cropH = headH / headRatio;
  var cropW = cropH * preset.aspect;

  // Too big for the image: shrink uniformly (head will be a bit larger).
  final fit = math.min(1, math.min(imageWidth / cropW, imageHeight / cropH));
  cropW *= fit;
  cropH *= fit;

  // Crown sits ~8–10% below the top edge.
  var top = headTop - cropH * preset.topMarginRatio;
  var left = faceCx - cropW / 2;
  left = left.clamp(0, imageWidth - cropW).toDouble();
  top = top.clamp(0, imageHeight - cropH).toDouble();

  return NRect(
    left / imageWidth,
    top / imageHeight,
    cropW / imageWidth,
    cropH / imageHeight,
  );
}
