import 'dart:typed_data';

import 'package:engine_conversion/src/ooxml/docx_writer.dart';
import 'package:engine_conversion/src/ooxml/zip_utils.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

@immutable
class DocxParagraph {
  const DocxParagraph(
    this.text, {
    this.headingLevel = 0,
    this.isBullet = false,
    this.pageBreakBefore = false,
  });

  final String text;

  /// 0 for body text, 1–6 for headings (Title counts as 1).
  final int headingLevel;
  final bool isBullet;
  final bool pageBreakBefore;
}

/// Extracts paragraphs (body, tables, headings, list items) from a .docx in
/// reading order. Formatting, images and floating text boxes are ignored.
List<DocxParagraph> readDocx(Uint8List bytes) {
  final archive = openPackage(bytes);
  final doc = requireXmlPart(archive, 'word/document.xml');
  final body = descendantsNamed(doc, 'body').firstOrNull ?? doc.rootElement;
  final out = <DocxParagraph>[];
  var pendingBreak = false;

  for (final p in descendantsNamed(body, 'p')) {
    // Skip paragraphs nested in another paragraph (text boxes) to avoid dupes.
    if (p.ancestors.whereType<XmlElement>().any((a) => localName(a) == 'p')) {
      continue;
    }
    final style = descendantsNamed(
      p,
      'pStyle',
    ).map((e) => attr(e, 'val')).firstOrNull;
    final text = StringBuffer();
    var hasPageBreak = false;
    for (final node in p.descendants.whereType<XmlElement>()) {
      switch (localName(node)) {
        case 't':
          text.write(node.innerText);
        case 'tab':
          if (node.parentElement != null &&
              localName(node.parentElement!) == 'r') {
            text.write('\t');
          }
        case 'br' || 'cr':
          if (attr(node, 'type') == 'page') {
            hasPageBreak = true;
          } else {
            text.write('\n');
          }
      }
    }
    final value = text.toString();
    if (value.trim().isEmpty && hasPageBreak) {
      pendingBreak = true;
      continue;
    }
    final level = _headingLevel(style);
    var isBullet =
        style != null &&
        (style.toLowerCase().contains('list') ||
            style.toLowerCase().contains('bullet'));
    isBullet = isBullet || descendantsNamed(p, 'numPr').isNotEmpty;
    final clean = value.startsWith(DocxBuilder.bulletPrefix)
        ? value.substring(DocxBuilder.bulletPrefix.length)
        : value;
    out.add(
      DocxParagraph(
        clean,
        headingLevel: level,
        isBullet: isBullet,
        pageBreakBefore: pendingBreak,
      ),
    );
    pendingBreak = hasPageBreak;
  }
  return out;
}

int _headingLevel(String? style) {
  if (style == null) return 0;
  final s = style.toLowerCase().replaceAll(' ', '');
  if (s == 'title') return 1;
  final m = RegExp(r'^heading(\d)$').firstMatch(s);
  return m == null ? 0 : int.parse(m[1]!);
}

/// Plain text with blank lines between paragraphs and "•" for list items.
/// Explicit page breaks become an extra blank line, or [pageBreak] (e.g. a
/// form feed) when given.
String docxToPlainText(List<DocxParagraph> paragraphs, {String? pageBreak}) {
  final out = StringBuffer();
  var breakPending = false;
  for (final p in paragraphs) {
    breakPending = breakPending || p.pageBreakBefore;
    if (p.text.trim().isEmpty) continue;
    if (out.isNotEmpty) {
      if (breakPending && pageBreak != null) {
        out.write(pageBreak);
      } else {
        out.writeln();
        if (breakPending) out.writeln();
      }
    }
    breakPending = false;
    out.writeln(p.isBullet ? '• ${p.text}' : p.text);
  }
  return out.toString().trimRight();
}
