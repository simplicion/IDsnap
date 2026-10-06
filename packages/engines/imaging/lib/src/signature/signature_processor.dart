import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/filters/illumination.dart';
import 'package:engine_imaging/src/filters/threshold.dart';
import 'package:engine_imaging/src/raster.dart';
import 'package:image/image.dart' as img;

/// Cleans a photographed signature.
///
/// * [cleanSignature] (application kits): removes the paper background and
///   shadows, trims to the ink, fits an exact pixel box on white and
///   compresses under a byte limit.
/// * [extractTransparent] (PRD 3.3, sign PDF): the same ink detection, but
///   the paper becomes transparent and the PNG is cropped tightly to the ink.
///
/// Isolate rule: heavy work runs through top-level functions that receive
/// only plain data (bytes and ints), never closures over this object.
class SignatureProcessorImpl implements SignatureProcessor {
  const SignatureProcessorImpl();

  @override
  Future<Result<EncodedImage>> cleanSignature(
    Uint8List photo, {
    required int width,
    required int height,
    int? maxBytes,
  }) async {
    if (photo.isEmpty) {
      return const Err(
        AppFailure(FailureCode.corruptFile, detail: 'Empty file'),
      );
    }
    if (width < 8 || height < 8) {
      return const Err(
        AppFailure(FailureCode.conversionFailed, detail: 'Output too small'),
      );
    }
    final SignatureOutcome out;
    try {
      out = await _runClean(photo, width, height, maxBytes);
    } on Object catch (e, st) {
      return Err(_signatureFailed(e, st));
    }
    final code = out.failureCode;
    if (code != null) {
      return Err(AppFailure(code, detail: out.failureDetail));
    }
    return Ok(
      EncodedImage(
        bytes: out.bytes!,
        width: width,
        height: height,
        format: ImageOutputFormat.jpeg,
      ),
    );
  }

  @override
  Future<Result<EncodedImage>> extractTransparent(
    Uint8List photo, {
    int maxDimension = 1200,
  }) async {
    if (photo.isEmpty) {
      return const Err(
        AppFailure(FailureCode.corruptFile, detail: 'Empty file'),
      );
    }
    final SignatureOutcome out;
    try {
      out = await _runTransparent(photo, math.max(16, maxDimension));
    } on Object catch (e, st) {
      return Err(_signatureFailed(e, st));
    }
    final code = out.failureCode;
    if (code != null) {
      return Err(
        AppFailure(
          code,
          detail: out.failureDetail,
          message: code == FailureCode.documentNotDetected
              ? 'No ink was found. Sign on plain white paper with a dark '
                    'pen, fill the frame and avoid shadows.'
              : null,
        ),
      );
    }
    return Ok(
      EncodedImage(
        bytes: out.bytes!,
        width: out.width!,
        height: out.height!,
        format: ImageOutputFormat.png,
      ),
    );
  }
}

/// Sendable result of [cleanSignatureSync] and
/// [extractTransparentSignatureSync].
class SignatureOutcome {
  const SignatureOutcome.ok(Uint8List this.bytes, {this.width, this.height})
    : failureCode = null,
      failureDetail = null;

  const SignatureOutcome.failed(
    FailureCode this.failureCode, [
    this.failureDetail,
  ]) : bytes = null,
       width = null,
       height = null;

  final Uint8List? bytes;

  /// Pixel size of [bytes]; set by the transparent mode.
  final int? width;
  final int? height;
  final FailureCode? failureCode;
  final String? failureDetail;
}

// Top-level so the isolate closure captures only its parameters.
Future<SignatureOutcome> _runClean(
  Uint8List photo,
  int width,
  int height,
  int? maxBytes,
) => runHeavy(() => cleanSignatureSync(photo, width, height, maxBytes));

Future<SignatureOutcome> _runTransparent(Uint8List photo, int maxDimension) =>
    runHeavy(() => extractTransparentSignatureSync(photo, maxDimension));

/// Longest edge processed; larger photos are downscaled first.
const _workDimension = 1800;

/// Fraction of pixels that must be ink for a signature to count.
const _minInkFraction = 0.0004;

