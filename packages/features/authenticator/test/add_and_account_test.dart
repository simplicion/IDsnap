import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  group('add manually', () {
    testWidgets('validates name and secret before saving', (tester) async {
      final env = Env();
      await env.pump(tester, initial: '/authenticator/add');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(find.text(AddAccountScreen.nameRequired), findsOneWidget);
      expect(find.text('Enter the secret key.'), findsOneWidget);
      expect(env.repo.accounts, isEmpty);

      await tester.enterText(_field('Account name'), 'me@example.com');
      await tester.enterText(_field('Secret key'), 'ABC1 8900');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(find.text(Base32.badCharacter), findsOneWidget);
      expect(env.repo.accounts, isEmpty);

      await tester.enterText(_field('Secret key'), 'mzxw6ytb');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(find.text(Base32.tooShort), findsOneWidget);
    });

    testWidgets('saves a valid account with advanced options', (tester) async {
      final env = Env();
      await env.pump(tester, initial: '/authenticator/add');
      await tester.enterText(_field('Account name'), ' me@example.com ');
      await tester.enterText(_field('Issuer (optional)'), 'GitHub');
      await tester.enterText(_field('Secret key'), 'jbsw y3dp ehpk 3pxp');
      await tester.tap(find.text('Advanced'));
      await settle(tester);
      await tester.tap(find.text('SHA256'));
      await tester.tap(find.text('8'));
      await tester.enterText(_field('Period (seconds)'), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(find.text(AddAccountScreen.periodInvalid), findsOneWidget);

      await tester.enterText(_field('Period (seconds)'), '60');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      final a = env.repo.accounts.single;
      expect(a.label, 'me@example.com');
      expect(a.issuer, 'GitHub');
      expect(a.algorithm, OtpAlgorithm.sha256);
      expect(a.digits, 8);
      expect(a.period, 60);
      expect(env.repo.secrets[a.secretKeyId], secretA);
      // Back on the list.
      expect(find.text('Authenticator'), findsOneWidget);
    });

    testWidgets('HOTP needs a counter', (tester) async {
      final env = Env();
      await env.pump(tester, initial: '/authenticator/add');
      await tester.enterText(_field('Account name'), 'bank');
      await tester.enterText(_field('Secret key'), secretA);
      await tester.tap(find.text('Advanced'));
      await settle(tester);
      await tester.tap(find.text('Counter-based'));
      await settle(tester);
      await tester.enterText(_field('Counter'), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(find.text(AddAccountScreen.counterInvalid), findsOneWidget);
      await tester.enterText(_field('Counter'), '7');
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await settle(tester);
      expect(env.repo.accounts.single.type, OtpType.hotp);
      expect(env.repo.accounts.single.counter, 7);
    });
  });

  group('scan QR', () {
    testWidgets('a detected otpauth URI adds the account', (tester) async {
      final env = Env();
      await env.pump(tester, initial: '/authenticator/scan');
      expect(find.text('camera'), findsOneWidget);
      env.qr.onDetect!('https://example.com');
      await settle(tester);
      expect(
        find.textContaining('Not an authenticator QR code'),
        findsOneWidget,
      );
      expect(env.repo.accounts, isEmpty);

      env.qr.onDetect!(
        'otpauth://totp/GitHub:me?secret=$secretA&issuer=GitHub',
      );
      await settle(tester);
      expect(env.repo.accounts.single.issuer, 'GitHub');
      expect(find.text('Authenticator'), findsOneWidget);
    });

    testWidgets('gallery image fallback', (tester) async {
      final env = Env();
      await env.pump(tester, initial: '/authenticator/scan');
      await tester.tap(find.text('Choose from gallery'));
      await settle(tester);
      expect(find.textContaining(ScanQrScreen.noQrInImage), findsOneWidget);

      env.qr.imageResult = const Ok('otpauth://totp/me?secret=$secretA');
      // The snackbar now covers the bottom button; use the app bar action.
      await tester.tap(find.byTooltip('Choose from gallery'));
      await settle(tester);
      expect(env.repo.accounts.single.label, 'me');
    });

    testWidgets('no camera: explains and still offers other paths', (
      tester,
    ) async {
      final env = Env()..qr.available = false;
      await env.pump(tester, initial: '/authenticator/scan');
      expect(find.text(FailureCode.cameraUnavailable.title), findsOneWidget);
      expect(find.text('Enter key manually'), findsOneWidget);
      await tester.tap(find.text('Enter key manually'));
      await settle(tester);
      expect(find.text('Secret key'), findsOneWidget);
    });
  });

  group('account page', () {
    Future<OtpAccount> open(WidgetTester tester, Env env) async {
      final a = env.repo.seed(
        const NewOtpAccount(label: 'me', issuer: 'GitHub', secret: secretA),
      );
      await env.pump(tester, initial: '/authenticator/account/${a.id}');
      return a;
    }

    testWidgets('recovery codes need re-authentication', (tester) async {
      final env = Env(lock: FakeAppLock(results: [const Ok(false)]));
      final a = await open(tester, env);
      env.repo.recovery[a.secretKeyId] = const [RecoveryCode('1111-2222')];
      final before = env.lock.calls;

      await tester.tap(find.text('Emergency recovery codes'));
      await settle(tester);
      expect(env.lock.calls, before + 1);
      expect(find.text('1111-2222'), findsNothing, reason: 'cancelled');

      await tester.tap(find.text('Emergency recovery codes'));
      await settle(tester);
      expect(find.text('1111-2222'), findsOneWidget);
    });

    testWidgets('paste several, mark used, copy with 60 s clear', (
      tester,
    ) async {
      final env = Env();
      final a = await open(tester, env);
      await tester.tap(find.text('Emergency recovery codes'));
      await settle(tester);
      expect(find.textContaining('No recovery codes saved'), findsOneWidget);

      await tester.tap(find.text('Paste several'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'aaaa-1111\n\n bbbb-2222 \naaaa-1111\ncccc-3333',
      );
      await tester.tap(find.text('Add codes'));
      await settle(tester);
      expect(env.repo.recovery[a.secretKeyId]!.map((c) => c.code), [
        'aaaa-1111',
        'bbbb-2222',
        'cccc-3333',
      ]);

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);
      expect(env.repo.recovery[a.secretKeyId]!.first.used, isTrue);

      await tester.tap(find.byTooltip('Copy code').at(1));
      await tester.pump();
      expect(env.clipboard.text, 'bbbb-2222');
      await tester.pump(const Duration(seconds: 61));
      expect(env.clipboard.text, '');
    });

    testWidgets('rename updates issuer and label', (tester) async {
      final env = Env();
      await open(tester, env);
      await tester.tap(find.text('Edit name and issuer'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Issuer'),
        'GitHub Work',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(env.repo.accounts.single.issuer, 'GitHub Work');
      expect(find.text('GitHub Work'), findsOneWidget);
    });

    testWidgets('delete confirms and wipes secrets', (tester) async {
      final env = Env();
      final a = await open(tester, env);
      env.repo.recovery[a.secretKeyId] = const [RecoveryCode('x')];
      await tester.tap(find.text('Remove account'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.repo.accounts, hasLength(1));

      await tester.tap(find.text('Remove account'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await settle(tester);
      expect(env.repo.accounts, isEmpty);
      expect(env.repo.secrets, isEmpty);
      expect(env.repo.recovery, isEmpty);
    });
  });
}
