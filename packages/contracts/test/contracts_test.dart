import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettings implements SettingsStore {
  AppSettings saved = const AppSettings();

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  test('unwired ports fail loudly with a helpful message', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(pdfEngineProvider),
      throwsA(
        predicate((e) => e.toString().contains('PdfEngine is not wired')),
      ),
    );
  });

  test('settings controller persists changes', () async {
    final store = _MemorySettings();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(theme: ThemePreference.dark));
    expect(store.saved.theme, ThemePreference.dark);
    expect(container.read(currentSettingsProvider).theme, ThemePreference.dark);
  });

  test('route contract builds expected paths', () {
    expect(Routes.scan(source: ScanSource.gallery), '/scan?source=gallery');
    expect(
      Routes.tool(ToolId.photoCrop, docId: 'a1'),
      '/tools/photo-crop?doc=a1',
    );
    expect(Routes.convert('pdf-to-docx'), '/tools/convert/pdf-to-docx');
    expect(Routes.document('x'), '/files/doc/x');
  });

  test('settings JSON round-trips and tolerates unknown values', () {
    const s = AppSettings(
      theme: ThemePreference.dark,
      ocrScript: OcrScript.devanagari,
      quality: QualityPreset.high,
    );
    expect(AppSettings.fromJson(s.toJson()).ocrScript, OcrScript.devanagari);
    expect(
      AppSettings.fromJson(const {'theme': 'neon'}).theme,
      ThemePreference.system,
    );
  });
}