const _noSignature = SignatureOutcome.failed(
  FailureCode.documentNotDetected,
  'No signature found',
);

/// Synchronous signature cleanup. Never throws; failures are returned.
SignatureOutcome cleanSignatureSync(
  Uint8List photo,
  int width,
  int height,
  int? maxBytes,
) {
  try {
    final found = _detectInk(fitWithin(decodeRgb(photo), _workDimension));
    if (found == null) return _noSignature;
    final InkMask(:w, :h, :norm, :ink, :minX, :minY, :maxX, :maxY) = found;

    // Trim to ink with 6% padding.
    final pad = (math.max(maxX - minX, maxY - minY) * 0.06).round() + 1;
    final cx0 = math.max(0, minX - pad);
    final cy0 = math.max(0, minY - pad);
    final cx1 = math.min(w - 1, maxX + pad);
    final cy1 = math.min(h - 1, maxY + pad);
    final cw = cx1 - cx0 + 1;
    final ch = cy1 - cy0 + 1;

    // Clean crop: ink keeps a darkened tone (anti-aliasing), paper is white.
    final crop = Uint8List(cw * ch);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final i = (cy0 + y) * w + cx0 + x;
        crop[y * cw + x] = ink[i] == 1 ? (norm[i] * 0.35).round() : 255;
      }
    }

    // Fit into the requested box, centered on white.
    final scale = math.min(width / cw, height / ch);
    final dw = math.max(1, (cw * scale).round());
    final dh = math.max(1, (ch * scale).round());
    final scaled = resizeRgb(Rgb.fromGray(crop, cw, ch), dw, dh);
    final canvas = Rgb(width, height)
      ..data.fillRange(0, width * height * 3, 255);
    final ox = (width - dw) ~/ 2;
    final oy = (height - dh) ~/ 2;
    for (var y = 0; y < dh; y++) {
      final src = y * dw * 3;
      final dst = ((oy + y) * width + ox) * 3;
      canvas.data.setRange(dst, dst + dw * 3, scaled.data, src);
    }

    var best = encodeJpeg(canvas, 95);
    if (maxBytes != null) {
      for (var q = 85; best.length > maxBytes && q >= 30; q -= 10) {
        best = encodeJpeg(canvas, q);
      }
    }
    return SignatureOutcome.ok(best);
  } on AppFailure catch (f) {
    return SignatureOutcome.failed(f.code, f.detail);
    // Large photos on low-memory devices must fail softly, not crash.
    // ignore: avoid_catching_errors
  } on OutOfMemoryError {
    return const SignatureOutcome.failed(FailureCode.memoryLimitExceeded);
  } on Object {
    return const SignatureOutcome.failed(FailureCode.corruptFile);
  }
}

/// Synchronous transparent signature extraction (PRD 3.3). Never throws.
///
/// * Paper becomes alpha 0; alpha rises with ink darkness between the paper
///   level and the ink level (auto-contrast), so stroke edges stay smooth.
/// * Every pixel takes one ink colour — the average of the core ink, kept
///   dark enough to read — so paper tint never bleeds into the strokes.
/// * The output is cropped tightly to the visible ink and scaled so its
///   longest edge is at most [maxDimension].
SignatureOutcome extractTransparentSignatureSync(
  Uint8List photo,
  int maxDimension,
) {
  try {
    final found = _detectInk(fitWithin(decodeRgb(photo), _workDimension));
    if (found == null) return _noSignature;
    final alpha = inkAlpha(found);

    // Tight crop to the visible ink with a hairline margin.
    final box = alphaBounds(alpha, found.w, found.h);
    if (box == null) return _noSignature;
    final pad = math.max(2, (math.max(box.width, box.height) * 0.02).round());
    final x0 = math.max(0, box.left - pad);
    final y0 = math.max(0, box.top - pad);
    final x1 = math.min(found.w - 1, box.right + pad);
    final y1 = math.min(found.h - 1, box.bottom + pad);
    var cw = x1 - x0 + 1;
    var ch = y1 - y0 + 1;
    var cropped = Uint8List(cw * ch);
    for (var y = 0; y < ch; y++) {
      final src = (y0 + y) * found.w + x0;
      cropped.setRange(y * cw, (y + 1) * cw, alpha, src);
    }

    final longest = math.max(cw, ch);
    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      final dw = math.max(1, (cw * scale).round());
      final dh = math.max(1, (ch * scale).round());
      final scaled = resizeRgb(Rgb.fromGray(cropped, cw, ch), dw, dh);
      cropped = Uint8List(dw * dh);
      for (var i = 0, p = 0; i < cropped.length; i++, p += 3) {
        cropped[i] = scaled.data[p];
      }
      cw = dw;
      ch = dh;
    }

    final (r, g, b) = inkColour(found);
    final png = encodeRgbaPng(cropped, cw, ch, r, g, b);
    return SignatureOutcome.ok(png, width: cw, height: ch);
  } on AppFailure catch (f) {
    return SignatureOutcome.failed(f.code, f.detail);
    // Large photos on low-memory devices must fail softly, not crash.
    // ignore: avoid_catching_errors
  } on OutOfMemoryError {
    return const SignatureOutcome.failed(FailureCode.memoryLimitExceeded);
  } on Object {
    return const SignatureOutcome.failed(FailureCode.corruptFile);
  }
}

