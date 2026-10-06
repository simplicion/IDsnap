import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/target_size.dart';
import 'package:feature_tools/src/screens/compress_image_screen.dart';
import 'package:feature_tools/src/screens/compress_pdf_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(PdfCompressionLevel.light);
  });

  group('compressPdfToTarget', () {
    late MockPdf pdf;
    setUp(() => pdf = MockPdf());

    test('stops at the first level under the limit', () async {
      when(
        () => pdf.compress(any(), PdfCompressionLevel.light),
      ).thenAnswer((_) async => Ok(_bytes(400 * 1024)));
      when(
        () => pdf.compress(any(), PdfCompressionLevel.recommended),
      ).thenAnswer((_) async => Ok(_bytes(180 * 1024)));
      final steps = <double>[];
      final r = await compressPdfToTarget(
        pdf,
        '/a.pdf',
        200 * 1024,
        onStep: steps.add,
      );
      expect(r.valueOrNull!.level, PdfCompressionLevel.recommended);
      expect(r.valueOrNull!.bytes.length, 180 * 1024);
      expect(steps.length, 2);
      verifyNever(() => pdf.compress(any(), PdfCompressionLevel.strong));
    });

    test('unreachable → targetSizeUnreachable with actionable copy', () async {
      when(
        () => pdf.compress(any(), any()),
      ).thenAnswer((_) async => Ok(_bytes(900 * 1024)));
      final r = await compressPdfToTarget(pdf, '/a.pdf', 100 * 1024);
      final f = r.failureOrNull!;
      expect(f.code, FailureCode.targetSizeUnreachable);
      expect(f.recovery, contains("Can't reach 100 KB"));
      expect(f.recovery, contains('Try fewer pages'));
    });

    test('a damaged file fails immediately, no further levels', () async {
      when(() => pdf.compress(any(), any())).thenAnswer(
        (_) async => const Err(AppFailure(FailureCode.passwordProtected)),
      );
      final r = await compressPdfToTarget(pdf, '/a.pdf', 100 * 1024);
      expect(r.failureOrNull?.code, FailureCode.passwordProtected);
      verify(() => pdf.compress(any(), any())).called(1);
    });
  });

  group('Compress PDF: target size mode', () {
    late Harness h;
    setUp(() {
      h = Harness();
      when(
        () => h.repo.byId('d1'),
      ).thenAnswer((_) async => doc('d1', name: 'Marksheet', size: 900 * 1024));
      when(() => h.files.exists(any())).thenAnswer((_) async => true);
      when(
        () => h.files.read(any()),
      ).thenAnswer((_) async => Uint8List.fromList('%PDF-1.7\n'.codeUnits));
      when(() => h.pdf.pageCount(any())).thenAnswer((_) async => const Ok(3));
    });

    Future<void> chooseTarget(WidgetTester tester, String chip) async {
      await h.pump(tester, const CompressPdfScreen(initialDocId: 'd1'));
      await tester.tap(find.text('Target size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compress under $chip'));
      await tester.pumpAndSettle();
    }

    testWidgets('saves the first result under the limit', (tester) async {
      when(
        () => h.pdf.compress(any(), PdfCompressionLevel.light),
      ).thenAnswer((_) async => Ok(_bytes(600 * 1024)));
      when(
        () => h.pdf.compress(any(), PdfCompressionLevel.recommended),
      ).thenAnswer((_) async => Ok(_bytes(280 * 1024)));
      when(
        () => h.commit(any()),
      ).thenAnswer((_) async => Ok(doc('out', size: 280 * 1024)));

      await chooseTarget(tester, '300 KB');

      final out =
          verify(() => h.commit(captureAny())).captured.single as OutputFile;
      expect(out.bytes.length, lessThanOrEqualTo(300 * 1024));
      expect(out.expectedPages, 3);
      expect(find.text('Under your 300 KB limit ✓'), findsOneWidget);
    });

    testWidgets('unreachable limit is a typed failure, nothing saved', (
      tester,
    ) async {
      when(
        () => h.pdf.compress(any(), any()),
      ).thenAnswer((_) async => Ok(_bytes(700 * 1024)));

      await chooseTarget(tester, '100 KB');

      expect(
        find.text(FailureCode.targetSizeUnreachable.title),
        findsOneWidget,
      );
      expect(find.textContaining("Can't reach 100 KB"), findsOneWidget);
      verifyNever(() => h.commit(any()));
    });
  });

  testWidgets('Compress image refuses to save above the target', (
    tester,
  ) async {
    final h = Harness();
    when(
      () => h.repo.byId('p1'),
    ).thenAnswer((_) async => doc('p1', format: DocumentFormat.jpeg));
    when(() => h.images.inspect(any())).thenAnswer(
      (_) async =>
          const Ok(ImageDetails(width: 4000, height: 3000, sizeBytes: 2000000)),
    );
    when(() => h.images.compress(any(), any())).thenAnswer(
      (_) async => Ok(
        EncodedImage(
          bytes: _bytes(260 * 1024),
          width: 1600,
          height: 1200,
          format: ImageOutputFormat.jpeg,
        ),
      ),
    );
    await h.pump(tester, const CompressImageScreen(initialDocId: 'p1'));
    await tester.tap(find.text('200 KB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress'));
    await tester.pumpAndSettle();
    expect(find.text(FailureCode.targetSizeUnreachable.title), findsOneWidget);
    expect(find.textContaining('smaller maximum size'), findsOneWidget);
    verifyNever(() => h.commit(any()));
  });
}
