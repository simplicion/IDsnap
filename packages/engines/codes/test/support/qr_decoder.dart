// A minimal, test-only QR decoder for clean (undamaged) symbols: reads the
// format information, unmasks the data modules in the standard zigzag
// order, de-interleaves the Reed-Solomon blocks and decodes byte-mode
// segments. It shares no layout code with the encoder, so an encode →
// decode round trip checks the symbol really carries the payload.
import 'dart:convert';

import 'package:qr/src/rs_block.dart' show QrRsBlock;

/// Standard alignment pattern centres per version (ISO/IEC 18004 Annex E).
const _alignment = <List<int>>[
  [],
  [6, 18],
  [6, 22],
  [6, 26],
  [6, 30],
  [6, 34],
  [6, 22, 38],
  [6, 24, 42],
  [6, 26, 46],
  [6, 28, 50],
  [6, 30, 54],
  [6, 32, 58],
  [6, 34, 62],
  [6, 26, 46, 66],
  [6, 26, 48, 70],
  [6, 26, 50, 74],
  [6, 30, 54, 78],
  [6, 30, 56, 82],
  [6, 30, 58, 86],
  [6, 34, 62, 90],
  [6, 28, 50, 72, 94],
  [6, 26, 50, 74, 98],
  [6, 30, 54, 78, 102],
  [6, 28, 54, 80, 106],
  [6, 32, 58, 84, 110],
  [6, 30, 58, 86, 114],
  [6, 34, 62, 90, 118],
  [6, 26, 50, 74, 98, 122],
  [6, 30, 54, 78, 102, 126],
  [6, 26, 52, 78, 104, 130],
  [6, 30, 56, 82, 108, 134],
  [6, 34, 60, 86, 112, 138],
  [6, 30, 58, 86, 114, 142],
  [6, 34, 62, 90, 118, 146],
  [6, 30, 54, 78, 102, 126, 150],
  [6, 24, 50, 76, 102, 128, 154],
  [6, 28, 54, 80, 106, 132, 158],
  [6, 32, 58, 84, 110, 136, 162],
  [6, 26, 54, 82, 110, 138, 166],
  [6, 30, 58, 86, 114, 142, 170],
];

class DecodedQr {
  DecodedQr(this.text, this.version, this.levelBits, this.mask);
  final String text;
  final int version;

  /// Format-info EC bits: L=01, M=00, Q=11, H=10 (the qr package values).
  final int levelBits;
  final int mask;
}

bool _mask(int m, int i, int j) => switch (m) {
  0 => (i + j).isEven,
  1 => i.isEven,
  2 => j % 3 == 0,
  3 => (i + j) % 3 == 0,
  4 => (i ~/ 2 + j ~/ 3).isEven,
  5 => (i * j) % 2 + (i * j) % 3 == 0,
  6 => ((i * j) % 2 + (i * j) % 3).isEven,
  _ => ((i * j) % 3 + (i + j) % 2).isEven,
};

/// Decodes a symbol given as `dark(row, col)` over [n]×[n] modules.
DecodedQr decodeQr(int n, bool Function(int row, int col) dark) {
  final version = (n - 17) ~/ 4;
  if (version < 1 || version > 40 || version * 4 + 17 != n) {
    throw StateError('bad size $n');
  }
  // Format information, first copy (column 8, top to bottom).
  var bits = 0;
  for (var i = 0; i < 15; i++) {
    final row = i < 6 ? i : (i < 8 ? i + 1 : n - 15 + i);
    if (dark(row, 8)) bits |= 1 << i;
  }
  final format = (bits ^ 0x5412) >> 10;
  final levelBits = format >> 3;
  final mask = format & 7;

  final function = List.generate(n, (_) => List<bool>.filled(n, false));
  void mark(int r0, int c0, int r1, int c1) {
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (r >= 0 && c >= 0 && r < n && c < n) function[r][c] = true;
      }
    }
  }

  mark(0, 0, 8, 8);
  mark(0, n - 8, 8, n - 1);
  mark(n - 8, 0, n - 1, 8);
  mark(6, 0, 6, n - 1);
  mark(0, 6, n - 1, 6);
  final centres = _alignment[version - 1];
  for (final r in centres) {
    for (final c in centres) {
      final inFinder =
          (r < 9 && c < 9) || (r < 9 && c > n - 10) || (r > n - 10 && c < 9);
      if (!inFinder) mark(r - 2, c - 2, r + 2, c + 2);
    }
  }
  if (version >= 7) {
    mark(0, n - 11, 5, n - 9);
    mark(n - 11, 0, n - 9, 5);
  }

  final dataBits = <bool>[];
  var upward = true;
  for (var col = n - 1; col > 0; col -= 2) {
    if (col == 6) col--;
    for (var k = 0; k < n; k++) {
      final row = upward ? n - 1 - k : k;
      for (var c = 0; c < 2; c++) {
        final x = col - c;
        if (function[row][x]) continue;
        dataBits.add(dark(row, x) != _mask(mask, row, x));
      }
    }
    upward = !upward;
  }
  final codewords = <int>[];
  for (var i = 0; i + 8 <= dataBits.length; i += 8) {
    var b = 0;
    for (var k = 0; k < 8; k++) {
      b = (b << 1) | (dataBits[i + k] ? 1 : 0);
    }
    codewords.add(b);
  }

  // qr package level constants: L=1, M=0, Q=3, H=2 — the same as the bits.
  final blocks = QrRsBlock.getRSBlocks(version, levelBits);
  final data = [for (final _ in blocks) <int>[]];
  var index = 0;
  final maxData = blocks
      .map((b) => b.dataCount)
      .reduce((a, b) => a > b ? a : b);
  for (var i = 0; i < maxData; i++) {
    for (var b = 0; b < blocks.length; b++) {
      if (i < blocks[b].dataCount) data[b].add(codewords[index++]);
    }
  }
  final stream = data.expand((d) => d).toList();

  var pos = 0;
  int read(int count) {
    var v = 0;
    for (var k = 0; k < count; k++) {
      final byte = stream[pos >> 3];
      v = (v << 1) | ((byte >> (7 - (pos & 7))) & 1);
      pos++;
    }
    return v;
  }

  final out = <int>[];
  while (pos + 4 <= stream.length * 8) {
    final mode = read(4);
    if (mode == 0) break;
    if (mode != 4) throw StateError('unsupported mode $mode');
    final length = read(version < 10 ? 8 : 16);
    for (var k = 0; k < length; k++) {
      out.add(read(8));
    }
  }
  return DecodedQr(utf8.decode(out), version, levelBits, mask);
}
