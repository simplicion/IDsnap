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
          const SectionHeader('Storage'),
          const _StorageSection(),
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
                title: const Text('About DocScan'),
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
            AsyncError() => const Text('Storage usage unavailable'),
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
            Icons.delete_forever_outlined,
            color: context.colors.error,
          ),
          title: Text(
            'Delete all documents',
            style: TextStyle(color: context.colors.error),
          ),
          subtitle: const Text(
            'Permanently removes every document from this device',
          ),
          onTap: () => _deleteAll(context, ref),
        ),
      ],
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final first = await confirmAction(
      context,
      title: 'Delete all documents?',
      message:
          'Every scan and file in DocScan will be removed from this device. Files you shared or saved elsewhere are not affected.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final second = await confirmAction(
      context,
      title: 'This cannot be undone',
      message: 'Are you absolutely sure? There is no backup or cloud copy.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!second) return;
    final repo = ref.read(documentRepositoryProvider);
    final files = ref.read(fileStoreProvider);
    final docs = await repo.watch(const DocumentQuery()).first;
    for (final d in docs) {
      await files.delete(d.relativePath);
      final thumb = d.thumbnailPath;
      if (thumb != null) await files.delete(thumb);
      await repo.remove(d.id);
    }
    await files.clearTemp();
    ref.invalidate(_usageProvider);
    if (context.mounted) {
      showAppSnack(context, 'Deleted ${docs.length} documents');
    }
  }
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
