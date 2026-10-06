import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/screens/ocr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

/// Two wrapped lines of one paragraph: `text` keeps the line break,
/// `readableText` joins them.
OcrResult _paragraph({OcrScript script = OcrScript.latin, int turns = 0}) =>
    OcrResult(
      script: script,
      quarterTurns: turns,
      blocks: const [
        OcrBlock([
          OcrLine(
            'The contract is signed by both',
            NRect(0.1, 0.20, 0.7, 0.03),
            confidence: 0.95,
          ),
          OcrLine(
            'parties today in the city.',
            NRect(0.1, 0.24, 0.6, 0.03),
            confidence: 0.95,
          ),
        ]),
      ],
    );

/// Canned recognizer: good Latin text for every path unless told otherwise.
class _FakeRecognizer implements TextRecognizer {
  _FakeRecognizer({
    this.installed = const {OcrScript.latin, OcrScript.devanagari},
  });

  final Set<OcrScript> installed;
  final failures = <String, AppFailure>{};
  final gates = <String, Completer<void>>{};
  final calls = <String>[];

  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      installed.contains(script)
      ? const EngineCapability(available: true, worksOffline: true)
      : EngineCapability.unavailable;

  @override
  Future<Result<OcrResult>> recognize(String path, OcrScript script) async {
    calls.add('$path|${script.name}');
    final gate = gates[path];
    if (gate != null) await gate.future;
    final f = failures[path];
    if (f != null) return Err(f);
    return Ok(_paragraph(script: script));
  }
}

/// Returns a fixed document result (for cases the real use case can only
/// reach with image preprocessing, e.g. rotated pages).
class _FixedRecognizeDocument implements RecognizeDocument {
  _FixedRecognizeDocument(this.result);

  final OcrDocumentResult result;

  @override
  Future<Result<OcrDocumentResult>> call(
    List<OcrSource> sources, {
    OcrOptions options = const OcrOptions(),
    OcrCancelToken? cancel,
    bool forceOcr = false,
    void Function(OcrProgress progress)? onProgress,
    void Function(OcrPage page)? onPage,
  }) async => Ok(result);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Setup {
  _Setup({Set<OcrScript>? installed})
    : ocr = _FakeRecognizer(
        installed: installed ?? const {OcrScript.latin, OcrScript.devanagari},
      );

  final h = Harness();
  final _FakeRecognizer ocr;
  final extra = <Override>[];

  void pickReturns(List<String> names) {
    when(
      () => h.picker.pickFiles(any(), multiple: any(named: 'multiple')),
    ).thenAnswer(
      (_) async =>
          Ok([for (final n in names) PickedFile(path: '/p/$n', name: n)]),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          textRecognizerProvider.overrideWithValue(ocr),
          ...extra,
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const OcrScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickAndRun(WidgetTester tester, List<String> names) async {
    pickReturns(names);
    await tester.tap(find.text('From device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recognize text'));
    await tester.pumpAndSettle();
  }
}

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(
      find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
    );

void main() {
  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(<DocumentFormat>{});
  });

  testWidgets('Auto is the default and reads with Latin first', (tester) async {
    final s = _Setup();
    await s.pump(tester);

    expect(_chip(tester, 'Auto').selected, isTrue);
    expect(_chip(tester, 'Latin').selected, isFalse);

    await s.pickAndRun(tester, ['a.jpg']);
    expect(s.ocr.calls, ['/p/a.jpg|latin']);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('Recognized'), findsOneWidget);
    expect(find.text('Page was rotated to read it'), findsNothing);
  });

  testWidgets('picker marks scripts that are not installed', (tester) async {
    final s = _Setup();
    await s.pump(tester);

    expect(find.text('Devanagari'), findsOneWidget);
    expect(find.text('Chinese (not installed)'), findsOneWidget);
    expect(find.text('Japanese (not installed)'), findsOneWidget);
    expect(find.text('Korean (not installed)'), findsOneWidget);

    await tester.tap(find.text('Devanagari'));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'Devanagari').selected, isTrue);
    expect(_chip(tester, 'Auto').selected, isFalse);

