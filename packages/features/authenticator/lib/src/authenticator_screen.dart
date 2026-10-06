import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart' show BackupResult;
import 'package:feature_authenticator/src/add_account_sheet.dart';
import 'package:feature_authenticator/src/auth_gate.dart';
import 'package:feature_authenticator/src/secure_scope.dart';
import 'package:feature_authenticator/src/services.dart';
import 'package:feature_authenticator/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Authenticator tab: every account with its current code.
///
/// Reveal gate: when "Require unlock" is on (default) and the device supports
/// biometrics or a screen lock, codes stay hidden until the user
/// authenticates — each time the tab is opened and after the app has been in
/// the background. FLAG_SECURE is on while the tab is visible.
class AuthenticatorScreen extends ConsumerStatefulWidget {
  const AuthenticatorScreen({super.key});

  static const unlockReason = 'Show your authenticator codes';
  static const noLockHint =
      'This phone has no screen lock, so codes are shown without unlocking. '
      'Set a screen lock in Settings to protect them.';

  @override
  ConsumerState<AuthenticatorScreen> createState() =>
      _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends ConsumerState<AuthenticatorScreen>
    with WidgetsBindingObserver {
  late final ValueNotifier<DateTime> _now;
  Timer? _ticker;
  bool _visible = false;
  bool _authenticating = false;
  AppFailure? _authFailure;

  @override
  void initState() {
    super.initState();
    _now = ValueNotifier(ref.read(authenticatorClockProvider).now());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _startTicker();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) unawaited(_reveal(auto: true));
      });
    } else {
      _ticker?.cancel();
      // Providers can't change mid-build; hide right after this frame.
      final leaving = !_insideAuthenticator();
      if (leaving) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_visible) ref.read(revealProvider.notifier).hide();
        });
      }
    }
  }

  /// True while the router still shows an authenticator page (e.g. an
  /// account pushed over the list), so the reveal survives sub-pages.
  bool _insideAuthenticator() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return false;
    final path = router.routerDelegate.currentConfiguration.uri.path;
    return path.startsWith(Routes.authenticator);
  }

  void _startTicker() {
    _ticker?.cancel();
    final clock = ref.read(authenticatorClockProvider);
    _now.value = clock.now();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _now.value = clock.now(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system credential screen can pause the app; don't hide mid-prompt.
    if (_authenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(revealProvider.notifier).hide();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _now.dispose();
    super.dispose();
  }

  /// An encrypted backup of just the accounts (secret keys and recovery
  /// codes), so users don't depend on the full backup (audit H-04). Always
  /// password-protected and behind a fresh unlock.
  Future<void> _exportAccounts() async {
    final accounts = ref.read(otpAccountsProvider).value ?? const [];
    if (accounts.isEmpty) {
      showAppSnack(context, 'There are no accounts to export yet.');
      return;
    }
    final choice = await askExportOptions(
      context,
      title: 'Export accounts',
      included: const [
        'Every authenticator account: name, secret key and settings',
        'Their recovery codes',
      ],
      allowUnprotected: false,
    );
    if (choice == null || !mounted) return;
    final auth = await authenticateUser(
      ref,
      'Confirm to export your accounts',
      acceptRecent: false,
    );
    if (!mounted) return;
    if (auth case Err(:final failure)) {
      showFailureSnack(context, failure);
      return;
    }
    if (auth.valueOrNull != true) return;
    final sections = [
      for (final s in ref.read(backupSectionsProvider))
        if (s.key == 'authenticator') s,
    ];
    final archiver = ref.read(libraryArchiverProvider);
    final now = ref.read(authenticatorClockProvider).now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final result = await runBackupJob<BackupResult>(
      context,
      title: 'Exporting accounts',
      job: (onProgress, cancel) => archiver.exportBackup(
        password: choice.password,
        sections: sections,
        includeDocuments: false,
        fileName: 'IDSnap authenticator $stamp.zip',
        onProgress: onProgress,
        cancel: cancel,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        await deliverBackup(context, ref, value);
      case Err(:final failure):
        showFailureSnack(context, failure);
    }
  }

  Future<void> _reveal({bool auto = false}) async {
    // Claimed synchronously so overlapping triggers (tab opened, accounts
    // loaded, a tap) never stack two system prompts.
    if (_authenticating || ref.read(revealProvider)) return;
    _authenticating = true;
    final settings = await ref.read(settingsProvider.future);
    // Don't prompt over an empty list.
    final skip =
        !settings.authenticatorRequireUnlock ||
        (auto && (ref.read(otpAccountsProvider).value?.isEmpty ?? true));
    if (!mounted) return;
    if (skip) {
      _authenticating = false;
      return;
    }
    setState(() => _authFailure = null);
    final result = await authenticateUser(
      ref,
      AuthenticatorScreen.unlockReason,
    );
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      result.fold((ok) {
        if (ok) ref.read(revealProvider.notifier).reveal();
      }, (f) => _authFailure = f);
    });
  }

  Future<void> _setRequireUnlock({required bool on}) async {
    if (!on) {
      // Turning protection off needs the owner's approval.
      final r = await authenticateUser(ref, 'Turn off unlock for codes');
      if (!mounted) return;
      if (r case Err(:final failure)) {
        showFailureSnack(context, failure);
        return;
      }
      if (r.valueOrNull != true) return;
    }
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(authenticatorRequireUnlock: on));
  }

  Future<void> _copy(String code) async {
    await ref.read(secureClipboardProvider).copy(code);
    if (!mounted) return;
    showAppSnack(
      context,
      'Code copied. The clipboard clears in '
      '${SecureClipboard.defaultClearAfter.inSeconds} seconds.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(otpAccountsProvider);
    final requireUnlock = ref.watch(
      currentSettingsProvider.select((s) => s.authenticatorRequireUnlock),
    );
    final capability = ref.watch(authCapabilityProvider);
    final lockAvailable = capability.value?.available;
    // Hidden while the capability is unknown, so nothing flashes.
    final gated = requireUnlock && (lockAvailable ?? true);
    final revealed = !gated || ref.watch(revealProvider);

    // Auto-prompt once accounts arrive if the tab opened before they loaded.
    ref.listen(otpAccountsProvider, (prev, next) {
      final wasEmpty = prev?.value?.isEmpty ?? true;
      if (wasEmpty && (next.value?.isNotEmpty ?? false) && _visible) {
        unawaited(_reveal(auto: true));
      }
    });

    return SecureScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Authenticator'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Authenticator options',
              onSelected: (v) {
                if (v == 'unlock') {
                  unawaited(_setRequireUnlock(on: !requireUnlock));
                } else if (v == 'export') {
                  unawaited(_exportAccounts());
                } else if (v == 'import') {
                  unawaited(importBackupFlow(context, ref));
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'unlock',
                  checked: requireUnlock,
                  child: const Text('Require unlock to show codes'),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Text('Export accounts'),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Import a backup'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: (accounts.value?.isNotEmpty ?? false)
            ? FloatingActionButton.extended(
                onPressed: () => showAddAccountSheet(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add account'),
              )
            : null,
        body: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FailureView(
            e is AppFailure
                ? e
                : AppFailure(
                    FailureCode.unknown,
                    cause: e,
                    heading: "Your accounts couldn't be loaded",
                    message:
                        'They are still saved on this phone. Try again, or '
                        'restart IDSnap.',
                  ),
            onRetry: () => ref.invalidate(otpAccountsProvider),
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No accounts yet',
                  message:
                      'Add the QR code or key a website shows when you turn '
                      'on two-step verification. Codes are made on this '
                      'phone and work offline.',
                  actionLabel: 'Add account',
                  onAction: () => showAddAccountSheet(context),
                )
              : ListView(
                  padding: const EdgeInsets.only(
                    top: Space.x2,
                    bottom: Space.x12 * 2,
                  ),
                  children: [
                    if (!revealed)
                      _HiddenBanner(
                        busy: _authenticating,
                        failure: _authFailure,
                        onReveal: _reveal,
                      ),
                    if (requireUnlock && lockAvailable == false)
                      const _Hint(AuthenticatorScreen.noLockHint),
                    for (final a in list)
                      AccountTile(
                        key: ValueKey(a.id),
                        account: a,
                        now: _now,
                        revealed: revealed,
                        onCopy: _copy,
                        onReveal: _reveal,
                        onOpen: () => unawaited(
                          context.push(Routes.authenticatorAccount(a.id)),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HiddenBanner extends StatelessWidget {
  const _HiddenBanner({
    required this.busy,
    required this.failure,
    required this.onReveal,
  });

  final bool busy;
  final AppFailure? failure;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return Card(
      margin: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x1,
        Space.gutter,
        Space.x2,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_off_rounded),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Text(
                    'Codes are hidden. Unlock with your fingerprint, face or '
                    'screen lock to see them.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
            if (f != null) ...[
              const SizedBox(height: Space.x2),
              Semantics(
                liveRegion: true,
                child: Text(
                  f.detail ?? '${f.title}. ${f.recovery}',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: Space.x3),
            FilledButton.icon(
              onPressed: busy ? null : onReveal,
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Show codes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x1,
      Space.gutter,
      Space.x2,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: context.ds.warning, size: 20),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
