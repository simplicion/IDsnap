import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/signature/signature_library.dart';
import 'package:feature_tools/src/signature/signature_pad.dart';
import 'package:feature_tools/src/signature/stamp_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _a4 = PdfPageDimensions(595, 842);

/// Minimal valid PNG header + IHDR for [w] x [h] (enough for the index).
Uint8List _png(int w, int h) => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
  (w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255,
  (h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255,
  8, 6, 0, 0, 0,
]);

Future<(int, int, Uint8List)> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData();
  final result = (image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  return result;
}

void main() {
  group('stamp placement (points ↔ view)', () {
    test('viewport maps points to view pixels and back', () {
      const v = PageViewport(page: _a4, viewWidth: 297.5);
      expect(v.scale, 0.5);
      expect(v.viewHeight, 421);
      const r = StampRect(100, 200, 150, 50);
      expect(v.toView(r), const Rect.fromLTWH(50, 100, 75, 25));
      expect(v.toPoints(v.toView(r)), r);
      expect(v.deltaToPoints(const Offset(10, -4)), const Offset(20, -8));
    });

    test('moving keeps the stamp on the page', () {
      const r = StampRect(500, 800, 80, 30);
      expect(
        moveStamp(r, const Offset(200, 200), _a4),
        const StampRect(515, 812, 80, 30),
      );
      expect(
        moveStamp(r, const Offset(-900, -900), _a4),
        const StampRect(0, 0, 80, 30),
      );
    });

    test('pinch scaling keeps aspect, centre and limits', () {
      const r = StampRect(100, 100, 100, 40);
      final bigger = scaleStamp(r, 2, _a4);
      expect((bigger.width, bigger.height), (200.0, 80.0));
      expect(bigger.center, r.center);
      final tiny = scaleStamp(r, 0.01, _a4);
      expect(tiny.height, closeTo(minStampPoints, 1e-9));
      expect(tiny.width / tiny.height, closeTo(2.5, 1e-9));
      final huge = scaleStamp(r, 100, _a4);
      expect(huge.width, lessThanOrEqualTo(_a4.width));
      expect(huge.right, lessThanOrEqualTo(_a4.width + 1e-9));
    });

    test('corner resize anchors the top-left corner', () {
      const r = StampRect(100, 100, 100, 40);
      final w = resizeStamp(r, 150, _a4);
      expect(w, const StampRect(100, 100, 150, 60));
      expect(resizeStamp(r, 5000, _a4).right, closeTo(_a4.width, 1e-9));
    });

    test('new signatures start inside the page with their aspect', () {
      final r = initialSignatureRect(_a4, 3);
      expect(r.width / r.height, closeTo(3, 1e-9));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(_a4.height));
      final tall = initialSignatureRect(_a4, 0.5);
      expect(tall.height, closeTo(_a4.height * 0.2, 1e-9));
    });

    test('date text', () {
      expect(formatStampDate(DateTime(2026, 9, 25)), '25 Sep 2026');
      final r = textStampRect(10, 20, '25 Sep 2026', 10);
      expect(r.height, 12);
      expect(r.width, closeTo(11 * 10 * 0.55, 1e-9));
    });
  });

  group('signature strokes', () {
    test('ink bounds trim to the strokes plus half the pen width', () {
      final b = signatureInkBounds([
        [const Offset(10, 20), const Offset(50, 25)],
        [const Offset(30, 60)],
      ], strokeWidth: 4)!;
      expect(b, const Rect.fromLTRB(8, 18, 52, 62));
      expect(signatureInkBounds(const []), isNull);
      expect(signatureInkBounds(const [<Offset>[]]), isNull);
    });

    test('smooth path uses quadratic curves through midpoints', () {
      final path = smoothStrokePath(const [
        Offset.zero,
        Offset(10, 10),
        Offset(20, 0),
        Offset(30, 10),
      ]);
      final bounds = path.getBounds();
      // Curves stay inside the control points' hull.
      expect(bounds.left, 0);
      expect(bounds.right, 30);
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(10));
    });

    test('controller: jitter filter, undo and clear', () {
      final c = SignaturePadController()
        ..begin(Offset.zero)
        ..extend(const Offset(0.1, 0.1)) // below minDistance: dropped
        ..extend(const Offset(5, 5))
        ..begin(const Offset(20, 20));
      expect(c.strokes.length, 2);
      expect(c.strokes.first.length, 2);
      c.undo();
      expect(c.strokes.length, 1);
      c.clear();
      expect(c.isEmpty, isTrue);
      c.dispose();
    });
  });

  testWidgets('canvas: draw → trimmed transparent PNG at 3×', (tester) async {
    final controller = SignaturePadController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: SignaturePad(controller: controller),
          ),
        ),
      ),
    );
    final pad = find.byKey(const ValueKey('signature-pad'));
    final topLeft = tester.getTopLeft(pad);
    final gesture = await tester.startGesture(topLeft + const Offset(50, 60));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(topLeft + Offset(50.0 + i * 10, 60.0 + (i % 5) * 8));
    }
    await gesture.up();
    await tester.pump();
    expect(controller.isEmpty, isFalse);
    controller.ink = SignatureInk.blue;

    final image = await tester.runAsync(controller.export);
    expect(image, isNotNull);
    expect(image!.png, isNotEmpty);
    // Stroke spans ~200 x 32 logical px, +pen width and padding, at 3×.
    expect(image.width, inInclusiveRange(600, 640));
    expect(image.height, inInclusiveRange(100, 130));

    final (w, h, rgba) = (await tester.runAsync(() => _decodeRgba(image.png)))!;
    expect((w, h), (image.width, image.height));
    int alphaAt(int x, int y) => rgba[(y * w + x) * 4 + 3];
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(w - 1, 0), 0);
    expect(alphaAt(0, h - 1), 0);
    expect(alphaAt(w - 1, h - 1), 0);
    var opaque = 0;
    var blue = 0;
    for (var i = 0; i < w * h; i++) {
      if (rgba[i * 4 + 3] == 255) {
        opaque++;
        if (rgba[i * 4 + 2] > rgba[i * 4]) blue++;
      }
    }
    expect(opaque, greaterThan(500), reason: 'ink is opaque');
    expect(blue, opaque, reason: 'blue ink');
  });

  testWidgets('empty canvas exports nothing', (tester) async {
    final controller = SignaturePadController();
    addTearDown(controller.dispose);
    expect(await tester.runAsync(controller.export), isNull);
  });

  group('FileSignatureLibrary', () {
    late Directory dir;
    late FileSignatureLibrary lib;
    var clock = DateTime(2026);
    var n = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sig_lib');
      clock = DateTime(2026);
      n = 0;
      lib = FileSignatureLibrary(
        '${dir.path}${Platform.pathSeparator}signatures',
        clock: () => clock = clock.add(const Duration(minutes: 1)),
        ids: () => 'sig${n++}',
      );
    });

    tearDown(() => dir.delete(recursive: true));

    test('empty until something is added', () async {
      expect((await lib.list()).valueOrNull, isEmpty);
    });

    test('add, list newest first, first is default, load', () async {
      final a = (await lib.add(
        _png(300, 100),
        width: 300,
        height: 100,
      )).valueOrNull!;
      expect(a.isDefault, isTrue);
      await lib.add(_png(200, 80), width: 200, height: 80);
      final list = (await lib.list()).valueOrNull!;
      expect([for (final s in list) s.id], ['sig1', 'sig0']);
      expect([for (final s in list) s.isDefault], [false, true]);
      expect((await lib.load('sig1')).valueOrNull, _png(200, 80));
      expect(
        File('${lib.directory}${Platform.pathSeparator}sig1.png').existsSync(),
        isTrue,
      );
    });

    test('set default and delete (default moves to the newest)', () async {
      for (var i = 0; i < 3; i++) {
        await lib.add(_png(10, 10), width: 10, height: 10);
      }
      expect((await lib.setDefault('sig1')).isOk, isTrue);
      var list = (await lib.list()).valueOrNull!;
      expect(list.singleWhere((s) => s.isDefault).id, 'sig1');
      expect((await lib.delete('sig1')).isOk, isTrue);
      list = (await lib.list()).valueOrNull!;
      expect(list.map((s) => s.id), ['sig2', 'sig0']);
      expect(list.singleWhere((s) => s.isDefault).id, 'sig2');
      expect(
        (await lib.delete('nope')).failureOrNull?.code,
        FailureCode.notFound,
      );
      expect(
        (await lib.load('sig1')).failureOrNull?.code,
        FailureCode.notFound,
      );
    });

    test('keeps at most five and explains why', () async {
      for (var i = 0; i < SignatureLibrary.capacity; i++) {
        expect(
          (await lib.add(_png(10, 10), width: 10, height: 10)).isOk,
          isTrue,
        );
      }
      final full = await lib.add(_png(10, 10), width: 10, height: 10);
      expect(full.failureOrNull?.code, FailureCode.targetSizeUnreachable);
      expect(full.failureOrNull?.recovery, contains('Delete one'));
    });

    test('rejects non-PNG data', () async {
      final r = await lib.add(
        Uint8List.fromList([1, 2, 3]),
        width: 1,
        height: 1,
      );
      expect(r.failureOrNull?.code, FailureCode.corruptFile);
    });

    test('rebuilds a damaged index from the PNG files', () async {
      await lib.add(_png(320, 90), width: 320, height: 90);
      await lib.add(_png(10, 10), width: 10, height: 10);
      File(
        '${lib.directory}${Platform.pathSeparator}${FileSignatureLibrary.indexName}',
      ).writeAsStringSync('{broken');
      final list = (await lib.list()).valueOrNull!;
      expect(list.length, 2);
      expect(list.where((s) => s.isDefault).length, 1);
      final big = list.singleWhere((s) => s.id == 'sig0');
      expect((big.width, big.height), (320, 90));
    });
  });
}
