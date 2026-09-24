import 'dart:typed_data';

import 'package:engine_imaging/src/raster.dart';

/// Low-resolution estimate of the paper (background) brightness of one
/// channel: downsample 1/[factor] (mean) → morphological closing (max then
/// min filter) to erase dark ink without biasing gradients → box blur.
class Background {
  Background._(this.width, this.height, this.factor, this.values);

  factory Background.estimate(
    Uint8List channel,
    int width,
    int height, {
    int factor = 8,
    int closeRadius = 3,
    int blurRadius = 3,
  }) {
    final w = (width + factor - 1) ~/ factor;
    final h = (height + factor - 1) ~/ factor;
    final sums = Float32List(w * h);
    final counts = Int32List(w * h);
    for (var y = 0; y < height; y++) {
      final row = (y ~/ factor) * w;
      final base = y * width;
      for (var x = 0; x < width; x++) {
        final b = row + x ~/ factor;
        sums[b] += channel[base + x];
        counts[b]++;
      }
    }
    var small = Float32List(w * h);
    for (var i = 0; i < small.length; i++) {
      small[i] = counts[i] == 0 ? 255 : sums[i] / counts[i];
    }
    small = _separable(small, w, h, closeRadius, _Op.max);
    small = _separable(small, w, h, closeRadius, _Op.min);
    small = _separable(small, w, h, blurRadius, _Op.mean);
    return Background._(w, h, factor, small);
  }

  final int width;
  final int height;
  final int factor;
  final Float32List values;

  /// Upsamples to full resolution one row at a time (bilinear), calling
  /// [onRow] with the background values of row y.
  void forEachRow(
    int fullWidth,
    int fullHeight,
    void Function(int y, Float32List row) onRow,
  ) {
    final x0 = Int32List(fullWidth);
    final x1 = Int32List(fullWidth);
    final ax = Float32List(fullWidth);
    for (var x = 0; x < fullWidth; x++) {
      var fx = (x + 0.5) / factor - 0.5;
      if (fx < 0) fx = 0;
      if (fx > width - 1) fx = width - 1.0;
      x0[x] = fx.toInt();
      x1[x] = x0[x] + 1 < width ? x0[x] + 1 : x0[x];
      ax[x] = fx - x0[x];
    }
    final row = Float32List(fullWidth);
    for (var y = 0; y < fullHeight; y++) {
      var fy = (y + 0.5) / factor - 0.5;
      if (fy < 0) fy = 0;
      if (fy > height - 1) fy = height - 1.0;
      final y0 = fy.toInt();
      final y1 = y0 + 1 < height ? y0 + 1 : y0;
      final ay = fy - y0;
      final r0 = y0 * width;
      final r1 = y1 * width;
      for (var x = 0; x < fullWidth; x++) {
        final a = ax[x];
        final top = values[r0 + x0[x]] * (1 - a) + values[r0 + x1[x]] * a;
        final bottom = values[r1 + x0[x]] * (1 - a) + values[r1 + x1[x]] * a;
        row[x] = top + (bottom - top) * ay;
      }
      onRow(y, row);
    }
  }

  static Float32List _separable(
    Float32List src,
    int w,
    int h,
    int radius,
    _Op op,
  ) {
    final tmp = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        tmp[y * w + x] = _reduce(src, y * w, x, w, radius, 1, op);
      }
    }
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[y * w + x] = _reduce(tmp, x, y, h, radius, w, op);
      }
    }
    return out;
  }

  static double _reduce(
    Float32List v,
    int base,
    int center,
    int length,
    int radius,
    int stride,
    _Op op,
  ) {
    final start = center - radius < 0 ? 0 : center - radius;
    final end = center + radius >= length ? length - 1 : center + radius;
    var acc = op == _Op.min ? double.infinity : (op == _Op.max ? -1.0 : 0.0);
    for (var i = start; i <= end; i++) {
      final x = v[base + i * stride];
      switch (op) {
        case _Op.max:
          if (x > acc) acc = x;
        case _Op.min:
          if (x < acc) acc = x;
        case _Op.mean:
          acc += x;
      }
    }
    return op == _Op.mean ? acc / (end - start + 1) : acc;
  }
}

enum _Op { max, min, mean }

/// Divides each channel by its own background so paper becomes white and
/// shadows / color casts are flattened. Returns a new image.
Rgb normalizeIllumination(Rgb src) {
  final n = src.width * src.height;
  final out = Rgb(src.width, src.height);
  final channel = Uint8List(n);
  for (var c = 0; c < 3; c++) {
    for (var i = 0, p = c; i < n; i++, p += 3) {
      channel[i] = src.data[p];
    }
    Background.estimate(channel, src.width, src.height).forEachRow(
      src.width,
      src.height,
      (y, bg) {
        final base = y * src.width;
        for (var x = 0; x < src.width; x++) {
          final b = bg[x];
          final v = channel[base + x];
          final o = (base + x) * 3 + c;
          if (b < 8) {
            out.data[o] = v;
          } else {
            final r = (v * 255 / b).round();
            out.data[o] = r > 255 ? 255 : r;
          }
        }
      },
    );
  }
  return out;
}

/// Same as [normalizeIllumination] for a single gray channel.
Uint8List normalizeGray(Uint8List gray, int width, int height) {
  final out = Uint8List(gray.length);
  Background.estimate(gray, width, height).forEachRow(width, height, (y, bg) {
    final base = y * width;
    for (var x = 0; x < width; x++) {
      final b = bg[x];
      final v = gray[base + x];
      if (b < 8) {
        out[base + x] = v;
      } else {
        final r = (v * 255 / b).round();
        out[base + x] = r > 255 ? 255 : r;
      }
    }
  });
  return out;
}
