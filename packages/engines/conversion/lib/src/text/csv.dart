/// RFC 4180 CSV parsing and writing, plus monospace table rendering.
library;

/// Picks `,`, `;` or tab from the first line (ignoring quoted text).
String detectDelimiter(String text) {
  final firstLine = text.split('\n').first.replaceAll(RegExp('"[^"]*"'), '');
  final counts = {
    ',': ','.allMatches(firstLine).length,
    ';': ';'.allMatches(firstLine).length,
    '\t': '\t'.allMatches(firstLine).length,
  };
  var best = ',';
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// Parses CSV into rows. Handles quoted fields, escaped quotes (`""`),
/// embedded delimiters and newlines, CRLF, and a UTF-8 BOM.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  var s = text;
  if (s.startsWith('﻿')) s = s.substring(1);
  final d = delimiter ?? detectDelimiter(s);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldStarted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"' && !fieldStarted && field.isEmpty) {
      inQuotes = true;
      fieldStarted = true;
    } else if (c == d) {
      endField();
    } else if (c == '\r') {
      if (i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else if (c == '\n') {
      endRow();
    } else {
      field.write(c);
      fieldStarted = true;
    }
  }
  if (field.isNotEmpty || row.isNotEmpty || fieldStarted) endRow();
  return rows;
}

/// Writes rows as CSV, quoting only when needed. Lines end with CRLF.
String writeCsv(List<List<String>> rows, {String delimiter = ','}) {
  String quote(String v) {
    final needs =
        v.contains(delimiter) ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r') ||
        v.startsWith(' ') ||
        v.endsWith(' ');
    return needs ? '"${v.replaceAll('"', '""')}"' : v;
  }

  return rows.map((r) => r.map(quote).join(delimiter)).join('\r\n');
}

/// Renders rows as an aligned monospace table with a header rule.
String csvToTable(List<List<String>> rows, {int maxColumnWidth = 32}) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  String cell(List<String> r, int c) {
    final v = c < r.length ? r[c].replaceAll(RegExp(r'\s+'), ' ') : '';
    return v.length > maxColumnWidth
        ? '${v.substring(0, maxColumnWidth - 1)}…'
        : v;
  }

  final widths = List<int>.filled(cols, 1);
  for (final r in rows) {
    for (var c = 0; c < cols; c++) {
      final len = cell(r, c).length;
      if (len > widths[c]) widths[c] = len;
    }
  }
  String line(List<String> r) => [
    for (var c = 0; c < cols; c++) cell(r, c).padRight(widths[c]),
  ].join(' | ').trimRight();

  final out = StringBuffer()
    ..writeln(line(rows.first))
    ..writeln(widths.map((w) => '-' * w).join('-+-'));
  for (final r in rows.skip(1)) {
    out.writeln(line(r));
  }
  return out.toString().trimRight();
}
