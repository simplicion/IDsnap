import 'dart:convert' show latin1;
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

// Minimal, defensive PDF object reader/writer used to append incremental
// updates (PRD 3.3 stamping). It reads classic and stream cross-reference
// sections, object streams and Flate/PNG-predictor data — enough to locate
// pages and their resources. Anything else throws [PdfSyntaxException] and
// the caller falls back to a PDFium re-save.

/// The file uses a construct this reader does not support, or is damaged.
class PdfSyntaxException implements Exception {
  const PdfSyntaxException(this.message);
  final String message;

  @override
  String toString() => 'PdfSyntaxException($message)';
}

@immutable
final class PdfRef {
  const PdfRef(this.number, this.generation);
  final int number;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is PdfRef &&
      other.number == number &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(number, generation);
}

/// A name without its leading slash (escapes such as `#20` kept verbatim).
@immutable
final class PdfName {
  const PdfName(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is PdfName && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A number kept as its source token so rewriting never loses precision.
final class PdfNumber {
  const PdfNumber(this.raw);
  final String raw;

  num get value => num.tryParse(raw) ?? double.tryParse(raw) ?? 0;
}

/// A literal or hex string, kept as raw bytes including its delimiters.
final class PdfRawString {
  const PdfRawString(this.bytes);
  final Uint8List bytes;
}

final class PdfNull {
  const PdfNull();
}

const pdfNull = PdfNull();

/// A stream object: its dictionary and still-encoded data.
final class PdfStreamObject {
  const PdfStreamObject(this.dict, this.data);
  final Map<String, Object> dict;
  final Uint8List data;
}

typedef PdfDict = Map<String, Object>;

bool _isWhite(int c) =>
    c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0;

bool _isDelim(int c) =>
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0x3C || // <
    c == 0x3E || // >
    c == 0x5B || // [
    c == 0x5D || // ]
    c == 0x7B || // {
    c == 0x7D || // }
    c == 0x2F || // /
    c == 0x25; // %

bool _isRegular(int c) => !_isWhite(c) && !_isDelim(c);

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Tokenizer and object parser over a byte buffer.
class PdfLexer {
  PdfLexer(this.bytes, [this.pos = 0]);

  final Uint8List bytes;
  int pos;

  static const _maxDepth = 64;

  bool get atEnd => pos >= bytes.length;

  void skipWhitespace() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// True (and consumes it) when [keyword] follows as a whole token.
  bool tryKeyword(String keyword) {
    skipWhitespace();
    final end = pos + keyword.length;
    if (end > bytes.length) return false;
    for (var i = 0; i < keyword.length; i++) {
      if (bytes[pos + i] != keyword.codeUnitAt(i)) return false;
    }
    if (end < bytes.length && _isRegular(bytes[end])) return false;
    pos = end;
    return true;
  }

  void expectKeyword(String keyword) {
    if (!tryKeyword(keyword)) {
      throw PdfSyntaxException('Expected "$keyword" at $pos');
    }
  }

  String _regularToken() {
    final start = pos;
    while (pos < bytes.length && _isRegular(bytes[pos])) {
      pos++;
    }
    return latin1.decode(Uint8List.sublistView(bytes, start, pos));
  }

  int readInt() {
    skipWhitespace();
    final token = _regularToken();
    final v = int.tryParse(token);
    if (v == null) throw PdfSyntaxException('Expected integer at $pos');
    return v;
  }

  Object parseObject([int depth = 0]) {
    if (depth > _maxDepth) throw const PdfSyntaxException('Nesting too deep');
    skipWhitespace();
    if (atEnd) throw const PdfSyntaxException('Unexpected end of data');
    final c = bytes[pos];
    switch (c) {
      case 0x2F: // /
        pos++;
        return PdfName(_regularToken());
      case 0x28: // (
        return _literalString();
      case 0x3C: // <
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) {
          pos += 2;
          final dict = <String, Object>{};
          while (true) {
            skipWhitespace();
            if (atEnd) throw const PdfSyntaxException('Unterminated dict');
            if (bytes[pos] == 0x3E &&
                pos + 1 < bytes.length &&
                bytes[pos + 1] == 0x3E) {
              pos += 2;
              return dict;
            }
            final key = parseObject(depth + 1);
            if (key is! PdfName) {
              throw PdfSyntaxException('Dictionary key expected at $pos');
            }
            dict[key.value] = parseObject(depth + 1);
          }
        }
        final start = pos;
        while (pos < bytes.length && bytes[pos] != 0x3E) {
          pos++;
        }
        if (atEnd) throw const PdfSyntaxException('Unterminated hex string');
        pos++;
        return PdfRawString(Uint8List.fromList(bytes.sublist(start, pos)));
      case 0x5B: // [
        pos++;
        final list = <Object>[];
        while (true) {
          skipWhitespace();
          if (atEnd) throw const PdfSyntaxException('Unterminated array');
          if (bytes[pos] == 0x5D) {
            pos++;
            return list;
          }
          list.add(parseObject(depth + 1));
        }
    }
    if (_isDigit(c) || c == 0x2B || c == 0x2D || c == 0x2E) {
      final token = _regularToken();
      final asInt = int.tryParse(token);
      if (asInt != null && asInt >= 0 && !token.startsWith('+')) {
        // Look ahead for "gen R".
        final save = pos;
        skipWhitespace();
        if (!atEnd && _isDigit(bytes[pos])) {
          final genToken = _regularToken();
          final gen = int.tryParse(genToken);
          if (gen != null && tryKeyword('R')) return PdfRef(asInt, gen);
        }
        pos = save;
      }
      if (num.tryParse(token) == null && double.tryParse(token) == null) {
        throw PdfSyntaxException('Bad number at $pos');
      }
      return PdfNumber(token);
    }
    final word = _regularToken();
    switch (word) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return pdfNull;
    }
    throw PdfSyntaxException('Unexpected token at $pos');
  }

