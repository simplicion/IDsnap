import 'dart:io';

import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_scanner/error_reporting.dart';
import 'package:docscan_scanner/startup_failure.dart';
import 'package:docscan_scanner/vault_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup shows progress only while files are encrypted', (
    tester,
  ) async {
    final progress = ValueNotifier<(int, int)?>(null);
    await tester.pumpWidget(VaultStartupScreen(progress: progress));
    expect(find.text('Encrypting your vault'), findsNothing);
    // Never a blank first frame: the splash shows at once, and says what
    // is happening when opening is slow.
    expect(find.text('IDSnap'), findsOneWidget);
    await tester.pump(StartupSplash.slowAfter);
    expect(find.text('Opening your vault…'), findsOneWidget);
    progress.value = (2, 8);
    await tester.pump();
    expect(find.text('Encrypting your vault'), findsOneWidget);
    expect(find.text('2 of 8 files'), findsOneWidget);
  });

  testWidgets('a missing key never erases without two confirmations', (
    tester,
  ) async {
    var erased = 0;
    await tester.pumpWidget(
      VaultRecoveryScreen(
        reason: VaultUnavailableReason.keyMissing,
        onErase: () async => erased++,
      ),
    );
    expect(find.textContaining('Export'), findsOneWidget);
    await tester.tap(find.text('Erase vault and start fresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Erase'));
    await tester.pumpAndSettle();
    expect(erased, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Erase everything'));
    await tester.pump();
    expect(erased, 1);
  });

  testWidgets('a keystore error offers no erase', (tester) async {
    await tester.pumpWidget(
      VaultRecoveryScreen(
        reason: VaultUnavailableReason.keystoreError,
        onErase: () async {},
      ),
    );
    expect(find.text('Erase vault and start fresh'), findsNothing);
    expect(find.textContaining('Restart the phone'), findsOneWidget);
  });

  testWidgets('any startup failure shows a recovery screen with Try again', (
    tester,
  ) async {
    var calls = 0;
    Future<List<Never>> failing({onVaultMigration}) async {
      calls++;
      throw StartupFailure(
        StartupStep.vault,
        StateError('SQLCipher is not available at /data/user/0/x/lib.so'),
        StackTrace.current,
      );
    }

    await tester.runAsync(() => startApp(build: failing));
    await tester.pump();
    expect(find.text("Your vault couldn't be opened"), findsOneWidget);
    expect(find.textContaining('Do not uninstall'), findsOneWidget);
    expect(find.textContaining('Export all data'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an untagged error (e.g. a font asset) is caught too', (
    tester,
  ) async {
    Future<List<Never>> failing({onVaultMigration}) async =>
        throw const FormatException('bad font');
    await tester.runAsync(() => startApp(build: failing));
    await tester.pump();
    expect(find.text("IDSnap couldn't start"), findsOneWidget);
  });

  test('copied details are redacted and name the step', () {
    LocalErrorLog.clear();
    final details = StartupRecoveryScreen.details(
      StartupFailure(
        StartupStep.pdfEngine,
        StateError('cannot open /storage/emulated/0/Passport scan.pdf'),
        StackTrace.empty,
      ),
    );
    expect(details, contains('step=pdfEngine'));
    expect(details, contains('StateError'));
    expect(details, isNot(contains('Passport')));
    expect(details, isNot(contains('/storage')));
  });

  test('out of storage gets its own explanation', () {
    const f = StartupFailure(
      StartupStep.vault,
      FileSystemException('write', 'x', OSError('No space', 28)),
      StackTrace.empty,
    );
    expect(f.explanation.$1, 'Your phone is out of storage');
  });

  testWidgets('release error widget has no error text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ReleaseErrorWidget()),
    );
    expect(find.textContaining("couldn't be shown"), findsOneWidget);
  });
}
