import 'dart:typed_data';

/// Otsu's global threshold for an 8-bit gray buffer.
int otsuThreshold(Uint8List gray) {
  final hist = Int32List(256);
  for (final v in gray) {
    hist[v]++;
  }
  final total = gray.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var best = 0.0;
  var threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/// Bradley–Roth adaptive threshold using an integral image. A pixel becomes
/// black when it is [sensitivity] darker than its local mean over a window
/// of about width/[windowDivisor]. Returns 0/255 values.
Uint8List adaptiveThreshold(
  Uint8List gray,
  int width,
  int height, {
  int windowDivisor = 16,
  double sensitivity = 0.15,
}) {
  final integral = Int64List((width + 1) * (height + 1));
  final stride = width + 1;
  for (var y = 0; y < height; y++) {
    var rowSum = 0;
    for (var x = 0; x < width; x++) {
      rowSum += gray[y * width + x];
      integral[(y + 1) * stride + x + 1] =
          integral[y * stride + x + 1] + rowSum;
    }
  }
  final half = ((width > height ? width : height) ~/ windowDivisor) ~/ 2;
  final r = half < 4 ? 4 : half;
  final out = Uint8List(gray.length);
  for (var y = 0; y < height; y++) {
    final y0 = (y - r).clamp(0, height - 1);
    final y1 = (y + r).clamp(0, height - 1);
    for (var x = 0; x < width; x++) {
      final x0 = (x - r).clamp(0, width - 1);
      final x1 = (x + r).clamp(0, width - 1);
      final count = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum =
          integral[(y1 + 1) * stride + x1 + 1] -
          integral[y0 * stride + x1 + 1] -
          integral[(y1 + 1) * stride + x0] +
          integral[y0 * stride + x0];
      final i = y * width + x;
      out[i] = gray[i] * count <= sum * (1 - sensitivity) ? 0 : 255;
    }
  }
  return out;
}