  PdfRawString _literalString() {
    final start = pos;
    pos++;
    var depth = 1;
    while (pos < bytes.length && depth > 0) {
      final c = bytes[pos];
      if (c == 0x5C) {
        pos += 2;
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29) depth--;
      pos++;
    }
    if (depth != 0) throw const PdfSyntaxException('Unterminated string');
    return PdfRawString(Uint8List.fromList(bytes.sublist(start, pos)));
  }
}

int? asInt(Object? o) => switch (o) {
  final PdfNumber n => n.value is int ? n.value as int : null,
  final int i => i,
  _ => null,
};

double? asDouble(Object? o) => switch (o) {
  final PdfNumber n => n.value.toDouble(),
  final num n => n.toDouble(),
  _ => null,
};

enum _EntryKind { free, direct, compressed }

class _XrefEntry {
  const _XrefEntry(this.kind, this.a, this.b);
  final _EntryKind kind;

  /// Offset (direct) or object-stream number (compressed).
  final int a;

  /// Generation (direct) or index in the object stream (compressed).
  final int b;
}

/// A parsed PDF file: cross-reference table, trailer and lazy objects.
class PdfFile {
  PdfFile(this.bytes) {
    _startXref = _findStartXref();
    _loadXrefChain();
  }

  final Uint8List bytes;
  final _xref = <int, _XrefEntry>{};
  final _cache = <int, Object>{};
  final _objectStreams = <int, (Uint8List, List<int>, int)>{};
  late int _startXref;
  late PdfDict _trailer;
  late bool _usesXrefStream;
  final _resolving = <int>{};

  /// Offset of the newest cross-reference section.
  int get startXref => _startXref;

  /// Newest trailer (for xref streams, the stream dictionary).
  PdfDict get trailer => _trailer;

  /// Whether the newest section is a cross-reference stream.
  bool get usesXrefStream => _usesXrefStream;

