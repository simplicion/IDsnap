import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// Shaded paper with a blue-black scribble in a known box
/// (x 200..700, y 230..390 before any padding).
Uint8List _photo({bool withInk = true}) {
  final im = img.Image(width: 900, height: 600);
  for (final p in im) {
    final v = 170 + (p.x / 900 * 60).round();
    p
      ..r = v
      ..g = v
      ..b = v - 4;
  }
  if (withInk) {
    for (var x = 204; x < 696; x++) {
      final y = 300 + (math.sin(x / 25) * 60).round();
      img.fillCircle(
        im,
        x: x,
        y: y,
        radius: 4,
        color: img.ColorRgb8(20, 30, 110),
      );
    }
  }
  return img.encodePng(im);
}

void main() {
  const processor = SignatureProcessorImpl();

  group('transparent signature', () {
    test('paper is transparent, ink opaque, tightly cropped', () async {
      final r = await processor.extractTransparent(_photo());
      expect(r.failureOrNull, isNull);
      final out = r.valueOrNull!;
      expect(out.format, ImageOutputFormat.png);
      final png = img.decodePng(Uint8List.fromList(out.bytes))!;
      expect(png.numChannels, 4);
      expect((png.width, png.height), (out.width, out.height));

      // Corners are paper: fully transparent.
      for (final (x, y) in [
        (0, 0),
        (png.width - 1, 0),
        (0, png.height - 1),
        (png.width - 1, png.height - 1),
      ]) {
        expect(png.getPixel(x, y).a, 0, reason: 'corner ($x,$y)');
      }

      // Tight crop: the scribble spans ~500 x ~130 px in the photo.
      expect(png.width, inInclusiveRange(440, 530));
      expect(png.height, inInclusiveRange(100, 160));

      // Ink pixels are opaque and keep a blue-ish dark colour.
      var opaque = 0;
      img.Pixel? sample;
      for (final p in png) {
        if (p.a >= 250) {
          opaque++;
          sample ??= p;
        }
      }
      expect(opaque, greaterThan(png.width * 4));
      expect(sample!.b, greaterThan(sample.r));
      expect(
        0.299 * sample.r + 0.587 * sample.g + 0.114 * sample.b,
        lessThan(90),
      );
    });

    test('respects maxDimension', () async {
      final r = await processor.extractTransparent(_photo(), maxDimension: 200);
      final out = r.valueOrNull!;
      expect(math.max(out.width, out.height), 200);
      final png = img.decodePng(Uint8List.fromList(out.bytes))!;
      expect(png.getPixel(0, 0).a, 0);
    });

    test('blank paper fails with actionable copy', () async {
      final r = await processor.extractTransparent(_photo(withInk: false));
      final f = r.failureOrNull!;
      expect(f.code, FailureCode.documentNotDetected);
      expect(f.recovery, contains('dark pen'));
    });

    test('garbage and empty input fail typed', () async {
      expect(
        (await processor.extractTransparent(Uint8List(0))).failureOrNull?.code,
        FailureCode.corruptFile,
      );
      expect(
        (await processor.extractTransparent(
          Uint8List.fromList([1, 2, 3, 4]),
        )).failureOrNull?.code,
        FailureCode.corruptFile,
      );
    });

    test('white-background kit mode still works after the refactor', () {
      final out = cleanSignatureSync(_photo(), 140, 60, 20 * 1024);
      expect(out.failureCode, isNull);
      final jpg = img.decodeJpg(out.bytes!)!;
      expect((jpg.width, jpg.height), (140, 60));
      expect(jpg.getPixel(0, 0).luminance, greaterThan(235));
    });
  });

  group('alphaBounds', () {
    test('finds the inclusive box of visible pixels', () {
      final a = Uint8List(10 * 8);
      a[2 * 10 + 3] = 255;
      a[5 * 10 + 7] = 10;
      final b = alphaBounds(a, 10, 8)!;
      expect((b.left, b.top, b.right, b.bottom), (3, 2, 7, 5));
      expect((b.width, b.height), (5, 4));
      expect(alphaBounds(a, 10, 8, threshold: 10)!.right, 3);
    });

    test('null when fully transparent', () {
      expect(alphaBounds(Uint8List(16), 4, 4), isNull);
    });
  });
}
