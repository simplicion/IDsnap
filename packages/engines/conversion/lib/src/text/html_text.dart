/// Converts HTML to readable plain text: drops scripts, styles and comments,
/// turns block elements into line breaks and decodes character entities.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp('<!--.*?-->', dotAll: true), '')
      .replaceAll(
        RegExp(
          r'<(script|style|head|noscript|template|svg)\b[^>]*>.*?</\1\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(RegExp('<!DOCTYPE[^>]*>', caseSensitive: false), '');

  // Whitespace in HTML source is not significant.
  s = s.replaceAll(RegExp(r'\s+'), ' ');

  s = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'<(td|th)\b[^>]*>', caseSensitive: false), '\t')
      .replaceAll(
        RegExp(
          '</?(p|div|h[1-6]|tr|table|ul|ol|section|article|header|footer|'
          'nav|main|aside|blockquote|pre|hr|dl|dt|dd|figure|figcaption|'
          r'title|form|fieldset)\b[^>]*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(RegExp('<[^>]*>'), '');

  s = decodeEntities(s);

  final lines = s
      .split('\n')
      .map(
        (l) => l
            .replaceAll(RegExp('[  ]+'), ' ')
            .replaceAll(RegExp(r'\t\s*'), '\t')
            .trim(),
      )
      .toList();
  final out = <String>[];
  for (final l in lines) {
    if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(l);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

const _named = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'bull': '•',
  'middot': '·',
  'euro': '€',
  'pound': '£',
  'yen': '¥',
  'cent': '¢',
  'deg': '°',
  'times': '×',
  'divide': '÷',
  'laquo': '«',
  'raquo': '»',
  'sect': '§',
  'para': '¶',
};

/// Decodes named (common subset), decimal and hex character references.
String decodeEntities(String s) =>
    s.replaceAllMapped(RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        return _codePoint(int.tryParse(e.substring(2), radix: 16)) ?? m[0]!;
      }
      if (e.startsWith('#')) {
        return _codePoint(int.tryParse(e.substring(1))) ?? m[0]!;
      }
      return _named[e] ?? _named[e.toLowerCase()] ?? m[0]!;
    });

String? _codePoint(int? cp) {
  if (cp == null || cp <= 0 || cp > 0x10FFFF) return null;
  if (cp >= 0xD800 && cp <= 0xDFFF) return null;
  return String.fromCharCode(cp);
}
