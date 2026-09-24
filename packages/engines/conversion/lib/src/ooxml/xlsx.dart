// XML is built from adjacent literals; whitespace between them is wrong.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:engine_conversion/src/ooxml/zip_utils.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

final _plainNumber = RegExp(r'^-?(0|[1-9]\d{0,14})(\.\d{1,15})?$');

/// Writes rows to a minimal, valid SpreadsheetML (.xlsx) workbook with one
/// sheet. Plain numbers become numeric cells; everything else is an inline
/// string, so leading zeros and codes like "007" are preserved.
Uint8List writeXlsx(List<List<String>> rows, {String sheetName = 'Sheet1'}) {
  final data = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    data.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v.isEmpty) continue;
      final ref = '${columnName(c)}${r + 1}';
      if (_plainNumber.hasMatch(v)) {
        data.write('<c r="$ref"><v>$v</v></c>');
      } else {
        data.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(v)}</t></is></c>',
        );
      }
    }
    data.write('</row>');
  }
  final safeName = xmlEscape(
    sheetName.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim().padRight(1, 'S'),
  );
  const h = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  return buildPackage({
    '[Content_Types].xml':
        '$h<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '$h<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '$h<workbook xmlns="$main" xmlns:r="$rel">'
        '<sheets><sheet name="${safeName.length > 31 ? safeName.substring(0, 31) : safeName}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '$h<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$rel/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="$rel/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '$h<styleSheet xmlns="$main">'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml':
        '$h<worksheet xmlns="$main" xmlns:r="$rel"><sheetData>$data</sheetData></worksheet>',
  });
}

/// A1-style column letters: 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var n = index + 1;
  final b = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    b.write(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return b.toString().split('').reversed.join();
}

/// Inverse of [columnName] for the letter part of a cell reference.
int columnIndex(String ref) {
  var n = 0;
  for (final code in ref.codeUnits) {
    if (code < 65 || code > 90) break;
    n = n * 26 + (code - 64);
  }
  return n - 1;
}

