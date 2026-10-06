import 'dart:async';
import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/lock_gate.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SettingsStore {
  _Store(this.settings);

  AppSettings settings;
  Completer<void>? hold;
  bool fail = false;

  @override
  Future<AppSettings> load() async {
    await hold?.future;
    if (fail) throw StateError('disk error');
    return settings;
  }

  @override
  Future<void> save(AppSettings s) async => settings = s;
}

/// Fake App Lock with the optional session state, like the real engine.
class _Lock implements AppLock, AppLockSession {
  Result<bool> answer = const Ok(true);
  bool available = true;
  int prompts = 0;
  Completer<Result<bool>>? pending;
  bool _inFlight = false;

  @override
  bool get isAuthenticating => _inFlight;

  @override
  bool recentlyAuthenticated({
    Duration within = AppLockSession.defaultRecentWindow,
  }) => false;

  @override
  Future<EngineCapability> capability() async =>
      EngineCapability(available: available, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async {
    prompts++;
    _inFlight = true;
    try {
      return await (pending?.future ?? Future.value(answer));
    } finally {
      _inFlight = false;
    }
  }
}

/// Records whether the app underneath may animate / hold focus.
class _Probe extends StatelessWidget {
  const _Probe(this.tickers);

  final List<bool> tickers;

  @override
  Widget build(BuildContext context) {
    tickers.add(TickerMode.valuesOf(context).enabled);
    return const Scaffold(body: Text('secret content'));
  }
}

void main() {
  late Duration mono;
  late DateTime now;
  late _Lock lock;
  late _Store store;
  late bool externalLaunch;
  late List<bool> secureCalls;
  late List<bool> tickers;

  Future<void> pump(
    WidgetTester tester,
    AppSettings settings, {
    bool settle = true,
    void Function(_Store)? configure,
  }) async {
    store = _Store(settings);
    configure?.call(store);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          appLockProvider.overrideWithValue(lock),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: LockGate(
            clock: () => now,
            elapsed: () => mono,
            setSecure: ({required enabled}) async => secureCalls.add(enabled),
            externalLaunch: () async => externalLaunch,
            child: _Probe(tickers),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  void lifecycle(WidgetTester tester, AppLifecycleState s) =>
      tester.binding.handleAppLifecycleStateChanged(s);

  void background(WidgetTester tester) {
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.paused);
  }

  Future<void> foreground(WidgetTester tester) async {
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  /// Away for [d] on both clocks.
  Future<void> away(WidgetTester tester, Duration d) async {
    background(tester);
    await tester.pump();
    mono += d;
    now = now.add(d);
    await foreground(tester);
  }

  final locked = find.text('IDSnap is locked');
  final content = find.text('secret content');

  setUp(() {
    mono = const Duration(hours: 1);
    now = DateTime(2026, 9, 25, 10);
    lock = _Lock();
    externalLaunch = false;
    secureCalls = [];
    tickers = [];
  });

  tearDown(() {
    // Leave the binding in the foreground for the next test.
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('disabled lock shows the app directly', (tester) async {
    await pump(tester, const AppSettings());
    expect(content, findsOneWidget);
    expect(locked, findsNothing);
    expect(lock.prompts, 0);
    expect(secureCalls, [false]);
    // Leaving and returning never locks.
    await away(tester, const Duration(hours: 2));
    expect(content, findsOneWidget);
    expect(lock.prompts, 0);
  });

  group('cold start', () {
    testWidgets('content is never painted before settings load or unlock', (
      tester,
    ) async {
      lock.pending = Completer();
      await pump(
        tester,
        const AppSettings(appLock: true),
        settle: false,
        configure: (s) => s.hold = Completer(),
      );
      // Frame 1: settings still loading → blank cover, app offstage.
      expect(content, findsNothing);
      expect(find.text('secret content', skipOffstage: false), findsOneWidget);
      expect(tickers.last, isFalse, reason: 'no animations/auto-prompts');
      expect(lock.prompts, 0);

      store.hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(content, findsNothing);
      expect(locked, findsOneWidget);
      expect(lock.prompts, 1, reason: 'prompt starts right away');
      expect(secureCalls, [true]);
      // The app underneath can't take keyboard focus while locked.
      final focus = tester.widget<ExcludeFocus>(
        find
            .ancestor(
              of: find.text('secret content', skipOffstage: false),
              matching: find.byType(ExcludeFocus),
            )
            .first,
      );
      expect(focus.excluding, isTrue);

      lock.pending!.complete(const Ok(true));
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);
      expect(tickers.last, isTrue);
      expect(locked, findsNothing);
    });

    testWidgets('cancel stays locked with an Unlock button', (tester) async {
      lock.answer = const Ok(false);
      await pump(tester, const AppSettings(appLock: true));
      expect(lock.prompts, 1);
      expect(locked, findsOneWidget);
      expect(content, findsNothing);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.textContaining('Try again'), findsNothing);

      lock.answer = const Ok(true);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(locked, findsNothing);
      expect(content, findsOneWidget);
    });

    testWidgets('launched in the background: prompts once resumed', (
      tester,
    ) async {
      lifecycle(tester, AppLifecycleState.inactive);
      await pump(tester, const AppSettings(appLock: true));
      expect(lock.prompts, 0);
      expect(locked, findsOneWidget);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lock.prompts, 1);
      expect(content, findsOneWidget);
    });

    testWidgets('unreadable settings fail closed', (tester) async {
      await pump(tester, const AppSettings(), configure: (s) => s.fail = true);
      expect(lock.prompts, 1);
      expect(content, findsOneWidget, reason: 'unlocked by the owner');
    });
  });

  group('background timeout', () {
    for (final (minutes, below, atLimit) in [
      (0, Duration.zero, Duration.zero),
      (1, const Duration(seconds: 59), const Duration(minutes: 1)),
      (5, const Duration(minutes: 4, seconds: 59), const Duration(minutes: 5)),
    ]) {
      testWidgets('lockAfterMinutes = $minutes', (tester) async {
        await pump(
          tester,
          AppSettings(appLock: true, lockAfterMinutes: minutes),
        );
        expect(lock.prompts, 1);

        if (minutes > 0) {
          await away(tester, below);
          expect(locked, findsNothing, reason: 'just under the limit');
          expect(lock.prompts, 1);
        }

        lock.answer = const Ok(false);
        await away(tester, atLimit);
        expect(locked, findsOneWidget, reason: 'at the limit');
        expect(content, findsNothing);
        expect(lock.prompts, 2);
      });
    }

    testWidgets('inactive alone never locks, even "Immediately"', (
      tester,
    ) async {
      await pump(tester, const AppSettings(appLock: true, lockAfterMinutes: 0));
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      mono += const Duration(minutes: 30);
      now = now.add(const Duration(minutes: 30));
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(locked, findsNothing);
      expect(content, findsOneWidget);
      expect(lock.prompts, 1);
    });

    testWidgets('phone asleep: wall clock counts when monotonic stalls', (
      tester,
    ) async {
      await pump(tester, const AppSettings(appLock: true));
      background(tester);
      await tester.pump();
      now = now.add(const Duration(minutes: 10));
      lock.answer = const Ok(false);
      mono += const Duration(seconds: 1);
      await foreground(tester);
      expect(locked, findsOneWidget);
    });

    testWidgets('wall clock set back: monotonic still counts', (tester) async {
      await pump(tester, const AppSettings(appLock: true));
      background(tester);
      await tester.pump();
      now = now.subtract(const Duration(hours: 1));
      lock.answer = const Ok(false);
      mono += const Duration(minutes: 2);
      await foreground(tester);
      expect(locked, findsOneWidget);
    });

    testWidgets('file picker / camera / share sheet do not re-lock', (
      tester,
    ) async {
      await pump(tester, const AppSettings(appLock: true, lockAfterMinutes: 0));
      externalLaunch = true;
      await away(tester, const Duration(minutes: 2));
      expect(locked, findsNothing);
      expect(lock.prompts, 1);

      // ...but a long trip away through one still does.
      lock.answer = const Ok(false);
      await away(tester, LockGate.excusedGrace);
      expect(locked, findsOneWidget);
      expect(lock.prompts, 2);

      // A normal trip away ("Immediately") locks again.
      externalLaunch = false;
      lock.answer = const Ok(true);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      await away(tester, const Duration(seconds: 1));
      expect(lock.prompts, 4);
    });

    testWidgets('a prompt from elsewhere (Settings) pausing the app does not '
        'cause a second prompt', (tester) async {
      await pump(tester, const AppSettings(appLock: true, lockAfterMinutes: 0));
      expect(lock.prompts, 1);
      // Settings asks to confirm; the credential screen pauses the app.
      lock.pending = Completer();
      final settingsPrompt = lock.authenticate('Confirm to turn off');
      background(tester);
      await tester.pump();
      mono += const Duration(seconds: 20);
      now = now.add(const Duration(seconds: 20));
      lock.pending!.complete(const Ok(true));
      await settingsPrompt;
      await foreground(tester);
      expect(lock.prompts, 2, reason: 'only the Settings prompt');
      expect(locked, findsNothing);
    });

    testWidgets('the lock prompt pausing the app is not a relock loop', (
      tester,
    ) async {
      lock.pending = Completer();
      await pump(tester, const AppSettings(appLock: true, lockAfterMinutes: 0));
      expect(lock.prompts, 1);
      // Device-credential screen pauses and resumes the app mid-prompt.
      await away(tester, const Duration(seconds: 15));
      expect(lock.prompts, 1, reason: 'no second prompt while one is up');
      lock.pending!.complete(const Ok(false));
      await tester.pumpAndSettle();
      // Cancelled; the resume that follows mustn't re-prompt.
      lock.pending = null;
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lock.prompts, 1);
      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('content is covered while the app is not in front', (
      tester,
    ) async {
      await pump(tester, const AppSettings(appLock: true));
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });
  });

  group('prompt outcomes', () {
    for (final (name, detail) in [
      ('lockout', LocalAuthAppLock.lockedOut),
      ('temporary lockout', LocalAuthAppLock.temporarilyLockedOut),
      (
        'biometrics not enrolled / changed',
        LocalAuthAppLock.biometricsNotSetUp,
      ),
    ]) {
      testWidgets('$name shows a clear message and keeps Unlock', (
        tester,
      ) async {
        lock.answer = Err(
          AppFailure(FailureCode.permissionDenied, detail: detail),
        );
        await pump(tester, const AppSettings(appLock: true));
        expect(find.text(detail), findsOneWidget);
        expect(find.text('Unlock'), findsOneWidget);
        expect(content, findsNothing);

        lock.answer = const Ok(true);
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        expect(content, findsOneWidget);
      });
    }

    testWidgets('screen lock removed: Continue turns App Lock off', (
      tester,
    ) async {
      lock
        ..available = false
        ..answer = const Err(
          AppFailure(
            FailureCode.permissionDenied,
            detail: LocalAuthAppLock.setUpScreenLock,
          ),
        );
      await pump(tester, const AppSettings(appLock: true));
      expect(find.text(LockGate.noScreenLockMessage), findsOneWidget);
      expect(content, findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);
      expect(store.settings.appLock, isFalse);
      expect(secureCalls.last, isFalse);
    });

    testWidgets('only one prompt at a time', (tester) async {
      lock.answer = const Ok(false);
      await pump(tester, const AppSettings(appLock: true));
      lock.pending = Completer();
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.tap(find.text('Unlock'), warnIfMissed: false);
      await tester.pump();
      // Resuming while the prompt is up doesn't add another.
      await away(tester, const Duration(minutes: 10));
      expect(lock.prompts, 2);
      lock.pending!.complete(const Ok(true));
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);
    });
  });

  group('settings toggles', () {
    testWidgets('turning the lock on mid-session does not lock you out', (
      tester,
    ) async {
      await pump(tester, const AppSettings());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LockGate)),
      );
      await container
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(appLock: true));
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);
      expect(lock.prompts, 0);
      expect(secureCalls, [false, true]);

      // From now on, leaving locks it.
      lock.answer = const Ok(false);
      await away(tester, const Duration(minutes: 2));
      expect(locked, findsOneWidget);

      // Turning it off (Settings authenticated) removes lock and flag.
      await container
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(appLock: false));
      await tester.pumpAndSettle();
      expect(content, findsOneWidget);
      expect(secureCalls.last, isFalse);
    });
  });

  test('native hosts register the same channel as SecureWindow', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/docscan/docscan_scanner/MainActivity.kt',
    ).readAsStringSync();
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    for (final src in [kotlin, swift]) {
      expect(src, contains('"${SecureWindow.channelName}"'));
      expect(src, contains('"setSecure"'));
      expect(src, contains('"consumeExternalLaunch"'));
    }
    expect(kotlin, contains('FlutterFragmentActivity()'));
    expect(kotlin, contains('FLAG_SECURE'));
    expect(swift, contains('willDeactivateNotification'));
    expect(swift, contains('didActivateNotification'));
  });
}
