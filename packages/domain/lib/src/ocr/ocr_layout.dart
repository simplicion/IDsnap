import 'dart:math' as math;

import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/ocr/ocr_geometry.dart';

/// Orders [blocks] (boxes in the upright frame) the way a person reads a
/// page: recursive XY-cut over block boxes.
///
/// * Blank vertical corridors that separate *columns* (blocks on each side
///   are not row-aligned) are read left column first, top to bottom.
/// * Otherwise the page is cut into horizontal bands at blank rows and each
///   band is read top to bottom; inside a band, side-by-side blocks (form
///   labels and values, table cells) are read left to right.
/// * Overlapping blocks fall back to row-major order.
///
/// Stable for single-column pages: they come back in top-to-bottom order.
List<OcrBlock> orderBlocksForReading(List<OcrBlock> blocks) {
  final items = <_Item>[];
  final boxless = <OcrBlock>[];
  for (final b in blocks) {
    final box = b.box;
    if (box == null) {
      boxless.add(b);
    } else {
      items.add(_Item(b, box));
    }
  }
  final out = <OcrBlock>[];
  _cut(items, out, 0);
  return out..addAll(boxless);
}

/// Returns [result] with its blocks in reading order. Boxes are interpreted
/// in the upright frame given by [OcrResult.quarterTurns].
OcrResult withReadingOrder(OcrResult result) {
  final t = result.quarterTurns;
  if (t % 4 == 0) {
    return result.copyWith(blocks: orderBlocksForReading(result.blocks));
  }
  final upright = [
    for (final b in result.blocks)
      OcrBlock([for (final l in b.lines) l.withBox(uprightBox(l.box, t))]),
  ];
  final ordered = orderBlocksForReading(upright);
  // Map back to the stored frame, keeping the new order.
  final back = 4 - t % 4;
  return result.copyWith(
    blocks: [
      for (final b in ordered)
        OcrBlock([
          for (final l in b.lines) l.withBox(rotateNRect(l.box, back)),
        ]),
    ],
  );
}

class _Item {
  _Item(this.block, this.box);

  final OcrBlock block;
  final NRect box;
}

const _minColumnGap = 0.01;
const _minRowGap = 0.001;

void _cut(List<_Item> items, List<OcrBlock> out, int depth) {
  if (items.length <= 1 || depth > 64) {
    out.addAll((items.toList()..sort(_rowMajor)).map((i) => i.block));
    return;
  }
  final rows = _split(items, vertical: false);
  final cols = _split(items, vertical: true);
  if (cols.length > 1 && (rows.length == 1 || _looksLikeColumns(cols))) {
    for (final g in cols) {
      _cut(g, out, depth + 1);
    }
    return;
  }
  if (rows.length > 1) {
    // Bands top to bottom, but consecutive bands that together form
    // columns (e.g. two columns between a title and a footer, whose
    // paragraph gaps happen to leave blank rows) are read column-wise.
    var i = 0;
    while (i < rows.length) {
      var end = -1;
      List<List<_Item>>? columns;
      for (var j = rows.length - 1; j > i; j--) {
        final union = [for (var k = i; k <= j; k++) ...rows[k]];
        final c = _split(union, vertical: true);
        if (c.length > 1 && _looksLikeColumns(c)) {
          end = j;
          columns = c;
          break;
        }
      }
      if (columns != null) {
        for (final g in columns) {
          _cut(g, out, depth + 1);
        }
        i = end + 1;
      } else {
        _cut(rows[i], out, depth + 1);
        i++;
      }
    }
    return;
  }
  out.addAll((items.toList()..sort(_rowMajor)).map((i) => i.block));
}

/// Groups items separated by blank corridors along x ([vertical] cut) or y.
List<List<_Item>> _split(List<_Item> items, {required bool vertical}) {
  double start(_Item i) => vertical ? i.box.left : i.box.top;
  double end(_Item i) => vertical ? i.box.right : i.box.bottom;
  final gap = vertical ? _minColumnGap : _minRowGap;
  final sorted = items.toList()..sort((a, b) => start(a).compareTo(start(b)));
  final groups = <List<_Item>>[];
  var current = <_Item>[];
  var reach = double.negativeInfinity;
  for (final i in sorted) {
    if (current.isNotEmpty && start(i) > reach + gap) {
      groups.add(current);
      current = [];
    }
    current.add(i);
    reach = math.max(reach, end(i));
  }
  if (current.isNotEmpty) groups.add(current);
  return groups;
}

/// Columns hold independent flows of text, so their blocks rarely start at
/// the same height. Rows of a form or table do. Treat the split as columns
/// when fewer than 60% of the blocks are row-aligned with another group.
bool _looksLikeColumns(List<List<_Item>> cols) {
  var aligned = 0;
  var total = 0;
  for (var g = 0; g < cols.length; g++) {
    for (final i in cols[g]) {
      total++;
      final h = i.box.height;
      var found = false;
      for (var o = 0; o < cols.length && !found; o++) {
        if (o == g) continue;
        for (final j in cols[o]) {
          final tol = 0.5 * math.min(h, j.box.height);
          if ((i.box.top - j.box.top).abs() <= tol) {
            found = true;
            break;
          }
        }
      }
      if (found) aligned++;
    }
  }
  return total == 0 || aligned / total < 0.6;
}

/// Same visual row (vertical overlap over half the smaller height) → left to
/// right, otherwise top to bottom.
int _rowMajor(_Item a, _Item b) {
  final overlap =
      math.min(a.box.bottom, b.box.bottom) - math.max(a.box.top, b.box.top);
  final minH = math.min(a.box.height, b.box.height);
  if (minH > 0 && overlap > 0.5 * minH) {
    return a.box.left.compareTo(b.box.left);
  }
  return a.box.top.compareTo(b.box.top);
}
