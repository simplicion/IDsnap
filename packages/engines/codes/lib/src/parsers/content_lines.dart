import 'package:engine_codes/src/text_utils.dart';

/// One vCard / iCalendar content line: `group.NAME;PARAM=a,b;BARE:value`.
class ContentLine {
  ContentLine({
    required this.name,
    required this.params,
    required this.bare,
    required this.rawValue,
    required this.text,
  });

  /// Upper-case property name without its group.
  final String name;

  /// Upper-case parameter names → values (quotes removed).
  final Map<String, List<String>> params;

  /// vCard 2.1 bare parameters (`TEL;WORK;VOICE:`), upper-case.
  final Set<String> bare;

  /// Value as written (after quoted-printable decoding).
  final String rawValue;

  /// The logical line, unfolded (for re-export).
  final String text;

  String? param(String key) => params[key]?.firstOrNull;

  /// TYPE values from `TYPE=` and 2.1 bare parameters, upper-case.
  Set<String> get types => {
    ...?params['TYPE']?.map((t) => t.toUpperCase()),
    ...bare,
  };

  bool get isBinary {
    final enc = (param('ENCODING') ?? '').toUpperCase();
    return enc == 'B' || enc == 'BASE64' || bare.contains('BASE64');
  }

  /// Text value with backslash escapes removed and `\n` as line breaks.
  String get value => unescapeBackslashes(rawValue, newlines: true);

  /// Structured value (N, ADR, ORG) split on unescaped `;`.
  List<String> get components => splitUnescaped(
    rawValue,
    ';',
  ).map((c) => unescapeBackslashes(c, newlines: true).trim()).toList();
}

/// Unfolds and parses content lines. Handles CRLF/LF/CR, folded lines
/// (leading space or tab) and quoted-printable soft line breaks.
List<ContentLine> parseContentLines(String raw) {
  final physical = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final logical = <String>[];
  for (final line in physical) {
    if (logical.isNotEmpty && _qpContinues(logical.last)) {
      final last = logical.removeLast();
      logical.add(last.substring(0, last.length - 1) + line.trimLeft());
      continue;
    }
    if (logical.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
      logical.add(logical.removeLast() + line.substring(1));
      continue;
    }
    if (line.trim().isEmpty) continue;
    logical.add(line);
  }
  return [for (final l in logical) ?_parseLine(l)];
}

bool _qpContinues(String line) {
  if (!line.endsWith('=')) return false;
  final colon = line.indexOf(':');
  if (colon < 0) return false;
  return line.substring(0, colon).toUpperCase().contains('QUOTED-PRINTABLE');
}

ContentLine? _parseLine(String line) {
  var inQuotes = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ':' && !inQuotes) {
      colon = i;
      break;
    }
  }
  if (colon <= 0) return null;
  final head = line.substring(0, colon);
  var value = line.substring(colon + 1);

  final parts = <String>[];
  final buf = StringBuffer();
  inQuotes = false;
  for (var i = 0; i < head.length; i++) {
    final c = head[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ';' && !inQuotes) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  parts.add(buf.toString());

  var name = parts.first.trim().toUpperCase();
  final dot = name.lastIndexOf('.');
  if (dot >= 0) name = name.substring(dot + 1);
  if (name.isEmpty) return null;

  final params = <String, List<String>>{};
  final bare = <String>{};
  for (final p in parts.skip(1)) {
    final eq = p.indexOf('=');
    if (eq < 0) {
      if (p.trim().isNotEmpty) bare.add(p.trim().toUpperCase());
      continue;
    }
    final key = p.substring(0, eq).trim().toUpperCase();
    final values = p
        .substring(eq + 1)
        .split(',')
        .map((v) => v.trim().replaceAll('"', ''))
        .where((v) => v.isNotEmpty)
        .toList();
    params.putIfAbsent(key, () => []).addAll(values);
  }

  final encoding = (params['ENCODING']?.firstOrNull ?? '').toUpperCase();
  if (encoding == 'QUOTED-PRINTABLE' || bare.contains('QUOTED-PRINTABLE')) {
    value = decodeQuotedPrintable(
      value,
      charset: params['CHARSET']?.firstOrNull,
    );
  }
  return ContentLine(
    name: name,
    params: params,
    bare: bare,
    rawValue: value,
    text: line,
  );
}