    await s.pickAndRun(tester, ['a.jpg']);
    expect(s.ocr.calls, ['/p/a.jpg|devanagari']);
  });

  testWidgets('shows progress with a label and Cancel keeps pages read', (
    tester,
  ) async {
    final s = _Setup();
    final gate = Completer<void>();
    s.ocr.gates['/p/b.jpg'] = gate;
    await s.pump(tester);
    s.pickReturns(['a.jpg', 'b.jpg']);
    await tester.tap(find.text('From device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recognize text'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('Reading b.jpg (2 of 2)…'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Stopping after this page…'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Stopped — 1 page read'), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('b.jpg'), findsNothing);
  });

  testWidgets('a failed page is shown inline and other pages are kept', (
    tester,
  ) async {
    final s = _Setup();
    s.ocr.failures['/p/b.jpg'] = const AppFailure(FailureCode.corruptFile);
    await s.pump(tester);
    await s.pickAndRun(tester, ['a.jpg', 'b.jpg', 'c.jpg']);

    expect(find.text("1 page couldn't be read"), findsOneWidget);
    expect(find.text("Couldn't read"), findsOneWidget);
    expect(find.text('File could not be read'), findsOneWidget);
    expect(find.text('b.jpg'), findsWidgets);
    expect(find.text('Recognized'), findsNWidgets(2));
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('missing model: Change language resets to Auto', (tester) async {
    final s = _Setup();
    await s.pump(tester);
    await tester.tap(find.text('Chinese (not installed)'));
    await tester.pumpAndSettle();
    expect(find.text('Not installed in this app'), findsOneWidget);

    await s.pickAndRun(tester, ['a.jpg']);
    expect(s.ocr.calls, isEmpty);
    expect(find.text('Text recognition unavailable'), findsOneWidget);
    expect(
      find.textContaining('Chinese text recognition is not installed'),
      findsOneWidget,
    );

    await tester.tap(find.text('Change language'));
    await tester.pumpAndSettle();
    expect(find.text('Text recognition unavailable'), findsNothing);
    expect(_chip(tester, 'Auto').selected, isTrue);

    await tester.tap(find.text('Recognize text'));
    await tester.pumpAndSettle();
    expect(s.ocr.calls, ['/p/a.jpg|latin']);
  });

  group('Save as searchable PDF', () {
    testWidgets('offered for Latin image results and builds a text layer', (
      tester,
    ) async {
      final s = _Setup();
      when(() => s.h.images.compress(any(), any())).thenAnswer(
        (_) async => const Ok(
          EncodedImage(
            bytes: [1, 2, 3],
            width: 10,
            height: 10,
            format: ImageOutputFormat.jpeg,
          ),
        ),
      );
      when(
        () => s.h.pdf.fromImages(
          any(),
          any(),
          textLayers: any(named: 'textLayers'),
        ),
      ).thenAnswer((_) async => Ok(Uint8List(4)));
      when(
        () => s.h.commit(any()),
      ).thenAnswer((_) async => Ok(doc('d1', name: 'a (searchable)')));
      await s.pump(tester);
      await s.pickAndRun(tester, ['a.jpg', 'b.png']);

      await tester.tap(find.text('Save as searchable PDF'));
      await tester.pumpAndSettle();
      final layers =
          verify(
                () => s.h.pdf.fromImages(
                  any(),
                  any(),
                  textLayers: captureAny(named: 'textLayers'),
                ),
              ).captured.single
              as List<OcrResult?>;
      expect(layers, hasLength(2));
      expect(layers.every((l) => l!.script == OcrScript.latin), isTrue);
      final out =
          verify(() => s.h.commit(captureAny())).captured.single as OutputFile;
      expect(out.format, DocumentFormat.pdf);
      expect(out.expectedPages, 2);
    });

    testWidgets('hidden for non-Latin results', (tester) async {
      final s = _Setup();
      await s.pump(tester);
      await tester.tap(find.text('Devanagari'));
      await tester.pumpAndSettle();
      await s.pickAndRun(tester, ['a.jpg']);
      expect(find.text('Save as TXT'), findsOneWidget);
      expect(find.text('Save as searchable PDF'), findsNothing);
    });

    testWidgets('hidden for PDF inputs', (tester) async {
      final s = _Setup();
      when(() => s.h.pdf.pageCount(any())).thenAnswer((_) async => const Ok(1));
      when(
        () => s.h.pdf.extractText(any()),
      ).thenAnswer((_) async => const Ok(['Embedded text of the report']));
      await s.pump(tester);
      await s.pickAndRun(tester, ['r.pdf']);
      expect(find.text('Text from PDF'), findsOneWidget);
      expect(find.text('Save as searchable PDF'), findsNothing);
    });

    testWidgets('hidden when a page failed', (tester) async {
      final s = _Setup();
      s.ocr.failures['/p/b.jpg'] = const AppFailure(FailureCode.corruptFile);
      await s.pump(tester);
      await s.pickAndRun(tester, ['a.jpg', 'b.jpg']);
      expect(find.text('Save as searchable PDF'), findsNothing);
    });
  });

  testWidgets('copy and TXT export use readableText', (tester) async {
    final expected = _paragraph().readableText;
    expect(expected, isNot(_paragraph().text), reason: 'fixture must wrap');

    final s = _Setup();
    when(
      () => s.h.share.copyText(any()),
    ).thenAnswer((_) async => const Ok(null));
    when(() => s.h.commit(any())).thenAnswer((_) async => Ok(doc('t1')));
    await s.pump(tester);
    await s.pickAndRun(tester, ['a.jpg', 'b.jpg']);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    verify(() => s.h.share.copyText('$expected\n\n$expected')).called(1);

    await tester.tap(find.text('Save as TXT'));
    await tester.pumpAndSettle();
    final out =
        verify(() => s.h.commit(captureAny())).captured.single as OutputFile;
    expect(String.fromCharCodes(out.bytes), '$expected\n\n$expected');
    expect(out.suggestedName, 'a (text)');
  });

  testWidgets('notes pages that were rotated to read them', (tester) async {
    final s = _Setup();
    s.extra.add(
      recognizeDocumentProvider.overrideWithValue(
        _FixedRecognizeDocument(
          OcrDocumentResult(
            pages: [
              OcrPage(
                sourceIndex: 0,
                pageIndex: 0,
                label: 'a.jpg',
                result: _paragraph(turns: 1),
              ),
            ],
          ),
        ),
      ),
    );
    await s.pump(tester);
    await s.pickAndRun(tester, ['a.jpg']);
    expect(find.text('Page was rotated to read it'), findsOneWidget);
  });
}
