import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Files extends Mock implements FileStore {}

class _Ocr extends Mock implements TextRecognizer {}

class _Store implements SettingsStore {
  AppSettings saved = const AppSettings(theme: ThemePreference.dark);

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings s) async => saved = s;
}

class _Lock implements AppLock {
  _Lock(this.answer);

  final bool answer;
  final reasons = <String>[];

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async {
    reasons.add(reason);
    return Ok(answer);
  }
}

class _Eraser implements VaultEraser {
  int deletedAll = 0;
  int erased = 0;

  @override
  Future<Result<int>> deleteAllDocuments({
    Future<void> Function(Document document)? onDeleted,
  }) async {
    deletedAll++;
    return const Ok(3);
  }

  @override
  Future<Result<void>> eraseEverything({
    Future<void> Function(Document document)? onDeleted,
  }) async {
    erased++;
    return const Ok(null);
  }
}

void main() {
  setUpAll(() => registerFallbackValue(OcrScript.latin));

  Future<(_Eraser, _Lock, List<int>)> pump(
    WidgetTester tester, {
    bool auth = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final files = _Files();
    final ocr = _Ocr();
    when(files.usage).thenAnswer(
      (_) async => const StorageUsage(documents: 1, originals: 0, temp: 0),
    );
    when(() => ocr.capability(any())).thenAnswer(
      (_) async => const EngineCapability(available: true, worksOffline: true),
    );
    final eraser = _Eraser();
    final lock = _Lock(auth);
    final restarts = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_Store()),
          fileStoreProvider.overrideWithValue(files),
          textRecognizerProvider.overrideWithValue(ocr),
          vaultEraserProvider.overrideWithValue(eraser),
          appLockProvider.overrideWithValue(lock),
          appRestartProvider.overrideWithValue(() => restarts.add(1)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (eraser, lock, restarts);
  }

  Future<void> open(WidgetTester tester, String title) async {
    final tile = find.widgetWithText(ListTile, title);
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
  }

  testWidgets('Erase everything: typed word, then unlock, then restart', (
    tester,
  ) async {
    final (eraser, lock, restarts) = await pump(tester);
    await open(tester, 'Erase everything');
    await tester.pumpAndSettle();
    // States what goes. The free build has no purchase to keep, so it
    // doesn't mention one (the paid wording is in settings_free_test.dart).
    expect(find.textContaining('authenticator'), findsWidgets);
    expect(find.textContaining('purchase is kept'), findsNothing);
    final confirm = find.widgetWithText(FilledButton, 'Erase everything');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'erase');
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(lock.reasons, ['Confirm to erase everything']);
    expect(eraser.erased, 1);
    expect(restarts, [1]);
  });

  testWidgets('Erase everything stops when the unlock fails', (tester) async {
    final (eraser, _, restarts) = await pump(tester, auth: false);
    await open(tester, 'Erase everything');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ERASE');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Erase everything'));
    await tester.pumpAndSettle();
    expect(eraser.erased, 0);
    expect(restarts, isEmpty);
  });

  testWidgets('Delete all documents says what it does and re-authenticates', (
    tester,
  ) async {
    final (eraser, lock, _) = await pump(tester);
    await open(tester, 'Delete all documents');
    await tester.pumpAndSettle();
    expect(find.textContaining('including those in locked folders'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(lock.reasons, ['Confirm to delete documents']);
    expect(eraser.deletedAll, 1);
    expect(eraser.erased, 0);
    expect(find.text('Deleted 3 documents'), findsOneWidget);
  });
}
