// Stage-by-stage timing of the render pipeline on a synthetic 12 MP photo.
// Run: dart run tool/profile.dart   (JIT)  or  dart compile exe tool/profile.dart (AOT).
// Benchmark output is the purpose of this tool.
// ignore_for_file: avoid_print

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/src/filters/enhance.dart';
import 'package:engine_imaging/src/geometry/warp.dart';
import 'package:engine_imaging/src/raster.dart';

void main() {
  const w = 4000;
  const h = 3000;
  final src = Rgb(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = ((y ~/ 12) % 3 == 1) ? 40 : 230 - x ~/ 40;
      final p = (y * w + x) * 3;
      src.data[p] = v;
      src.data[p + 1] = v;
      src.data[p + 2] = v;
    }
  }
  final jpeg = encodeJpeg(src, 90);
  T time<T>(String label, T Function() f) {
    final sw = Stopwatch()..start();
    final r = f();
    print('${label.padRight(22)} ${sw.elapsedMilliseconds} ms');
    return r;
  }

  for (var round = 0; round < 2; round++) {
    print('--- round $round');
    final rgb = time('decode+toRgb', () => decodeRgb(jpeg));
    const quad = Quad(
      NPoint(0.05, 0.04),
      NPoint(0.96, 0.06),
      NPoint(0.94, 0.97),
      NPoint(0.03, 0.95),
    );
    final size = warpSize(quad, rgb.width, rgb.height);
    final small = time(
      'resize to fit',
      () => resizeRgb(
        rgb,
        (rgb.width * 0.78).round(),
        (rgb.height * 0.78).round(),
      ),
    );
    final s2 = warpSize(quad, small.width, small.height);
    final warped = time(
      'warp',
      () => warpPerspective(small, quad, s2.width, s2.height),
    );
    time(
      'filter enhanced',
      () => applyFilter(warped, EnhancementFilter.enhanced),
    );
    time(
      'filter blackWhite',
      () => applyFilter(warped, EnhancementFilter.blackWhite),
    );
    time('rotate', () => rotateQuarterTurns(warped, 1));
    time('encode jpeg q90', () => encodeJpeg(warped, 90));
    time('encode jpeg q78', () => encodeJpeg(warped, 78));
    print('warp size ${size.width}x${size.height} → ${s2.width}x${s2.height}');
  }
}
