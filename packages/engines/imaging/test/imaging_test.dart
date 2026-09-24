import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_imaging/src/filters/enhance.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

const engine = ImagingEngine();

/// Dark background with a white convex polygon, encoded as PNG.
Uint8List polygonImage(int w, int h, List<List<double>> corners) {
  final image = img.Image(width: w, height: h)
    ..clear(img.ColorRgb8(40, 45, 50));
  img.fillPolygon(
    image,
    vertices: [for (final c in corners) img.Point(c[0], c[1])],
    color: img.ColorRgb8(245, 245, 240),
  );
  return img.encodePng(image);
}

/// A "document": off-white page, shadow gradient, dark text bars.
Rgb syntheticPage(int w, int h) {
  final rgb = Rgb(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final shade = 1 - 0.45 * (x / w); // shadow toward the right
      var v = (235 * shade).round();
      final line = (y ~/ 12) % 3 == 1 && x > w * 0.1 && x < w * 0.9;
      if (line) v = (40 * shade).round();
      final p = (y * w + x) * 3;
      rgb.data[p] = v;
      rgb.data[p + 1] = v;
      rgb.data[p + 2] = (v * 0.95).round();
    }
  }
  return rgb;
}

img.Image decode(List<int> bytes) =>
    img.decodeImage(Uint8List.fromList(bytes))!;

