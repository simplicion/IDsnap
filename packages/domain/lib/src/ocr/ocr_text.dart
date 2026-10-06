import 'dart:math' as math;

import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:docscan_domain/src/ocr/ocr_geometry.dart';

/// Turns recognized lines into readable text (see [OcrResult.readableText]).
///
/// Per block, in stored order:
/// * a line ending in a hyphen that splits a word is joined to the next line
///   (`"docu-" + "ment"` → `"document"`; `"Jean-" + "Pierre"` keeps it);
/// * a line that runs (nearly) to the block's right edge is a wrapped line
///   and is joined to the next with a space (no space for Chinese/Japanese);
/// * short lines, lines ending with `:` and list items keep their line
///   break, so forms, addresses and bullet lists survive;
/// * blocks are separated by a blank line.
String formatOcrText(OcrResult result) {
  final paragraphs = <String>[];
  for (final block in result.blocks) {
    final text = formatOcrBlock(
      block,
      script: result.script,
      quarterTurns: result.quarterTurns,
    );
    if (text.isNotEmpty) paragraphs.add(text);
  }
  return paragraphs.join('\n\n');
}

/// Formats one block; see [formatOcrText].
String formatOcrBlock(
  OcrBlock block, {
  OcrScript script = OcrScript.latin,
  int quarterTurns = 0,
}) {
  final lines = <({String text, NRect box})>[
    for (final l in block.lines)
      (text: cleanOcrLine(l.text), box: uprightBox(l.box, quarterTurns)),
  ].where((l) => l.text.isNotEmpty).toList();
  if (lines.isEmpty) return '';

  var blockLeft = double.infinity;
  var blockRight = double.negativeInfinity;
  var maxWidth = 0.0;
  for (final l in lines) {
    blockLeft = math.min(blockLeft, l.box.left);
    blockRight = math.max(blockRight, l.box.right);
    maxWidth = math.max(maxWidth, l.box.width);
  }
  final blockWidth = blockRight - blockLeft;

  final out = StringBuffer(lines.first.text);
  for (var i = 1; i < lines.length; i++) {
    final prev = lines[i - 1];
    final next = lines[i].text;
    final prevText = out.toString();
    final listItem = _listItem.hasMatch(next);

    final hyphen = _trailingHyphen.firstMatch(prevText);
    if (hyphen != null && !listItem && _startsWithLetter(next)) {
      final mark = hyphen.group(1)!;
      final soft = mark == '\u00AD';
      final lower = _startsLowercase(next);
      _replaceBuffer(
        out,
        (soft || lower)
            ? prevText.substring(0, prevText.length - mark.length)
            : prevText,
      );
      out.write(next);
      continue;
    }

    final wrapped =
        blockWidth > 0 &&
        prev.box.right >= blockRight - 0.15 * blockWidth &&
        prev.box.width >= 0.6 * maxWidth;
    final endsLabel = prevText.endsWith(':');
    // "Name: Rahul" / "Class: 12": field rows, not a wrapped sentence.
    final fieldRows = _field.hasMatch(next) && _field.hasMatch(prev.text);
    if (wrapped && !listItem && !endsLabel && !fieldRows) {
      out
        ..write(_joiner(script, prevText, next))
        ..write(next);
    } else {
      out
        ..write('\n')
        ..write(next);
    }
  }
  return out.toString();
}

/// Normalizes whitespace and common recognition artifacts in one line:
/// ligatures, non-breaking/odd spaces, runs of spaces, and spaces before
/// `,` `.` `;` `)` or after `(`.
String cleanOcrLine(String line) {
  var s = line;
  _ligatures.forEach((k, v) => s = s.replaceAll(k, v));
  s = s
      .replaceAll(_oddSpaces, ' ')
      .replaceAll(_zeroWidth, '')
      .replaceAll(RegExp(' {2,}'), ' ')
      .replaceAllMapped(
        RegExp(r'(\p{L}|\p{N}) ([,.;)\]])(?=\s|$)', unicode: true),
        (m) => '${m[1]}${m[2]}',
      )
      .replaceAllMapped(RegExp(r'([(\[]) (?=\S)'), (m) => m[1]!);
  return s.trim();
}

/// Joins two wrapped lines of the same paragraph.
String _joiner(OcrScript script, String prev, String next) {
  if (!script.joinsWithoutSpace) return ' ';
  final a = prev.isEmpty ? '' : prev[prev.length - 1];
  final b = next.isEmpty ? '' : next[0];
  // Latin words inside CJK text still need their space.
  return _asciiWord.hasMatch(a) && _asciiWord.hasMatch(b) ? ' ' : '';
}

void _replaceBuffer(StringBuffer b, String s) {
  b
    ..clear()
    ..write(s);
}

bool _startsWithLetter(String s) =>
    s.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(s);

bool _startsLowercase(String s) =>
    s.isNotEmpty && RegExp(r'^\p{Ll}', unicode: true).hasMatch(s);

final _trailingHyphen = RegExp(r'\p{L}([-\u00AD\u2010])$', unicode: true);
final _listItem = RegExp(
  r'^(?:[•·▪◦‣*–—-]\s|\(?\d{1,3}[.)]\s|\(?[a-zA-Z][.)]\s|[ivxIVX]{1,4}[.)]\s)',
);
final _asciiWord = RegExp('[A-Za-z0-9]');
final _field = RegExp(r'^[^:.!?]{1,30}:\s*\S');
final _oddSpaces = RegExp('[\t\u00A0\u2000-\u200A\u202F\u205F\u3000]');
final _zeroWidth = RegExp('[\u200B\uFEFF]');
const _ligatures = {
  '\uFB00': 'ff',
  '\uFB01': 'fi',
  '\uFB02': 'fl',
  '\uFB03': 'ffi',
  '\uFB04': 'ffl',
};
