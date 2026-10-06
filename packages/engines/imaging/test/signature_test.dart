import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// Gray, slightly shaded paper with a dark wavy scribble.
Uint8List scribblePhoto({bool withInk = true}) {
  final im = img.Image(width: 900, height: 600);
  for (final p in im) {
    // Uneven lighting: left side darker, like a phone shadow.
    final v = 150 + (p.x / 900 * 60).round();
    p
      ..r = v
      ..g = v
      ..b = v - 6;
  }
  if (withInk) {
    for (var x = 200; x < 700; x++) {
      final y = 300 + (math.sin(x / 25) * 60).round();
      img.fillCircle(
        im,
        x: x,
        y: y,
        radius: 4,
        color: img.ColorRgb8(25, 25, 40),
      );
    }
    img.drawLine(
      im,
      x1: 260,
      y1: 380,
      x2: 640,
      y2: 360,
      color: img.ColorRgb8(20, 20, 35),
      thickness: 6,
    );
  }
  return img.encodeJpg(im, quality: 92);
}

void main() {
  const processor = SignatureProcessorImpl();

  test(
    'cleans a signature to exact size, white paper, dark ink, under limit',
    () async {
      final r = await processor.cleanSignature(
        scribblePhoto(),
        width: 140,
        height: 60,
        maxBytes: 20 * 1024,
      );
      expect(r.failureOrNull, isNull);
      final out = r.valueOrNull!;
      expect(out.bytes.length, lessThanOrEqualTo(20 * 1024));
      final decoded = img.decodeJpg(Uint8List.fromList(out.bytes))!;
      expect((decoded.width, decoded.height), (140, 60));

      var white = 0;
      var dark = 0;
      for (final p in decoded) {
        final l = p.luminance;
        if (l > 235) white++;
        if (l < 90) dark++;
      }
      const total = 140 * 60;
      expect(white / total, greaterThan(0.6), reason: 'paper must turn white');
      expect(dark, greaterThan(total * 0.02), reason: 'ink must stay dark');
    },
  );

  test('blank paper reports "No signature found"', () async {
    final r = await processor.cleanSignature(
      scribblePhoto(withInk: false),
      width: 140,
      height: 60,
    );
    expect(r.failureOrNull?.code, FailureCode.documentNotDetected);
    expect(r.failureOrNull?.detail, 'No signature found');
  });

  test('garbage input fails with a typed error', () async {
    final r = await processor.cleanSignature(
      Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      width: 140,
      height: 60,
    );
    expect(r.failureOrNull?.code, FailureCode.corruptFile);
  });

  test('backgroundUniformity is high for plain, low for busy borders', () {
    final plain = img.Image(width: 300, height: 400);
    img.fill(plain, color: img.ColorRgb8(240, 240, 240));
    img.fillCircle(
      plain,
      x: 150,
      y: 180,
      radius: 80,
      color: img.ColorRgb8(90, 60, 50),
    );
    final busy = img.Image(width: 300, height: 400);
    final rnd = math.Random(3);
    // Busy scene: 25px blocks of random brightness (furniture, posters).
    for (var by = 0; by < 400; by += 25) {
      for (var bx = 0; bx < 300; bx += 25) {
        final v = rnd.nextInt(256);
        img.fillRect(
          busy,
          x1: bx,
          y1: by,
          x2: bx + 24,
          y2: by + 24,
          color: img.ColorRgb8(v, v, v),
        );
      }
    }
    final plainScore = backgroundUniformitySync(img.encodeJpg(plain));
    final busyScore = backgroundUniformitySync(img.encodeJpg(busy));
    expect(plainScore, greaterThan(0.9));
    expect(busyScore, lessThan(0.5));
    expect(backgroundUniformitySync(Uint8List(4)), isNull);
  });
}