void main() {
  test('homography maps the four corners exactly', () {
    final from = [
      [0.0, 0.0],
      [100.0, 0.0],
      [100.0, 50.0],
      [0.0, 50.0],
    ];
    final to = [
      [12.0, 7.0],
      [140.0, 20.0],
      [120.0, 90.0],
      [5.0, 70.0],
    ];
    final h = Homography.fromPoints(from, to);
    for (var i = 0; i < 4; i++) {
      final m = h.map(from[i][0], from[i][1]);
      expect(m[0], closeTo(to[i][0], 1e-9));
      expect(m[1], closeTo(to[i][1], 1e-9));
    }
    expect(
      () => Homography.fromPoints(from, [
        for (final _ in to) [1.0, 1.0],
      ]),
      throwsArgumentError,
    );
  });

  test('warps a skewed page into a mostly-white rectangle', () async {
    const w = 400;
    const h = 300;
    final corners = [
      [60.0, 40.0],
      [340.0, 70.0],
      [320.0, 260.0],
      [80.0, 240.0],
    ];
    final bytes = polygonImage(w, h, corners);
    final quad = Quad(
      NPoint(corners[0][0] / w, corners[0][1] / h),
      NPoint(corners[1][0] / w, corners[1][1] / h),
      NPoint(corners[2][0] / w, corners[2][1] / h),
      NPoint(corners[3][0] / w, corners[3][1] / h),
    );
    final result = await engine.renderPage(
      bytes,
      PageEdits(quad: quad, filter: EnhancementFilter.original),
    );
    final out = decode(result.valueOrNull!);
    var white = 0;
    for (final p in out) {
      if (p.luminance > 180) white++;
    }
    expect(white / (out.width * out.height), greaterThan(0.93));
    expect(out.width, greaterThan(out.height));
  });

  group('detectDocument', () {
    test('finds a rotated page within 3%', () async {
      const w = 400;
      const h = 300;
      const angle = 12 * math.pi / 180;
      final c = [200.0, 150.0];
      final corners = [
        for (final (dx, dy) in [(-120, -80), (120, -80), (120, 80), (-120, 80)])
          [
            c[0] + dx * math.cos(angle) - dy * math.sin(angle),
            c[1] + dx * math.sin(angle) + dy * math.cos(angle),
          ],
      ];
      final result = await engine.detectDocument(polygonImage(w, h, corners));
      final detected = result.valueOrNull!;
      expect(
        detected.confidence,
        greaterThanOrEqualTo(DetectedQuad.acceptThreshold),
      );
      for (var i = 0; i < 4; i++) {
        final p = detected.quad.points[i];
        expect(p.x, closeTo(corners[i][0] / w, 0.03), reason: 'corner $i x');
        expect(p.y, closeTo(corners[i][1] / h, 0.03), reason: 'corner $i y');
      }
    });

    test('reports low confidence on noise', () async {
      final rnd = math.Random(7);
      final image = img.Image(width: 320, height: 240);
      for (final p in image) {
        final v = rnd.nextInt(256);
        p.setRgb(v, v, v);
      }
      final result = await engine.detectDocument(img.encodePng(image));
      expect(
        result.valueOrNull!.confidence,
        lessThan(DetectedQuad.acceptThreshold),
      );
    });
  });

  group('filters', () {
    final page = syntheticPage(300, 200);

    test('every filter renders', () async {
      final bytes = encodeJpeg(page, 95);
      for (final f in EnhancementFilter.values) {
        final r = await engine.renderPage(
          bytes,
          PageEdits(filter: f, quarterTurns: 1),
        );
        final out = decode(r.valueOrNull!);
        expect(out.width, 200, reason: f.name); // rotated 90°
        expect(out.height, 300, reason: f.name);
      }
    });

    test('black & white output is strictly binary', () {
      final out = applyFilter(page, EnhancementFilter.blackWhite);
      expect(out.data.every((v) => v == 0 || v == 255), isTrue);
      final black = out.data.where((v) => v == 0).length / out.data.length;
      expect(black, inInclusiveRange(0.15, 0.5)); // text kept, shadow gone
    });

    test('shadow removal flattens the paper', () {
      final out = applyFilter(page, EnhancementFilter.noShadow);
      // Paper pixels at the left and right edges (row 0 is paper).
      final left = out.data[(0 * 300 + 5) * 3];
      final right = out.data[(0 * 300 + 294) * 3];
      expect((left - right).abs(), lessThan(20));
      expect(
        page.data[(0 * 300 + 5) * 3] - page.data[(0 * 300 + 294) * 3],
        greaterThan(80),
      );
    });

    test('filters never mutate their input', () {
      final copy = Uint8List.fromList(page.data);
      for (final f in EnhancementFilter.values) {
        applyFilter(page, f);
      }
      expect(page.data, copy);
    });
  });

  test('compress meets a target size', () async {
    final rnd = math.Random(3);
    final image = img.Image(width: 1200, height: 900);
    for (final p in image) {
      p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
    const target = 60 * 1024;
    final r = await engine.compress(
      img.encodePng(image),
      const ImageCompressionOptions(targetBytes: target, quality: 90),
    );
    final out = r.valueOrNull!;
    expect(out.bytes.length, lessThanOrEqualTo(target));
    expect(out.format, ImageOutputFormat.jpeg);
  });

  test('crop to passport preset yields exact pixel size', () async {
    final bytes = encodeJpeg(syntheticPage(800, 600), 90);
    const preset = CropPreset.passportIntl;
    final rect = NRect.centeredWithAspect(preset.aspect, 800, 600);
    final r = await engine.crop(
      bytes,
      rect,
      outputWidth: preset.pixelWidth,
      outputHeight: preset.pixelHeight,
    );
    final out = r.valueOrNull!;
    expect((out.width, out.height), (413, 531));
    final decoded = decode(out.bytes);
    expect((decoded.width, decoded.height), (413, 531));
  });

  group('inspect', () {
    test('reads dimensions', () async {
      final r = await engine.inspect(encodePng(syntheticPage(120, 80)));
      expect((r.valueOrNull!.width, r.valueOrNull!.height), (120, 80));
    });

    test('rejects garbage and HEIC', () async {
      final garbage = await engine.inspect(
        Uint8List.fromList(List.filled(64, 7)),
      );
      expect(garbage.failureOrNull?.code, FailureCode.corruptFile);
      final heic = Uint8List.fromList([
        0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, //
        ...'heic'.codeUnits, 0, 0, 0, 0,
      ]);
      final r = await engine.inspect(heic);
      expect(r.failureOrNull?.code, FailureCode.unsupportedFormat);
      final render = await engine.renderPage(heic, const PageEdits());
      expect(render.failureOrNull?.code, FailureCode.unsupportedFormat);
    });
  });

  test(
    'render benchmark (3000px)',
    tags: 'bench',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final bytes = encodeJpeg(syntheticPage(4000, 3000), 90);
      const quad = Quad(
        NPoint(0.05, 0.04),
        NPoint(0.96, 0.06),
        NPoint(0.94, 0.97),
        NPoint(0.03, 0.95),
      );
      for (final f in [
        EnhancementFilter.original,
        EnhancementFilter.enhanced,
        EnhancementFilter.blackWhite,
      ]) {
        final sw = Stopwatch()..start();
        final r = await engine.renderPage(
          bytes,
          PageEdits(quad: quad, filter: f),
          preset: QualityPreset.high,
        );
        sw.stop();
        expect(r.isOk, isTrue);
        // Benchmark output is the point of this test.
        // Benchmark output is the point of this test.
        // ignore: avoid_print
        print(
          'render ${f.name} 4000x3000 → 3000px: ${sw.elapsedMilliseconds} ms',
        );
      }
      final sw = Stopwatch()..start();
      await engine.detectDocument(bytes);
      // Benchmark output is the point of this test.
      // ignore: avoid_print
      print('detect 4000x3000: ${sw.elapsedMilliseconds} ms');
    },
  );
}