/// Ink pixels of a signature photo, after illumination normalisation.
class InkMask {
  const InkMask({
    required this.w,
    required this.h,
    required this.rgb,
    required this.norm,
    required this.ink,
    required this.inkCount,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final int w;
  final int h;
  final Rgb rgb;

  /// Illumination-normalised gray (paper ≈ 255).
  final Uint8List norm;

  /// 1 where a pixel is ink.
  final Uint8List ink;
  final int inkCount;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
}

/// Finds ink: locally dark AND globally darkish, which removes paper texture
/// and shadows. Null when there is too little ink to be a signature.
InkMask? _detectInk(Rgb rgb) {
  final w = rgb.width;
  final h = rgb.height;
  final norm = normalizeGray(rgb.luma(), w, h);
  final local = adaptiveThreshold(norm, w, h, sensitivity: 0.22);
  final global = otsuThreshold(norm);
  final darkLimit = math.min(global, 190);
  final ink = Uint8List(w * h);
  var inkCount = 0;
  var minX = w;
  var minY = h;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (local[i] == 0 && norm[i] < darkLimit) {
        ink[i] = 1;
        inkCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (inkCount < w * h * _minInkFraction || maxX < 0) return null;
  return InkMask(
    w: w,
    h: h,
    rgb: rgb,
    norm: norm,
    ink: ink,
    inkCount: inkCount,
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
  );
}

/// Alpha (0–255) per pixel from ink darkness. Only pixels within 2 px of
/// detected ink can be visible, so paper texture and specks stay clear.
Uint8List inkAlpha(InkMask m) {
  final w = m.w;
  final h = m.h;
  // Paper and ink levels from histograms (auto-contrast).
  final paperHist = List<int>.filled(256, 0);
  final inkHist = List<int>.filled(256, 0);
  var paperCount = 0;
  for (var i = 0; i < m.norm.length; i++) {
    if (m.ink[i] == 1) {
      inkHist[m.norm[i]]++;
    } else {
      paperHist[m.norm[i]]++;
      paperCount++;
    }
  }
  final paper = math.max(_percentile(paperHist, paperCount, 0.5), 60);
  final inkLevel = math.min(_percentile(inkHist, m.inkCount, 0.25), paper - 40);
  final range = (paper - inkLevel).toDouble();

  // Dilate the ink mask by 2 px (separable max) to keep anti-aliased edges.
  final rows = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 0;
      for (var dx = -2; dx <= 2 && v == 0; dx++) {
        final xx = x + dx;
        if (xx >= 0 && xx < w) v = m.ink[y * w + xx];
      }
      rows[y * w + x] = v;
    }
  }
  final alpha = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var near = false;
      for (var dy = -2; dy <= 2 && !near; dy++) {
        final yy = y + dy;
        if (yy >= 0 && yy < h) near = rows[yy * w + x] == 1;
      }
      if (!near) continue;
      final i = y * w + x;
      final t = ((paper - m.norm[i]) / range).clamp(0.0, 1.0);
      // A gentle curve makes strokes solid without hard edges.
      final a = math.pow(t, 0.7) * 255;
      alpha[i] = a < 20 ? 0 : a.round();
    }
  }
  return alpha;
}

