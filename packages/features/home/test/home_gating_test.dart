import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Drafts implements DraftStore {
  @override
  Future<ScanDraft?> load() async => null;
  @override
  Future<void> save(ScanDraft d) async {}
  @override
  Future<void> clear({bool deleteImages = true}) async {}
}

class _Repo extends Mock implements DocumentRepository {
  @override
  Stream<List<Document>> watch(DocumentQuery query) => Stream.value(const []);
}

class _Settings implements SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings s) async {}
}

class _Files extends Mock implements FileStore {}

const _expired = ExpiredEntitlement(reason: LapseReason.trialEnded);

Future<List<String>> _pump(WidgetTester tester, EntitlementState state) async {
  tester.view
    ..physicalSize = const Size(390, 1600) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final visited = <String>[];
  Widget page(GoRouterState s) {
    visited.add(s.uri.toString());
    return Scaffold(body: Text('page ${s.uri.path}'));
  }

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => HomeScreen(now: DateTime(2026, 9, 24, 9)),
      ),
      GoRoute(path: '/paywall', builder: (_, s) => page(s)),
      GoRoute(path: '/subscription', builder: (_, s) => page(s)),
      GoRoute(path: '/scan', builder: (_, s) => page(s)),
      GoRoute(path: '/scan/id-card', builder: (_, s) => page(s)),
      GoRoute(path: '/tools/:tool', builder: (_, s) => page(s)),
      GoRoute(path: '/authenticator', builder: (_, s) => page(s)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(_Settings()),
        draftStoreProvider.overrideWithValue(_Drafts()),
        documentRepositoryProvider.overrideWithValue(_Repo()),
        fileStoreProvider.overrideWithValue(_Files()),
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
  testWidgets('after the trial, a locked quick action opens the paywall', (
    tester,
  ) async {
    final visited = await _pump(tester, _expired);
    expect(find.text('Pro'), findsWidgets);
    await tester.tap(find.text('Extract text'));
    await tester.pumpAndSettle();
    expect(visited.single, startsWith('/paywall?feature=ocr'));
  });

  testWidgets('after the trial, Scan opens the paywall', (tester) async {
    final visited = await _pump(tester, _expired);
    await tester.tap(find.text('Scan a document'));
    await tester.pumpAndSettle();
    expect(visited.single, startsWith('/paywall?feature=scan'));
  });

  testWidgets('the Authenticator shortcut is never gated', (tester) async {
    final visited = await _pump(tester, _expired);
    await tester.tap(find.text('Authenticator'));
    await tester.pumpAndSettle();
    expect(visited, ['/authenticator']);
  });

  testWidgets('during the free day tools open directly, without badges', (
    tester,
  ) async {
    final visited = await _pump(
      tester,
      TrialEntitlement(endsAt: DateTime.now().add(const Duration(hours: 20))),
    );
    expect(find.text('Pro'), findsNothing);
    await tester.tap(find.text('ID card (front & back)'));
    await tester.pumpAndSettle();
    expect(visited, ['/scan/id-card']);
  });

  testWidgets('free-day banner counts down in hours', (tester) async {
    await _pump(
      tester,
      TrialEntitlement(
        endsAt: DateTime.now().add(const Duration(hours: 4, minutes: 30)),
      ),
    );
    expect(find.text('Free day ends in 5 h'), findsOneWidget);
  });

  testWidgets('day pass banner only in its last day', (tester) async {
    await _pump(
      tester,
      DayPassEntitlement(
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      ),
    );
    expect(find.textContaining('Day pass ends in'), findsNothing);
  });

  testWidgets('day pass countdown in the last 24 h', (tester) async {
    await _pump(
      tester,
      DayPassEntitlement(
        expiresAt: DateTime.now().add(const Duration(hours: 2, minutes: 10)),
      ),
    );
    expect(find.text('Day pass ends in 3 h'), findsOneWidget);
  });

  testWidgets('never activated: connect once', (tester) async {
    await _pump(
      tester,
      const ExpiredEntitlement(reason: LapseReason.notActivated),
    );
    expect(
      find.text('Connect to the internet once to start your free day'),
      findsOneWidget,
    );
  });

  testWidgets('expired banner has a clear call to action', (tester) async {
    final visited = await _pump(tester, _expired);
    expect(find.text('Your free day has ended'), findsOneWidget);
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(visited.single, '/paywall');
  });

  testWidgets('clock set back: honest banner', (tester) async {
    await _pump(
      tester,
      const ExpiredEntitlement(reason: LapseReason.clockTampered),
    );
    expect(find.text("Check your phone's date"), findsOneWidget);
  });
}
