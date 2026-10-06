import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';

class ControlledSave extends Mock implements SaveScanAsPdf {
  final completer = Completer<Result<Document>>();
  void Function(double)? progress;
  String? savedName;
  OcrScript? script;

  @override
  Future<Result<Document>> call(
    ScanDraft draft, {
    required String name,
    QualityPreset preset = QualityPreset.balanced,
    PdfBuildOptions options = const PdfBuildOptions(),
    OcrScript? searchableScript,
    String? folderId,
    void Function(double progress)? onProgress,
  }) {
    savedName = name;
    script = searchableScript;
    progress = onProgress;
    return completer.future;
  }
}

final _doc = Document(
  id: 'doc1',
  name: 'Lease',
  format: DocumentFormat.pdf,
  relativePath: 'documents/doc1.pdf',
  sizeBytes: 204800,
  pageCount: 2,
  createdAt: DateTime(2026, 9, 24),
  updatedAt: DateTime(2026, 9, 24),
);

void main() {
  late Fakes fakes;
  late ControlledSave save;

  Future<void> pumpSave(WidgetTester tester) async {
    fakes = Fakes(draft: draftWith(2));
    save = ControlledSave();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakes.overrides,
          saveScanAsPdfProvider.overrideWithValue(save),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SaveScreen(now: DateTime(2026, 9, 24, 14, 5)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows progress, then success only after the use case returns Ok',
    (tester) async {
      await pumpSave(tester);
      expect(find.text('Scan 2026-09-24 14.05'), findsOneWidget);
      expect(find.text('2 pages · saved on this phone'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Lease');
      await tester.tap(find.text('Save PDF'));
      await tester.pump();

      expect(find.text('Creating your PDF…'), findsOneWidget);
      expect(find.text('PDF saved'), findsNothing);
      expect(save.savedName, 'Lease');
      expect(save.script, OcrScript.latin);

      save.progress!(0.5);
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('PDF saved'), findsNothing);

      save.completer.complete(Ok(_doc));
      await tester.pumpAndSettle();

      expect(find.text('PDF saved'), findsOneWidget);
      expect(find.text('Lease.pdf'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      // The draft is cleared only after a validated save.
      expect(fakes.drafts.clears, 1);
    },
  );

  testWidgets('a failed save shows the error and keeps the draft', (
    tester,
  ) async {
    await pumpSave(tester);
    await tester.scrollUntilVisible(
      find.byType(Switch),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Save PDF'));
    await tester.pump();
    expect(save.script, isNull);

    save.completer.complete(
      const Err(AppFailure(FailureCode.outputValidationFailed)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PDF saved'), findsNothing);
    expect(find.text(FailureCode.outputValidationFailed.title), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(fakes.drafts.clears, 0);
    expect(fakes.drafts.draft, isNotNull);
  });
}