  /// Numbers of every in-use object (direct or in an object stream), in
  /// cross-reference order. Used by full rewrites (PDF encryption).
  Iterable<int> get objectNumbers => [
    for (final e in _xref.entries)
      if (e.value.kind != _EntryKind.free) e.key,
  ];

  /// Whether object [number] lives in an object stream (its strings are
  /// then not individually encrypted in an encrypted file).
  bool isCompressed(int number) => _xref[number]?.kind == _EntryKind.compressed;

  /// Decrypts raw stream data before object streams are decoded; set when
  /// reading an encrypted file.
  Uint8List Function(Uint8List data)? streamDecryptor;

  int _findStartXref() {
    const key = 'startxref';
    final from = bytes.length - 1;
    final to = (bytes.length - 4096).clamp(0, bytes.length);
    for (var i = from - key.length; i >= to; i--) {
      var match = true;
      for (var k = 0; k < key.length; k++) {
        if (bytes[i + k] != key.codeUnitAt(k)) {
          match = false;
          break;
        }
      }
      if (match) {
        final lexer = PdfLexer(bytes, i + key.length);
        return lexer.readInt();
      }
    }
    throw const PdfSyntaxException('startxref not found');
  }

  void _loadXrefChain() {
    int? offset = _startXref;
    final visited = <int>{};
    var first = true;
    while (offset != null) {
      if (!visited.add(offset) || visited.length > 256) {
        throw const PdfSyntaxException('Cross-reference loop');
      }
      if (offset < 0 || offset >= bytes.length) {
        throw const PdfSyntaxException('Cross-reference offset out of range');
      }
      final lexer = PdfLexer(bytes, offset);
      final PdfDict section;
      final bool isStream;
      if (lexer.tryKeyword('xref')) {
        section = _readClassicSection(lexer);
        isStream = false;
        final hybrid = asInt(section['XRefStm']);
        if (hybrid != null) _readXrefStream(hybrid);
      } else {
        section = _readXrefStream(offset);
        isStream = true;
      }
      if (first) {
        _trailer = section;
        _usesXrefStream = isStream;
        first = false;
      }
      offset = asInt(section['Prev']);
    }
  }

  PdfDict _readClassicSection(PdfLexer lexer) {
    while (true) {
      if (lexer.tryKeyword('trailer')) {
        final dict = lexer.parseObject();
        if (dict is! Map<String, Object>) {
          throw const PdfSyntaxException('Bad trailer');
        }
        return dict;
      }
      final start = lexer.readInt();
      final count = lexer.readInt();
      if (count < 0 || count > 10000000) {
        throw const PdfSyntaxException('Bad xref subsection');
      }
      for (var i = 0; i < count; i++) {
        final off = lexer.readInt();
        final gen = lexer.readInt();
        lexer.skipWhitespace();
        if (lexer.atEnd) throw const PdfSyntaxException('Truncated xref');
        final type = lexer.bytes[lexer.pos++];
        final num = start + i;
        if (_xref.containsKey(num)) continue;
        _xref[num] =
            type ==
                0x6E // n
            ? _XrefEntry(_EntryKind.direct, off, gen)
            : const _XrefEntry(_EntryKind.free, 0, 0);
      }
    }
  }

