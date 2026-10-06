import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/src/passport_photo/capture_machine.dart';
import 'package:feature_scan/src/passport_photo/face_checks.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:feature_scan/src/passport_photo/photo_processing.dart';
import 'package:feature_scan/src/passport_photo/print_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'passport_photo_fakes.dart';

void main() {
  group('PhotoPreset', () {
    test('labels are term-specific with sizes', () {
      expect(PhotoPreset.passport.label, 'Passport size (35 × 45 mm)');
      expect(PhotoPreset.square.label, 'Square photo (2 × 2 in / 51 × 51 mm)');
      expect(PhotoPreset.stamp.label, 'Stamp size (20 × 25 mm)');
      expect(PhotoPreset.id30x40.label, 'ID photo (30 × 40 mm)');
    });

    test('no country names in any preset label', () {
      final banned = RegExp(
        r'\b(US|USA|Green Card|Schengen|India|UK|Canada|China|EU)\b',
      );
      for (final p in PhotoPreset.builtIn) {
        expect(banned.hasMatch(p.label), isFalse, reason: p.label);
      }
    });

    test('pixel sizes at 300 dpi', () {
      expect(PhotoPreset.passport.pixelWidth, 413);
      expect(PhotoPreset.passport.pixelHeight, 531);
      expect(PhotoPreset.square.pixelWidth, 600);
      expect(PhotoPreset.stamp.pixelWidth, 236);
      expect(PhotoPreset.stamp.pixelHeight, 295);
    });

    test('custom sizes convert mm, inches and exact pixels', () {
      final px = PhotoPreset.custom(
        width: 350,
        height: 450,
        unit: SizeUnit.px,
        maxKb: 50,
      );
      expect(px.pixelWidth, 350);
      expect(px.pixelHeight, 450);
      expect(px.maxBytes, 50 * 1024);
      expect(px.label, 'Custom (350 × 450 px, max 50 KB)');
      final inch = PhotoPreset.custom(width: 2, height: 2, unit: SizeUnit.inch);
      expect(inch.widthMm, closeTo(50.8, 1e-9));
      expect(inch.pixelWidth, 600);
    });

    test('toCropPreset keeps framing parameters', () {
      final c = PhotoPreset.square.toCropPreset();
      expect(c.headRatio, 0.6);
      expect(c.topMarginRatio, 0.12);
      expect(c.aspect, 1);
    });

    test('validateCustomSize', () {
      expect(
        validateCustomSize(width: 35, height: 45, unit: SizeUnit.mm),
        isNull,
      );
      expect(
        validateCustomSize(width: 0, height: 45, unit: SizeUnit.mm),
        isNotNull,
      );
      expect(
        validateCustomSize(width: 10, height: 45, unit: SizeUnit.mm),
        contains('narrow'),
      );
      expect(
        validateCustomSize(width: 50, height: 50, unit: SizeUnit.px),
        contains('between'),
      );
      expect(
        validateCustomSize(width: 35, height: 45, unit: SizeUnit.mm, maxKb: 2),
        contains('KB'),
      );
    });
  });

  group('GuideGeometry', () {
    test('frame keeps the preset pixel aspect and is centred', () {
      final g = passportGuide();
      final pixelAspect = (g.frame.width * 3) / (g.frame.height * 4);
      expect(pixelAspect, closeTo(35 / 45, 1e-9));
      expect(g.frame.left + g.frame.width / 2, closeTo(0.5, 1e-9));
      expect(g.frame.top + g.frame.height / 2, closeTo(0.5, 1e-9));
    });

    test('oval is the target head height with the eye line inside', () {
      final g = passportGuide();
      expect(g.oval.height / g.frame.height, closeTo(0.75, 1e-9));
      expect(g.eyeLineY, greaterThan(g.oval.top));
      expect(g.eyeLineY, lessThan(g.oval.bottom));
    });

    test('square preset on a portrait preview is width-limited', () {
      final g = GuideGeometry.forPreset(
        PhotoPreset.square,
        previewAspect: 3 / 4,
      );
      expect(g.frame.width, closeTo(0.8, 1e-9));
    });
  });

  group('evaluateFace', () {
    final g = passportGuide();

    test('a well-placed face passes every check', () {
      final r = evaluateFace(frameOf([goodFace(g)]), g);
      expect(r.allPass, isTrue, reason: r.hint);
      expect(r.hint, 'Great — hold still');
    });

    test('no face / several faces', () {
      expect(evaluateFace(frameOf([]), g).hint, contains('no face found'));
      final two = evaluateFace(frameOf([goodFace(g), goodFace(g)]), g);
      expect(two.failing, contains(FaceCheck.oneFace));
      expect(two.hint, contains('one person'));
    });

    test('head size: closer / back', () {
      expect(
        evaluateFace(frameOf([goodFace(g, scale: 0.6)]), g).hint,
        'Move a little closer',
      );
      expect(
        evaluateFace(frameOf([goodFace(g, scale: 1.3)]), g).hint,
        'Move back a little',
      );
    });

    test('off-centre face', () {
      final r = evaluateFace(frameOf([goodFace(g, dx: 0.2)]), g);
      expect(r.failing, {FaceCheck.centred});
      expect(r.hint, contains('Centre'));
    });

    test('roll and yaw limits', () {
      expect(
        evaluateFace(frameOf([goodFace(g, roll: 7.9)]), g).allPass,
        isTrue,
      );
      expect(evaluateFace(frameOf([goodFace(g, roll: -9)]), g).failing, {
        FaceCheck.level,
      });
      expect(evaluateFace(frameOf([goodFace(g, yaw: 13)]), g).failing, {
        FaceCheck.facingCamera,
      });
    });

    test('eyes closed fails only when classification is available', () {
      expect(evaluateFace(frameOf([goodFace(g, eyes: 0.1)]), g).failing, {
        FaceCheck.eyesOpen,
      });
      expect(
        evaluateFace(frameOf([goodFace(g, eyes: null)]), g).allPass,
        isTrue,
      );
    });

    test('lighting', () {
      expect(
        evaluateFace(frameOf([goodFace(g)], brightness: 0.1), g).hint,
        contains('more light'),
      );
      expect(
        evaluateFace(frameOf([goodFace(g)], brightness: 0.97), g).hint,
        contains('Too bright'),
      );
      expect(
        evaluateFace(frameOf([goodFace(g)], brightness: null), g).allPass,
        isTrue,
      );
    });

    test('movement between frames is not steady', () {
      final r = evaluateFace(
        frameOf([goodFace(g)]),
        g,
        previous: goodFace(g, dx: 0.05),
      );
      expect(r.failing, {FaceCheck.steady});
      expect(r.hint, 'Hold still');
    });
  });

  group('CaptureMachine', () {
    final t0 = DateTime(2026, 9, 25, 10);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('fake face stream → hold → countdown → fire once', () {
      final m = CaptureMachine();
      final g = passportGuide();
      final phases = <CapturePhase>[];
      LiveFace? prev;
      for (var ms = 0; ms <= 900; ms += 150) {
        final face = goodFace(g);
        final checks = evaluateFace(frameOf([face]), g, previous: prev);
        prev = face;
        phases.add(m.onChecks(allPass: checks.allPass, now: at(ms)));
      }
      expect(phases.first, const Holding(0));
      expect(phases.whereType<Holding>().length, greaterThan(3));
      expect(m.phase, const Countdown(3));
      expect(m.tick(at(900 + 1100)), const Countdown(2));
      expect(m.tick(at(900 + 2100)), const Countdown(1));
      expect(m.tick(at(900 + 3000)), isA<Fire>());
      // Fire is terminal until reset.
      expect(m.onChecks(allPass: true, now: at(5000)), isA<Fire>());
      m.reset();
      expect(m.phase, isA<Searching>());
    });

    test('a failing frame resets the dwell', () {
      final m = CaptureMachine()
        ..onChecks(allPass: true, now: at(0))
        ..onChecks(allPass: true, now: at(600));
      expect(m.onChecks(allPass: false, now: at(700)), isA<Searching>());
      expect(m.passSince, isNull);
      expect(m.onChecks(allPass: true, now: at(800)), const Holding(0));
      expect(m.onChecks(allPass: true, now: at(1400)), isA<Holding>());
      expect(m.onChecks(allPass: true, now: at(1600)), const Countdown(3));
    });

    test('brief failures during countdown are tolerated, long ones cancel', () {
      final m = CaptureMachine()
        ..onChecks(allPass: true, now: at(0))
        ..onChecks(allPass: true, now: at(800));
      expect(m.phase, isA<Countdown>());
      // Blink.
      expect(m.onChecks(allPass: false, now: at(1000)), isA<Countdown>());
      expect(m.onChecks(allPass: true, now: at(1200)), isA<Countdown>());
      // Walks away.
      m
        ..onChecks(allPass: false, now: at(1300))
        ..onChecks(allPass: false, now: at(1500));
      expect(m.onChecks(allPass: false, now: at(1800)), isA<Searching>());
    });

    test('cancel turns auto-capture off; re-enabling restarts the dwell', () {
      final m = CaptureMachine()
        ..onChecks(allPass: true, now: at(0))
        ..onChecks(allPass: true, now: at(800))
        ..cancel();
      expect(m.phase, isA<Manual>());
      expect(m.onChecks(allPass: true, now: at(2000)), isA<Manual>());
      expect(m.tick(at(9000)), isA<Manual>());
      m.setAuto(enabled: true);
      expect(m.onChecks(allPass: true, now: at(9100)), const Holding(0));
    });
  });

  group('print sheet', () {
    test('4 × 6 in fits 6 passport-size photos (2 × 3)', () {
      final c = printSheetCapacity(
        PrintPaper.photo4x6,
        photoWidthMm: 35,
        photoHeightMm: 45,
      );
      expect((c.columns, c.rows, c.landscape), (2, 3, false));
    });

    test('A4 fits more; count limits and centres the grid', () {
      final jpeg = Uint8List(4);
      final full = layoutPrintSheet(
        jpeg: jpeg,
        photoWidthMm: 35,
        photoHeightMm: 45,
        paper: PrintPaper.a4,
      );
      expect(full.capacity, 30);
      expect(full.images, hasLength(30));
      final four = layoutPrintSheet(
        jpeg: jpeg,
        photoWidthMm: 35,
        photoHeightMm: 45,
        paper: PrintPaper.a4,
        count: 4,
      );
      expect(four.images, hasLength(4));
      final left = four.images.first.left;
      final right = four.images.last.left + four.images.last.width;
      expect(left, closeTo(four.pageWidthPt - right, 1e-6));
      expect(four.images.first.width, closeTo(35 * 72 / 25.4, 1e-9));
      for (final i in full.images) {
        expect(i.left + i.width, lessThanOrEqualTo(full.pageWidthPt));
        expect(i.top + i.height, lessThanOrEqualTo(full.pageHeightPt));
      }
    });

    test('a 2 × 2 in photo on 4 × 6 in paper fits 2', () {
      final c = printSheetCapacity(
        PrintPaper.photo4x6,
        photoWidthMm: 50.8,
        photoHeightMm: 50.8,
      );
      expect(c.columns * c.rows, 2);
    });
  });

  group('adjustCropRect', () {
    test('keeps pixel aspect and stays inside the image', () {
      const start = NRect(0.3, 0.3, 0.35 * 3 / 4, 0.35);
      final moved = adjustCropRect(
        start,
        imageWidth: 3000,
        imageHeight: 4000,
        aspect: 35 / 45,
        dx: 2,
        dy: -2,
      );
      expect(moved.right, closeTo(1, 1e-9));
      expect(moved.top, closeTo(0, 1e-9));
      expect(
        (moved.width * 3000) / (moved.height * 4000),
        closeTo(35 / 45, 1e-9),
      );
      final huge = adjustCropRect(
        start,
        imageWidth: 3000,
        imageHeight: 4000,
        aspect: 35 / 45,
        scale: 10,
      );
      expect(huge.width, lessThanOrEqualTo(1 + 1e-9));
      expect(huge.height, lessThanOrEqualTo(1 + 1e-9));
    });

    test('unmirrorBox flips x only when mirrored', () {
      const b = NRect(0.1, 0.2, 0.3, 0.4);
      expect(unmirrorBox(b, mirrored: false), same(b));
      final u = unmirrorBox(b, mirrored: true);
      expect(u.left, closeTo(0.6, 1e-9));
      expect(u.top, 0.2);
    });
  });

  group('PassportPhotoProcessor', () {
    late PassportImages images;
    late FakeFaceLocator faces;
    late PassportPhotoProcessor p;

    setUp(() {
      images = PassportImages();
      faces = FakeFaceLocator();
      p = PassportPhotoProcessor(
        files: FakeFileStore(),
        images: images,
        faces: faces,
      );
    });

    test('auto-frames with autoFramePortrait and exact pixel size', () async {
      final src = (await p.load('/tmp/a.jpg')).valueOrNull!;
      expect(src.width, 3000);
      expect(src.face, isNotNull);
      final rect = p.autoRect(src, PhotoPreset.passport);
      final expected = autoFramePortrait(
        face: src.face!,
        preset: PhotoPreset.passport.toCropPreset(),
        imageWidth: 3000,
        imageHeight: 4000,
      )!;
      expect(rect.left, expected.left);
      expect(rect.height, expected.height);
      final out = (await p.render(
        src,
        PhotoPreset.passport,
        rect,
      )).valueOrNull!;
      expect(images.crops.single.$2, 413);
      expect(images.crops.single.$3, 531);
      expect(images.compressions, isEmpty); // no size limit
      expect(images.renders, isEmpty);
      expect(out.withinLimit, isTrue);
    });

    test('falls back to the live box, then to a centred crop', () async {
      faces.next = const Ok(null);
      const live = NRect(0.4, 0.3, 0.2, 0.2);
      final withLive = (await p.load(
        '/tmp/a.jpg',
        fallbackFace: live,
      )).valueOrNull!;
      expect(withLive.face, live);
      final none = (await p.load('/tmp/a.jpg')).valueOrNull!;
      expect(none.face, isNull);
      final r = p.autoRect(none, PhotoPreset.passport);
      expect(r.left + r.width / 2, closeTo(0.5, 1e-9));
    });

    test('compresses to the size limit and brightens on request', () async {
      final preset = PhotoPreset.custom(
        width: 35,
        height: 45,
        unit: SizeUnit.mm,
        maxKb: 50,
      );
      final src = (await p.load('/tmp/a.jpg')).valueOrNull!;
      final out = (await p.render(
        src,
        preset,
        p.autoRect(src, preset),
        brighten: true,
      )).valueOrNull!;
      expect(images.renders.single, same(brightenEdits));
      expect(images.compressions.single.targetBytes, 50 * 1024);
      expect(out.sizeBytes, 40 * 1024);
      expect(out.withinLimit, isTrue);

      images.compressTo = 60 * 1024;
      final over = (await p.render(
        src,
        preset,
        p.autoRect(src, preset),
      )).valueOrNull!;
      expect(over.withinLimit, isFalse);
    });
  });
}
