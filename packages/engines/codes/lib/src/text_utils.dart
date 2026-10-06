import 'dart:convert';

/// Splits [input] on [separator] characters that are not escaped with a
/// backslash. Segments keep their escapes; see [unescapeBackslashes].
List<String> splitUnescaped(String input, String separator) {
  final parts = <String>[];
  final current = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == r'\' && i + 1 < input.length) {
      current
        ..write(c)
        ..write(input[i + 1]);
      i++;
    } else if (c == separator) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
  }
  parts.add(current.toString());
  return parts;
}

/// Index of the first [char] in [input] at or after [start] that is not
/// escaped with a backslash, or -1.
int indexOfUnescaped(String input, String char, [int start = 0]) {
  for (var i = start; i < input.length; i++) {
    final c = input[i];
    if (c == r'\') {
      i++;
    } else if (c == char) {
      return i;
    }
  }
  return -1;
}

/// Removes backslash escapes (`\;` → `;`, `\\` → `\`). With [newlines],
/// `\n` / `\N` become line breaks (vCard / iCalendar text values).
String unescapeBackslashes(String input, {bool newlines = false}) {
  if (!input.contains(r'\')) return input;
  final out = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == r'\' && i + 1 < input.length) {
      final next = input[i + 1];
      if (newlines && (next == 'n' || next == 'N')) {
        out.write('\n');
      } else {
        out.write(next);
      }
      i++;
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// Escapes [chars] (and the backslash itself) with a backslash.
String escapeBackslashes(String input, String chars) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    final c = String.fromCharCode(rune);
    if (c == r'\' || chars.contains(c)) out.write(r'\');
    out.write(c);
  }
  return out.toString();
}

/// Percent-decoding that never throws (bad escapes are kept as typed).
/// `+` is kept as a plus sign unless [plusAsSpace].
String safeDecodeComponent(String input, {bool plusAsSpace = false}) {
  final source = plusAsSpace ? input.replaceAll('+', ' ') : input;
  try {
    return Uri.decodeComponent(source);
  } on Object {
    return source;
  }
}

/// Parses `a=1&b=2` query text into a case-insensitive (lower-cased keys)
/// map. Later duplicates are ignored.
Map<String, String> parseQuery(String query, {bool plusAsSpace = false}) {
  final map = <String, String>{};
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final key = safeDecodeComponent(
      eq < 0 ? pair : pair.substring(0, eq),
      plusAsSpace: plusAsSpace,
    ).toLowerCase().trim();
    final value = eq < 0
        ? ''
        : safeDecodeComponent(pair.substring(eq + 1), plusAsSpace: plusAsSpace);
    if (key.isNotEmpty) map.putIfAbsent(key, () => value);
  }
  return map;
}

/// Decodes quoted-printable text (vCard 2.1). Soft line breaks must already
/// be removed. Bytes are decoded as UTF-8 unless [charset] names Latin-1.
String decodeQuotedPrintable(String input, {String? charset}) {
  final bytes = <int>[];
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x3D && i + 2 < input.length) {
      final hex = int.tryParse(input.substring(i + 1, i + 3), radix: 16);
      if (hex != null) {
        bytes.add(hex);
        i += 2;
        continue;
      }
    }
    if (c < 0x80) {
      bytes.add(c);
    } else {
      bytes.addAll(utf8.encode(String.fromCharCode(c)));
    }
  }
  final cs = charset?.toLowerCase() ?? 'utf-8';
  if (cs.contains('8859') || cs.contains('latin') || cs.contains('1252')) {
    return latin1.decode(bytes, allowInvalid: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Removes a case-insensitive [prefix] from [input], or returns null.
String? stripPrefixIgnoreCase(String input, String prefix) =>
    input.length >= prefix.length &&
        input.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase()
    ? input.substring(prefix.length)
    : null;

/// Collapses runs of whitespace; null when the result is empty.
String? cleanOrNull(String? value) {
  if (value == null) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

String twoDigits(int n) => n.toString().padLeft(2, '0');