  PdfDict _readXrefStream(int offset) {
    final (_, _, obj) = _parseIndirect(bytes, offset);
    if (obj is! PdfStreamObject) {
      throw const PdfSyntaxException('Expected an xref stream');
    }
    final dict = obj.dict;
    final type = dict['Type'];
    if (type is! PdfName || type.value != 'XRef') {
      throw const PdfSyntaxException('Expected /Type /XRef');
    }
    final w = dict['W'];
    if (w is! List<Object> || w.length != 3) {
      throw const PdfSyntaxException('Bad /W');
    }
    final widths = [for (final x in w) asInt(x) ?? -1];
    if (widths.any((x) => x < 0 || x > 8)) {
      throw const PdfSyntaxException('Bad /W');
    }
    final size = asInt(dict['Size']) ?? 0;
    final indexObj = dict['Index'];
    final index = indexObj is List<Object>
        ? [for (final x in indexObj) asInt(x) ?? 0]
        : [0, size];
    final data = decodeStream(obj);
    final rowLen = widths[0] + widths[1] + widths[2];
    var p = 0;
    int field(int width, int fallback) {
      if (width == 0) return fallback;
      var v = 0;
      for (var i = 0; i < width; i++) {
        v = (v << 8) | data[p++];
      }
      return v;
    }

    for (var s = 0; s + 1 < index.length; s += 2) {
      final start = index[s];
      final count = index[s + 1];
      for (var i = 0; i < count; i++) {
        if (p + rowLen > data.length) {
          throw const PdfSyntaxException('Truncated xref stream');
        }
        final t = field(widths[0], 1);
        final a = field(widths[1], 0);
        final b = field(widths[2], 0);
        final num = start + i;
        if (_xref.containsKey(num)) continue;
        _xref[num] = switch (t) {
          1 => _XrefEntry(_EntryKind.direct, a, b),
          2 => _XrefEntry(_EntryKind.compressed, a, b),
          _ => const _XrefEntry(_EntryKind.free, 0, 0),
        };
      }
    }
    return dict;
  }

  /// Parses `num gen obj … endobj` at [offset] of [data].
  (int, int, Object) _parseIndirect(Uint8List data, int offset) {
    final lexer = PdfLexer(data, offset);
    final num = lexer.readInt();
    final gen = lexer.readInt();
    lexer.expectKeyword('obj');
    final value = lexer.parseObject();
    if (value is Map<String, Object> && lexer.tryKeyword('stream')) {
      // The keyword is followed by CRLF or LF.
      if (lexer.pos < data.length && data[lexer.pos] == 0x0D) lexer.pos++;
      if (lexer.pos < data.length && data[lexer.pos] == 0x0A) lexer.pos++;
      final start = lexer.pos;
      final end = _streamEnd(data, start, value);
      return (
        num,
        gen,
        PdfStreamObject(value, Uint8List.sublistView(data, start, end)),
      );
    }
    return (num, gen, value);
  }

  int _streamEnd(Uint8List data, int start, PdfDict dict) {
    var length = asInt(dict['Length']);
    final lengthObj = dict['Length'];
    if (length == null && lengthObj is PdfRef) {
      try {
        length = asInt(resolve(lengthObj));
      } on PdfSyntaxException {
        length = null;
      }
    }
    if (length != null && length >= 0 && start + length <= data.length) {
      final after = PdfLexer(data, start + length);
      if (after.tryKeyword('endstream')) return start + length;
    }
    // Fallback: scan for the keyword and trim the EOL before it.
    final at = _indexOf(data, 'endstream', start);
    if (at < 0) throw const PdfSyntaxException('Unterminated stream');
    var end = at;
    if (end > start && data[end - 1] == 0x0A) end--;
    if (end > start && data[end - 1] == 0x0D) end--;
    return end;
  }

