import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// RGBA raster: dark background, white page inset by 10% on each side.
DecodedRaster pageRaster(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inside = x >= w * 0.1 && x < w * 0.9 && y >= h * 0.1 && y < h * 0.9;
      final v = inside ? 250 : 30;
      final p = (y * w + x) * 4;
      rgba
        ..[p] = v
        ..[p + 1] = v
        ..[p + 2] = v
        ..[p + 3] = 255;
    }
  }
  return DecodedRaster(rgba: rgba, width: w, height: h);
}

class FakeDecoder {
  FakeDecoder(this.raster);

  final DecodedRaster? raster;
  final requested = <int?>[];

  Future<DecodedRaster?> call(Uint8List encoded, {int? maxDimension}) async {
    requested.add(maxDimension);
    return raster;
  }
}

/// Bytes package:image cannot decode: success proves the decoder was used.
final undecodable = Uint8List.fromList(List.filled(256, 7));

const pageQuad = Quad(
  NPoint(0.1, 0.1),
  NPoint(0.9, 0.1),
  NPoint(0.9, 0.9),
  NPoint(0.1, 0.9),
);

void main() {
  test('renderPage uses the injected decoder with warp headroom', () async {
    final fake = FakeDecoder(pageRaster(1000, 750));
    final engine = ImagingEngine(decoder: fake.call);
    final r = await engine.renderPage(
      undecodable,
      const PageEdits(quad: pageQuad, filter: EnhancementFilter.original),
    );
    expect(fake.requested, [
      (QualityPreset.balanced.maxDimension * 1.25).ceil(),
    ]);
    final out = img.decodeJpg(r.valueOrNull!)!;
    // 80% of 1000×750, no upscaling beyond the decoded source.
    expect(out.width, closeTo(800, 2));
    expect(out.height, closeTo(600, 2));
    var white = 0;
    for (final p in out) {
      if (p.luminance > 200) white++;
    }
    expect(white / (out.width * out.height), greaterThan(0.97));
  });

  test('detect and thumbnail request their own decode sizes', () async {
    final fake = FakeDecoder(pageRaster(640, 480));
    final engine = ImagingEngine(decoder: fake.call);
    final d = (await engine.detectDocument(undecodable)).valueOrNull!;
    expect(d.isConfident, isTrue);
    expect(d.quad.topLeft.x, closeTo(0.1, 0.03));
    final t = (await engine.thumbnail(
      undecodable,
      maxDimension: 200,
    )).valueOrNull!;
    final thumb = img.decodeJpg(t)!;
    expect((thumb.width, thumb.height), (200, 150));
    expect(fake.requested, [ImagingEngine.detectDecodeSize, 200]);
  });

  test('transparent pixels are composited onto white', () async {
    final raster = DecodedRaster(
      rgba: Uint8List(4 * 4 * 4),
      width: 4,
      height: 4,
    );
    final rgb = RasterSource.decoded(raster).toRgb();
    expect(rgb.data.every((v) => v == 255), isTrue);
  });

  test(
    'falls back to package:image when the decoder returns null or throws',
    () async {
      final png = img.encodePng(
        img.Image(width: 40, height: 30)..clear(img.ColorRgb8(200, 10, 10)),
      );
      final nullEngine = ImagingEngine(decoder: FakeDecoder(null).call);
      expect((await nullEngine.thumbnail(png, maxDimension: 20)).isOk, isTrue);

      final throwing = ImagingEngine(
        decoder: (bytes, {maxDimension}) async => throw StateError('codec'),
      );
      final r = await throwing.compress(png, const ImageCompressionOptions());
      expect((r.valueOrNull!.width, r.valueOrNull!.height), (40, 30));

      final bad = await nullEngine.renderPage(undecodable, const PageEdits());
      expect(bad.failureOrNull?.code, FailureCode.corruptFile);
    },
  );

  test(
    'decoder-path render benchmark (balanced, decode excluded)',
    tags: 'bench',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      const preset = QualityPreset.balanced;
      final size = ImagingEngine.renderDecodeSize(preset);
      final raster = pageRaster(size, (size * 0.75).round());
      final engine = ImagingEngine(decoder: FakeDecoder(raster).call);
      const skewed = Quad(
        NPoint(0.05, 0.04),
        NPoint(0.96, 0.06),
        NPoint(0.94, 0.97),
        NPoint(0.03, 0.95),
      );
      for (final f in EnhancementFilter.values) {
        final sw = Stopwatch()..start();
        final r = await engine.renderPage(
          undecodable,
          PageEdits(quad: skewed, filter: f),
        );
        sw.stop();
        expect(r.isOk, isTrue);
        // Benchmark output is the point of this test.
        // ignore: avoid_print
        print(
          'decoder path ${raster.width}x${raster.height} ${f.name}: ${sw.elapsedMilliseconds} ms',
        );
      }
      final sw = Stopwatch()..start();
      await ImagingEngine(
        decoder: FakeDecoder(pageRaster(640, 480)).call,
      ).detectDocument(undecodable);
      // Benchmark output is the point of this test.
      // ignore: avoid_print
      print('decoder path detect 640x480: ${sw.elapsedMilliseconds} ms');
    },
  );
}
