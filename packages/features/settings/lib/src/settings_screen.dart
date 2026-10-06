import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:go_router/go_router.dart';

final FutureProvider<StorageUsage> _usageProvider =
    FutureProvider.autoDispose<StorageUsage>(
      (ref) => ref.watch(fileStoreProvider).usage(),
    );

final FutureProviderFamily<EngineCapability, OcrScript> _ocrCapabilityProvider =
    FutureProvider.autoDispose.family<EngineCapability, OcrScript>(
      (ref, script) => ref.watch(textRecognizerProvider).capability(script),
    );

/// Settings tab.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(currentSettingsProvider);
    Future<void> change(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).change(f);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x12),
        children: [
          const SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              children: [
                for (final t in ThemePreference.values) ...[
                  Expanded(
                    child: _ThemeTile(
                      preference: t,
                      selected: s.theme == t,
                      onTap: () => change((c) => c.copyWith(theme: t)),
                    ),
                  ),
                  if (t != ThemePreference.values.last)
                    const SizedBox(width: Space.x3),
                ],
              ],
            ),
          ),
          const SectionHeader('Scanning'),
          _Group(
            children: [
              _ChoiceTile<EnhancementFilter>(
                icon: Icons.auto_fix_high_rounded,
                title: 'Default filter',
                value: s.defaultFilter,
                values: EnhancementFilter.values,
                label: (f) => f.label,
                onChanged: (v) => change((c) => c.copyWith(defaultFilter: v)),
              ),
              _ChoiceTile<QualityPreset>(
                icon: Icons.high_quality_rounded,
                title: 'PDF quality',
                value: s.quality,
                values: QualityPreset.values,
                label: (q) => q.label,
                hint: (q) => q.hint,
                onChanged: (v) => change((c) => c.copyWith(quality: v)),
              ),
              _ChoiceTile<PdfPageSize>(
                icon: Icons.crop_portrait_rounded,
                title: 'Page size',
                value: s.pageSize,
                values: PdfPageSize.values,
                label: (p) => p.label,
                onChanged: (v) => change((c) => c.copyWith(pageSize: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.crop_free_rounded),
                title: const Text('Detect page edges'),
                subtitle: const Text(
                  'Find the page outline automatically. You can always adjust corners.',
                ),
                value: s.autoDetectEdges,
                onChanged: (v) => change((c) => c.copyWith(autoDetectEdges: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.manage_search_rounded),
                title: const Text('Searchable PDFs'),
                subtitle: const Text(
                  'Add recognized text so you can search and copy it. Latin script only.',
                ),
                value: s.searchablePdf,
                onChanged: (v) => change((c) => c.copyWith(searchablePdf: v)),
              ),
            ],
          ),
          const SectionHeader('Text recognition'),
          _Group(
            children: [
              _ChoiceTile<OcrScript>(
                icon: Icons.translate_rounded,
                title: 'Language',
                value: s.ocrScript,
                values: OcrScript.values,
                label: (o) => o.label,
                onChanged: (v) => change((c) => c.copyWith(ocrScript: v)),
              ),
              _OcrCapabilityNote(script: s.ocrScript),
            ],
          ),
          const SectionHeader('Security & data'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('App Lock'),
                subtitle: Text(s.appLock ? 'On' : 'Off'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(Routes.security)),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Your data'),
                subtitle: const Text('Export or import all documents'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(Routes.dataExport)),
              ),
            ],
          ),
          const SectionHeader('Storage'),
          const _StorageSection(),
          // Free build: what "free with ads" means, and the ad privacy
          // choices. Paid builds: the plan. Settings never shows ads.
          if (ref.watch(monetizationModeProvider).isFree) ...[
            const SectionHeader('Free with ads'),
            const _FreeWithAdsGroup(),
          ] else ...[
            const SectionHeader('IDSnap Pro'),
            const _Group(children: [_SubscriptionTile()]),
          ],
          const SectionHeader('About'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Privacy'),
                subtitle: const Text(
                  'Your documents never leave this device unless you share them',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(Routes.privacy)),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About IDSnap'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(Routes.about)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card wrapping a group of list tiles.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: Space.x4, endIndent: Space.x4),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Mini light/dark preview so users see the theme before choosing it.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget mock(ThemeData t) => ColoredBox(
      color: t.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(Space.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: t.colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < 2; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                height: 8,
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );

    final preview = switch (preference) {
      ThemePreference.light => mock(AppTheme.light()),
      ThemePreference.dark => mock(AppTheme.dark()),
      ThemePreference.system => Row(
        children: [
          Expanded(child: mock(AppTheme.light())),
          Expanded(child: mock(AppTheme.dark())),
        ],
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: 'Theme: ${preference.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: Radii.cardAll,
                border: Border.all(
                  color: selected ? context.colors.primary : context.ds.border,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(borderRadius: Radii.cardAll, child: preview),
            ),
            const SizedBox(height: Space.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    preference.label,
                    style: context.text.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// List tile that opens a bottom sheet of choices.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final IconData icon;
  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final String Function(T)? hint;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(label(value)),
    trailing: const Icon(Icons.expand_more_rounded),
    onTap: () async {
      final picked = await showModalBottomSheet<T>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.x2,
                ),
                child: Text(title, style: context.text.titleMedium),
              ),
              for (final v in values)
                ListTile(
                  title: Text(label(v)),
                  subtitle: hint == null ? null : Text(hint!(v)),
                  trailing: v == value
                      ? Icon(Icons.check_rounded, color: context.colors.primary)
                      : null,
                  selected: v == value,
                  onTap: () => Navigator.pop(context, v),
                ),
            ],
          ),
        ),
      );
      if (picked != null) onChanged(picked);
    },
  );
}

