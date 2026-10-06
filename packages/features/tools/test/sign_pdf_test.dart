import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/signature/create_signature.dart';
import 'package:feature_tools/src/signature/sign_pdf_screen.dart';
import 'package:feature_tools/src/signature/signature_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

class MockStamper extends Mock implements PdfStamper {}

/// 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _FakeLibrary implements SignatureLibrary {
  final saved = [
    SavedSignature(
      id: 's1',
      fileName: 's1.png',
      createdAt: DateTime(2026),
      width: 300,
      height: 100,
      isDefault: true,
    ),
  ];

  @override
  Future<Result<List<SavedSignature>>> list() async => Ok(saved);

  @override
  Future<Result<Uint8List>> load(String id) async => Ok(_png);

  @override
  Future<Result<SavedSignature>> add(
    Uint8List png, {
    required int width,
    required int height,
  }) async => const Err(AppFailure(FailureCode.targetSizeUnreachable));

  @override
  Future<Result<void>> delete(String id) async => const Ok(null);

  @override
  Future<Result<void>> setDefault(String id) async => const Ok(null);
}

void main() {
  late Harness h;
  late MockStamper stamper;

  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(<PdfStamp>[]);
  });

  setUp(() {
    h = Harness();
    stamper = MockStamper();
    when(
      () => h.repo.byId('d1'),
    ).thenAnswer((_) async => doc('d1', name: 'Lease'));
    when(() => h.files.exists(any())).thenAnswer((_) async => true);
    when(
      () => h.files.read(any()),
    ).thenAnswer((_) async => Uint8List.fromList('%PDF-1.7\n'.codeUnits));
    when(
      () => h.pdf.renderPage(
        any(),
        any(),
        targetWidth: any(named: 'targetWidth'),
      ),
    ).thenAnswer((_) async => Ok(_png));
    when(() => h.pdf.pageCount(any())).thenAnswer((_) async => const Ok(2));
    when(() => stamper.pageDimensions(any())).thenAnswer(
      (_) async =>
          const Ok([PdfPageDimensions(595, 842), PdfPageDimensions(595, 842)]),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1000, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          pdfStamperProvider.overrideWithValue(stamper),
          signatureLibraryProvider.overrideWithValue(_FakeLibrary()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SignPdfScreen(initialDocId: 'd1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> placeSignatureAndDate(WidgetTester tester) async {
    await tester.tap(find.text('Place signature'));
    await tester.pumpAndSettle();
    expect(find.byType(StampEditorScreen), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Add signature'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a signature'), findsOneWidget);
    await tester.tap(find.byType(SavedSignatureTile));
    await tester.pumpAndSettle();
    final stamp = find.byKey(const ValueKey('stamp-1'));
    expect(stamp, findsOneWidget);

    // Drag the signature 40 logical px right.
    final before = tester.getTopLeft(stamp);
    final finger = await tester.startGesture(tester.getCenter(stamp));
    for (var i = 0; i < 8; i++) {
      await finger.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(stamp).dx, greaterThan(before.dx + 20));

    // Move to page 2 and add the date there.
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(stamp, findsNothing);
    await tester.tap(find.text('Add date'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stamp-2')), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('pick → place signature & date → save via CommitOutput', (
    tester,
  ) async {
    when(() => stamper.stamp(any(), any())).thenAnswer(
      (_) async => Ok(
        StampedPdf(
          bytes: Uint8List.fromList([1, 2, 3]),
          pageCount: 2,
          method: StampMethod.incremental,
        ),
      ),
    );
    when(() => h.commit(any())).thenAnswer((_) async => Ok(doc('out')));
    await pump(tester);
    expect(find.text('Place a signature first'), findsOneWidget);

    await placeSignatureAndDate(tester);
    expect(find.text('2 items on pages 1, 2'), findsOneWidget);

    await tester.tap(find.text('Save signed PDF'));
    await tester.pumpAndSettle();

    final stamps =
        verify(
              () => stamper.stamp('/app/documents/d1.pdf', captureAny()),
            ).captured.single
            as List<PdfStamp>;
    expect(stamps.length, 2);
    final sig = stamps[0] as PdfImageStamp;
    expect(sig.pageIndex, 0);
    expect(sig.png, _png);
    expect(sig.width / sig.height, closeTo(3, 1e-6));
    // initialSignatureRect centres horizontally; the drag moved it right.
    expect(sig.left, greaterThan((595 - sig.width) / 2));
    final date = stamps[1] as PdfTextStamp;
    expect(date.pageIndex, 1);
    expect(date.text, formatDateLike);

    final out =
        verify(() => h.commit(captureAny())).captured.single as OutputFile;
    expect(out.suggestedName, 'Lease (signed)');
    expect(out.expectedPages, 2);
    expect(out.format, DocumentFormat.pdf);
    expect(find.text('Saved to ID Vault'), findsOneWidget);
    expect(find.textContaining('text are unchanged'), findsOneWidget);
  });

  testWidgets('stamping errors show the typed failure, nothing is saved', (
    tester,
  ) async {
    when(() => stamper.stamp(any(), any())).thenAnswer(
      (_) async => const Err(
        AppFailure(FailureCode.passwordProtected, detail: 'Lease.pdf'),
      ),
    );
    await pump(tester);
    await placeSignatureAndDate(tester);
    await tester.tap(find.text('Save signed PDF'));
    await tester.pumpAndSettle();
    expect(find.text(FailureCode.passwordProtected.title), findsOneWidget);
    verifyNever(() => h.commit(any()));
  });
}

/// "25 Sep 2026"-style date.
final formatDateLike = matches(RegExp(r'^\d{1,2} [A-Z][a-z]{2} \d{4}$'));
