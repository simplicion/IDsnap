import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

void main() {
  group('autoFramePortrait', () {
    // 3000×4000 portrait photo, face box roughly central.
    const face = NRect(0.4, 0.3, 0.2, 0.15);

    test('keeps the preset pixel aspect and centers the face', () {
      final r = autoFramePortrait(
        face: face,
        preset: CropPreset.passportIntl,
        imageWidth: 3000,
        imageHeight: 4000,
      )!;
      final aspect = (r.width * 3000) / (r.height * 4000);
      expect(aspect, closeTo(35 / 45, 1e-6));
      expect(r.left + r.width / 2, closeTo(0.5, 1e-6));
    });

    test('head fills the preset head ratio', () {
      final r = autoFramePortrait(
        face: face,
        preset: CropPreset.passportIntl,
        imageWidth: 3000,
        imageHeight: 4000,
      )!;
      final headH = face.height * 1.3;
      expect(headH / r.height, closeTo(0.75, 1e-6));
    });

    test('stays inside the image when the face is near an edge', () {
      final r = autoFramePortrait(
        face: const NRect(0.02, 0.01, 0.3, 0.25),
        preset: CropPreset.passportUs,
        imageWidth: 2000,
        imageHeight: 2000,
      )!;
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(1 + 1e-9));
      expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
    });

    test('document presets are not auto-framed', () {
      expect(
        autoFramePortrait(
          face: face,
          preset: CropPreset.a4,
          imageWidth: 3000,
          imageHeight: 4000,
        ),
        isNull,
      );
    });
  });
}
