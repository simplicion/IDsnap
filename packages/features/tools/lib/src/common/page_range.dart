/// Parsed page selection. [pages] are 0-based, in the order typed, without
/// duplicates.
class PageRangeResult {
  const PageRangeResult.ok(this.pages) : error = null;
  const PageRangeResult.error(String this.error) : pages = const [];

  final List<int> pages;
  final String? error;

  bool get isValid => error == null;
}

/// Parses "1-3, 5, 8-10" (1-based) for a document with [pageCount] pages.
/// Also accepts open ranges ("7-" = 7 to the end) and en/em dashes.
PageRangeResult parsePageRanges(String input, int pageCount) {
  final text = input.trim();
  if (text.isEmpty) {
    return const PageRangeResult.error('Enter pages, for example 1-3, 5');
  }
  final pattern = RegExp(r'^(\d+)\s*(-\s*(\d*))?$');
  final seen = <int>{};
  final out = <int>[];
  for (final raw in text.split(RegExp('[,;]'))) {
    final part = raw.trim().replaceAll(RegExp('[–—]'), '-');
    if (part.isEmpty) continue;
    final m = pattern.firstMatch(part);
    if (m == null) {
      return PageRangeResult.error('"$part" is not a page or range');
    }
    final start = int.parse(m[1]!);
    final end = m[2] == null
        ? start
        : (m[3]!.isEmpty ? pageCount : int.parse(m[3]!));
    if (start < 1 || end < 1) {
      return const PageRangeResult.error('Page numbers start at 1');
    }
    if (start > pageCount || end > pageCount) {
      return PageRangeResult.error(
        'This PDF has $pageCount page${pageCount == 1 ? '' : 's'}',
      );
    }
    if (start > end) {
      return PageRangeResult.error('Write "$part" as $end-$start');
    }
    for (var p = start; p <= end; p++) {
      if (seen.add(p - 1)) out.add(p - 1);
    }
  }
  if (out.isEmpty) return const PageRangeResult.error('No pages selected');
  return PageRangeResult.ok(out);
}

/// Groups `0..pageCount-1` into consecutive chunks of [size].
List<List<int>> chunkPages(int pageCount, int size) {
  assert(size > 0, 'size must be positive');
  return [
    for (var s = 0; s < pageCount; s += size)
      [for (var i = s; i < s + size && i < pageCount; i++) i],
  ];
}

/// "1–3" or "5" label for 0-based [pages] that are consecutive.
String describePages(List<int> pages) {
  if (pages.isEmpty) return '';
  if (pages.length == 1) return '${pages.first + 1}';
  return '${pages.first + 1}–${pages.last + 1}';
}