@immutable
class XlsxSheet {
  const XlsxSheet(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

/// Reads cell values from every sheet, in workbook order. Resolves shared
/// strings, inline strings, booleans, errors and cached formula results.
List<XlsxSheet> readXlsx(Uint8List bytes) {
  final archive = openPackage(bytes);
  final workbook = requireXmlPart(archive, 'xl/workbook.xml');
  final rels = readRelationships(archive, 'xl/_rels/workbook.xml.rels');

  final shared = <String>[];
  final sst = readXmlPart(archive, 'xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in descendantsNamed(sst, 'si')) {
      // Rich text runs: concatenate every <t>, skipping phonetic hints.
      shared.add(
        descendantsNamed(si, 't')
            .where(
              (t) => !t.ancestors.whereType<XmlElement>().any(
                (a) => localName(a) == 'rPh',
              ),
            )
            .map((t) => t.innerText)
            .join(),
      );
    }
  }

  final styles = _readDateStyles(archive);
  final date1904 = descendantsNamed(
    workbook,
    'workbookPr',
  ).any((e) => const {'1', 'true'}.contains(attr(e, 'date1904')));

  final sheets = <XlsxSheet>[];
  for (final sheet in descendantsNamed(workbook, 'sheet')) {
    final name = attr(sheet, 'name') ?? 'Sheet${sheets.length + 1}';
    final target = rels[relationshipId(sheet)];
    if (target == null) continue;
    final path = resolveTarget('xl/workbook.xml', target);
    final xml = readXmlPart(archive, path);
    if (xml == null) continue;
    final rows = <List<String>>[];
    for (final row in descendantsNamed(xml, 'row')) {
      final rowIndex =
          (int.tryParse(attr(row, 'r') ?? '') ?? rows.length + 1) - 1;
      while (rows.length < rowIndex) {
        rows.add(<String>[]);
      }
      final cells = <String>[];
      for (final c in row.childElements.where((e) => localName(e) == 'c')) {
        final ref = attr(c, 'r');
        final col = ref == null ? cells.length : columnIndex(ref);
        while (cells.length < col) {
          cells.add('');
        }
        final type = attr(c, 't');
        final v = c.childElements
            .where((e) => localName(e) == 'v')
            .firstOrNull
            ?.innerText;
        final value = switch (type) {
          's' => _at(shared, v) ?? '',
          'inlineStr' => descendantsNamed(
            c,
            't',
          ).map((t) => t.innerText).join(),
          'b' => v == '1' ? 'TRUE' : 'FALSE',
          null || 'n' => _formatNumber(
            v ?? '',
            _at(styles, attr(c, 's')),
            date1904: date1904,
          ),
          _ => v ?? '',
        };
        cells.add(value);
      }
      rows.add(cells);
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
      rows.removeLast();
    }
    sheets.add(XlsxSheet(name, rows));
  }
  return sheets;
}

/// How a cell style displays numbers, as far as CSV export cares.
enum XlsxNumberKind { plain, date, time, dateTime }

/// Kind per `cellXfs` index (the cell `s` attribute).
List<XlsxNumberKind> _readDateStyles(Archive archive) {
  final doc = readXmlPart(archive, 'xl/styles.xml');
  if (doc == null) return const [];
  final custom = <int, String>{
    for (final f in descendantsNamed(doc, 'numFmt'))
      ?int.tryParse(attr(f, 'numFmtId') ?? ''): attr(f, 'formatCode') ?? '',
  };
  final xfs = descendantsNamed(doc, 'cellXfs').firstOrNull;
  if (xfs == null) return const [];
  return [
    for (final xf in xfs.childElements.where((e) => localName(e) == 'xf'))
      _kindFor(int.tryParse(attr(xf, 'numFmtId') ?? '') ?? 0, custom),
  ];
}

XlsxNumberKind _kindFor(int id, Map<int, String> custom) {
  final code = custom[id];
  if (code != null) return classifyNumberFormat(code);
  return switch (id) {
    14 || 15 || 16 || 17 => XlsxNumberKind.date,
    18 || 19 || 20 || 21 || 45 || 46 || 47 => XlsxNumberKind.time,
    22 => XlsxNumberKind.dateTime,
    _ => XlsxNumberKind.plain,
  };
}

/// Classifies a custom Excel number format code. Quoted literals, escapes
/// and `[...]` sections (colors, locales, elapsed time) are ignored. `m` is
/// a month unless the format also has hours or seconds.
XlsxNumberKind classifyNumberFormat(String code) {
  final c = code
      .split(';')
      .first
      .replaceAll(RegExp('"[^"]*"'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase();
  final hasTime = c.contains('h') || c.contains('s');
  final hasDate =
      c.contains('d') || c.contains('y') || (c.contains('m') && !hasTime);
  if (hasDate && hasTime) return XlsxNumberKind.dateTime;
  if (hasDate) return XlsxNumberKind.date;
  if (hasTime && RegExp('[hs]').hasMatch(c)) return XlsxNumberKind.time;
  return XlsxNumberKind.plain;
}

/// Renders an Excel serial as ISO `yyyy-MM-dd` / `HH:mm:ss` when the cell is
/// date-formatted; other numbers are returned unchanged.
String _formatNumber(
  String raw,
  XlsxNumberKind? kind, {
  required bool date1904,
}) {
  if (kind == null || kind == XlsxNumberKind.plain) return raw;
  final serial = double.tryParse(raw);
  if (serial == null || serial < 0) return raw;
  return formatExcelSerial(serial, kind: kind.name, date1904: date1904);
}

/// Converts an Excel serial date. [kind] is `date`, `time` or `dateTime`.
/// Uses the 1899-12-30 epoch, which absorbs Excel's fictitious 1900-02-29
/// for every date after February 1900.
String formatExcelSerial(
  double serial, {
  String kind = 'date',
  bool date1904 = false,
}) {
  final epoch = date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
  final ms = (serial * 86400000).round();
  final dt = epoch.add(Duration(milliseconds: ms));
  String two(int v) => v.toString().padLeft(2, '0');
  final date =
      '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}';
  final time = '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  return switch (kind) {
    'time' => time,
    'dateTime' =>
      dt.hour == 0 && dt.minute == 0 && dt.second == 0 ? date : '$date $time',
    _ => date,
  };
}

/// Element at a numeric string index, or null when missing/out of range.
T? _at<T>(List<T> list, String? index) {
  final i = int.tryParse(index ?? '');
  return i == null || i < 0 || i >= list.length ? null : list[i];
}
