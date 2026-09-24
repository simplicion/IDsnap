import 'package:docscan_core/docscan_core.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final docs = [
    doc('1', 'Invoice March', DocumentFormat.pdf),
    doc('2', 'Receipt photo', DocumentFormat.jpeg, favorite: true),
    doc('3', 'Meeting notes', DocumentFormat.txt),
  ];

  group('FilesScreen', () {
    testWidgets('lists documents and filters by type', (tester) async {
      final repo = FakeRepository(docs);
      await tester.pumpWidget(
        harness(
          const FilesScreen(),
          overrides: baseOverrides(repo, FakeFileStore()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invoice March'), findsOneWidget);
      expect(find.text('Receipt photo'), findsOneWidget);
      expect(find.text('Meeting notes'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'PDFs'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice March'), findsOneWidget);
      expect(find.text('Receipt photo'), findsNothing);
    });

    testWidgets('search with no results shows an empty state', (tester) async {
      final repo = FakeRepository(docs);
      await tester.pumpWidget(
        harness(
          const FilesScreen(),
          overrides: baseOverrides(repo, FakeFileStore()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice March'), findsOneWidget);
    });

    testWidgets('empty library invites the user to scan', (tester) async {
      await tester.pumpWidget(
        harness(
          const FilesScreen(),
          overrides: baseOverrides(FakeRepository([]), FakeFileStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Scan a document'), findsOneWidget);
    });
  });

  group('PendingDeleteController', () {
    testWidgets('undo cancels deletion; otherwise it commits after the delay', (
      tester,
    ) async {
      final repo = FakeRepository(docs);
      final files = FakeFileStore();
      final container = ProviderContainer(
        overrides: baseOverrides(repo, files),
      );
      addTearDown(container.dispose);
      final pending = container.read(pendingDeletesProvider.notifier)
        ..schedule([docs[0]]);
      expect(container.read(pendingDeletesProvider), {'1'});
      pending.undo([docs[0]]);
      expect(container.read(pendingDeletesProvider), isEmpty);
      await tester.pump(
        PendingDeleteController.delay + const Duration(seconds: 1),
      );
      expect(repo.removed, isEmpty);
      expect(files.deleted, isEmpty);

      pending.schedule([docs[1]]);
      await tester.pump(
        PendingDeleteController.delay + const Duration(seconds: 1),
      );
      await tester.pump();
      expect(repo.removed, ['2']);
      expect(files.deleted, contains('documents/2.jpg'));
      expect(container.read(pendingDeletesProvider), isEmpty);
    });
  });

  group('DocumentScreen', () {
    testWidgets('shows the content of a text document', (tester) async {
      final repo = FakeRepository(docs);
      final files = FakeFileStore(
        texts: {'/abs/documents/3.txt': 'Agenda: ship the scanner'},
      );
      await tester.pumpWidget(
        harness(
          const DocumentScreen(documentId: '3'),
          overrides: baseOverrides(repo, files),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Agenda: ship the scanner'), findsOneWidget);
      expect(find.text('Convert'), findsOneWidget);
    });

    testWidgets('unknown id shows not found', (tester) async {
      await tester.pumpWidget(
        harness(
          const DocumentScreen(documentId: 'missing'),
          overrides: baseOverrides(FakeRepository(docs), FakeFileStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(FailureCode.notFound.title), findsOneWidget);
    });
  });
}
