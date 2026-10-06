import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Store extends Mock implements SettingsStore {}

class _Files extends Mock implements FileStore {}

class _Ocr extends Mock implements TextRecognizer {}

void main() {
  setUpAll(() => registerFallbackValue(OcrScript.latin));

  testWidgets('Subscription entry shows the plan and opens its screen', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files();
    final ocr = _Ocr();
    when(store.load).thenAnswer((_) async => const AppSettings());
    when(files.usage).thenAnswer(
      (_) async => const StorageUsage(documents: 0, originals: 0, temp: 0),
    );
    when(() => ocr.capability(any())).thenAnswer(
      (_) async => const EngineCapability(available: true, worksOffline: true),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: Routes.subscription,
          builder: (_, _) => const Scaffold(body: Text('Subscription page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          fileStoreProvider.overrideWithValue(files),
          textRecognizerProvider.overrideWithValue(ocr),
          // A paid mode: the default build is free with ads (ADR-0013).
          monetizationModeProvider.overrideWithValue(MonetizationMode.licence),
          entitlementServiceProvider.overrideWithValue(
            StaticEntitlementService(
              DayPassEntitlement(
                expiresAt: DateTime.now().add(
                  const Duration(days: 9, minutes: 30),
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Subscription'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Day pass · ends in 9 days 1 h'), findsOneWidget);
    await tester.tap(find.text('Subscription'));
    await tester.pumpAndSettle();
    expect(find.text('Subscription page'), findsOneWidget);
  });
}
