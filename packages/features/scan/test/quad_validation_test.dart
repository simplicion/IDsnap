import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a normal page outline is valid', () {
    const quad = Quad(
      NPoint(0.1, 0.05),
      NPoint(0.92, 0.1),
      NPoint(0.95, 0.95),
      NPoint(0.05, 0.9),
    );
    expect(validateQuad(quad), isNull);
    expect(validateQuad(Quad.full), isNull);
  });

  test('crossed corners are rejected with a helpful message', () {
    // Top-right and bottom-right swapped → self-intersecting "bow tie".
    const quad = Quad(
      NPoint(0.1, 0.1),
      NPoint(0.9, 0.9),
      NPoint(0.9, 0.1),
      NPoint(0.1, 0.9),
    );
    expect(validateQuad(quad), contains('cross'));
  });

  test('a tiny selection is rejected', () {
    const quad = Quad(
      NPoint(0.5, 0.5),
      NPoint(0.55, 0.5),
      NPoint(0.55, 0.55),
      NPoint(0.5, 0.55),
    );
    expect(validateQuad(quad), contains('too small'));
  });
}
