import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<List<String>> _pump(WidgetTester tester, EntitlementState state) async {
  tester.view
    ..physicalSize = const Size(1200, 4000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final visited = <String>[];
  Widget page(GoRouterState s) {
    visited.add(s.uri.toString());
    return const Scaffold(body: Text('page'));
  }

  final router = GoRouter(
    initialLocation: Routes.tools,
    routes: [
      GoRoute(path: Routes.tools, builder: (_, _) => const ToolsScreen()),
      GoRoute(path: '/paywall', builder: (_, s) => page(s)),
      GoRoute(path: '/tools/:tool', builder: (_, s) => page(s)),
      GoRoute(path: '/scan', builder: (_, s) => page(s)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // A paid mode: the default build is free with ads (ADR-0013).
        monetizationModeProvider.overrideWithValue(MonetizationMode.licence),
        entitlementServiceProvider.overrideWithValue(
          StaticEntitlementService(state),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return visited;
}

void main() {
  testWidgets('after the trial, a locked tool opens the paywall', (
    tester,
  ) async {
    final visited = await _pump(
      tester,
      const ExpiredEntitlement(reason: LapseReason.trialEnded),
    );
    expect(find.text('Pro'), findsWidgets);
    await tester.tap(find.text('Merge PDFs'));
    await tester.pumpAndSettle();
    expect(visited.single, '/paywall?feature=pdfTools');
  });

  testWidgets('with Pro, tools open directly and show no badge', (
    tester,
  ) async {
    final visited = await _pump(tester, const MonthlyEntitlement());
    expect(find.text('Pro'), findsNothing);
    await tester.tap(find.text('Sign PDF'));
    await tester.pumpAndSettle();
    expect(visited.single, '/tools/sign-pdf');
  });
}
