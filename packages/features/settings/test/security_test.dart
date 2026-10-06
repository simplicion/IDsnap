import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SettingsStore {
  AppSettings saved = const AppSettings();

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings s) async => saved = s;
}

class _Lock implements AppLock {
  _Lock(this.answer);

  Result<bool> answer;
  int prompts = 0;
  bool available = true;

  @override
  Future<EngineCapability> capability() async => EngineCapability(
    available: available,
    worksOffline: true,
    note: available ? null : 'Set a screen lock first.',
  );

  @override
  Future<Result<bool>> authenticate(String reason) async {
    prompts++;
    return answer;
  }
}

class _Archiver implements LibraryArchiver {
  int exports = 0;
  String? password;
  List<BackupSection>? sections;

  @override
  Future<Result<BackupResult>> exportBackup({
    String? password,
    List<BackupSection> sections = const [],
    bool includeDocuments = true,
    String? fileName,
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  }) async {
    exports++;
    this.password = password;
    this.sections = sections;
    onProgress?.call(const BackupProgress(BackupStage.finishing, 1));
    return Ok(
      BackupResult(
        path: '/cache/share/x/IDSnap backup 2026-10-06.zip',
        fileName: 'IDSnap backup 2026-10-06.zip',
        sizeBytes: 3,
        protected: password != null,
      ),
    );
  }

  @override
  Future<Result<ImportSummary>> importBackup(
    String zipPath, {
    String? password,
    List<BackupSection> sections = const [],
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  }) async => const Ok(ImportSummary(documents: 2));
}

class _Share implements ShareService, FileSaver {
  String? savedName;

  @override
  Future<Result<bool>> saveFileToDevice(String path, String fileName) async {
    savedName = fileName;
    return const Ok(true);
  }

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) async {
    savedName = fileName;
    return const Ok(true);
  }

  @override
  Future<Result<void>> share(List<String> p, {String? subject}) async =>
      const Ok(null);

  @override
  Future<Result<void>> shareText(String text) async => const Ok(null);

  @override
  Future<Result<void>> copyText(String text) async => const Ok(null);
}

Widget _app(Widget child, List<Object> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(theme: AppTheme.light(), home: child),
);