/// Average colour of the core ink, darkened so light pens still read well.
(int, int, int) inkColour(InkMask m) {
  // Only the darker half of the ink: edge pixels are mixed with paper.
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < m.ink.length; i++) {
    if (m.ink[i] == 1) hist[m.norm[i]]++;
  }
  final threshold = _percentile(hist, m.inkCount, 0.5);
  var r = 0;
  var g = 0;
  var b = 0;
  var n = 0;
  for (var i = 0, p = 0; i < m.ink.length; i++, p += 3) {
    if (m.ink[i] == 1 && m.norm[i] <= threshold) {
      r += m.rgb.data[p];
      g += m.rgb.data[p + 1];
      b += m.rgb.data[p + 2];
      n++;
    }
  }
  if (n == 0) return (0, 0, 0);
  var rr = r / n;
  var gg = g / n;
  var bb = b / n;
  const maxLuma = 70.0;
  final luma = 0.299 * rr + 0.587 * gg + 0.114 * bb;
  if (luma > maxLuma) {
    final k = maxLuma / luma;
    rr *= k;
    gg *= k;
    bb *= k;
  }
  return (rr.round(), gg.round(), bb.round());
}

int _percentile(List<int> hist, int total, double q) {
  if (total <= 0) return 0;
  final target = total * q;
  var acc = 0;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= target) return v;
  }
  return 255;
}

/// Inclusive pixel bounds of alpha > [threshold], or null when fully clear.
({int left, int top, int right, int bottom, int width, int height})?
alphaBounds(Uint8List alpha, int width, int height, {int threshold = 0}) {
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      if (alpha[row + x] > threshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return (
    left: minX,
    top: minY,
    right: maxX,
    bottom: maxY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

/// PNG of a single colour with a per-pixel alpha channel.
Uint8List encodeRgbaPng(
  Uint8List alpha,
  int width,
  int height,
  int r,
  int g,
  int b,
) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0, p = 0; i < alpha.length; i++, p += 4) {
    rgba[p] = r;
    rgba[p + 1] = g;
    rgba[p + 2] = b;
    rgba[p + 3] = alpha[i];
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return img.encodePng(image);
}

/// 0..1 score of how plain the outer 10% border of a photo is (1 = perfectly
/// uniform). Used only as a *hint* ("background may not be plain") for visa
/// photos — never as a compliance check.
Future<double?> backgroundUniformity(Uint8List jpeg) =>
    runHeavy(() => backgroundUniformitySync(jpeg));

/// Synchronous [backgroundUniformity]; returns null when undecodable.
double? backgroundUniformitySync(Uint8List jpeg) {
  try {
    final rgb = fitWithin(decodeRgb(jpeg), 256);
    final w = rgb.width;
    final h = rgb.height;
    final gray = rgb.luma();
    final bx = math.max(1, (w * 0.1).round());
    final by = math.max(1, (h * 0.1).round());
    var n = 0;
    var sum = 0.0;
    var sumSq = 0.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x >= bx && x < w - bx && y >= by && y < h - by) continue;
        final v = gray[y * w + x].toDouble();
        n++;
        sum += v;
        sumSq += v * v;
      }
    }
    if (n == 0) return null;
    final mean = sum / n;
    final std = math.sqrt(math.max(0, sumSq / n - mean * mean));
    return (1 - std / 64).clamp(0.0, 1.0);
  } on Object {
    return null;
  }
}

/// A signature photo that couldn't be cleaned up for an unexpected reason
/// (audit M-04: specific title and next step, not "Something went wrong").
AppFailure _signatureFailed(Object e, StackTrace st) => AppFailure(
  FailureCode.unknown,
  cause: e,
  stackTrace: st,
  heading: "The signature couldn't be cleaned up",
  message:
      'Nothing was saved. Take a new photo of the signature on plain white '
      'paper in good light, or choose another photo.',
  action: FailureAction.retry,
);
