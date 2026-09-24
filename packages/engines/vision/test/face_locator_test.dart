import 'package:engine_vision/src/mlkit_face_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('largestFaceBox picks the biggest face and normalizes it', () {
    final box = largestFaceBox(
      [
        (left: 10, top: 10, width: 50, height: 50),
        (left: 400, top: 300, width: 200, height: 260),
      ],
      1000,
      2000,
    )!;
    expect(box.left, closeTo(0.4, 1e-9));
    expect(box.top, closeTo(0.15, 1e-9));
    expect(box.width, closeTo(0.2, 1e-9));
    expect(box.height, closeTo(0.13, 1e-9));
  });

  test('clamps boxes that extend past the image', () {
    final box = largestFaceBox(
      [(left: -20, top: -10, width: 120, height: 110)],
      100,
      100,
    )!;
    expect(box.left, 0);
    expect(box.top, 0);
    expect(box.right, closeTo(1, 1e-9));
  });

  test('no faces returns null', () {
    expect(largestFaceBox([], 100, 100), isNull);
  });
}
