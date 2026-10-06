import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Store implements SettingsStore {
  _Store(this.saved);

  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings s) async => saved = s;
}

class _Repo extends Mock implements DocumentRepository {}

class _Reminders implements ReminderScheduler {
  bool grant = true;
  final scheduled = <String>[];
  final cancelled = <String>[];

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<void>> requestPermission() async => grant
      ? const Ok(null)
      : const Err(
          AppFailure(
            FailureCode.permissionDenied,
            heading: 'Notifications are off for IDSnap',
            message: 'Allow them in Settings.',
          ),
        );

  @override
  Future<Result<void>> scheduleExpiry(Document document) async {
    scheduled.add(document.id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancel(String documentId) async {
    cancelled.add(documentId);
    return const Ok(null);
  }
}

Document _doc(String id, {DateTime? expiresAt}) => Document(
  id: id,
  name: id,
  format: DocumentFormat.pdf,
  relativePath: 'documents/$id.pdf',
  sizeBytes: 1,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  expiresAt: expiresAt,
);

void main() {
  setUpAll(() => registerFallbackValue(const DocumentQuery()));

  Future<(_Store, _Reminders)> pump(
    WidgetTester tester, {
    required bool on,
    bool grant = true,
  }) async {
    final store = _Store(AppSettings(expiryReminders: on));
    final reminders = _Reminders()..grant = grant;
    final repo = _Repo();
    when(() => repo.watch(any())).thenAnswer(
      (_) => Stream.value([
        _doc('passport', expiresAt: DateTime(2031)),
        _doc('receipt'),
        _doc('licence', expiresAt: DateTime(2029, 5)),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          documentRepositoryProvider.overrideWithValue(repo),
          reminderSchedulerProvider.overrideWithValue(reminders),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const DataScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (store, reminders);
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Expiry reminders'), 200);
    await tester.tap(find.text('Expiry reminders'));
    await tester.pumpAndSettle();
  }

  testWidgets('turning reminders off cancels every reminder', (tester) async {
    final (store, reminders) = await pump(tester, on: true);
    await toggle(tester);
    expect(store.saved.expiryReminders, isFalse);
    expect(reminders.cancelled, unorderedEquals(['passport', 'licence']));
    expect(find.text('Expiry reminders are off'), findsOneWidget);
  });

  testWidgets('turning reminders on schedules every expiring document', (
    tester,
  ) async {
    final (store, reminders) = await pump(tester, on: false);
    await toggle(tester);
    expect(store.saved.expiryReminders, isTrue);
    expect(reminders.scheduled, unorderedEquals(['passport', 'licence']));
    expect(
      find.text('Expiry reminders are on for 2 documents.'),
      findsOneWidget,
    );
  });

  testWidgets('denied permission keeps the switch off and explains why', (
    tester,
  ) async {
    final (store, reminders) = await pump(tester, on: false, grant: false);
    await toggle(tester);
    expect(store.saved.expiryReminders, isFalse);
    expect(reminders.scheduled, isEmpty);
    expect(
      find.textContaining('Notifications are off for IDSnap'),
      findsOneWidget,
    );
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Expiry reminders'),
    );
    expect(tile.value, isFalse);
  });
}