class _OcrCapabilityNote extends ConsumerWidget {
  const _OcrCapabilityNote({required this.script});

  final OcrScript script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(_ocrCapabilityProvider(script));
    final (icon, color, text) = switch (cap) {
      AsyncData(:final value)
          when value.available &&
              value.worksOffline &&
              !value.requiresDownload =>
        (
          Icons.cloud_off_rounded,
          context.ds.success,
          value.note ?? 'Installed. Recognition runs on this device, offline.',
        ),
      AsyncData(:final value) when value.available && value.requiresDownload =>
        (
          Icons.download_rounded,
          context.ds.warning,
          value.note ??
              'Downloaded by the system on first use, then works offline.',
        ),
      AsyncData(:final value) => (
        Icons.block_rounded,
        context.colors.error,
        value.note ?? 'Not available on this device.',
      ),
      AsyncError() => (
        Icons.help_outline_rounded,
        context.ds.textSecondary,
        'Availability unknown.',
      ),
      _ => (
        Icons.hourglass_empty_rounded,
        context.ds.textSecondary,
        'Checking availability…',
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: context.text.bodyMedium),
      subtitle: const Text(
        'Recognition quality varies with print quality, lighting and handwriting. Review text before relying on it.',
      ),
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(_usageProvider);
    return _Group(
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: switch (usage) {
            AsyncData(:final value) => _UsageBar(usage: value),
            AsyncError() => const Text(
              "Storage usage couldn't be measured. Your files are not "
              'affected — reopen Settings to try again.',
            ),
            _ => const LinearProgressIndicator(),
          },
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear temporary files'),
          subtitle: const Text(
            'Frees space used while processing. Your documents are kept.',
          ),
          onTap: () async {
            await ref.read(fileStoreProvider).clearTemp();
            ref.invalidate(_usageProvider);
            if (context.mounted) {
              showAppSnack(context, 'Temporary files cleared');
            }
          },
        ),
        ListTile(
          leading: Icon(
            Icons.delete_sweep_outlined,
            color: context.colors.error,
          ),
          title: Text(
            'Delete all documents',
            style: TextStyle(color: context.colors.error),
          ),
          subtitle: const Text(
            'Every document, also in locked folders. Folders, notes and '
            'authenticator accounts stay.',
          ),
          onTap: () => _deleteAllDocuments(context, ref),
        ),
        ListTile(
          leading: Icon(
            Icons.delete_forever_outlined,
            color: context.colors.error,
          ),
          title: Text(
            'Erase everything',
            style: TextStyle(color: context.colors.error),
          ),
          subtitle: Text(
            'Documents, folders, notes, authenticator accounts, signatures, '
            'QR history and settings.'
            '${ref.watch(monetizationModeProvider).isFree ? '' : ' Your IDSnap Pro purchase is kept.'}',
          ),
          onTap: () => _eraseEverything(context, ref),
        ),
      ],
    );
  }

  /// Cancels a deleted document's expiry reminders (best effort: the
  /// scheduler may not be wired in every build).
  static Future<void> Function(Document) _cancelReminders(WidgetRef ref) =>
      (d) async {
        try {
          await ref.read(reminderSchedulerProvider).cancel(d.id);
        } on Object {
          // No scheduler: nothing was scheduled.
        }
      };

  Future<void> _deleteAllDocuments(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Delete all documents?',
      message:
          'Every document in IDSnap, including those in locked folders, '
          'will be permanently removed from this phone. Folders, notes, '
          'authenticator accounts and settings stay. Files you shared or '
          'saved elsewhere are not affected.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    // Locked folders are included, so confirm it's the owner first.
    if (!await reauthenticateForBackup(ref, 'Confirm to delete documents') ||
        !context.mounted) {
      return;
    }
    final result = await ref
        .read(vaultEraserProvider)
        .deleteAllDocuments(onDeleted: _cancelReminders(ref));
    ref.invalidate(_usageProvider);
    if (!context.mounted) return;
    result.fold(
      (n) => showAppSnack(
        context,
        n == 1 ? 'Deleted 1 document' : 'Deleted $n documents',
      ),
      (f) => showFailureSnack(context, f),
    );
  }

  Future<void> _eraseEverything(BuildContext context, WidgetRef ref) async {
    final typed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _EraseConfirmDialog(paid: !ref.read(monetizationModeProvider).isFree),
    );
    if (typed != true || !context.mounted) return;
    if (!await reauthenticateForBackup(ref, 'Confirm to erase everything') ||
        !context.mounted) {
      return;
    }
    final restart = ref.read(appRestartProvider);
    final result = await ref
        .read(vaultEraserProvider)
        .eraseEverything(onDeleted: _cancelReminders(ref));
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        if (restart != null) {
          restart(); // Every screen starts again from the empty vault.
          return;
        }
        ref
          ..invalidate(settingsProvider)
          ..invalidate(_usageProvider);
        showAppSnack(
          context,
          'Everything was erased. Close and reopen IDSnap to finish.',
        );
      case Err(:final failure):
        ref.invalidate(_usageProvider);
        showFailureSnack(context, failure);
    }
  }
}

