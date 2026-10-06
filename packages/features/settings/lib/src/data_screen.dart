import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Your data" (roadmap B4/B5, audit H-04/H-05): the full backup — the way
/// to move to a new phone — its import, and vault display preferences.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  /// Why an OS backup isn't enough (ADR-0010).
  static const backupNote =
      'Your vault files and database are encrypted on this phone '
      '(AES-256). The key never leaves this phone, so a phone or cloud '
      "backup can't restore your vault to a new phone. Export all data "
      'before you change phones.';

  /// What the full backup contains (shown before exporting).
  static const included = [
    'Every document, in its folders (with expiry dates)',
    'Secure notes (locked ones too)',
    'Authenticator accounts: secret keys and recovery codes',
    'Saved signatures and QR scan history',
    'Folder colours, icons and locks, and your settings',
  ];

  /// Paid builds (licence / store).
  static const notIncluded = [
    _pinsNote,
    'Your IDSnap Pro purchase — restore it from the store on the new phone.',
  ];

  /// The free build has no purchase to mention (ADR-0013).
  static const notIncludedFree = [_pinsNote];

  static const _pinsNote =
      'Folder and note PINs — they never leave this phone. Locked folders '
      "come back locked with the new phone's screen lock; set PINs again "
      'there.';

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  Future<void> _export() async {
    final choice = await askExportOptions(
      context,
      title: 'Export all data',
      included: DataScreen.included,
      notIncluded: ref.read(monetizationModeProvider).isFree
          ? DataScreen.notIncludedFree
          : DataScreen.notIncluded,
    );
    if (choice == null || !mounted) return;
    // The backup holds decrypted documents and 2FA secrets: always confirm
    // it's the owner (ADR-0010), whether or not App Lock is on.
    if (!await reauthenticateForBackup(ref, 'Confirm to export your data') ||
        !mounted) {
      return;
    }
    final archiver = ref.read(libraryArchiverProvider);
    final sections = ref.read(backupSectionsProvider);
    final result = await runBackupJob<BackupResult>(
      context,
      title: 'Exporting your data',
      job: (onProgress, cancel) => archiver.exportBackup(
        password: choice.password,
        sections: sections,
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

  Future<void> _import() async {
    final summary = await importBackupFlow(context, ref);
    if (summary == null || !mounted) return;
    // Restored settings replace this phone's; imported documents with an
    // expiry date get their reminders (no permission prompt here).
    ref.invalidate(settingsProvider);
    await ref.read(expiryRemindersProvider).resync();
  }

  /// The switch only turns on once the notification permission is granted
  /// and reminders are scheduled; turning it off cancels them (audit H-01).
  Future<void> _setReminders(bool on) async {
    final reminders = ref.read(expiryRemindersProvider);
    final settings = ref.read(settingsProvider.notifier);
    if (!on) {
      await settings.change((c) => c.copyWith(expiryReminders: false));
      final r = await reminders.disableAll();
      if (!mounted) return;
      r.fold(
        (_) => showAppSnack(context, 'Expiry reminders are off'),
        (f) => showFailureSnack(context, f),
      );
      return;
    }
    final r = await reminders.enableAll();
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        await settings.change((c) => c.copyWith(expiryReminders: true));
        if (!mounted) return;
        showAppSnack(
          context,
          value == 1
              ? 'Expiry reminders are on for 1 document.'
              : 'Expiry reminders are on for $value documents.',
        );
      case Err(:final failure):
        showFailureSnack(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(currentSettingsProvider);
    void change(AppSettings Function(AppSettings) update) =>
        ref.read(settingsProvider.notifier).change(update);
    return Scaffold(
      appBar: AppBar(title: const Text('Your data')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x12),
        children: [
          const SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Export all data'),
            subtitle: const Text(
              'Documents, notes, authenticator accounts, signatures and '
              'settings in one password-protected ZIP — the way to move to '
              'a new phone',
            ),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Import an IDSnap backup'),
            subtitle: const Text(
              'Restores everything in the backup. Items already here are '
              'skipped. Everything is encrypted again on this phone.',
            ),
            onTap: _import,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x2,
              Space.gutter,
              0,
            ),
            child: Text(
              DataScreen.backupNote,
              style: context.text.bodySmall?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          ),
          const SectionHeader('Vault'),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Show privacy banner'),
            subtitle: const Text('"Your documents never leave this phone"'),
            value: s.showPrivacyBanner,
            onChanged: (v) => change((c) => c.copyWith(showPrivacyBanner: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Expiry reminders'),
            subtitle: const Text(
              'Local notifications 30 and 7 days before a document expires',
            ),
            value: s.expiryReminders,
            onChanged: _setReminders,
          ),
        ],
      ),
    );
  }
}
