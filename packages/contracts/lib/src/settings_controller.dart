import 'package:docscan_contracts/src/providers.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide settings. Read by the app (theme), scan flow (defaults) and the
/// settings screen.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  Future<void> change(AppSettings Function(AppSettings current) update) async {
    final current = state.value ?? const AppSettings();
    final next = update(current);
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Synchronous view with defaults while loading.
final currentSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsProvider).value ?? const AppSettings(),
);
