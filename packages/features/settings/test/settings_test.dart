import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsStore extends Mock implements SettingsStore {}

class _MockFileStore extends Mock implements FileStore {}

class _MockRecognizer extends Mock implements TextRecognizer {}

void main() {
  setUpAll(() => registerFallbackValue(const AppSettings()));

  late _MockSettingsStore store;
  late _MockFileStore files;
  late _MockRecognizer ocr;

  setUp(() {
    store = _MockSettingsStore();
    files = _MockFileStore();
    ocr = _MockRecognizer();
    when(() => store.load()).thenAnswer((_) async => const AppSettings());
    when(() => store.save(any())).thenAnswer((_) async {});
    when(() => files.usage()).thenAnswer(
      (_) async => const StorageUsage(
        documents: 3 * 1024 * 1024,
        originals: 1024 * 1024,
        temp: 2048,
      ),
    );
    when(() => files.clearTemp()).thenAnswer((_) async {});
    when(() => ocr.capability(any())).thenAnswer(
      (_) async => const EngineCapability(available: true, worksOffline: true),
    );
  });

  setUpAll(() => registerFallbackValue(OcrScript.latin));

  Widget app() => ProviderScope(
    overrides: [
      settingsStoreProvider.overrideWithValue(store),
      fileStoreProvider.overrideWithValue(files),
      textRecognizerProvider.overrideWithValue(ocr),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
  );

  testWidgets('choosing Dark theme saves settings', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Theme: Dark'));
    await tester.pumpAndSettle();

    final saved =
        verify(() => store.save(captureAny())).captured.single as AppSettings;
    expect(saved.theme, ThemePreference.dark);
  });

  testWidgets('shows storage usage and OCR availability', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('used on this device'),
      200,
    );
    expect(find.textContaining('used on this device'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Clear temporary files'), 200);
    await tester.tap(find.text('Clear temporary files'));
    await tester.pumpAndSettle();
    verify(() => files.clearTemp()).called(1);
    expect(find.text('Temporary files cleared'), findsOneWidget);
  });

  testWidgets('privacy page states no uploads and no certification', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const PrivacyScreen()),
    );
    expect(find.text('No uploads'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Not a certified copy'), 200);
    expect(find.text('Not a certified copy'), findsOneWidget);
  });
}
