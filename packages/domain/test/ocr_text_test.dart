import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

OcrLine _l(
  String t,
  double left,
  double top,
  double width, {
  double h = 0.02,
}) => OcrLine(t, NRect(left, top, width, h));

OcrResult _r(List<OcrBlock> blocks, {OcrScript script = OcrScript.latin}) =>
    OcrResult(blocks: blocks, script: script);

void main() {
  group('reading order', () {
    List<String> order(List<OcrBlock> blocks) =>
        orderBlocksForReading(blocks).map((b) => b.lines.first.text).toList();

    test('two columns under a full-width title, footer last', () {
      final blocks = [
        // Deliberately shuffled, as engines may return them.
        OcrBlock([_l('R1', 0.55, 0.20, 0.35), _l('r1b', 0.55, 0.23, 0.35)]),
        OcrBlock([_l('Footer', 0.1, 0.92, 0.8)]),
        OcrBlock([_l('L1', 0.10, 0.20, 0.35), _l('l1b', 0.10, 0.23, 0.35)]),
        OcrBlock([_l('Title', 0.1, 0.05, 0.8, h: 0.04)]),
        OcrBlock([_l('R2', 0.55, 0.55, 0.35), _l('r2b', 0.55, 0.58, 0.35)]),
        OcrBlock([_l('L2', 0.10, 0.40, 0.35), _l('l2b', 0.10, 0.43, 0.35)]),
      ];
      expect(order(blocks), ['Title', 'L1', 'L2', 'R1', 'R2', 'Footer']);
    });

    test('form rows (label | value) read left to right, row by row', () {
      final blocks = [
        OcrBlock([_l('Rahul', 0.5, 0.10, 0.3)]),
        OcrBlock([_l('Class:', 0.1, 0.15, 0.2)]),
        OcrBlock([_l('Name:', 0.1, 0.10, 0.2)]),
        OcrBlock([_l('12', 0.5, 0.15, 0.1)]),
        OcrBlock([_l('Roll:', 0.1, 0.20, 0.2)]),
        OcrBlock([_l('42', 0.5, 0.20, 0.1)]),
      ];
      expect(order(blocks), ['Name:', 'Rahul', 'Class:', '12', 'Roll:', '42']);
    });

    test('single column stays top to bottom', () {
      final blocks = [
        OcrBlock([_l('c', 0.1, 0.5, 0.8)]),
        OcrBlock([_l('a', 0.1, 0.1, 0.8)]),
        OcrBlock([_l('b', 0.12, 0.3, 0.7)]),
      ];
      expect(order(blocks), ['a', 'b', 'c']);
    });

    test('overlapping blocks fall back to row-major order', () {
      final blocks = [
        OcrBlock([_l('right', 0.45, 0.101, 0.4)]),
        OcrBlock([_l('left', 0.1, 0.1, 0.4)]),
        OcrBlock([_l('below', 0.3, 0.11, 0.4)]),
      ];
      expect(order(blocks).first, 'left');
    });

    test('withReadingOrder works in the upright frame of a rotated page', () {
      // Upright: "first" above "second". Stored in the input frame, which
      // is the upright frame rotated back by 1 quarter turn.
      const up1 = NRect(0.1, 0.1, 0.8, 0.05);
      const up2 = NRect(0.1, 0.5, 0.8, 0.05);
      final stored = OcrResult(
        script: OcrScript.latin,
        quarterTurns: 1,
        blocks: [
          OcrBlock([OcrLine('second', rotateNRect(up2, 3))]),
          OcrBlock([OcrLine('first', rotateNRect(up1, 3))]),
        ],
      );
      final ordered = withReadingOrder(stored);
      expect(ordered.blocks.map((b) => b.text), ['first', 'second']);
      expect(ordered.blocks.first.lines.first.box, rotateNRect(up1, 3));
    });
  });

  group('geometry', () {
    test('rotateNRect: four quarter turns are the identity', () {
      const r = NRect(0.1, 0.2, 0.3, 0.1);
      var x = r;
      for (var i = 0; i < 4; i++) {
        x = rotateNRect(x, 1);
      }
      expect(x.left, closeTo(r.left, 1e-12));
      expect(x.top, closeTo(r.top, 1e-12));
      expect(x.width, closeTo(r.width, 1e-12));
      expect(x.height, closeTo(r.height, 1e-12));
    });

    test('rotateNRect 1 turn matches a clockwise image rotation', () {
      // Top-left corner area moves to the top-right after 90° clockwise.
      final r = rotateNRect(const NRect(0, 0, 0.2, 0.1), 1);
      expect(r.left, closeTo(0.9, 1e-12));
      expect(r.top, 0);
      expect(r.width, closeTo(0.1, 1e-12));
      expect(r.height, closeTo(0.2, 1e-12));
    });

    test('unrotateResult maps boxes back and records the turns', () {
      const up = NRect(0.1, 0.1, 0.5, 0.05);
      final res = unrotateResult(
        const OcrResult(
          script: OcrScript.latin,
          blocks: [
            OcrBlock([OcrLine('x', up)]),
          ],
        ),
        3,
      );
      expect(res.quarterTurns, 3);
      final back = rotateNRect(res.lines.first.box, 3);
      expect(back.left, closeTo(up.left, 1e-12));
      expect(back.top, closeTo(up.top, 1e-12));
    });

    test('block box is the union of its lines', () {
      final b = OcrBlock([_l('a', 0.1, 0.1, 0.3), _l('b', 0.2, 0.2, 0.5)]);
      expect(b.box!.left, 0.1);
      expect(b.box!.right, closeTo(0.7, 1e-12));
      expect(b.box!.bottom, closeTo(0.22, 1e-12));
      expect(const OcrBlock([]).box, isNull);
    });
  });

  group('readable text', () {
    test('joins wrapped lines into one paragraph', () {
      final r = _r([
        OcrBlock([
          _l('The quick brown fox jumps', 0.1, 0.10, 0.80),
          _l('over the lazy dog and runs', 0.1, 0.13, 0.79),
          _l('away.', 0.1, 0.16, 0.10),
        ]),
      ]);
      expect(
        r.readableText,
        'The quick brown fox jumps over the lazy dog and runs away.',
      );
      // Raw text keeps the engine's line breaks.
      expect(r.text.split('\n'), hasLength(3));
    });

    test('removes end-of-line hyphenation', () {
      final r = _r([
        OcrBlock([
          _l('Please sign the docu-', 0.1, 0.10, 0.80),
          _l('ment before Friday.', 0.1, 0.13, 0.50),
        ]),
      ]);
      expect(r.readableText, 'Please sign the document before Friday.');
    });

    test('keeps hyphens of compound names and drops soft hyphens', () {
      final names = _r([
        OcrBlock([
          _l('Signed by Jean-', 0.1, 0.10, 0.80),
          _l('Pierre Martin', 0.1, 0.13, 0.30),
        ]),
      ]);
      expect(names.readableText, 'Signed by Jean-Pierre Martin');
      final soft = _r([
        OcrBlock([
          _l('infor\u00AD', 0.1, 0.10, 0.80),
          _l('Mation', 0.1, 0.13, 0.30),
        ]),
      ]);
      expect(soft.readableText, 'inforMation');
    });

    test('keeps line breaks in forms, labels and lists', () {
      final r = _r([
        OcrBlock([
          _l('Name: Rahul', 0.1, 0.10, 0.30),
          _l('Class: 12', 0.1, 0.13, 0.20),
        ]),
        OcrBlock([
          _l('Items to bring:', 0.1, 0.30, 0.80),
          _l('• A pen and some paper for the exam hall', 0.1, 0.33, 0.80),
          _l('• Your ID card', 0.1, 0.36, 0.30),
          _l('1. Arrive early', 0.1, 0.39, 0.30),
        ]),
      ]);
      expect(
        r.readableText,
        'Name: Rahul\nClass: 12\n\n'
        'Items to bring:\n'
        '• A pen and some paper for the exam hall\n'
        '• Your ID card\n'
        '1. Arrive early',
      );
    });

    test('Chinese/Japanese wrapped lines join without a space', () {
      final r = _r([
        OcrBlock([_l('今日は良い天気です', 0.1, 0.10, 0.80), _l('ね。', 0.1, 0.13, 0.10)]),
      ], script: OcrScript.japanese);
      expect(r.readableText, '今日は良い天気ですね。');
    });

    test('cleans whitespace, ligatures and spaces before punctuation', () {
      expect(cleanOcrLine('  Total\u00A0 :  5 ,  ok .  '), 'Total : 5, ok.');
      expect(cleanOcrLine('\uFB01rst ( note )'), 'first (note)');
      expect(cleanOcrLine('a\u200Bb'), 'ab');
      // Zero-width joiners shape Devanagari conjuncts: keep them.
      expect(cleanOcrLine('क\u094D\u200Dष'), 'क\u094D\u200Dष');
    });

    test('empty and blank lines produce no text', () {
      final r = _r([
        OcrBlock([_l('   ', 0.1, 0.1, 0.1)]),
      ]);
      expect(r.readableText, '');
    });
  });

  group('quality', () {
    test('more confident text scores higher; tiny garbage is poor', () {
      final good = assessOcr(
        _r([
          const OcrBlock([
            OcrLine(
              'Invoice number 12345 due 2026',
              NRect(0, 0, 1, 0.1),
              confidence: 0.95,
            ),
          ]),
        ]),
      );
      final bad = assessOcr(
        _r([
          const OcrBlock([
            OcrLine('~I', NRect(0, 0, 1, 0.1), confidence: 0.3),
            OcrLine('l.', NRect(0, 0, 1, 0.1), confidence: 0.2),
          ]),
        ]),
      );
      expect(good.score, greaterThan(bad.score));
      expect(good.isPoor, isFalse);
      expect(bad.isPoor, isTrue);
      expect(clearlyBetter(good, bad), isTrue);
      expect(clearlyBetter(bad, good), isFalse);
    });

    test('rotation candidates follow reported line angles', () {
      OcrResult withAngle(double a) => _r([
        OcrBlock([OcrLine('x', const NRect(0, 0, 0.5, 0.1), angle: a)]),
      ]);
      expect(rotationCandidates(withAngle(90)).first, 3);
      expect(rotationCandidates(withAngle(-90)).first, 1);
      expect(rotationCandidates(withAngle(180)).first, 2);
      expect(rotationCandidates(_r(const [])), [2, 1, 3]);
    });

    test('median line height is measured across the text', () {
      final r = _r([
        const OcrBlock([
          OcrLine('a', NRect(0, 0, 0.5, 0.01)),
          OcrLine('b', NRect(0, 0, 0.5, 0.02)),
          OcrLine('c', NRect(0, 0, 0.5, 0.03)),
        ]),
      ]);
      expect(medianLineHeightPx(r, imageWidth: 1000, imageHeight: 1000), 20);
    });
  });
}
