import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_scanner/app.dart';
import 'package:docscan_scanner/app_info.dart';
import 'package:docscan_scanner/bootstrap.dart';
import 'package:docscan_scanner/error_reporting.dart';
import 'package:docscan_scanner/startup_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Builds the production overrides; replaceable in tests.
typedef OverridesBuilder =
    Future<List<Override>> Function({VaultMigrationProgress? onVaultMigration});

/// Starts IDSnap: unlocks (and, once, encrypts) the vault, then runs the
/// app. A startup screen is shown at once (never a blank page) and reports
/// encryption progress when there is any. When the vault can't be unlocked
/// on this phone a recovery screen is shown (ADR-0010); ANY other startup
/// failure (SQLCipher, the keystore, PDFium, assets, migrations, billing)
/// shows [StartupRecoveryScreen] with Try again (audit H-08).
Future<void> startApp({OverridesBuilder build = buildOverrides}) async {
  final progress = ValueNotifier<(int, int)?>(null);
  runApp(VaultStartupScreen(progress: progress));
  try {
    final overrides = await build(
      onVaultMigration: (done, total) => progress.value = (done, total),
    );
    ProviderContainer? current;
    // Also re-run by "Erase everything" (appRestartProvider): a fresh
    // container over the same services, so every cached provider in every
    // feature starts again from the now-empty storage (audit H-06).
    void launch() {
      final previous = current;
      final container = current = ProviderContainer(
        overrides: [...overrides, appRestartProvider.overrideWithValue(launch)],
      );
      runApp(
        UncontrolledProviderScope(
          key: UniqueKey(),
          container: container,
          child: const DocScanApp(),
        ),
      );
      // After the first frame: bring expiry reminders in line with the
      // setting (covers imports, restores and app updates). Never prompts.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
        unawaited(resyncReminders(container));
      });
    }

    launch();
  } on VaultUnavailableException catch (e) {
    runApp(
      VaultRecoveryScreen(
        reason: e.reason,
        onErase: () async {
          await eraseVault(
            root: await defaultVaultRoot(),
            cacheRoot: await defaultVaultCache(),
            keys: vaultKeyStore(),
          );
          await startApp(build: build);
        },
      ),
    );
  } on Object catch (e, st) {
    final failure = e is StartupFailure
        ? e
        : StartupFailure(StartupStep.app, e, st);
    LocalErrorLog.record(
      'startup_failed',
      failure.cause,
      where: failure.step.name,
    );
    runApp(
      StartupRecoveryScreen(
        failure: failure,
        onRetry: () => startApp(build: build),
      ),
    );
  }
}

/// Re-schedules (or cancels) every expiry reminder to match the setting.
/// Failures are logged locally; the user sees them when they next touch
/// reminders.
@visibleForTesting
Future<void> resyncReminders(ProviderContainer container) async {
  try {
    final r = await container.read(expiryRemindersProvider).resync();
    if (r case Err(:final failure)) {
      LocalErrorLog.record('reminder_resync', failure);
    }
  } on Object catch (e) {
    LocalErrorLog.record('reminder_resync', e);
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'IDSnap',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(body: SafeArea(child: child)),
  );
}

/// IDSnap splash while the vault opens (and billing reads its cached
/// state); a progress panel while files are encrypted (once).
class VaultStartupScreen extends StatelessWidget {
  const VaultStartupScreen({required this.progress, super.key});

  /// `(done, total)` files; null while nothing needs migrating.
  final ValueListenable<(int, int)?> progress;

  @override
  Widget build(BuildContext context) => _Shell(
    child: ValueListenableBuilder<(int, int)?>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value == null) return const StartupSplash();
        final (done, total) = value;
        return Padding(
          padding: const EdgeInsets.all(Space.x8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const IconBadge(Icons.enhanced_encryption_rounded, size: 72),
              const SizedBox(height: Space.x5),
              Text(
                'Encrypting your vault',
                style: context.text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.x2),
              Text(
                'This happens once. Your files stay on this phone, and '
                "nothing is lost if it's interrupted.",
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.x5),
              LinearProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(height: Space.x2),
              Text(
                '$done of $total files',
                style: context.text.bodySmall,
                semanticsLabel: '$done of $total files encrypted',
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Shown while the vault opens, so the first frame is never blank. The
/// "Opening…" line appears only when opening takes noticeably long, to
/// avoid a flash on fast phones.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key});

  static const slowAfter = Duration(milliseconds: 700);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(StartupSplash.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const IconBadge(Icons.lock_rounded, size: 72),
        const SizedBox(height: Space.x4),
        Text('IDSnap', style: context.text.headlineSmall),
        const SizedBox(height: Space.x5),
        if (_slow) ...[
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: Space.x3),
          Text('Opening your vault…', style: context.text.bodyMedium),
        ] else
          const SizedBox(height: 24 + Space.x3),
      ],
    ),
  );
}

