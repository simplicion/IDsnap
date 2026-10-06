import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:feature_tools/src/screens/compress_image_screen.dart';
import 'package:feature_tools/src/screens/convert_screen.dart';
import 'package:feature_tools/src/screens/merge_screen.dart';
import 'package:feature_tools/src/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

FilledButton _primary(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );

void main() {
  setUpAll(registerFallbacks);

  group('ToolsScreen', () {
    testWidgets('shows every section and tool', (tester) async {
      final h = Harness();
      await h.pump(tester, const ToolsScreen());
      for (final s in ToolSection.values) {
        expect(find.text(s.title), findsOneWidget, reason: s.title);
      }
      for (final t in toolCatalog) {
        expect(find.text(t.title), findsOneWidget, reason: t.title);
      }
      expect(find.text('PDF → DOCX'), findsOneWidget);
    });

    testWidgets('search filters tiles and hides empty sections', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, const ToolsScreen());
      await tester.enterText(find.byType(TextField), 'compress');
      await tester.pumpAndSettle();
      expect(find.text('Compress PDF'), findsOneWidget);
      expect(find.text('Compress image'), findsOneWidget);
      expect(find.text('Merge PDFs'), findsNothing);
      expect(find.text(ToolSection.text.title), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No tools match'), findsOneWidget);
    });
  });

  testWidgets('Compress image: target size chip is passed to compress', (
    tester,
  ) async {
    final h = Harness();
    final photo = doc('p1', format: DocumentFormat.jpeg, name: 'Selfie');
    when(() => h.repo.byId('p1')).thenAnswer((_) async => photo);
    when(() => h.images.inspect(any())).thenAnswer(
      (_) async =>
          const Ok(ImageDetails(width: 4000, height: 3000, sizeBytes: 2000000)),
    );
    when(() => h.images.compress(any(), any())).thenAnswer(
      (_) async => Ok(
        EncodedImage(
          bytes: Uint8List(150 * 1024),
          width: 1600,
          height: 1200,
          format: ImageOutputFormat.jpeg,
        ),
      ),
    );
    when(() => h.commit(any())).thenAnswer(
      (_) async =>
          Ok(doc('out', format: DocumentFormat.jpeg, size: 150 * 1024)),
    );

    await h.pump(tester, const CompressImageScreen(initialDocId: 'p1'));
    expect(find.text('Selfie.jpg'), findsOneWidget);

    await tester.tap(find.text('200 KB'));
    await tester.pumpAndSettle();
    // Quality slider hides when a target size drives quality.
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('Compress'));
    await tester.pumpAndSettle();

    final options =
        verify(() => h.images.compress(any(), captureAny())).captured.single
            as ImageCompressionOptions;
    expect(options.targetBytes, 200 * 1024);
    expect(options.format, ImageOutputFormat.jpeg);
    verify(() => h.commit(any())).called(1);
    expect(find.text('Saved to ID Vault'), findsOneWidget);
  });

  testWidgets('Merge requires at least two PDFs', (tester) async {
    final h = Harness();
    when(() => h.repo.byId('a')).thenAnswer((_) async => doc('a'));
    await h.pump(tester, const MergeScreen(initialDocId: 'a'));

    expect(find.text('1. Report.pdf'), findsOneWidget);
    expect(_primary(tester, 'Add at least 2 PDFs').onPressed, isNull);
    expect(find.text('Add one more PDF to merge.'), findsOneWidget);
    verifyNever(() => h.pdf.merge(any()));
  });

  testWidgets('Convert screen renders fidelity note from its spec', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester, const ConvertScreen(specId: 'pdf-docx'));
    expect(find.text('PDF to Word'), findsOneWidget);
    expect(find.text(FidelityClass.content.label), findsOneWidget);
    expect(find.text(FidelityClass.content.explanation), findsOneWidget);
    expect(find.text('• Tables become plain paragraphs.'), findsOneWidget);
    expect(find.byType(FidelityNote), findsOneWidget);
    expect(_primary(tester, 'Convert').onPressed, isNull);
  });

  testWidgets('Convert screen handles unknown spec', (tester) async {
    final h = Harness();
    await h.pump(tester, const ConvertScreen(specId: 'nope'));
    expect(find.text('Converter not found'), findsOneWidget);
  });

  testWidgets('Convert list groups specs by category', (tester) async {
    final h = Harness();
    await h.pump(tester, const ConvertListScreen());
    expect(find.text(ConversionCategory.fromPdf.label), findsOneWidget);
    expect(find.text(ConversionCategory.toPdf.label), findsOneWidget);
    expect(find.text('TXT → PDF'), findsOneWidget);
  });

  test('public API exports the range parser', () {
    expect(parsePageRanges('1', 1).pages, [0]);
    expect(FailureCode.values, isNotEmpty);
  });
}
