import 'package:feature_tools/src/common/page_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePageRanges', () {
    test('parses singles and ranges into 0-based indices in order', () {
      final r = parsePageRanges('1-3, 5, 8-10', 10);
      expect(r.isValid, isTrue);
      expect(r.pages, [0, 1, 2, 4, 7, 8, 9]);
    });

    test('keeps typed order and drops duplicates', () {
      expect(parsePageRanges('5, 1-2, 2, 5', 6).pages, [4, 0, 1]);
    });

    test('supports open ranges and en dashes', () {
      expect(parsePageRanges('7-', 9).pages, [6, 7, 8]);
      expect(parsePageRanges('2–3', 5).pages, [1, 2]);
    });

    test('tolerates spaces and semicolons', () {
      expect(parsePageRanges(' 1 - 2 ; 4 ', 4).pages, [0, 1, 3]);
    });

    test('rejects empty, garbage, zero, reversed and out-of-range input', () {
      expect(parsePageRanges('', 5).error, isNotNull);
      expect(parsePageRanges('abc', 5).error, contains('abc'));
      expect(parsePageRanges('0', 5).error, contains('start at 1'));
      expect(parsePageRanges('4-2', 5).error, contains('2-4'));
      expect(parsePageRanges('1-9', 5).error, contains('5 pages'));
      expect(parsePageRanges(',,', 5).error, 'No pages selected');
    });
  });

  test('chunkPages groups consecutive pages with a short tail', () {
    expect(chunkPages(5, 2), [
      [0, 1],
      [2, 3],
      [4],
    ]);
    expect(chunkPages(3, 1), [
      [0],
      [1],
      [2],
    ]);
  });

  test('describePages', () {
    expect(describePages([0]), '1');
    expect(describePages([2, 3, 4]), '3–5');
  });
}
