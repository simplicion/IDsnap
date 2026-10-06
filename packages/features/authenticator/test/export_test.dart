import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:feature_authenticator/src/setup_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class _Section implements BackupSection {
  @override
  String get key => 'authenticator';

  @override
  String get label => 'Authenticator accounts';

  @override
  Future<BackupSectionData?> export() async =>
      const BackupSectionData(version: 1, data: <Object?>[], count: 1);

  @override
  Future<int> restore(Object? data, {required int version}) async => 0;

  @override
  Future<void> erase() async {}
}

class _Archiver implements LibraryArchiver {
  String? password;
  bool? includeDocuments;
  List<String>? sectionKeys;
  String? fileName;

  @override
  Future<Result<BackupResult>> exportBackup({
    String? password,
    List<BackupSection> sections = const [],
    bool includeDocuments = true,
    String? fileName,
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  }) async {
    this.password = password;
    this.includeDocuments = includeDocuments;
    this.fileName = fileName;
    sectionKeys = [for (final s in sections) s.key];
    return Ok(
      BackupResult(
        path: '/cache/share/a/$fileName',
        fileName: fileName!,
        sizeBytes: 10,
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
  }) async => const Ok(ImportSummary());
}

void main() {
  test('setup URI round-trips through the otpauth parser', () {
    for (final account in [
      const NewOtpAccount(
        label: 'me@example.com',
        issuer: 'Git Hub & Co',
        secret: secretA,
      ),
      const NewOtpAccount(
        label: 'counter user',
        secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        type: OtpType.hotp,
        algorithm: OtpAlgorithm.sha256,
        digits: 8,
        counter: 42,
      ),
    ]) {
      final stored = OtpAccount(
        id: 'x',
        label: account.label,
        issuer: account.issuer,
        secretKeyId: 'otp.x',
        type: account.type,
        algorithm: account.algorithm,
        digits: account.digits,
        period: account.period,
        counter: account.counter,
        createdAt: DateTime(2026),
      );
      final secret = codec.decodeSecret(account.secret).valueOrNull!;
      expect(base32Encode(secret), account.secret);
      final parsed = codec.parseUri(otpAuthUri(stored, secret));
      expect(parsed.valueOrNull, account);
    }
    expect(base32Encode(Uint8List.fromList('foobar'.codeUnits)), 'MZXW6YTBOI');
  });

  testWidgets('Show setup QR needs a fresh unlock', (tester) async {
    final env = Env(lock: FakeAppLock(results: [const Ok(false)]));
    final a = env.repo.seed(
      const NewOtpAccount(label: 'me', issuer: 'GitHub', secret: secretA),
    );
    await env.pump(tester, initial: '/authenticator/account/${a.id}');
    final before = env.lock.calls;

    await tester.tap(find.text('Show setup QR'));
    await settle(tester);
    expect(env.lock.calls, before + 1);
    expect(find.textContaining('Setup QR'), findsNothing, reason: 'cancelled');

    await tester.tap(find.text('Show setup QR'));
    await settle(tester);
    expect(find.text('Setup QR · GitHub'), findsOneWidget);
    expect(find.textContaining('never share or screenshot'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Setup QR · GitHub'), findsNothing);
  });

  testWidgets('Export accounts: password required, unlock, accounts only', (
    tester,
  ) async {
    final env = Env();
    env.repo.seed(const NewOtpAccount(label: 'me', secret: secretA));
    final archiver = _Archiver();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides(tester),
          libraryArchiverProvider.overrideWithValue(archiver),
          backupSectionsProvider.overrideWithValue([_Section()]),
          plainFileAccessProvider.overrideWithValue(
            const PassThroughFileAccess(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AuthenticatorScreen(),
        ),
      ),
    );
    await settle(tester);
    final before = env.lock.calls;
    await tester.tap(find.byTooltip('Authenticator options'));
    await settle(tester);
    await tester.tap(find.text('Export accounts'));
    await settle(tester);
    // No "unprotected" switch for a file of 2FA secrets.
    expect(find.text('Protect this backup with a password'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'Accounts-Pass-1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat password'),
      'Accounts-Pass-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await settle(tester);
    expect(env.lock.calls, before + 1);
    expect(archiver.password, 'Accounts-Pass-1');
    expect(archiver.includeDocuments, isFalse);
    expect(archiver.sectionKeys, ['authenticator']);
    expect(archiver.fileName, startsWith('IDSnap authenticator '));
    expect(find.text('Backup ready · password-protected'), findsOneWidget);
  });
}
