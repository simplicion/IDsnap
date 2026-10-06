import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

const _good = 'The contract is signed by both parties today';

OcrResult _text(
  String text, {
  double conf = 0.95,
  double h = 0.03,
  OcrScript script = OcrScript.latin,
  double? angle,
}) => OcrResult(
  script: script,
  blocks: [
    OcrBlock([
      OcrLine(text, NRect(0.1, 0.2, 0.6, h), confidence: conf, angle: angle),
    ]),
  ],
);

final _garbage = _text('~ l', conf: 0.3);

/// Returns canned results keyed by (image path, script).
class FakeRecognizer implements TextRecognizer {
  FakeRecognizer(this.answers, {this.installed = const {OcrScript.latin}});

  final Map<String, OcrResult> answers;
  final Set<OcrScript> installed;
  final calls = <String>[];

  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      installed.contains(script)
      ? const EngineCapability(available: true, worksOffline: true)
      : EngineCapability(
          available: false,
          worksOffline: false,
          note: '${script.shortLabel} is not installed in this build.',
        );

  @override
  Future<Result<OcrResult>> recognize(String path, OcrScript script) async {
    calls.add('$path|${script.name}');
    final r = answers['$path|${script.name}'] ?? answers[path];
    return Ok(
      (r ?? OcrResult(blocks: const [], script: script)).copyWith(
        script: script,
      ),
    );
  }
}

class FakePreparer implements OcrImagePreparer {
  FakePreparer({this.normalizeFailure, this.size = 1000});

  final AppFailure? normalizeFailure;
  final int size;
  final variants = <OcrVariant>[];
  final released = <String>[];
  final created = <String>[];

  static String nameOf(OcrVariant v) =>
      'r${v.quarterTurns}${v.scale == 1 ? '' : '_s${v.scale}'}'
      '${v.enhance ? '_e' : ''}';

  @override
  Future<Result<OcrImage>> normalize(String imagePath) async {
    final f = normalizeFailure;
    if (f != null) return Err(f);
    created.add('base');
    return Ok(
      OcrImage(path: 'base', width: size, height: size, temporary: true),
    );
  }

  @override
  Future<Result<OcrImage>> variant(OcrImage base, OcrVariant v) async {
    variants.add(v);
    final name = nameOf(v);
    created.add(name);
    return Ok(
      OcrImage(
        path: name,
        width: (size * v.scale).round(),
        height: (size * v.scale).round(),
        temporary: true,
      ),
    );
  }

  @override
  Future<void> release(OcrImage image) async => released.add(image.path);
}

