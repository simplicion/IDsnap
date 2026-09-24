import 'package:engine_conversion/engine_conversion.dart';
import 'package:test/test.dart';

void main() {
  group('htmlToText', () {
    test('removes script, style and comments; decodes entities', () {
      const html = '''
<!DOCTYPE html><html><head><title>T</title><style>p{color:red}</style></head>
<body><script>alert("x < y")</script><!-- secret -->
<h1>Price &amp; tax</h1><p>1 &lt; 2 &gt; 0 &#8377;500 &#x20AC;9 &nbsp;ok</p>
<ul><li>One</li><li>Two</li></ul></body></html>''';
      final text = htmlToText(html);
      expect(text, isNot(contains('alert')));
      expect(text, isNot(contains('color')));
      expect(text, isNot(contains('secret')));
      expect(text, contains('Price & tax'));
      expect(text, contains('1 < 2 > 0 ₹500 €9 ok'));
      expect(text, contains('• One'));
      expect(text, contains('• Two'));
    });

    test('collapses source whitespace and keeps paragraph breaks', () {
      expect(htmlToText('<p>a\n   b</p><p>c</p>'), 'a b\n\nc');
    });

    test('leaves unknown entities untouched', () {
      expect(decodeEntities('&bogus; &#xZZ;'), '&bogus; &#xZZ;');
    });
  });

  group('CSV', () {
    test('parses quotes, escaped quotes, embedded delimiters and newlines', () {
      final rows = parseCsv(
        'name,note\r\n"Doe, J","said ""hi""\nthen left"\r\nA,',
      );
      expect(rows, [
        ['name', 'note'],
        ['Doe, J', 'said "hi"\nthen left'],
        ['A', ''],
      ]);
    });

    test('detects semicolon and tab delimiters', () {
      expect(parseCsv('a;b\n1;2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(detectDelimiter('a\tb\tc'), '\t');
    });

    test('write → parse round-trips', () {
      final rows = [
        ['a,b', 'q"uote', 'multi\nline', ' pad ', 'हिन्दी ₹'],
        ['1', '', '3', '4', '5'],
      ];
      expect(parseCsv(writeCsv(rows)), rows);
    });

    test('table rendering aligns columns', () {
      final table = csvToTable([
        ['Item', 'Qty'],
        ['Apple', '10'],
      ]).split('\n');
      expect(table[0], 'Item  | Qty');
      expect(table[1], '------+----');
      expect(table[2], 'Apple | 10');
    });
  });

  group('Markdown', () {
    test('parses headings, lists, quotes, code and inline markup', () {
      final blocks = parseMarkdown('''
# Title
Some **bold** and _em_ text
continues here with a [link](https://x.y).

- one
* two
1. first
> quoted
```
code **kept**
```
''');
      expect(blocks.map((b) => b.kind), [
        MdBlockKind.heading,
        MdBlockKind.paragraph,
        MdBlockKind.bullet,
        MdBlockKind.bullet,
        MdBlockKind.numbered,
        MdBlockKind.quote,
        MdBlockKind.code,
      ]);
      expect(
        blocks[1].text,
        'Some bold and em text continues here with a link (https://x.y).',
      );
      expect(blocks[6].text, 'code **kept**');
    });

    test('plain text upper-cases H1 and groups list items', () {
      final text = markdownToPlainText('# Notes\n\n- a\n- b\n\n## Sub');
      expect(text, 'NOTES\n\n• a\n• b\n\nSub');
    });
  });
}
