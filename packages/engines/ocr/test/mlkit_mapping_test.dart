import 'dart:math';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_ocr/engine_ocr.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

mlkit.TextLine _line(String text, Rect box, {double? conf}) => mlkit.TextLine(
  text: text,
  elements: const [],
  boundingBox: box,
  recognizedLanguages: const [],
  cornerPoints: const <Point<int>>[],
  confidence: conf,
  angle: 0,
);

void main() {
  test('normalizeRect scales and clamps', () {
    final r = normalizeRect(const Rect.fromLTRB(-10, 50, 110, 150), 100, 200);
    expect(r.left, 0);
    expect(r.top, 0.25);
    expect(r.width, 1);
    expect(r.height, 0.5);
  });

  test('toOcrResult keeps lines, drops blank ones and empty blocks', () {
    final text = mlkit.RecognizedText(
      text: 'Name: Rahul\nClass: 12',
      blocks: [
        mlkit.TextBlock(
          text: 'Name: Rahul\nClass: 12',
          lines: [
            _line(
              'Name: Rahul',
              const Rect.fromLTWH(10, 10, 200, 20),
              conf: 0.9,
            ),
            _line('Class: 12', const Rect.fromLTWH(10, 40, 100, 20)),
            _line('   ', const Rect.fromLTWH(0, 0, 1, 1)),
          ],
          boundingBox: const Rect.fromLTWH(10, 10, 200, 50),
          recognizedLanguages: const [],
          cornerPoints: const [],
        ),
        mlkit.TextBlock(
          text: '',
          lines: const [],
          boundingBox: Rect.zero,
          recognizedLanguages: const [],
          cornerPoints: const [],
        ),
      ],
    );
    final r = toOcrResult(text, 400, 800, OcrScript.latin);
    expect(r.blocks, hasLength(1));
    expect(r.text, 'Name: Rahul\nClass: 12');
    expect(r.lines.first.box.left, closeTo(0.025, 1e-9));
    expect(r.lines.first.confidence, 0.9);
  });

  test('toOcrResult with zero size returns empty', () {
    final r = toOcrResult(
      mlkit.RecognizedText(text: '', blocks: const []),
      0,
      0,
      OcrScript.latin,
    );
    expect(r.isEmpty, isTrue);
  });

  test('script mapping covers every OcrScript', () {
    for (final s in OcrScript.values) {
      expect(toMlKitScript(s).name, isNotEmpty);
    }
    expect(
      toMlKitScript(OcrScript.devanagari),
      mlkit.TextRecognitionScript.devanagiri,
    );
  });

  test('platform codes map to typed failures', () {
    expect(mapPlatformCode('ModelUnavailable'), FailureCode.modelUnavailable);
    expect(
      mapPlatformCode('java.lang.NoClassDefFoundError'),
      FailureCode.modelUnavailable,
    );
    expect(
      mapPlatformCode('InputImageConverterError: decode'),
      FailureCode.corruptFile,
    );
    expect(mapPlatformCode('other'), FailureCode.unknown);
  });

  test('capability is honest per platform and bundled script', () async {
    final off = MlKitTextRecognizer(isSupportedPlatform: false);
    expect((await off.capability(OcrScript.latin)).available, isFalse);
    expect(
      (await off.recognize('x.jpg', OcrScript.latin)).failureOrNull?.code,
      FailureCode.modelUnavailable,
    );

    final on = MlKitTextRecognizer(isSupportedPlatform: true);
    final latin = await on.capability(OcrScript.latin);
    expect(latin.available && latin.worksOffline, isTrue);
    expect((await on.capability(OcrScript.korean)).available, isFalse);
    expect(
      (await on.recognize('missing.jpg', OcrScript.latin)).failureOrNull?.code,
      FailureCode.notFound,
    );
  });
}