  static int _indexOf(Uint8List data, String keyword, int from) {
    final first = keyword.codeUnitAt(0);
    outer:
    for (var i = from; i <= data.length - keyword.length; i++) {
      if (data[i] != first) continue;
      for (var k = 1; k < keyword.length; k++) {
        if (data[i + k] != keyword.codeUnitAt(k)) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// The object for [number], or [pdfNull] when it is free or missing.
  Object object(int number) {
    final cached = _cache[number];
    if (cached != null) return cached;
    if (!_resolving.add(number)) {
      throw const PdfSyntaxException('Reference cycle');
    }
    try {
      final entry = _xref[number];
      final Object value;
      if (entry == null || entry.kind == _EntryKind.free) {
        value = pdfNull;
      } else if (entry.kind == _EntryKind.direct) {
        final (n, _, obj) = _parseIndirect(bytes, entry.a);
        if (n != number) {
          throw const PdfSyntaxException('Object number mismatch');
        }
        value = obj;
      } else {
        value = _fromObjectStream(entry.a, entry.b);
      }
      _cache[number] = value;
      return value;
    } finally {
      _resolving.remove(number);
    }
  }

  Object _fromObjectStream(int streamNumber, int index) {
    var loaded = _objectStreams[streamNumber];
    if (loaded == null) {
      final stream = object(streamNumber);
      if (stream is! PdfStreamObject) {
        throw const PdfSyntaxException('Object stream missing');
      }
      final n = asInt(stream.dict['N']) ?? 0;
      final first = asInt(stream.dict['First']) ?? 0;
      final decrypt = streamDecryptor;
      final data = decodeStream(
        decrypt == null
            ? stream
            : PdfStreamObject(stream.dict, decrypt(stream.data)),
      );
      final lexer = PdfLexer(data);
      final offsets = <int>[];
      for (var i = 0; i < n; i++) {
        lexer.readInt(); // object number
        offsets.add(lexer.readInt());
      }
      loaded = (data, offsets, first);
      _objectStreams[streamNumber] = loaded;
    }
    final (data, offsets, first) = loaded;
    if (index < 0 || index >= offsets.length) {
      throw const PdfSyntaxException('Object stream index out of range');
    }
    return PdfLexer(data, first + offsets[index]).parseObject();
  }

  /// Follows [value] if it is a reference.
  Object resolve(Object? value) => switch (value) {
    null => pdfNull,
    final PdfRef r => object(r.number),
    final Object o => o,
  };

  /// Decoded stream data (no filter, or FlateDecode with PNG predictors).
  Uint8List decodeStream(PdfStreamObject stream) {
    var filter = resolve(stream.dict['Filter']);
    var parms = resolve(stream.dict['DecodeParms']);
    if (filter is List<Object>) {
      if (filter.isEmpty) {
        filter = pdfNull;
      } else if (filter.length == 1) {
        filter = resolve(filter.first);
        if (parms is List<Object>) {
          parms = parms.isEmpty ? pdfNull : resolve(parms.first);
        }
      } else {
        throw const PdfSyntaxException('Chained filters');
      }
    }
    if (filter is PdfNull) return stream.data;
    if (filter is! PdfName || filter.value != 'FlateDecode') {
      throw const PdfSyntaxException('Unsupported filter');
    }
    final Uint8List inflated;
    try {
      inflated = Uint8List.fromList(zlib.decode(stream.data));
    } on Object {
      throw const PdfSyntaxException('Bad Flate data');
    }
    if (parms is! Map<String, Object>) return inflated;
    final predictor = asInt(parms['Predictor']) ?? 1;
    if (predictor < 2) return inflated;
    if (predictor < 10) throw const PdfSyntaxException('TIFF predictor');
    return _unpredictPng(
      inflated,
      columns: asInt(parms['Columns']) ?? 1,
      colors: asInt(parms['Colors']) ?? 1,
      bits: asInt(parms['BitsPerComponent']) ?? 8,
    );
  }

  static Uint8List _unpredictPng(
    Uint8List data, {
    required int columns,
    required int colors,
    required int bits,
  }) {
    final bpp = ((colors * bits) / 8).ceil().clamp(1, 16);
    final rowLen = ((columns * colors * bits) / 8).ceil();
    final rows = data.length ~/ (rowLen + 1);
    final out = Uint8List(rows * rowLen);
    for (var r = 0; r < rows; r++) {
      final type = data[r * (rowLen + 1)];
      final src = r * (rowLen + 1) + 1;
      final dst = r * rowLen;
      for (var i = 0; i < rowLen; i++) {
        final raw = data[src + i];
        final left = i >= bpp ? out[dst + i - bpp] : 0;
        final up = r > 0 ? out[dst - rowLen + i] : 0;
        final upLeft = r > 0 && i >= bpp ? out[dst - rowLen + i - bpp] : 0;
        final int v;
        switch (type) {
          case 0:
            v = raw;
          case 1:
            v = raw + left;
          case 2:
            v = raw + up;
          case 3:
            v = raw + ((left + up) >> 1);
          case 4:
            final p = left + up - upLeft;
            final pa = (p - left).abs();
            final pb = (p - up).abs();
            final pc = (p - upLeft).abs();
            v =
                raw +
                (pa <= pb && pa <= pc
                    ? left
                    : pb <= pc
                    ? up
                    : upLeft);
          default:
            throw const PdfSyntaxException('Bad PNG predictor');
        }
        out[dst + i] = v & 0xFF;
      }
    }
    return out;
  }

  /// Leaf pages in document order, with inherited attributes applied.
  List<PdfPageNode> pages() {
    final root = resolve(_trailer['Root']);
    if (root is! Map<String, Object>) {
      throw const PdfSyntaxException('No document catalog');
    }
    final out = <PdfPageNode>[];
    _walk(root['Pages'], const {}, out, <int>{}, 0);
    return out;
  }

  static const _inheritable = ['Resources', 'MediaBox', 'CropBox', 'Rotate'];

  void _walk(
    Object? node,
    PdfDict inherited,
    List<PdfPageNode> out,
    Set<int> visited,
    int depth,
  ) {
    if (depth > 64) throw const PdfSyntaxException('Page tree too deep');
    if (node is! PdfRef) {
      throw const PdfSyntaxException('Page tree node is not indirect');
    }
    if (!visited.add(node.number)) {
      throw const PdfSyntaxException('Page tree cycle');
    }
    final dict = resolve(node);
    if (dict is! Map<String, Object>) {
      throw const PdfSyntaxException('Bad page tree node');
    }
    final type = dict['Type'];
    final kids = resolve(dict['Kids']);
    final isLeaf =
        (type is PdfName && type.value == 'Page') || kids is! List<Object>;
    final merged = {
      ...inherited,
      for (final k in _inheritable)
        if (dict.containsKey(k)) k: dict[k]!,
    };
    if (isLeaf) {
      out.add(PdfPageNode(node, dict, merged));
      return;
    }
    for (final kid in kids) {
      _walk(kid, merged, out, visited, depth + 1);
    }
  }
}

/// A leaf page: its reference, own dictionary and inherited attributes.
class PdfPageNode {
  const PdfPageNode(this.ref, this.dict, this.attributes);
  final PdfRef ref;
  final PdfDict dict;

  /// Resources, MediaBox, CropBox and Rotate, own values over inherited.
  final PdfDict attributes;
}

/// Serializes PDF objects.
class PdfWriter {
  final _out = BytesBuilder(copy: false);

  int get length => _out.length;

  Uint8List takeBytes() => _out.takeBytes();

  void raw(List<int> bytes) => _out.add(bytes);

  void text(String s) => _out.add(latin1.encode(s));

  void value(Object o) {
    switch (o) {
      case final PdfName n:
        text('/${n.value}');
      case final PdfNumber n:
        text(n.raw);
      case final int i:
        text('$i');
      case final double d:
        text(formatPdfNumber(d));
      case final PdfRawString s:
        raw(s.bytes);
      case final bool b:
        text(b ? 'true' : 'false');
      case PdfNull():
        text('null');
      case final PdfRef r:
        text('${r.number} ${r.generation} R');
      case final List<Object> list:
        text('[');
        for (final (i, item) in list.indexed) {
          if (i > 0) text(' ');
          value(item);
        }
        text(']');
      case final Map<String, Object> dict:
        text('<<');
        for (final e in dict.entries) {
          text('/${e.key} ');
          value(e.value);
          text('\n');
        }
        text('>>');
      default:
        throw PdfSyntaxException('Cannot write ${o.runtimeType}');
    }
  }
}

/// Compact decimal (max 4 places, no exponent) for content streams.
String formatPdfNumber(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  final rounded = (v * 10000).roundToDouble() / 10000;
  if (rounded == rounded.truncateToDouble()) {
    return rounded.toInt().toString();
  }
  var s = rounded.toStringAsFixed(4);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s == '-0' ? '0' : s;
}