void main() {
  group('RecognizeText orientation', () {
    test('a good upright pass tries nothing else', () async {
      final ocr = FakeRecognizer({'base': _text(_good)});
      final prep = FakePreparer();
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('in.jpg');
      expect(r.valueOrNull!.text, _good);
      expect(r.valueOrNull!.quarterTurns, 0);
      expect(prep.variants, isEmpty);
      expect(prep.released, ['base']);
    });

    test('an upside-down page is read at 180° and boxes map back', () async {
      final ocr = FakeRecognizer({'base': _garbage, 'r2': _text(_good)});
      final prep = FakePreparer();
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('in.jpg');
      final res = r.valueOrNull!;
      expect(res.text, _good);
      expect(res.quarterTurns, 2);
      // Upright box (0.1, 0.2, 0.6, h) seen in the unrotated input frame.
      final box = res.lines.first.box;
      expect(box.left, closeTo(0.3, 1e-9));
      expect(box.top, closeTo(1 - 0.2 - 0.03, 1e-9));
      // Every temp image is released, including losing variants.
      expect(prep.released.toSet(), prep.created.toSet());
    });

    test('keeps the best of all rotations when none is good', () async {
      final ocr = FakeRecognizer({
        'base': _garbage,
        'r1': _text('Some readable words here', conf: 0.7),
        'r2': _garbage,
        'r3': _text('Some readable words', conf: 0.5),
      });
      final prep = FakePreparer();
      final r = await RecognizeText(recognizer: ocr, preparer: prep)(
        'in.jpg',
        options: const OcrOptions(enhance: OcrEnhance.off),
      );
      expect(r.valueOrNull!.quarterTurns, 1);
      expect(prep.variants.map((v) => v.quarterTurns), [2, 1, 3]);
    });

    test('line angles pick the likely rotation first and stop early', () async {
      final ocr = FakeRecognizer({
        'base': _text('~ l', conf: 0.3, angle: 90),
        'r3': _text(_good),
      });
      final prep = FakePreparer();
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('in.jpg');
      expect(r.valueOrNull!.quarterTurns, 3);
      expect(prep.variants.map((v) => v.quarterTurns), [3]);
    });

    test('autoRotate off never rotates', () async {
      final ocr = FakeRecognizer({'base': _garbage, 'r2': _text(_good)});
      final prep = FakePreparer();
      await RecognizeText(recognizer: ocr, preparer: prep)(
        'in.jpg',
        options: const OcrOptions(autoRotate: false, enhance: OcrEnhance.off),
      );
      expect(prep.variants.where((v) => v.quarterTurns != 0), isEmpty);
    });
  });

  group('RecognizeText preprocessing', () {
    test('small text is upscaled towards the target height', () async {
      // 0.01 × 1000 px = 10 px tall lines → scale 3 (capped).
      final ocr = FakeRecognizer({
        'base': _text(_good, h: 0.01, conf: 0.85),
        'r0_s3.0': _text('$_good and more words', h: 0.01),
      });
      final prep = FakePreparer();
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('in.jpg');
      expect(prep.variants.single.scale, 3);
      expect(r.valueOrNull!.text, '$_good and more words');
    });

    test('large text is not rescaled', () async {
      final ocr = FakeRecognizer({'base': _text(_good, h: 0.05)});
      final prep = FakePreparer();
      await RecognizeText(recognizer: ocr, preparer: prep)('in.jpg');
      expect(prep.variants, isEmpty);
    });

    test(
      'enhance always uses the enhanced image unless clearly worse',
      () async {
        final ocr = FakeRecognizer({
          'base': _text(_good),
          'r0_e': _text(_good, conf: 0.9),
        });
        final prep = FakePreparer();
        final r = await RecognizeText(recognizer: ocr, preparer: prep)(
          'in.jpg',
          options: const OcrOptions(enhance: OcrEnhance.always),
        );
        expect(prep.variants.single.enhance, isTrue);
        expect(r.valueOrNull!.confidence, 0.9);
      },
    );

    test('an image our decoder cannot read goes to the engine as is', () async {
      final ocr = FakeRecognizer({'in.heic': _text(_good)});
      final prep = FakePreparer(
        normalizeFailure: const AppFailure(FailureCode.unsupportedFormat),
      );
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('in.heic');
      expect(r.valueOrNull!.text, _good);
      expect(prep.variants, isEmpty);
    });

    test('a missing file is reported, not retried', () async {
      final ocr = FakeRecognizer({});
      final prep = FakePreparer(
        normalizeFailure: const AppFailure(FailureCode.notFound),
      );
      final r = await RecognizeText(recognizer: ocr, preparer: prep)('x.jpg');
      expect(r.failureOrNull?.code, FailureCode.notFound);
      expect(ocr.calls, isEmpty);
    });

    test('cancellation returns processingCancelled', () async {
      final ocr = FakeRecognizer({'base': _text(_good)});
      final token = OcrCancelToken()..cancel();
      final r = await RecognizeText(recognizer: ocr, preparer: FakePreparer())(
        'in.jpg',
        cancel: token,
      );
      expect(r.failureOrNull?.code, FailureCode.processingCancelled);
    });
  });

  group('RecognizeText scripts', () {
    test('explicit script that is not installed is a typed failure', () async {
      final ocr = FakeRecognizer({});
      final r = await RecognizeText(recognizer: ocr)(
        'in.jpg',
        options: const OcrOptions(script: OcrScript.korean),
      );
      final f = r.failureOrNull!;
      expect(f.code, FailureCode.modelUnavailable);
      expect(f.detail, 'Korean');
      expect(f.recovery, contains('not installed'));
      expect(f.nextAction, FailureAction.changeLanguage);
      expect(ocr.calls, isEmpty);
    });

    test('Auto runs Latin first and keeps it when good', () async {
      final ocr = FakeRecognizer(
        {'base': _text(_good)},
        installed: {OcrScript.latin, OcrScript.devanagari},
      );
      final r = await RecognizeText(recognizer: ocr, preparer: FakePreparer())(
        'in.jpg',
      );
      expect(r.valueOrNull!.script, OcrScript.latin);
      expect(ocr.calls, ['base|latin']);
    });

    test('Auto retries installed scripts only, best wins', () async {
      const hindi = 'यह अनुबंध आज दोनों पक्षों द्वारा हस्ताक्षरित है';
      final ocr = FakeRecognizer(
        {
          'base|latin': _text('Yah anu bandh aaj', conf: 0.4),
          'base|devanagari': _text(hindi, script: OcrScript.devanagari),
        },
        installed: {OcrScript.latin, OcrScript.devanagari},
      );
      final r = await RecognizeText(recognizer: ocr)('base');
      expect(r.valueOrNull!.script, OcrScript.devanagari);
      expect(r.valueOrNull!.text, hindi);
      expect(ocr.calls.where((c) => c.contains('chinese')), isEmpty);
    });

    test('Auto with nothing installed explains why', () async {
      final ocr = FakeRecognizer({}, installed: const {});
      final r = await RecognizeText(recognizer: ocr)('in.jpg');
      expect(r.failureOrNull?.code, FailureCode.modelUnavailable);
    });

    test('recognizer failures pass through typed', () async {
      final r = await RecognizeText(recognizer: _FailingRecognizer())('a.jpg');
      expect(r.failureOrNull?.code, FailureCode.corruptFile);
    });
  });

  group('RecognizeDocument', () {
    late FakeRecognizer ocr;
    late _FakePdf pdf;
    late _FakeFiles files;
    late RecognizeDocument job;

    setUp(() {
      ocr = FakeRecognizer({
        'photo.jpg': _text('Photo text is readable here'),
        'tmp0.png': _text('First page text of the report'),
        'tmp2.png': _text('Third page text of the report'),
      });
      pdf = _FakePdf();
      files = _FakeFiles();
      job = RecognizeDocument(
        recognize: RecognizeText(recognizer: ocr),
        pdf: pdf,
        files: files,
      );
    });

    test('reads pages one by one; a bad page does not stop the job', () async {
      pdf.badPages = {3};
      final progress = <OcrProgress>[];
      final r = await job(const [
        OcrImageSource('photo.jpg', 'photo.jpg'),
        OcrPdfSource('report.pdf', 'report.pdf'),
      ], onProgress: progress.add);
      final pages = r.valueOrNull!.pages;
      expect(pages.map((p) => p.label), [
        'photo.jpg',
        'report.pdf · page 1',
        'report.pdf · page 2',
        'report.pdf · page 3',
        'report.pdf · page 4',
      ]);
      expect(pages[0].text, 'Photo text is readable here');
      expect(pages[1].text, 'First page text of the report');
      expect(pages[2].fromPdfText, isTrue);
      expect(pages[2].text, 'Embedded page two');
      expect(pages[3].text, 'Third page text of the report');
      expect(pages[4].failure?.code, FailureCode.corruptFile);
      expect(pages[4].failure?.detail, 'report.pdf · page 4');
      expect(r.valueOrNull!.failedCount, 1);
      // Pages with a text layer are not rendered; temps are all deleted.
      expect(pdf.rendered, [0, 2, 3]);
      expect(files.live, isEmpty);
      expect(progress.last.done, progress.last.total);
      expect(progress.last.total, 5);
    });

    test('forceOcr ignores the embedded text layer', () async {
      await job(const [OcrPdfSource('report.pdf', 'r.pdf')], forceOcr: true);
      expect(pdf.rendered, [0, 1, 2, 3]);
    });

    test('cancel returns the pages finished so far', () async {
      final token = OcrCancelToken();
      final r = await job(
        const [OcrPdfSource('report.pdf', 'r.pdf')],
        cancel: token,
        onPage: (_) => token.cancel(),
      );
      expect(r.valueOrNull!.cancelled, isTrue);
      expect(r.valueOrNull!.pages, hasLength(1));
      expect(files.live, isEmpty);
    });

    test(
      'an unreadable PDF is one failed entry; other files still run',
      () async {
        pdf.locked = true;
        final r = await job(const [
          OcrPdfSource('report.pdf', 'secret.pdf'),
          OcrImageSource('photo.jpg', 'photo.jpg'),
        ]);
        final pages = r.valueOrNull!.pages;
        expect(pages.first.failure?.code, FailureCode.passwordProtected);
        expect(pages.last.text, 'Photo text is readable here');
      },
    );

    test('a missing model stops the whole job with a typed failure', () async {
      final r = await job(const [
        OcrImageSource('photo.jpg', 'photo.jpg'),
      ], options: const OcrOptions(script: OcrScript.chinese));
      expect(r.failureOrNull?.code, FailureCode.modelUnavailable);
    });
  });
}

class _FailingRecognizer implements TextRecognizer {
  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<OcrResult>> recognize(String path, OcrScript script) async =>
      const Err(AppFailure(FailureCode.corruptFile));
}

class _FakePdf implements PdfEngine {
  Set<int> badPages = {};
  bool locked = false;
  final rendered = <int>[];

  @override
  Future<Result<int>> pageCount(String path) async => locked
      ? const Err(AppFailure(FailureCode.passwordProtected))
      : const Ok(4);

  @override
  Future<Result<List<String>>> extractText(String path) async =>
      const Ok(['', 'Embedded page two', '', '']);

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) async {
    rendered.add(index);
    if (badPages.contains(index)) {
      return const Err(AppFailure(FailureCode.corruptFile));
    }
    return Ok(Uint8List.fromList([index]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFiles implements FileStore {
  final live = <String>{};

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async {
    final path = 'tmp${bytes.first}.$extension';
    live.add(path);
    return path;
  }

  @override
  Future<void> delete(String path) async => live.remove(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
