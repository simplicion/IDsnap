import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('delete removes a page and Undo restores it', (tester) async {
    final fakes = Fakes(draft: draftWith(2));
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakes.overrides,
        child: MaterialApp(theme: AppTheme.light(), home: const ReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 2'), findsOneWidget);
    for (final label in ['Crop', 'Rotate', 'Filters', 'Retake', 'Delete']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Page 1 deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(fakes.drafts.draft?.pages.length, 2);
    expect(fakes.files.deleted, isEmpty);
  });

  testWidgets('rotate persists to the draft', (tester) async {
    final fakes = Fakes(draft: draftWith(1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakes.overrides,
        child: MaterialApp(theme: AppTheme.dark(), home: const ReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();
    expect(fakes.drafts.draft?.pages.single.edits.quarterTurns, 1);
  });
}
