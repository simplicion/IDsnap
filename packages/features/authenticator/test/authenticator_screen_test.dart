import 'dart:async';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('list', () {
    testWidgets('empty state offers to add an account', (tester) async {
      final env = Env();
      await env.pump(tester);
      expect(find.text('No accounts yet'), findsOneWidget);
      await tester.tap(find.text('Add account'));
      await settle(tester);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Enter key manually'), findsOneWidget);
      // Nothing to reveal → no prompt.
      expect(env.lock.calls, 0);
    });

    testWidgets('shows issuer, label, grouped code and a synced ring', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(
        const NewOtpAccount(
          label: 'me@example.com',
          issuer: 'GitHub',
          secret: secretA,
        ),
      );
      await env.pump(tester);

      expect(env.lock.calls, 1, reason: 'opening the tab asks to unlock');
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('me@example.com'), findsOneWidget);
      final code = expectedTotp(Env.base);
      expect(
        find.text('${code.substring(0, 3)} ${code.substring(3)}'),
        findsOneWidget,
      );

      // 5 s into the step (+1 s of settling) → 24 s left, primary colour.
      final ring = tester.widget<CountdownRing>(find.byType(CountdownRing));
      expect(ring.seconds, 24);
      expect(ring.warning, isFalse);

      // Last 5 s: the ring switches to the error colour.
      await tester.pump(const Duration(seconds: 19));
      await tester.pump(const Duration(milliseconds: 300));
      final late = tester.widget<CountdownRing>(find.byType(CountdownRing));
      expect(late.seconds, lessThanOrEqualTo(5));
      expect(late.warning, isTrue);
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CountdownRing),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((p) => p.painter)
          .whereType<RingPainter>()
          .single;
      expect(
        painter.color,
        Theme.of(tester.element(find.byType(CountdownRing))).colorScheme.error,
      );

      // Rolls over to the next step's code at the boundary.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      final next = expectedTotp(Env.base.add(const Duration(seconds: 25)));
      expect(next, isNot(code));
      expect(
        find.text('${next.substring(0, 3)} ${next.substring(3)}'),
        findsOneWidget,
      );
      expect(
        tester.widget<CountdownRing>(find.byType(CountdownRing)).seconds,
        greaterThan(25),
      );
    });

    testWidgets('8-digit codes are grouped 4 + 4', (tester) async {
      final env = Env();
      env.repo.seed(
        const NewOtpAccount(label: 'x', secret: secretA, digits: 8),
      );
      await env.pump(tester);
      expect(find.textContaining(RegExp(r'^\d{4} \d{4}$')), findsOneWidget);
    });

    testWidgets('tap copies; clipboard clears after 60 s if unchanged', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);

      final code = expectedTotp(Env.base);
      await tester.tap(find.byKey(const ValueKey('code-a0')));
      await tester.pump();
      expect(env.clipboard.text, code);
      expect(find.textContaining('Code copied'), findsOneWidget);

      await tester.pump(const Duration(seconds: 59));
      expect(env.clipboard.text, code);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(env.clipboard.text, '');
    });

    testWidgets('clipboard is left alone if the user copied something else', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      await tester.tap(find.byKey(const ValueKey('code-a0')));
      await tester.pump();
      env.clipboard.text = 'my own note';
      await tester.pump(const Duration(seconds: 61));
      expect(env.clipboard.text, 'my own note');
    });

    testWidgets('HOTP shows the counter code and advances on "Next code"', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(
        const NewOtpAccount(
          label: 'bank',
          secret: secretA,
          type: OtpType.hotp,
          counter: 3,
        ),
      );
      await env.pump(tester);
      final bytes = codec.decodeSecret(secretA).valueOrNull!;
      String grouped(int c) {
        final v = codec.hotp(bytes, counter: c);
        return '${v.substring(0, 3)} ${v.substring(3)}';
      }

      expect(find.byType(CountdownRing), findsNothing);
      expect(find.text(grouped(3)), findsOneWidget);
      await tester.tap(find.byTooltip('Next code'));
      await settle(tester);
      expect(env.repo.accounts.single.counter, 4);
      expect(find.text(grouped(4)), findsOneWidget);
    });

    testWidgets('a missing secret shows a typed error on the row', (
      tester,
    ) async {
      final env = Env();
      final a = env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      env.repo.secrets.remove(a.secretKeyId);
      await env.pump(tester);
      expect(
        find.textContaining(FailureCode.secretUnavailable.title),
        findsOneWidget,
      );
      expect(find.textContaining('Something went wrong'), findsNothing);
    });
  });

  group('reveal gate', () {
    testWidgets('codes stay hidden until the user authenticates', (
      tester,
    ) async {
      final env = Env(lock: FakeAppLock(results: [const Ok(false)]));
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);

      expect(env.lock.calls, 1);
      expect(find.text('••• •••'), findsOneWidget);
      expect(find.text('Show codes'), findsOneWidget);
      // Tapping a hidden code doesn't copy it.
      await tester.tap(find.byKey(const ValueKey('code-a0')));
      await settle(tester);
      expect(env.clipboard.writes, isEmpty);
      expect(env.lock.calls, 2, reason: 'tapping a hidden row asks again');

      final code = expectedTotp(Env.base);
      expect(
        find.text('${code.substring(0, 3)} ${code.substring(3)}'),
        findsOneWidget,
      );
      expect(find.text('Show codes'), findsNothing);
    });

    testWidgets('an auth failure is explained, not generic', (tester) async {
      final env = Env(
        lock: FakeAppLock(
          results: [
            const Err(
              AppFailure(
                FailureCode.permissionDenied,
                detail: 'Too many attempts.',
              ),
            ),
          ],
        ),
      );
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      expect(find.text('Too many attempts.'), findsOneWidget);
      expect(find.text('••• •••'), findsOneWidget);
    });

    testWidgets('hides again after the app goes to the background', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      expect(find.text('••• •••'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.text('••• •••'), findsOneWidget);

      await tester.tap(find.text('Show codes'));
      await settle(tester);
      expect(find.text('••• •••'), findsNothing);
    });

    testWidgets('leaving the tab hides codes; coming back asks again', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      final router = await env.pump(tester);
      expect(env.lock.calls, 1);

      router.go('/other');
      await settle(tester);
      expect(find.text('other tab'), findsOneWidget);

      env.lock.results = [...env.lock.results, const Ok(true), const Ok(false)];
      router.go('/authenticator');
      await settle(tester);
      // Asked again on return; this time the user cancels → hidden.
      expect(env.lock.calls, 2);
      expect(find.text('••• •••'), findsOneWidget);
    });

    testWidgets('an account page keeps codes revealed on return', (
      tester,
    ) async {
      final env = Env();
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      await tester.tap(find.byTooltip('Account options'));
      await settle(tester);
      expect(find.text('Emergency recovery codes'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(env.lock.calls, 1);
      expect(find.text('••• •••'), findsNothing);
    });

    testWidgets('no screen lock → codes shown directly with a hint', (
      tester,
    ) async {
      final env = Env(lock: FakeAppLock(available: false));
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      expect(env.lock.calls, 0);
      expect(find.text('••• •••'), findsNothing);
      expect(find.text(AuthenticatorScreen.noLockHint), findsOneWidget);
    });

    testWidgets('setting off → no prompt, codes shown', (tester) async {
      final env = Env(
        settings: const AppSettings(authenticatorRequireUnlock: false),
      );
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);
      expect(env.lock.calls, 0);
      expect(find.text('••• •••'), findsNothing);
    });

    testWidgets('turning the setting off requires authentication', (
      tester,
    ) async {
      final env = Env(
        lock: FakeAppLock(results: [const Ok(true), const Ok(false)]),
      );
      env.repo.seed(const NewOtpAccount(label: 'x', secret: secretA));
      await env.pump(tester);

      Future<void> toggle() async {
        await tester.tap(find.byTooltip('Authenticator options'));
        await settle(tester);
        await tester.tap(find.text('Require unlock to show codes'));
        await settle(tester);
      }

      await toggle(); // Auth cancelled → stays on.
      expect(env.settings.settings.authenticatorRequireUnlock, isTrue);
      await toggle(); // Auth ok → off.
      expect(env.settings.settings.authenticatorRequireUnlock, isFalse);
      await toggle(); // Turning on needs no auth.
      expect(env.settings.settings.authenticatorRequireUnlock, isTrue);
      expect(env.lock.calls, 3);
    });
  });

  group('FLAG_SECURE', () {
    testWidgets('on while visible, restored when leaving', (tester) async {
      final env = Env();
      final router = await env.pump(tester);
      expect(env.secure.calls, [true]);

      // Sub-pages keep it on without flicker.
      unawaited(router.push('/authenticator/add'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(env.secure.calls, [true]);

      router.go('/other');
      await settle(tester);
      // App Lock is off, so the flag goes back off.
      expect(env.secure.calls, [true, false]);
    });

    testWidgets('restores to on when App Lock wants it', (tester) async {
      final env = Env(settings: const AppSettings(appLock: true));
      final router = await env.pump(tester);
      router.go('/other');
      await settle(tester);
      expect(env.secure.calls.last, isTrue);
    });
  });

  test('groupCode', () {
    expect(groupCode('123456'), '123 456');
    expect(groupCode('12345678'), '1234 5678');
    expect(groupCode('•••'), '•••');
  });

  test('remainingInStep follows wall-clock boundaries', () {
    final r = remainingInStep(DateTime.utc(2026, 1, 1, 0, 0, 25, 500), 30);
    expect(r.seconds, 5);
    expect(r.fraction, closeTo(4.5 / 30, 1e-9));
    expect(remainingInStep(DateTime.utc(2026, 1, 1, 0, 1), 60).seconds, 60);
  });
}
