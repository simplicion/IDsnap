import 'package:meta/meta.dart';

enum MdBlockKind { heading, bullet, numbered, quote, code, paragraph, rule }

/// A simplified Markdown block used for text and DOCX output.
@immutable
class MdBlock {
  const MdBlock(this.kind, this.text, {this.level = 0});

  final MdBlockKind kind;
  final String text;

  /// Heading level (1–6) or list number.
  final int level;
}

/// Parses the common CommonMark subset: ATX headings, bullet and numbered
/// lists, block quotes, fenced code, rules and paragraphs.
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  final para = <String>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');

  void flush() {
    if (para.isEmpty) return;
    blocks.add(MdBlock(MdBlockKind.paragraph, stripInline(para.join(' '))));
    para.clear();
  }

  final heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
  final bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
  final numbered = RegExp(r'^\s*(\d{1,9})[.)]\s+(.*)$');
  final quote = RegExp(r'^\s{0,3}>\s?(.*)$');
  final fence = RegExp(r'^\s{0,3}(```|~~~)');
  final rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (fence.hasMatch(line)) {
      flush();
      final marker = fence.firstMatch(line)![1]!;
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith(marker)) {
        code.add(lines[i]);
        i++;
      }
      blocks.add(MdBlock(MdBlockKind.code, code.join('\n')));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    if (rule.hasMatch(line)) {
      flush();
      blocks.add(const MdBlock(MdBlockKind.rule, ''));
      continue;
    }
    final h = heading.firstMatch(line);
    if (h != null) {
      flush();
      blocks.add(
        MdBlock(MdBlockKind.heading, stripInline(h[2]!), level: h[1]!.length),
      );
      continue;
    }
    final b = bullet.firstMatch(line);
    if (b != null) {
      flush();
      blocks.add(MdBlock(MdBlockKind.bullet, stripInline(b[1]!)));
      continue;
    }
    final n = numbered.firstMatch(line);
    if (n != null) {
      flush();
      blocks.add(
        MdBlock(
          MdBlockKind.numbered,
          stripInline(n[2]!),
          level: int.parse(n[1]!),
        ),
      );
      continue;
    }
    final q = quote.firstMatch(line);
    if (q != null) {
      flush();
      blocks.add(MdBlock(MdBlockKind.quote, stripInline(q[1]!)));
      continue;
    }
    para.add(line.trim());
  }
  flush();
  return blocks;
}

/// Removes inline Markdown markup, keeping readable text.
String stripInline(String s) => s
    .replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (m) => '[Image: ${m[1]}]',
    )
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)\s]+)[^)]*\)'),
      (m) => '${m[1]} (${m[2]})',
    )
    .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!)
    .replaceAllMapped(
      RegExp(r'(?<![\w*])([*_])(?!\s)(.+?)(?<!\s)\1(?![\w*])'),
      (m) => m[2]!,
    )
    .replaceAllMapped(RegExp('~~(.+?)~~'), (m) => m[1]!)
    .replaceAllMapped(RegExp('`([^`]+)`'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'\\([\\`*_{}\[\]()#+\-.!>])'), (m) => m[1]!);

/// Renders blocks as structured plain text (for TXT/PDF output). Level-1
/// headings are upper-cased; headings get surrounding blank lines.
String markdownToPlainText(String source, {String bullet = '•'}) {
  final out = StringBuffer();
  var first = true;
  for (final b in parseMarkdown(source)) {
    if (!first) out.writeln();
    first = false;
    switch (b.kind) {
      case MdBlockKind.heading:
        out.writeln(b.level == 1 ? b.text.toUpperCase() : b.text);
      case MdBlockKind.bullet:
        out.writeln('$bullet ${b.text}');
      case MdBlockKind.numbered:
        out.writeln('${b.level}. ${b.text}');
      case MdBlockKind.quote:
        out.writeln('    ${b.text}');
      case MdBlockKind.code:
        out.writeln(b.text.split('\n').map((l) => '    $l').join('\n'));
      case MdBlockKind.rule:
        out.writeln('-' * 40);
      case MdBlockKind.paragraph:
        out.writeln(b.text);
    }
  }
  // Consecutive list items read better without blank lines between them.
  return out
      .toString()
      .replaceAllMapped(
        RegExp(r'(^(?:•|-|\d+\.) .*)\n\n(?=(?:•|-|\d+\.) )', multiLine: true),
        (m) => '${m[1]}\n',
      )
      .trimRight();
}
