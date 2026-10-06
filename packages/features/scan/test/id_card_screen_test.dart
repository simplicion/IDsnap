import 'dart:async';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'id_card_fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late IdCardFakes fakes;

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/scan/id-card?slot=national_id',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(
          path: '/files/doc/:id',
          builder: (_, s) => Text('DOC ${s.pathParameters['id']}'),
        ),
        ...scanRoutes(),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakes.overrides,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 780),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  setUp(() => fakes = IdCardFakes());

  testWidgets('full flow: front, back, preview, save → success after commit', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.text('Scan the front of your card'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 2, front of card'), findsOneWidget);

    fakes.scanner.next = const Ok(['/cache/front.jpg']);
    await tester.tap(find.text('Scan front'));
    await _settle(tester);
    expect(find.text('Now flip the card over'), findsOneWidget);
    expect(find.text('Front captured'), findsOneWidget);

    fakes.scanner.next = const Ok(['/cache/back.jpg']);
    await tester.tap(find.text('Scan back'));
    await _settle(tester);
    expect(find.text('Review and save'), findsOneWidget);
    expect(find.textContaining('Not a certified'), findsOneWidget);

    // Hold the commit to observe the in-progress state.
    fakes.commit.gate = Completer<void>();
    await tester.ensureVisible(find.text('Save PDF'));
    await tester.tap(find.text('Save PDF'));
    await _settle(tester);
    expect(find.text('Creating your ID card PDF…'), findsOneWidget);
    expect(find.text('ID card copy saved'), findsNothing);
    expect(fakes.sheet.calls.single.$1, hasLength(2));

    fakes.commit.gate!.complete();
    await _settle(tester);
    expect(find.text('ID card copy saved'), findsOneWidget);
    // The real destination, not a legacy category.
    expect(find.text('Saved to ID Vault'), findsOneWidget);
    expect(find.textContaining('Filed in'), findsNothing);
    expect(fakes.recordingRepo.updates, isEmpty);

    await tester.tap(find.text('Open'));
    await _settle(tester);
    expect(find.text('DOC doc1'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('commit failure shows a typed failure view, not success', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Scan front'));
    await _settle(tester);
    await tester.tap(find.text('Scan back'));
    await _settle(tester);
    fakes.commit.failWith = const AppFailure(
      FailureCode.outputValidationFailed,
    );
    await tester.ensureVisible(find.text('Save PDF'));
    await tester.tap(find.text('Save PDF'));
    await _settle(tester);
    expect(find.text('Output could not be verified'), findsOneWidget);
    expect(find.text('ID card copy saved'), findsNothing);
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text('Save PDF'), findsOneWidget);
  });

  testWidgets('watermark switch reveals purpose field and preview label', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Scan front'));
    await _settle(tester);
    await tester.tap(find.text('Scan back'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('Add "COPY" watermark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add "COPY" watermark'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'hotel check-in');
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('COPY — for hotel check-in only'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('COPY — for hotel check-in only'), findsOneWidget);
  });

  testWidgets('back from step 2 returns to step 1', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Scan front'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.text('Scan the front of your card'), findsOneWidget);
  });

  testWidgets('no overflow at 2x text', (tester) async {
    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Scan front'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Scan front'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('Scan back'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Scan back'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