void main() {
  testWidgets('turning App Lock on requires authentication', (tester) async {
    final store = _Store();
    final lock = _Lock(const Ok(false));
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(lock),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text(SecurityScreen.explanation), findsOneWidget);

    // Cancelled prompt: stays off.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lock.prompts, 1);
    expect(store.saved.appLock, isFalse);

    // Successful prompt: turns on and reveals the timeout choice.
    lock.answer = const Ok(true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.saved.appLock, isTrue);
    expect(find.text('After 5 minutes'), findsOneWidget);
    await tester.tap(find.text('After 5 minutes'));
    await tester.pumpAndSettle();
    expect(store.saved.lockAfterMinutes, 5);
  });

  testWidgets('no screen lock shows the actionable message', (tester) async {
    final lock = _Lock(
      const Err(
        AppFailure(FailureCode.permissionDenied, detail: 'Set a screen lock'),
      ),
    );
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(_Store()),
        appLockProvider.overrideWithValue(lock),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Set a screen lock'), findsOneWidget);
  });

  testWidgets('turning App Lock off also requires authentication', (
    tester,
  ) async {
    final store = _Store()..saved = const AppSettings(appLock: true);
    final lock = _Lock(const Ok(false));
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(lock),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lock.prompts, 1);
    expect(store.saved.appLock, isTrue, reason: 'cancelled: stays on');

    lock.answer = const Ok(true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lock.prompts, 2);
    expect(store.saved.appLock, isFalse);
  });

  testWidgets('without a screen lock the switch is disabled and explained', (
    tester,
  ) async {
    final store = _Store();
    final lock = _Lock(const Ok(true))..available = false;
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(lock),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set a screen lock first.'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lock.prompts, 0);
    expect(store.saved.appLock, isFalse);
  });

  testWidgets('lock left on after the screen lock was removed can be '
      'turned off without an impossible prompt', (tester) async {
    final store = _Store()..saved = const AppSettings(appLock: true);
    final lock = _Lock(const Ok(false))..available = false;
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(lock),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lock.prompts, 0);
    expect(store.saved.appLock, isFalse);
  });

  testWidgets('copy is honest about what App Lock does', (tester) async {
    await tester.pumpWidget(
      _app(const SecurityScreen(), [
        settingsStoreProvider.overrideWithValue(_Store()),
        appLockProvider.overrideWithValue(_Lock(const Ok(true))),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text(SecurityScreen.explanation), findsOneWidget);
    expect(
      SecurityScreen.explanation,
      startsWith(
        'Your vault files and database are encrypted on this phone (AES-256).',
      ),
    );
    // The backup limitation is stated, not hidden.
    expect(find.textContaining("can't restore your vault"), findsOneWidget);
    expect(find.textContaining('bank-grade'), findsNothing);
  });

  List<Object> exportOverrides(
    _Lock lock,
    _Archiver archiver,
    _Share share,
  ) => [
    settingsStoreProvider.overrideWithValue(
      _Store()..saved = const AppSettings(appLock: true),
    ),
    appLockProvider.overrideWithValue(lock),
    libraryArchiverProvider.overrideWithValue(archiver),
    shareServiceProvider.overrideWithValue(share),
    plainFileAccessProvider.overrideWithValue(const PassThroughFileAccess()),
  ];

  Future<void> enterPassword(WidgetTester tester, String a, [String? b]) async {
    await tester.enterText(find.widgetWithText(TextField, 'Password'), a);
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat password'),
      b ?? a,
    );
  }

  final protectSwitch = find.widgetWithText(
    SwitchListTile,
    'Protect this backup with a password',
  );

  testWidgets('export is password-protected by default and re-authenticates', (
    tester,
  ) async {
    final lock = _Lock(const Ok(true));
    final archiver = _Archiver();
    final share = _Share();
    await tester.pumpWidget(
      _app(const DataScreen(), exportOverrides(lock, archiver, share)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all data'));
    await tester.pumpAndSettle();
    // What's in it (incl. 2FA secrets) and what isn't (PINs, licence).
    expect(find.textContaining('Authenticator accounts'), findsOneWidget);
    expect(find.textContaining('PINs'), findsOneWidget);
    final protect = tester.widget<SwitchListTile>(protectSwitch);
    expect(protect.value, isTrue);

    // Too short, then mismatched: refused.
    await enterPassword(tester, 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8'), findsOneWidget);
    await enterPassword(tester, 'Strong-pass-1', 'Strong-pass-2');
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.text("The passwords don't match."), findsOneWidget);
    expect(archiver.exports, 0);

    await enterPassword(tester, 'Strong-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(lock.prompts, 1);
    expect(archiver.exports, 1);
    expect(archiver.password, 'Strong-pass-1');
    expect(find.text('Backup ready · password-protected'), findsOneWidget);
    await tester.tap(find.text('Save to this phone'));
    await tester.pumpAndSettle();
    expect(share.savedName, startsWith('IDSnap backup '));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Save to this phone'), findsNothing);
  });

  testWidgets('an unprotected export needs an explicit acknowledgement', (
    tester,
  ) async {
    final archiver = _Archiver();
    await tester.pumpWidget(
      _app(
        const DataScreen(),
        exportOverrides(_Lock(const Ok(true)), archiver, _Share()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all data'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(protectSwitch);
    await tester.tap(protectSwitch);
    await tester.pumpAndSettle();
    expect(find.textContaining('two-step verification secret'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.text('Tick the box to confirm.'), findsOneWidget);
    expect(archiver.exports, 0);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(archiver.exports, 1);
    expect(archiver.password, isNull);
    expect(find.text('Backup ready · NOT encrypted'), findsOneWidget);
  });

  testWidgets('failed re-authentication blocks the export', (tester) async {
    final archiver = _Archiver();
    await tester.pumpWidget(
      _app(
        const DataScreen(),
        exportOverrides(_Lock(const Ok(false)), archiver, _Share()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all data'));
    await tester.pumpAndSettle();
    await enterPassword(tester, 'Strong-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(archiver.exports, 0);
  });

  testWidgets('vault preferences persist', (tester) async {
    final store = _Store();
    await tester.pumpWidget(
      _app(const DataScreen(), [
        settingsStoreProvider.overrideWithValue(store),
      ]),
    );
    await tester.pumpAndSettle();
    // Folders are user-created now; the old fixed-category switch is gone.
    expect(find.text('Hide empty categories'), findsNothing);
    await tester.tap(find.text('Show privacy banner'));
    await tester.pumpAndSettle();
    expect(store.saved.showPrivacyBanner, isFalse);
  });
}