/// "Erase everything" asks the user to type a word, so it can't happen by
/// a stray tap.
class _EraseConfirmDialog extends StatefulWidget {
  const _EraseConfirmDialog({required this.paid});

  /// A paid build keeps the purchase, and says so.
  final bool paid;

  static const word = 'ERASE';

  @override
  State<_EraseConfirmDialog> createState() => _EraseConfirmDialogState();
}

class _EraseConfirmDialogState extends State<_EraseConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ok =>
      _controller.text.trim().toUpperCase() == _EraseConfirmDialog.word;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Erase everything?'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This permanently removes from this phone: every document '
          '(also in locked folders), folders, secure notes, authenticator '
          'accounts with their secret keys and recovery codes, saved '
          'signatures, QR history, folder and note PINs, drafts, temporary '
          'files and your settings. IDSnap starts fresh.'
          '${widget.paid ? ' Your IDSnap Pro purchase is kept.' : ''}',
        ),
        const SizedBox(height: Space.x3),
        const Text(
          'Turn off two-step verification on those websites first, or '
          'export your data — without it you can lose access to accounts.',
        ),
        const SizedBox(height: Space.x3),
        TextField(
          controller: _controller,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Type ${_EraseConfirmDialog.word} to confirm',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.error,
          foregroundColor: context.colors.onError,
        ),
        onPressed: _ok ? () => Navigator.pop(context, true) : null,
        child: const Text('Erase everything'),
      ),
    ],
  );
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final parts = <(String, int, Color)>[
      ('Documents', usage.documents, context.colors.primary),
      ('Scan originals', usage.originals, context.colors.secondary),
      ('Temporary', usage.temp, context.colors.tertiary),
    ];
    final total = usage.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatBytes(total)} used on this device',
          style: context.text.titleSmall,
        ),
        const SizedBox(height: Space.x3),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: total == 0
                ? ColoredBox(color: context.colors.surfaceContainerHighest)
                : Row(
                    children: [
                      for (final (_, bytes, color) in parts)
                        if (bytes > 0)
                          Expanded(
                            flex: (bytes * 1000 / total).ceil(),
                            child: ColoredBox(color: color),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Space.x3),
        Wrap(
          spacing: Space.x4,
          runSpacing: Space.x1,
          children: [
            for (final (label, bytes, color) in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$label · ${formatBytes(bytes)}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Settings › Subscription entry: current plan at a glance.
class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(entitlementProvider);
    final subtitle = switch (state) {
      FreeEntitlement() => 'Free · Every feature is unlocked',
      TrialEntitlement(:final endsAt) =>
        'Free day · ends in ${formatTimeLeft(endsAt, DateTime.now())}',
      DayPassEntitlement(:final expiresAt) =>
        'Day pass · ends in ${formatTimeLeft(expiresAt, DateTime.now())}',
      MonthlyEntitlement() => 'IDSnap Pro · Monthly',
      ExpiredEntitlement(reason: LapseReason.notActivated) =>
        'Not activated · Connect once to start your free day',
      ExpiredEntitlement() => 'No active plan · Free features only',
    };
    return ListTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: const Text('Subscription'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => unawaited(context.push(Routes.subscription)),
    );
  }
}

/// Settings in the free build (ADR-0013): says plainly that IDSnap is free
/// and shows ads, and offers the ad privacy choices when the consent
/// platform requires them (EEA, UK, Switzerland, some US states).
class _FreeWithAdsGroup extends ConsumerStatefulWidget {
  const _FreeWithAdsGroup();

  @override
  ConsumerState<_FreeWithAdsGroup> createState() => _FreeWithAdsGroupState();
}

class _FreeWithAdsGroupState extends ConsumerState<_FreeWithAdsGroup> {
  AdsService? _ads;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ads?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ads = ref.watch(adsServiceProvider);
    if (!identical(ads, _ads)) {
      _ads?.removeListener(_changed);
      _ads = ads..addListener(_changed);
    }
    return _Group(
      children: [
        const ListTile(
          leading: Icon(Icons.volunteer_activism_outlined),
          title: Text('IDSnap is free'),
          subtitle: Text(
            'Every feature is unlocked, with no trial and nothing to buy. '
            'Ads on Home, Tools and some tool screens pay for it. There are '
            'never ads in your ID Vault, the Authenticator, Secure notes or '
            'Settings.',
          ),
        ),
        if (ads.privacyOptionsRequired)
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Ad privacy choices'),
            subtitle: const Text(
              'Change whether ads may be personalised for you',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => unawaited(ads.openPrivacyOptions()),
          ),
      ],
    );
  }
}