/// Shown when startup fails for any reason other than a missing vault key
/// (audit H-08): what happened in plain words, Try again, Copy details
/// (redacted: step, error type, app version; never document contents) and
/// Contact support. Nothing in the vault is changed from here.
class StartupRecoveryScreen extends StatefulWidget {
  const StartupRecoveryScreen({
    required this.failure,
    required this.onRetry,
    super.key,
  });

  final StartupFailure failure;
  final Future<void> Function() onRetry;

  /// The text "Copy details" puts on the clipboard.
  static String details(StartupFailure failure) => [
    'IDSnap $appVersion',
    'Startup failure: ${failure.diagnostics}',
    ...LocalErrorLog.recent,
  ].join('\n');

  @override
  State<StartupRecoveryScreen> createState() => _StartupRecoveryScreenState();
}

class _StartupRecoveryScreenState extends State<StartupRecoveryScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.onRetry();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: StartupRecoveryScreen.details(widget.failure)),
    );
    if (context.mounted) {
      showAppSnack(
        context,
        'Details copied. They contain no document contents.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = widget.failure.explanation;
    return _Shell(
      child: Builder(
        builder: (context) => _busy
            ? const StartupSplash()
            : ListView(
                padding: const EdgeInsets.all(Space.x8),
                children: [
                  const SizedBox(height: Space.x8),
                  Center(
                    child: IconBadge(
                      Icons.error_outline_rounded,
                      color: context.colors.error,
                      size: 72,
                    ),
                  ),
                  const SizedBox(height: Space.x5),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      title,
                      style: context.text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: Space.x4),
                  Text(body, style: context.text.bodyLarge),
                  const SizedBox(height: Space.x3),
                  Text(
                    'Once IDSnap opens again, keep a copy of your documents '
                    'with Settings › Your data › Export all data.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.x8),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: Space.x2),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy details'),
                  ),
                  if (SupportContact.available) ...[
                    const SizedBox(height: Space.x2),
                    TextButton.icon(
                      onPressed: () => SupportContact.contact(
                        context,
                        failure: AppFailure(
                          FailureCode.unknown,
                          cause: widget.failure.cause,
                          heading: title,
                        ),
                        where: 'startup (${widget.failure.step.name})',
                      ),
                      icon: const Icon(Icons.mail_outline_rounded),
                      label: const Text('Contact support'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Shown when encrypted data exists but can't be unlocked on this phone.
/// Never creates a new key silently: the user decides.
class VaultRecoveryScreen extends StatefulWidget {
  const VaultRecoveryScreen({
    required this.reason,
    required this.onErase,
    super.key,
  });

  final VaultUnavailableReason reason;
  final Future<void> Function() onErase;

  static String explanation(VaultUnavailableReason reason) => switch (reason) {
    VaultUnavailableReason.keystoreError =>
      "IDSnap couldn't read its encryption key from this phone's secure "
          'storage. Restart the phone and open IDSnap again. Your files are '
          'still here.',
    VaultUnavailableReason.keyMissing || VaultUnavailableReason.keyMismatch =>
      'Your vault is encrypted with a key that is kept only on the phone '
          'where it was created. That key is not on this phone (this '
          'happens after restoring a phone backup or moving to a new '
          "phone), so these files can't be opened here.\n\n"
          'To bring your documents over, use Settings › Your data › Export '
          'all data on the old phone, then import that ZIP here.',
  };

  @override
  State<VaultRecoveryScreen> createState() => _VaultRecoveryScreenState();
}

class _VaultRecoveryScreenState extends State<VaultRecoveryScreen> {
  bool _busy = false;

  Future<void> _erase(BuildContext context) async {
    final first = await confirmAction(
      context,
      title: 'Erase the vault on this phone?',
      message:
          "This deletes the encrypted files that can't be opened here and "
          "starts an empty vault. It can't be undone.",
      confirmLabel: 'Erase',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final second = await confirmAction(
      context,
      title: 'Are you sure?',
      message:
          'If the old phone still works, export your data there first. '
          'Erase everything on this phone now?',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!second || !mounted) return;
    setState(() => _busy = true);
    await widget.onErase();
  }

  @override
  Widget build(BuildContext context) => _Shell(
    child: Builder(
      builder: (context) => _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Space.x8),
              children: [
                const SizedBox(height: Space.x8),
                const Center(child: IconBadge(Icons.key_off_rounded, size: 72)),
                const SizedBox(height: Space.x5),
                Text(
                  "Your vault can't be unlocked on this phone",
                  style: context.text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.x4),
                Text(
                  VaultRecoveryScreen.explanation(widget.reason),
                  style: context.text.bodyLarge,
                ),
                const SizedBox(height: Space.x8),
                if (widget.reason != VaultUnavailableReason.keystoreError)
                  OutlinedButton.icon(
                    onPressed: () => _erase(context),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Erase vault and start fresh'),
                  ),
                if (SupportContact.available) ...[
                  const SizedBox(height: Space.x2),
                  TextButton.icon(
                    onPressed: () => SupportContact.contact(
                      context,
                      where: 'vault recovery (${widget.reason.name})',
                    ),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Contact support'),
                  ),
                ],
              ],
            ),
    ),
  );
}
